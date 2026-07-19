import 'dart:math';

import '../../isolate/compute_service.dart';
import '../../llm/llm_client.dart';
import '../../logger/app_logger.dart';
import '../../memory/memory_manager.dart';
import '../../pet/pet_economy.dart';
import '../message_transformer.dart';

/// 上下文压缩变换器
///
/// 当消息列表的估算 token 数超过阈值时，自动触发压缩：
/// 1. 将即将丢弃的早期消息沉淀到长期记忆（Qdrant/SQLite）
/// 2. 调用 LLM 对早期消息生成摘要
/// 3. 用摘要替换原始消息，保留最近 N 轮完整对话
///
/// 特色：压缩前的"沉淀"步骤确保信息不会真正丢失——
/// 后续对话如果语义相关，MemoryRecallHook 能从长期记忆中召回。
class ContextCompactor extends MessageTransformer {
  /// 用于生成摘要的 LLM（复用当前对话模型或指定轻量模型）
  final LlmClient llm;

  /// 长期记忆管理器（可选，有则执行沉淀）
  final MemoryManager? memoryManager;

  /// 记忆 collection 名称
  final String? memoryCollection;

  /// 是否使用 Qdrant 向量存储
  final bool useQdrant;

  /// 触发压缩的 token 阈值。
  /// 当 > 0 时使用该固定值；当 == 0 时表示由 [contextWindow] 动态计算。
  final int tokenThreshold;

  /// 模型上下文窗口大小 (token)。用于动态计算压缩阈值。
  /// 0 表示未知——此时退回保守默认值。
  final int contextWindow;

  /// 兜底默认上下文窗口 (128K)，用于 contextWindow 未知时计算阈值。
  /// 当今主流模型最低都有 128K，安全兜底。
  static const int _defaultContextWindow = 128000;

  /// 基于模型 context window 计算动态阈值的比例。
  /// 触发压缩 = contextWindow * ratio。
  /// 预留 40% 给工具循环累积、system prompt + 工具定义 + 保真区 + LLM 回复空间。
  static const double _thresholdRatio = 0.60;

  /// 动态计算出的实际阈值
  int get effectiveThreshold {
    if (tokenThreshold > 0) return tokenThreshold;
    final ctx = contextWindow > 0 ? contextWindow : _defaultContextWindow;
    return (ctx * _thresholdRatio).toInt();
  }

  /// 压缩后保留最近多少轮对话（一轮 = user + assistant）
  final int keepRecentTurns;

  /// 摘要的目标最大 token 数
  final int summaryMaxTokens;

  /// 是否已在当前 pipeline 调用中执行过压缩（防止同一轮重复压缩）
  bool _compactedThisRound = false;

  ContextCompactor({
    required this.llm,
    this.memoryManager,
    this.memoryCollection,
    this.useQdrant = false,
    this.tokenThreshold = 0,
    this.contextWindow = 0,
    this.keepRecentTurns = 6,
    this.summaryMaxTokens = 800,
  });

  @override
  String get name => 'ContextCompactor';

  @override
  bool shouldActivate(List<Map<String, dynamic>> messages) {
    // 消息太少不需要压缩
    if (messages.length < (keepRecentTurns * 2 + 3)) return false;
    // 估算 token 超阈值才激活
    final threshold = effectiveThreshold;
    final tokens = _estimateTokens(messages);
    if (tokens > threshold && !_compactedThisRound) {
      AppLogger.instance.log(
        '[Compactor] 触发压缩: 估算 $tokens tokens > 阈值 $threshold'
        '${contextWindow > 0 ? " (contextWindow=$contextWindow, ratio=$_thresholdRatio)" : " (默认阈值)"}',
      );
      return true;
    }
    return false;
  }

  @override
  Future<List<Map<String, dynamic>>> transform(
    List<Map<String, dynamic>> messages,
  ) async {
    _compactedThisRound = true;

    // ─── 分区 ───
    // system (第一条) | 可压缩区 | 保真区 (最近 N 轮)
    final system = messages.first;
    final recentCount = _findRecentBoundary(messages);
    final compressible = messages.sublist(1, messages.length - recentCount);
    final recent = messages.sublist(messages.length - recentCount);

    if (compressible.isEmpty) {
      AppLogger.instance.log('[Compactor] 可压缩区为空，跳过');
      return messages;
    }

    AppLogger.instance.log(
      '[Compactor] 分区: system=1, 压缩区=${compressible.length}条, '
      '保真区=${recent.length}条',
    );

    // ─── 第一步：沉淀到长期记忆 ───
    if (memoryManager != null && memoryCollection != null) {
      await _sinkToMemory(compressible);
    }

    // ─── 第二步：生成摘要 ───
    final summary = await _summarize(compressible);

    // ─── 第三步：重组消息列表 ───
    final result = <Map<String, dynamic>>[
      system,
      {'role': 'system', 'content': '[以下是之前对话的摘要，供你参考上下文]\n$summary'},
      ...recent,
    ];

    // ─── 第四步：清理孤立的工具结果 ───
    // 收集所有 assistant 消息中的 tool_call_id
    final validToolCallIds = <String>{};
    for (final msg in result) {
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        for (final tc in msg['tool_calls'] as List) {
          final id = tc['id'] as String?;
          if (id != null) validToolCallIds.add(id);
        }
      }
    }

    // 过滤掉没有对应工具调用的 tool 消息
    final cleaned = result.where((msg) {
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        final isValid = toolCallId != null && validToolCallIds.contains(toolCallId);
        if (!isValid) {
          AppLogger.instance.log(
            '[Compactor] 移除孤立的工具结果: tool_call_id=$toolCallId'
          );
        }
        return isValid;
      }
      return true;
    }).toList();

    final newTokens = _estimateTokens(cleaned);
    AppLogger.instance.log(
      '[Compactor] 压缩完成: ${messages.length}条→${cleaned.length}条, '
      '估算 token: $newTokens',
    );

    return cleaned;
  }

  /// 重置轮次标记（每次新消息开始时由外部重置）
  void resetRound() => _compactedThisRound = false;

  // ─── 私有方法 ─────────────────────────────────────────────

  /// 估算消息列表的 token 数（粗略：中文 ~1.5 token/字，英文 ~0.75 token/词）
  int _estimateTokens(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final msg in messages) {
      final content = msg['content'];
      if (content is String) {
        total += _estimateStringTokens(content);
      } else if (content is List) {
        // Multimodal content parts
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            total += _estimateStringTokens(part['text'] as String? ?? '');
          }
        }
      }
      // tool_calls 参数也算 token
      if (msg['tool_calls'] is List) {
        for (final tc in msg['tool_calls'] as List) {
          final args = tc['function']?['arguments'] as String? ?? '';
          total += _estimateStringTokens(args);
        }
      }
      total += 4; // 每条消息的元数据开销 (role, separators)
    }
    return total;
  }

  int _estimateStringTokens(String text) {
    if (text.isEmpty) return 0;
    return ComputeService.estimateTokens(text);
  }

  /// 把上下文压缩期间的记忆沉淀/摘要请求计入宠物经济统计。
  /// 这些是真实的后台 LLM 调用，主聊天窗口的 token 计数不会覆盖到，
  /// 单独估算并上报，避免 totalTokensSpent 系统性偏低。
  void _recordTokenUsage(List<Map<String, dynamic>> prompt, String result) {
    var tokens = 0;
    for (final msg in prompt) {
      final content = msg['content'];
      if (content is String) {
        tokens += ComputeService.estimateTokens(content);
      }
    }
    tokens += ComputeService.estimateTokens(result);
    if (tokens > 0) {
      PetEconomy.instance.rewardForTokens(tokens);
    }
  }

  /// 找到保真区的起始位置：保留最近 keepRecentTurns 轮完整对话
  /// 一轮 = user + assistant（可能包含中间的 tool 消息）
  ///
  /// 特别处理：确保工具调用和工具结果成对保留，避免孤立的 tool 消息。
  int _findRecentBoundary(List<Map<String, dynamic>> messages) {
    int turnsFound = 0;
    int idx = messages.length - 1;

    while (idx > 0 && turnsFound < keepRecentTurns) {
      final role = messages[idx]['role'] as String?;
      if (role == 'user') turnsFound++;
      idx--;
    }

    // idx+1 是初步的保真区起始位置
    int boundaryIdx = idx + 1;

    // 向前扩展：确保所有 tool 消息都有对应的 assistant 工具调用
    // 从边界开始向后扫描，收集所有 tool_call_id
    final toolCallIdsInRecent = <String>{};
    for (int i = boundaryIdx; i < messages.length; i++) {
      final msg = messages[i];
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        if (toolCallId != null) {
          toolCallIdsInRecent.add(toolCallId);
        }
      }
    }

    // 如果有 tool 消息，向前查找对应的 assistant 工具调用
    if (toolCallIdsInRecent.isNotEmpty) {
      for (int i = boundaryIdx - 1; i > 0; i--) {
        final msg = messages[i];
        if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
          final toolCalls = msg['tool_calls'] as List;
          for (final tc in toolCalls) {
            final id = tc['id'] as String?;
            if (id != null && toolCallIdsInRecent.contains(id)) {
              // 找到了对应的工具调用，扩展边界到这里
              boundaryIdx = i;
              // 移除已匹配的 ID
              toolCallIdsInRecent.remove(id);
              if (toolCallIdsInRecent.isEmpty) break;
            }
          }
        }
        if (toolCallIdsInRecent.isEmpty) break;
      }

      // 如果仍有未匹配的 tool_call_id，记录警告
      if (toolCallIdsInRecent.isNotEmpty) {
        AppLogger.instance.log(
          '[Compactor] 警告: 发现 ${toolCallIdsInRecent.length} 个孤立的工具结果，'
          '将在压缩时移除: ${toolCallIdsInRecent.join(", ")}'
        );
      }
    }

    final boundary = messages.length - boundaryIdx;
    return min(boundary, messages.length - 1); // 至少保留 system
  }

  /// 将即将被压缩的消息沉淀到长期记忆
  ///
  /// 每 3 轮对话为一组，调用 LLM 提取值得记忆的信息并存储。
  /// 这确保了即使摘要被再次压缩，重要信息仍可通过语义检索召回。
  Future<void> _sinkToMemory(List<Map<String, dynamic>> messages) async {
    AppLogger.instance.log('[Compactor] 开始记忆沉淀: ${messages.length}条消息');

    // 按 6 条为一组（约 3 轮对话）批量处理
    const batchSize = 6;
    int stored = 0;

    for (int i = 0; i < messages.length; i += batchSize) {
      final batch = messages.sublist(i, min(i + batchSize, messages.length));
      final text = _messagesToText(batch);
      if (text.length < 50) continue; // 太短跳过

      try {
        final extractPrompt = [
          {
            'role': 'system',
            'content':
                '你是一个记忆提取器。分析下面的对话片段，提取所有值得长期记住的信息'
                '（如：用户偏好、技术决策、项目约定、重要结论、配置信息、关键事实）。\n\n'
                '如果有多条值得记忆的信息，每条一行输出，保持简洁（方便日后语义检索）。\n'
                '如果没有值得记住的信息（普通闲聊、一次性问答），只输出: SKIP',
          },
          {'role': 'user', 'content': text},
        ];

        final response = await llm.chat(extractPrompt);
        final result = response.content?.trim() ?? '';
        _recordTokenUsage(extractPrompt, result);

        if (result.isEmpty || result.toUpperCase().startsWith('SKIP')) continue;

        // 每条记忆单独存储（方便精确召回）
        final memories = result.split('\n').where((l) => l.trim().isNotEmpty);
        for (final memory in memories) {
          final cleanMemory = memory.replaceFirst(RegExp(r'^[-•]\s*'), '');
          if (cleanMemory.length < 10) continue;
          await memoryManager!.store(
            text: cleanMemory,
            collectionName: memoryCollection!,
            useQdrant: useQdrant,
            metadata: {
              'source': 'compaction_sink',
              'batch_index': i ~/ batchSize,
            },
          );
          stored++;
        }
      } catch (e) {
        AppLogger.instance.log('[Compactor] 沉淀批次失败: $e');
      }
    }

    AppLogger.instance.log('[Compactor] 沉淀完成: 存入 $stored 条记忆');
  }

  /// 生成对话摘要
  Future<String> _summarize(List<Map<String, dynamic>> messages) async {
    final text = _messagesToText(messages);

    AppLogger.instance.log('[Compactor] 生成摘要: 原文 ${text.length} 字符');

    try {
      final summaryPrompt = [
        {
          'role': 'system',
          'content':
              '你是一个对话摘要生成器。将下面的对话历史压缩为一段简洁的摘要。\n\n'
              '要求：\n'
              '- 保留关键信息：用户的需求、做出的决策、重要结论\n'
              '- 保留技术细节：涉及的文件、函数、配置、错误信息\n'
              '- 保留进度状态：已完成什么、正在进行什么、待办事项\n'
              '- 使用简洁的要点格式\n'
              '- 控制在 400 字以内\n'
              '- 直接输出摘要内容，不要前缀或解释',
        },
        {'role': 'user', 'content': text},
      ];

      final response = await llm.chat(summaryPrompt);

      final summary = response.content?.trim() ?? '';
      _recordTokenUsage(summaryPrompt, summary);
      AppLogger.instance.log('[Compactor] 摘要生成完成: ${summary.length} 字符');
      return summary.isEmpty ? _fallbackSummary(messages) : summary;
    } catch (e) {
      AppLogger.instance.log('[Compactor] 摘要生成失败: $e, 使用降级方案');
      return _fallbackSummary(messages);
    }
  }

  /// 降级摘要：LLM 调用失败时，取每轮对话的首 50 字符
  String _fallbackSummary(List<Map<String, dynamic>> messages) {
    final lines = <String>[];
    for (final msg in messages) {
      final role = msg['role'] as String? ?? '';
      if (role == 'user' || role == 'assistant') {
        final content = msg['content'];
        final text = content is String ? content : '';
        if (text.isNotEmpty) {
          final preview = text.length > 80
              ? '${text.substring(0, 80)}...'
              : text;
          lines.add('[$role] $preview');
        }
      }
    }
    return lines.take(20).join('\n');
  }

  /// 将消息列表格式化为可读文本（供 LLM 阅读）
  String _messagesToText(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] as String? ?? 'unknown';
      final content = msg['content'];
      String text = '';
      if (content is String) {
        text = content;
      } else if (content is List) {
        text = (content)
            .where((p) => p is Map && p['type'] == 'text')
            .map((p) => p['text'] as String? ?? '')
            .join(' ');
      }
      if (text.isEmpty) continue;
      // 截断过长的单条消息（避免摘要输入过大）
      if (text.length > 500) text = '${text.substring(0, 500)}...';
      buffer.writeln('[$role]: $text');
    }
    return buffer.toString();
  }
}

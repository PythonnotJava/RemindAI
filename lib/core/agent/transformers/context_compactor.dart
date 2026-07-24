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
/// 参考，一种压缩上下文节省每轮对话token的方法：https://github.com/Hmbown/CodeWhale/issues/580
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

  /// 模型名称，用于智能默认值推断
  final String modelName;

  /// 根据模型名称推断合理的默认上下文窗口
  static int _inferDefaultContextWindow(String modelName) {
    final nameLower = modelName.toLowerCase();

    // DeepSeek 系列：1M 上下文
    if (nameLower.contains('deepseek')) {
      return 1000000;
    }

    // Claude 系列：200K 上下文
    if (nameLower.contains('claude')) {
      return 200000;
    }

    // Gemini Pro 1.5/2.0：1M+ 上下文
    if (nameLower.contains('gemini') &&
        (nameLower.contains('1.5') ||
            nameLower.contains('2.0') ||
            nameLower.contains('pro'))) {
      return 1000000;
    }

    // GPT-5 系列：128K 上下文（推测）
    if (nameLower.contains('gpt-5')) {
      return 128000;
    }

    // GPT-4 系列：128K 上下文
    if (nameLower.contains('gpt-4')) {
      return 128000;
    }

    // 其他模型保守估计 128K
    return _defaultContextWindow;
  }

  /// 兜底默认上下文窗口，当 contextWindow 未知且无法从模型名推断时使用。
  static const int _defaultContextWindow = 128000;

  /// 模型特定的压缩阈值比例配置
  static const Map<String, double> _modelThresholds = {
    'claude-opus-4': 0.50,
    'claude-sonnet-4': 0.50,
    'claude-3-5-sonnet': 0.50,
    'claude-3-opus': 0.50,
    'gpt-5': 0.5,
    'gpt-4': 0.50,
    'gpt-4-turbo': 0.50,
    'deepseek': 0.50,
    'gemini-1.5-pro': 0.50,
    'gemini-2.0': 0.50,
  };

  /// 小上下文模型的阈值下限（避免压缩后空间不足）
  static const double _smallContextFloor = 0.75;
  static const int _smallContextLimit = 512000; // 512K

  /// 基于模型 context window 计算动态阈值的比例。
  /// 触发压缩 = contextWindow * ratio。
  /// 预留空间给：工具循环累积、system prompt + 工具定义 + 保真区 + LLM 回复。
  static const double _defaultThresholdRatio = 0.50;

  /// 动态计算出的实际阈值
  int get effectiveThreshold {
    if (tokenThreshold > 0) return tokenThreshold;

    final ctx = contextWindow > 0
        ? contextWindow
        : _inferDefaultContextWindow(modelName);

    // 1. 获取模型特定阈值（匹配任意子串）
    double ratio = _defaultThresholdRatio;
    for (final entry in _modelThresholds.entries) {
      if (modelName.toLowerCase().contains(entry.key.toLowerCase())) {
        ratio = entry.value;
        break;
      }
    }

    // 2. 小上下文模型调整：提高阈值延迟压缩
    if (ctx < _smallContextLimit && ratio < _smallContextFloor) {
      ratio = _smallContextFloor;
    }

    return (ctx * ratio).toInt();
  }

  /// 压缩后保留最近多少轮对话（一轮 = user + assistant）
  final int keepRecentTurns;

  /// 摘要的目标最大 token 数
  final int summaryMaxTokens;

  /// 是否已在当前 pipeline 调用中执行过压缩（防止同一轮重复压缩）
  bool _compactedThisRound = false;

  /// 上一次压缩生成的总结（用于迭代式总结）
  String? _previousSummary;

  /// 压缩失败计数（用于指数退避）
  int _compressionFailures = 0;

  /// 上次失败时间
  DateTime? _lastFailureTime;

  /// 上下文压缩器构造函数
  ///
  /// 参数说明：
  /// - [tokenThreshold]: 手动指定的压缩触发阈值（0 表示自动计算）
  /// - [contextWindow]: 模型上下文窗口大小（用于计算默认阈值）
  /// - [keepRecentTurns]: 保留最近 N 轮对话（默认 6 轮）
  /// - [summaryMaxTokens]: 总结的最大长度（默认 800 tokens）
  ///
  /// 阈值计算逻辑：
  /// 1. 如果 tokenThreshold > 0：直接使用该值
  /// 2. 如果 contextWindow > 0：使用 contextWindow * 50%
  /// 3. 否则：使用保守兜底值 128K * 50% = 64K
  ///
  /// 为什么是 50%？
  /// - 给输出留足空间：输入占 50%，输出可以用剩余 50%
  /// - 避免"满载崩溃"：压缩后立即生成长回答不会超限
  /// - 实际压缩比通常 > 90%：压缩后远低于 50%，下次触发有充足缓冲
  ContextCompactor({
    required this.llm,
    this.memoryManager,
    this.memoryCollection,
    this.useQdrant = false,
    this.tokenThreshold = 0,
    this.contextWindow = 0,
    this.modelName = '',
    this.keepRecentTurns = 4, // Loop 模式降低保留轮数，减少请求体大小
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
      // 计算实际使用的比例（用于日志）
      final ctx = contextWindow > 0
          ? contextWindow
          : _inferDefaultContextWindow(modelName);
      final actualRatio = threshold / ctx;
      AppLogger.instance.log(
        '[Compactor] 触发压缩: 估算 $tokens tokens > 阈值 $threshold '
        '(contextWindow=$ctx, ratio=${actualRatio.toStringAsFixed(2)}, model=$modelName)',
      );
      return true;
    }
    return false;
  }

  @override
  Future<List<Map<String, dynamic>>> transform(
    List<Map<String, dynamic>> messages,
  ) async {
    // ─── 预处理：清理孤立的工具调用和结果 ───
    // 无论是否触发压缩，都应该执行完整性检查
    // 防止因为某些异常导致 tool_calls 和 tool_result 不匹配
    messages = _cleanOrphanedToolMessages(messages);

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
    final compressibleEnd = messages.length - recentCount;
    final summary = await _summarizeCacheAligned(messages, compressibleEnd);

    // ─── 第三步：重组消息列表 ───
    final result = <Map<String, dynamic>>[
      system,
      {'role': 'system', 'content': '[以下是之前对话的摘要，供你参考上下文]\n$summary'},
      ...recent,
    ];

    // ─── 第四步：再次清理孤立消息（压缩可能破坏完整性）───
    final cleaned = _cleanOrphanedToolMessages(result);

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

  /// 检查是否应跳过 LLM 压缩（失败冷却期）
  bool _shouldSkipLLMCompression() {
    if (_compressionFailures == 0) return false;
    if (_lastFailureTime == null) return false;

    // 指数退避: 2^n 分钟
    final cooldownMinutes = 1 << _compressionFailures; // 2, 4, 8, 16, 32...
    final elapsed = DateTime.now().difference(_lastFailureTime!);

    if (elapsed.inMinutes < cooldownMinutes) {
      AppLogger.instance.log(
        '[Compactor] ⏸️  冷却期活跃: 已失败 $_compressionFailures 次，'
        '需等待 $cooldownMinutes 分钟 (已过 ${elapsed.inMinutes} 分钟)',
      );
      return true;
    }

    return false;
  }

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

  /// 清理孤立的工具调用和工具结果
  ///
  /// 算法思想：
  /// 1. 收集所有 assistant 消息中的 tool_call_id（有效的工具调用）
  /// 2. 收集所有 tool 消息中的 tool_call_id（有效的工具结果）
  /// 3. 移除没有对应工具调用的 tool 结果（孤立结果）
  /// 4. 移除没有对应工具结果的 assistant tool_calls（孤立调用）
  ///
  /// 为什么需要这个？
  /// - 并行工具调用时，某个工具执行失败可能导致缺少 tool result
  /// - 上下文压缩边界可能割裂 tool_calls 和 tool_result
  /// - 数据库加载时可能丢失某些消息
  /// - OpenAI API 强制要求 tool_calls 和 tool_result 必须成对出现
  ///
  /// 这个清理是防御性的，无论是否触发压缩都应该执行。
  List<Map<String, dynamic>> _cleanOrphanedToolMessages(
    List<Map<String, dynamic>> messages,
  ) {
    // 1. 收集所有 assistant 消息中的 tool_call_id
    final validToolCallIds = <String>{};
    for (final msg in messages) {
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        for (final tc in msg['tool_calls'] as List) {
          final id = tc['id'] as String?;
          if (id != null) validToolCallIds.add(id);
        }
      }
    }

    // 2. 收集所有 tool 结果消息的 tool_call_id
    final validToolResultIds = <String>{};
    for (final msg in messages) {
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        if (toolCallId != null) validToolResultIds.add(toolCallId);
      }
    }

    // 3. 过滤掉孤立的消息
    final cleaned = messages.where((msg) {
      // 移除没有对应工具调用的 tool 结果
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        final isValid =
            toolCallId != null && validToolCallIds.contains(toolCallId);
        if (!isValid) {
          AppLogger.instance.log(
            '[Compactor] 🗑️  清理孤立的工具结果: tool_call_id=$toolCallId',
          );
        }
        return isValid;
      }

      // 移除没有对应工具结果的 assistant tool_calls
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        final toolCalls = msg['tool_calls'] as List;
        // 检查所有 tool_calls 是否都有对应的结果
        final allToolCallsHaveResults = toolCalls.every((tc) {
          final id = tc['id'] as String?;
          return id != null && validToolResultIds.contains(id);
        });

        if (!allToolCallsHaveResults) {
          final missingIds = toolCalls
              .where((tc) {
                final id = tc['id'] as String?;
                return id == null || !validToolResultIds.contains(id);
              })
              .map((tc) => tc['id'] as String?)
              .where((id) => id != null)
              .join(', ');
          AppLogger.instance.log(
            '[Compactor] 🗑️  清理缺少工具结果的 assistant 消息: tool_call_ids=[$missingIds]',
          );
          return false;
        }
      }

      return true;
    }).toList();

    final removedCount = messages.length - cleaned.length;
    if (removedCount > 0) {
      AppLogger.instance.log('[Compactor] ✅ 完整性检查: 移除 $removedCount 条孤立消息');
    }

    return cleaned;
  }

  /// 找到保真区的起始位置：保留最近 keepRecentTurns 轮完整对话
  /// 一轮 = user + assistant（可能包含中间的 tool 消息）
  ///
  /// 算法思想：
  /// - **压缩策略**：按轮数保留，而非按 token 百分比
  ///   * 原因：轮数更稳定、可预测。无论每轮长短，都保留固定轮数的完整上下文
  ///   * 例如：100 轮对话，无论总计 10K 还是 1M tokens，都保留最近 6 轮
  ///
  /// - **触发阈值**：当前对话达到 contextWindow * 50% 时触发压缩
  ///   * 例如：DeepSeek V3 (1M) → 达到 500K tokens 时压缩
  ///
  /// - **压缩结果**：system + 总结 + 最近 6 轮
  ///   * 旧对话 → 生成总结 (~500 tokens) + 沉淀到向量数据库
  ///   * 保真区 → 完整保留，包含工具调用和结果
  ///
  /// - **工具调用成对保留**：双向检查确保 tool_calls 和 tool_results 不被割裂
  ///   1. 向前扩展：保真区的 tool 结果 → 对应的 assistant tool_calls 也保留
  ///   2. 向后检查：保真区的 assistant tool_calls → 对应的 tool 结果也必须在保真区
  ///
  /// 特别处理：双向检查确保工具调用和工具结果成对保留。
  /// 1. 向前扩展：保真区的 tool 结果 → 对应的 assistant tool_calls 也保留
  /// 2. 向后检查：保真区的 assistant tool_calls → 对应的 tool 结果也必须在保真区
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

    // ─── 第一步：向前扩展（保真区的 tool 结果 → assistant tool_calls）───
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
          '将在压缩时移除: ${toolCallIdsInRecent.join(", ")}',
        );
      }
    }

    // ─── 第二步：向后检查（保真区的 assistant tool_calls → tool 结果）───
    // 收集保真区内所有 assistant 的 tool_call_ids
    final assistantToolCallIds = <String>{};
    for (int i = boundaryIdx; i < messages.length; i++) {
      final msg = messages[i];
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        final toolCalls = msg['tool_calls'] as List;
        for (final tc in toolCalls) {
          final id = tc['id'] as String?;
          if (id != null) assistantToolCallIds.add(id);
        }
      }
    }

    // 检查这些 tool_call_ids 是否都有对应的 tool 结果在保真区
    if (assistantToolCallIds.isNotEmpty) {
      // 收集保真区内的 tool 结果
      final toolResultIds = <String>{};
      for (int i = boundaryIdx; i < messages.length; i++) {
        final msg = messages[i];
        if (msg['role'] == 'tool') {
          final toolCallId = msg['tool_call_id'] as String?;
          if (toolCallId != null) toolResultIds.add(toolCallId);
        }
      }

      // 找出缺失的 tool 结果
      final missingToolResults = assistantToolCallIds.difference(toolResultIds);
      if (missingToolResults.isNotEmpty) {
        AppLogger.instance.log(
          '[Compactor] 警告: 发现 ${missingToolResults.length} 个工具调用缺少对应结果，'
          '将移除这些 assistant 消息: ${missingToolResults.join(", ")}',
        );
        print('[Compactor] ⚠️  检测到工具调用-结果不匹配，将在压缩时修复');
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

  /// 生成对话摘要（Cache-Aligned 方式）
  ///
  /// 复用原始消息上下文结构，将摘要指令作为普通 user 消息追加，
  /// 使得前缀部分能够命中 LLM 的 prompt cache，节省 90-97% 的摘要成本。
  ///
  /// [allMessages] 完整的原始消息列表（包含 system + 历史 + 保真区）
  /// [compressibleEnd] 可压缩区的结束位置索引
  Future<String> _summarizeCacheAligned(
    List<Map<String, dynamic>> allMessages,
    int compressibleEnd,
  ) async {
    final compressible = allMessages.sublist(1, compressibleEnd);

    // ─── 估算对比数据（不实际调用，仅用于日志展示）───
    final traditionalEstimate = _estimateTraditionalSummaryCost(compressible);
    final cacheAlignedEstimate = _estimateCacheAlignedSummaryCost(
      allMessages,
      compressibleEnd,
    );

    final separator = '[Compactor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    final comparison = '[Compactor] 📊 摘要策略对比（基于估算）:';
    final traditional =
        '[Compactor]   传统方式: ~$traditionalEstimate tokens (独立请求，0% 缓存)';
    final cacheAligned =
        '[Compactor]   Cache-Aligned: ~$cacheAlignedEstimate tokens (复用上下文，预期 95%+ 缓存命中)';
    final savings =
        '[Compactor]   💰 预估节省: ${traditionalEstimate - cacheAlignedEstimate} tokens (${((1 - cacheAlignedEstimate / traditionalEstimate) * 100).toStringAsFixed(1)}%)';

    // 写入日志文件
    AppLogger.instance.log(separator);
    AppLogger.instance.log(comparison);
    AppLogger.instance.log(traditional);
    AppLogger.instance.log(cacheAligned);
    AppLogger.instance.log(savings);
    AppLogger.instance.log('[Compactor] ');

    // 同时输出到终端
    print(separator);
    print(comparison);
    print(traditional);
    print(cacheAligned);
    print(savings);
    print('');

    // 检查冷却期
    if (_shouldSkipLLMCompression()) {
      AppLogger.instance.log('[Compactor] 跳过 LLM 压缩，使用降级方案');
      print('[Compactor] 跳过 LLM 压缩，使用降级方案');
      return _fallbackSummary(compressible);
    }

    try {
      // ─── 构造 Cache-Aligned 请求 ───
      // 保留原始消息结构（包括 system、所有历史消息），仅追加摘要指令
      final summaryInstruction = StringBuffer();

      // 如果有上一次的总结，先展示它
      if (_previousSummary != null && _previousSummary!.isNotEmpty) {
        summaryInstruction.write(
          '【上一次的总结】：\n'
          '$_previousSummary\n\n'
          '现在，请基于上述历史总结，更新并补充下面新对话的内容。\n\n',
        );
      }

      summaryInstruction.write(
        '请为${_previousSummary != null ? "新" : "上述"}对话生成一段简洁摘要。要求：\n'
        '- 保留关键信息：用户需求、决策、结论\n'
        '- 保留技术细节：文件、函数、配置、错误\n'
        '- 保留进度状态：已完成、正在进行、待办\n',
      );

      if (_previousSummary != null) {
        summaryInstruction.write(
          '- 将新信息与历史总结合并，保持时间顺序\n'
          '- 去除重复信息，突出新的进展\n',
        );
      }

      summaryInstruction.write(
        '- 使用要点格式，控制在 ${_previousSummary != null ? "600" : "400"} 字以内\n'
        '- 直接输出摘要，不要前缀或解释',
      );

      final summaryRequest = [
        ...allMessages.sublist(0, compressibleEnd), // 复用前缀，命中 cache
        {'role': 'user', 'content': summaryInstruction.toString()},
      ];

      AppLogger.instance.log('[Compactor] ⏱️  调用 LLM 生成摘要...');
      print('[Compactor] ⏱️  调用 LLM 生成摘要...');

      final response = await llm.chat(summaryRequest);
      final summary = response.content?.trim() ?? '';

      // ─── 记录真实 token 使用情况 ───
      _recordTokenUsage(summaryRequest, summary);

      // 如果 LLM 返回了 usage 信息，展示真实效果
      if (response.usage != null) {
        final usage = response.usage!;
        final cachedTokens = usage.promptCacheReadInputTokens ?? 0;
        final inputTokens = usage.promptTokens ?? 0;
        final totalInput = cachedTokens + inputTokens;
        final cacheHitRate = totalInput > 0
            ? (cachedTokens / totalInput * 100)
            : 0;

        final completed = '[Compactor] ✅ 摘要生成完成: ${summary.length} 字符';
        final apiResponse = '[Compactor] 📈 真实 API 响应:';
        final cached = '[Compactor]     缓存命中: $cachedTokens tokens';
        final input = '[Compactor]     实际输入: $inputTokens tokens';
        final output =
            '[Compactor]     输出: ${usage.completionTokens ?? 0} tokens';
        final hitRate =
            '[Compactor]     缓存命中率: ${cacheHitRate.toStringAsFixed(1)}% ✨';

        // 写入日志文件
        AppLogger.instance.log(completed);
        AppLogger.instance.log(apiResponse);
        AppLogger.instance.log(cached);
        AppLogger.instance.log(input);
        AppLogger.instance.log(output);
        AppLogger.instance.log(hitRate);

        // 同时输出到终端
        print(completed);
        print(apiResponse);
        print(cached);
        print(input);
        print(output);
        print(hitRate);
      } else {
        final completed = '[Compactor] ✅ 摘要生成完成: ${summary.length} 字符';
        AppLogger.instance.log(completed);
        print(completed);
      }

      AppLogger.instance.log('[Compactor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('[Compactor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 保存总结供下次迭代使用
      if (summary.isNotEmpty) {
        _previousSummary = summary;
        // 成功则重置失败计数
        _compressionFailures = 0;
        _lastFailureTime = null;
      }

      return summary.isEmpty ? _fallbackSummary(compressible) : summary;
    } catch (e) {
      // 记录失败
      _compressionFailures++;
      _lastFailureTime = DateTime.now();

      final error = '[Compactor] ❌ 摘要生成失败 (第 $_compressionFailures 次): $e';
      final fallback = '[Compactor] 使用降级方案（消息预览）';
      final cooldown =
          '[Compactor] ⏱️  下次冷却时间: ${1 << _compressionFailures} 分钟';
      final endSeparator = '[Compactor] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

      // 写入日志文件
      AppLogger.instance.log(error);
      AppLogger.instance.log(fallback);
      AppLogger.instance.log(cooldown);
      AppLogger.instance.log(endSeparator);

      // 同时输出到终端
      print(error);
      print(fallback);
      print(cooldown);
      print(endSeparator);

      return _fallbackSummary(compressible);
    }
  }

  /// 估算传统方式的摘要成本（不实际调用 LLM）
  int _estimateTraditionalSummaryCost(List<Map<String, dynamic>> messages) {
    final text = _messagesToText(messages);
    // 传统方式：system prompt (~300 tokens) + 格式化文本 + 输出 (~400 tokens)
    return 300 + _estimateStringTokens(text) + 400;
  }

  /// 估算 Cache-Aligned 方式的成本（不实际调用 LLM）
  int _estimateCacheAlignedSummaryCost(
    List<Map<String, dynamic>> allMessages,
    int compressibleEnd,
  ) {
    // Cache-Aligned 方式：仅摘要指令 (~150 tokens) + 输出 (~400 tokens)
    // 前缀部分预期 95%+ 命中缓存，不计入实际成本
    return 150 + 400;
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

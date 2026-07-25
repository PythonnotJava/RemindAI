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
  ///
  /// 注意：比例是基于"可用输入空间"，不是总上下文窗口
  /// 可用输入 = contextWindow - maxOutputTokens (12.8K)
  ///
  /// 例如 claude-opus-4 (200K):
  /// - 可用输入: 200K - 12.8K = 187.2K
  /// - 触发阈值: 187.2K * 0.60 = 112.3K (约 56% 总上下文)
  static const Map<String, double> _modelThresholds = {
    'claude-opus-4': 0.60,
    'claude-sonnet-4': 0.60,
    'claude-3-5-sonnet': 0.60,
    'claude-3-opus': 0.60,
    'gpt-5': 0.50, // 提前触发，预留更多空间
    'gpt-4': 0.60,
    'gpt-4-turbo': 0.60,
    'deepseek': 0.60,
    'gemini-1.5-pro': 0.60,
    'gemini-2.0': 0.60,
  };

  /// 小上下文模型的阈值下限（避免压缩后空间不足）
  static const double _smallContextFloor = 0.75;
  static const int _smallContextLimit = 512000; // 512K

  /// 基于模型 context window 计算动态阈值的比例。
  /// 触发压缩 = (contextWindow - maxOutputTokens) * ratio。
  /// 预留空间给：LLM 输出 (maxOutputTokens) + 多轮对话累积。
  static const double _defaultThresholdRatio = 0.60;

  /// 预留给 LLM 输出的 token 空间
  static const int _maxOutputTokens = 12800;

  /// 动态计算出的实际阈值
  ///
  /// 计算公式：
  /// ```
  /// 可用输入空间 = contextWindow - maxOutputTokens
  /// 触发阈值 = 可用输入空间 * ratio
  /// ```
  ///
  /// 例如（128K 上下文）：
  /// ```
  /// 可用输入: 128K - 12.8K = 115.2K
  /// 触发阈值: 115.2K * 0.60 = 69.1K (约 54% 总上下文)
  /// ```
  ///
  /// 为什么预留输出空间？
  /// - 避免压缩后 + LLM 输出 > contextWindow 导致溢出
  /// - 确保 LLM 始终有足够空间生成完整回复
  int get effectiveThreshold {
    if (tokenThreshold > 0) return tokenThreshold;

    final ctx = contextWindow > 0
        ? contextWindow
        : _inferDefaultContextWindow(modelName);

    // 可用输入空间 = 总上下文 - 预留输出空间
    final availableInput = ctx - _maxOutputTokens;

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

    return (availableInput * ratio).toInt();
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

  /// 上次压缩时的消息轮数（用于检测频繁压缩）
  int _lastCompressionRound = 0;

  /// 频繁压缩计数器（连续 < 10 轮就压缩的次数）
  int _frequentCompressionCount = 0;

  /// 工具结果压缩阈值（单个工具结果超过此大小时压缩）
  static const int _toolResultCompressionThreshold = 5000;

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
    // ─── 优化 1: 工具结果智能压缩 ───
    // 在清理孤立消息之前，先压缩超大工具结果
    messages = _compressLargeToolResults(messages);

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

    // ─── 预检：保真区大小检查 ───
    final recentTokens = _estimateTokens(recent);
    final threshold = effectiveThreshold;
    final systemTokens = _estimateTokens([system]);
    final summaryEstimate = 800; // 预估摘要大小

    final projectedTotal = systemTokens + summaryEstimate + recentTokens;
    if (projectedTotal > threshold) {
      final ctx = contextWindow > 0
          ? contextWindow
          : _inferDefaultContextWindow(modelName);
      final ratio = (projectedTotal / ctx * 100).toStringAsFixed(1);

      AppLogger.instance.log('[Compactor] ⚠️  预检失败: 保真区过大');
      AppLogger.instance.log(
        '[Compactor] 预计压缩后: $projectedTotal tokens > 阈值 $threshold '
        '($ratio% 上下文占用)',
      );
      AppLogger.instance.log(
        '[Compactor] 保真区: ${recent.length}条消息, 约$recentTokens tokens',
      );
      AppLogger.instance.log(
        '[Compactor] ⚠️  继续压缩但可能无效，建议减少 keepRecentTurns (当前=$keepRecentTurns)',
      );
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
    final oldTokens = _estimateTokens(messages);
    AppLogger.instance.log(
      '[Compactor] 压缩完成: ${messages.length}条→${cleaned.length}条, '
      '估算 token: $oldTokens → $newTokens',
    );

    // ─── 第五步：验证压缩效果 ───
    // 如果压缩后仍然超过阈值，说明保真区太大，压缩无效
    if (newTokens > threshold) {
      final ctx = contextWindow > 0
          ? contextWindow
          : _inferDefaultContextWindow(modelName);
      final ratio = (newTokens / ctx * 100).toStringAsFixed(1);

      AppLogger.instance.log(
        '[Compactor] ⚠️  压缩后仍超阈值: $newTokens > $threshold '
        '($ratio% 上下文占用)',
      );
      AppLogger.instance.log(
        '[Compactor] 原因: 保真区过大 (${recent.length}条消息, 约${_estimateTokens(recent)} tokens)',
      );
      AppLogger.instance.log(
        '[Compactor] 建议: 减少 keepRecentTurns (当前=$keepRecentTurns) '
        '或增加上下文窗口',
      );

      // 注意：仍然返回压缩结果（至少移除了一些旧内容）
      // 但标记已压缩，避免下次立即重复压缩
    }

    // ─── 优化 2: 检测频繁压缩并自适应调整 ───
    _detectAndAdjustFrequentCompression(messages);

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

  /// 清理孤立的工具调用和工具结果（防御层 1/3）
  ///
  /// 算法思想：
  /// 1. 收集所有 assistant 消息中的 tool_call_id（有效的工具调用）
  /// 2. 收集所有 tool 消息中的 tool_call_id（有效的工具结果）
  /// 3. 移除没有对应工具调用的 tool 结果（孤立结果）
  /// 4. 从 assistant 消息中移除没有对应结果的 tool_calls（不删除整个消息）
  ///
  /// 为什么需要这个？
  /// - 并行工具调用时，某个工具执行失败可能导致缺少 tool result
  /// - 上下文压缩边界可能割裂 tool_calls 和 tool_result
  /// - 数据库加载时可能丢失某些消息
  /// - OpenAI API 强制要求 tool_calls 和 tool_result 必须成对出现
  ///
  /// **重要**：此方法会移除**部分匹配**的 tool_calls。即使一个 assistant 消息
  /// 有 3 个 tool_calls 但只有 2 个对应结果，也会只保留那 2 个，删除第 3 个。
  /// 这确保了发送给 LLM 的消息绝对不会有孤立的 tool_calls。
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

    // 3. 清理消息
    final cleaned = <Map<String, dynamic>>[];
    int removedToolResults = 0;
    int removedToolCalls = 0;

    for (final msg in messages) {
      // 移除没有对应工具调用的 tool 结果
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        final isValid =
            toolCallId != null && validToolCallIds.contains(toolCallId);
        if (!isValid) {
          AppLogger.instance.log(
            '[Compactor] 🗑️  清理孤立的工具结果: tool_call_id=$toolCallId',
          );
          removedToolResults++;
          continue; // 跳过这个消息
        }
        cleaned.add(msg);
        continue;
      }

      // 清理 assistant 消息中没有对应结果的 tool_calls
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        final toolCalls = msg['tool_calls'] as List;

        // 过滤出有对应结果的 tool_calls
        final validToolCalls = toolCalls.where((tc) {
          final id = tc['id'] as String?;
          return id != null && validToolResultIds.contains(id);
        }).toList();

        // 如果有 tool_calls 被移除，记录日志
        if (validToolCalls.length < toolCalls.length) {
          final removedIds = toolCalls
              .where((tc) {
                final id = tc['id'] as String?;
                return id == null || !validToolResultIds.contains(id);
              })
              .map((tc) => tc['id'] as String?)
              .where((id) => id != null)
              .join(', ');
          AppLogger.instance.log(
            '[Compactor] 🗑️  移除孤立的工具调用: tool_call_ids=[$removedIds]',
          );
          removedToolCalls += (toolCalls.length - validToolCalls.length);
        }

        // 创建清理后的消息副本
        final cleanedMsg = Map<String, dynamic>.from(msg);

        if (validToolCalls.isEmpty) {
          // 所有 tool_calls 都被移除
          cleanedMsg.remove('tool_calls');

          // 如果 content 也为空，插入占位符
          final content = cleanedMsg['content'];
          if (content == null ||
              (content is String && content.trim().isEmpty) ||
              (content is List && content.isEmpty)) {
            cleanedMsg['content'] = '(tool calls removed during compression)';
          }
        } else if (validToolCalls.length < toolCalls.length) {
          // ✅ 部分 tool_calls 被移除：只保留有结果的
          // 这是关键修复：即使只缺少一个结果，也只保留有结果的 tool_calls
          cleanedMsg['tool_calls'] = validToolCalls;
          AppLogger.instance.log(
            '[Compactor] ⚠️  部分工具调用配对不完整: 保留 ${validToolCalls.length}/${toolCalls.length} 个',
          );
        } else {
          // 全部有效
          cleanedMsg['tool_calls'] = validToolCalls;
        }

        cleaned.add(cleanedMsg);
        continue;
      }

      // 其他消息保持原样
      cleaned.add(msg);
    }

    if (removedToolResults > 0 || removedToolCalls > 0) {
      AppLogger.instance.log(
        '[Compactor] ✅ 完整性检查: 移除 $removedToolResults 个孤立工具结果, '
        '$removedToolCalls 个孤立工具调用',
      );
    }

    return cleaned;
  }

  /// 找到保真区的起始位置：保留最近 keepRecentTurns 轮完整对话
  /// 一轮 = user + assistant（可能包含中间的 tool 消息）
  ///
  /// ## 压缩策略设计
  ///
  /// ### 触发时机
  /// - 当估算 tokens 超过可用输入空间的 60% 时触发压缩
  /// - 可用输入空间 = contextWindow - maxOutputTokens (预留输出空间)
  /// - 例如：128K 上下文，预留 12.8K 输出 → 触发阈值 = 115.2K * 0.60 = 69.1K
  ///
  /// ### 保留策略（Token 预算驱动 + 轮数下限）
  ///
  /// **主标准：Token 预算**
  /// - 目标预算：可用输入空间的 25% (例如 128K → 28.8K)
  /// - 软上限：目标预算 * 1.5 = 37.5% (例如 128K → 43.2K)
  /// - 从后向前累积消息，直到达到软上限
  ///
  /// **辅助标准：轮数下限**
  /// - 至少保留 2 轮完整对话（无论 token 大小）
  /// - 防止极端情况下保留内容过少
  ///
  /// **取两者中更保守的（保留更多）**
  /// - 如果 token 预算只能保留 1 轮，但轮数下限要求 2 轮 → 保留 2 轮
  /// - 如果 2 轮只有 10K tokens，但 token 预算允许 28K → 保留更多轮
  ///
  /// ### 为什么是 25% 预算？
  ///
  /// ```
  /// 触发阈值: 60% 可用输入 (例如 69K)
  /// 压缩到:   25% 可用输入 (例如 29K)
  /// 释放空间: 40K tokens
  /// 效果:     足够多轮对话后才再次触发，避免频繁压缩
  /// ```
  ///
  /// ### 软上限 1.5x 的作用
  ///
  /// 避免切割超大单消息（如长工具结果）：
  /// ```
  /// 预算 28K，最后一条消息 15K：
  /// - 如果严格限制 28K → 不保留这条 → 可能丢失重要上下文
  /// - 软上限 43K → 可以保留 → 压缩后 43K (33.5%)
  /// ```
  ///
  /// ### 边界对齐
  ///
  /// **向前扩展保护**：
  /// - 如果保真区包含 tool 结果，向前扩展到对应的 assistant tool_calls
  /// - 确保工具调用组 (assistant + tool results) 的完整性
  ///
  /// ### 压缩效果
  ///
  /// - 压缩后占用：25-37.5% 可用输入空间 (约 20-30% 总上下文)
  /// - 剩余空间：60-75K tokens (足够输出 + 多轮对话)
  /// - 避免溢出：始终预留 maxOutputTokens (12.8K) 给 LLM 输出
  ///
  /// ### 对比其他方案
  ///
  /// - **按轮数保留（旧方案）**：固定保留 4 轮，但轮数长短不一，压缩效果不可预测
  /// - **Token 预算驱动（方案 A）**：压缩后空间可预测，释放足够缓冲
  /// - **Hermes 方案**：类似 token 预算，但配置更复杂（预算 20K，软上限 1.5x，轮数下限 3）
  /// - **LangChain 方案**：保留最近 10% 上下文（约 12.8K），但依赖 AI 主动触发压缩
  ///
  /// 我们的方案结合了 token 预算的可预测性和轮数下限的保底保护，同时预留输出空间避免溢出。
  int _findRecentBoundary(List<Map<String, dynamic>> messages) {
    // ─── 第一步：计算 Token 预算 ───
    final ctx = contextWindow > 0
        ? contextWindow
        : _inferDefaultContextWindow(modelName);

    // 预留输出空间（避免 LLM 输出时溢出）
    final maxOutputTokens = 12800; // 约 9600 个中文字
    final availableInput = ctx - maxOutputTokens;

    // Token 预算：可用输入空间的 25%
    final budget = (availableInput * 0.25).toInt();
    final softCeiling = (budget * 1.5).toInt(); // 软上限：37.5%

    // ─── 第二步：按 Token 预算从后向前累积 ───
    int idxByBudget = messages.length - 1;
    int accumulated = 0;
    int messagesInTail = 0;

    while (idxByBudget > 0) {
      final msgTokens = _estimateTokens([messages[idxByBudget]]);

      // 如果超过软上限且已保护至少 3 条消息，停止
      if (accumulated + msgTokens > softCeiling && messagesInTail >= 3) {
        break;
      }

      accumulated += msgTokens;
      messagesInTail++;
      idxByBudget--;
    }

    // ─── 第三步：按轮数下限保护（至少保留 2 轮）───
    final minTurns = 2;
    int turnsFound = 0;
    int idxByTurns = messages.length - 1;

    while (idxByTurns > 0 && turnsFound < minTurns) {
      final role = messages[idxByTurns]['role'] as String?;
      if (role == 'user') turnsFound++;
      idxByTurns--;
    }

    // ─── 第四步：取两者中更保守的（保留更多）───
    int boundaryIdx = max(idxByBudget, idxByTurns) + 1;

    // 确保不超出范围
    boundaryIdx = max(1, min(boundaryIdx, messages.length - 1));

    // ─── 记录策略选择日志 ───
    final strategyUsed = (idxByBudget >= idxByTurns) ? 'Token预算' : '轮数下限';
    final recentTokens = accumulated;
    final recentPercent = (recentTokens / availableInput * 100).toStringAsFixed(
      1,
    );

    AppLogger.instance.log(
      '[Compactor] 保留策略: $strategyUsed | '
      '预算=${(budget / 1024).toStringAsFixed(1)}K, '
      '软上限=${(softCeiling / 1024).toStringAsFixed(1)}K, '
      '实际保留=${(recentTokens / 1024).toStringAsFixed(1)}K ($recentPercent% 可用输入)',
    );

    // ─── 第五步：向前扩展（保真区的 tool 结果 → assistant tool_calls）───
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

  // ─── 优化方法 ─────────────────────────────────────────────

  /// 优化 1: 压缩超大工具结果
  ///
  /// ## 问题背景
  /// 在 Loop 长对话中，批量工具调用可能产生大量输出：
  /// - 例如：读取 20 个文件，每个 3000 字符 = 60K tokens
  /// - 这些都在保真区（最近消息），无法通过常规压缩移除
  /// - 导致保真区过大，压缩无效，可能溢出上下文窗口
  ///
  /// ## 解决方案
  /// 检测单个工具结果是否超过阈值（5000 字符），如果超过：
  /// 1. 只保留前 500 字符（足够 LLM 理解结果概要）
  /// 2. 添加元信息：完整长度 + token 数
  /// 3. 完整内容可选地沉淀到记忆系统（TODO）
  ///
  /// ## 效果
  /// - 降低 70-90% 工具结果占用
  /// - 解决单轮超大输出问题
  /// - 保留关键信息（前 500 字通常包含核心内容）
  ///
  /// ## 示例
  /// ```
  /// 原始工具结果（10000 字符）：
  /// "这是一个很长的文件内容... [9500 字符] ...结束"
  ///
  /// 压缩后（500 字符）：
  /// "这是一个很长的文件内容... [450 字符]
  /// [工具结果已自动压缩，完整内容 10000 字符 / 约 7.5K tokens]"
  /// ```
  List<Map<String, dynamic>> _compressLargeToolResults(
    List<Map<String, dynamic>> messages,
  ) {
    int compressedCount = 0;
    int savedTokens = 0;

    final processed = <Map<String, dynamic>>[];
    for (final msg in messages) {
      if (msg['role'] == 'tool') {
        final content = msg['content'];
        if (content is String &&
            content.length > _toolResultCompressionThreshold) {
          // ─── 计算节省的 token 数 ───
          // 完整内容的 tokens - 压缩后内容的 tokens
          final originalTokens = _estimateStringTokens(content);
          final compressedTokens = _estimateStringTokens(
            content.substring(0, 500),
          );
          savedTokens += originalTokens - compressedTokens;
          compressedCount++;

          // ─── 创建压缩后的消息 ───
          // 保留：前 500 字符 + 元信息（长度、token 数）
          final compressed = Map<String, dynamic>.from(msg);
          compressed['content'] =
              '${content.substring(0, 500)}...\n\n'
              '[工具结果已自动压缩，完整内容 ${content.length} 字符 / '
              '约 ${(originalTokens / 1024).toStringAsFixed(1)}K tokens]';
          processed.add(compressed);
        } else {
          // 未超过阈值，保持原样
          processed.add(msg);
        }
      } else {
        // 非工具消息，保持原样
        processed.add(msg);
      }
    }

    // ─── 记录压缩效果 ───
    if (compressedCount > 0) {
      AppLogger.instance.log(
        '[Compactor] 🗜️ 压缩了 $compressedCount 个超大工具结果, '
        '节省约 ${(savedTokens / 1024).toStringAsFixed(1)}K tokens',
      );
    }

    return processed;
  }

  /// 优化 2: 检测频繁压缩并自适应调整保真区大小
  ///
  /// ## 问题背景
  /// 在 Loop 快速迭代中，可能出现频繁压缩：
  /// - 压缩后释放空间，但很快又超阈值
  /// - 每次压缩需要 3-10 秒（LLM 生成摘要）
  /// - 频繁压缩导致 10% 时间在压缩，影响性能
  ///
  /// ## 根本原因
  /// 保真区（keepRecentTurns）设置过大：
  /// - 保真区占用 40K tokens
  /// - 压缩后：摘要 800 tokens + 保真区 40K = 40.8K
  /// - 仅释放 10K 空间，迭代 5 轮就又超阈值
  /// - 导致频繁压缩
  ///
  /// ## 解决方案
  /// 检测压缩间隔，自动发现频繁压缩模式：
  /// 1. 记录每次压缩时的轮数（_lastCompressionRound）
  /// 2. 下次压缩时计算间隔：currentRound - lastRound
  /// 3. 如果间隔 < 10 轮 → 认为频繁
  /// 4. 连续 2 次频繁 → 发出调优建议
  ///
  /// ## 为什么是"建议"而不是"自动调整"？
  /// - keepRecentTurns 是 final 字段（构造时设定）
  /// - 自动调整需要改为可变字段（影响架构设计）
  /// - 当前提供日志建议，由开发者决定是否调整配置
  /// - 更安全：避免运行时自动修改，保持行为可预测
  ///
  /// ## 效果
  /// - 实时发现频繁压缩问题
  /// - 提供明确的调优方向（降低 keepRecentTurns）
  /// - 避免性能下降（< 10% → < 5% 时间在压缩）
  ///
  /// ## 示例日志
  /// ```
  /// [Compactor] ⚠️ 检测到频繁压缩: 距上次仅 7 轮（计数: 1）
  /// [Compactor] ⚠️ 检测到频繁压缩: 距上次仅 6 轮（计数: 2）
  /// [Compactor] 💡 建议: 降低 keepRecentTurns 从 4 至 3，以减少频繁压缩
  /// ```
  ///
  /// ## 参数说明
  /// - allMessages: 当前完整的消息列表，用于计算轮数
  void _detectAndAdjustFrequentCompression(
    List<Map<String, dynamic>> allMessages,
  ) {
    // ─── 第一步：计算当前轮数 ───
    // 轮数 = user 消息的数量（每个 user 消息代表一轮对话）
    int currentRound = 0;
    for (final msg in allMessages) {
      if (msg['role'] == 'user') currentRound++;
    }

    // ─── 第二步：检测频繁压缩 ───
    if (_lastCompressionRound > 0) {
      // 计算距离上次压缩的轮数
      final roundsSinceLastCompression = currentRound - _lastCompressionRound;

      // ─── 判断：间隔 < 10 轮认为是频繁压缩 ───
      // 为什么是 10 轮？
      // - 正常情况：压缩后释放 40-50K tokens，足够 15-20 轮
      // - < 10 轮就再次压缩 → 说明保真区过大，释放空间不足
      if (roundsSinceLastCompression < 10) {
        _frequentCompressionCount++;
        AppLogger.instance.log(
          '[Compactor] ⚠️  检测到频繁压缩: 距上次仅 $roundsSinceLastCompression 轮 '
          '(计数: $_frequentCompressionCount)',
        );

        // ─── 第三步：连续频繁 → 发出调优建议 ───
        // 连续 2 次频繁压缩 → 说明配置不合理，需要调整
        if (_frequentCompressionCount >= 2 && keepRecentTurns > 2) {
          final oldKeep = keepRecentTurns;
          final newKeep = oldKeep - 1;

          AppLogger.instance.log(
            '[Compactor] 💡 建议: 降低 keepRecentTurns 从 $oldKeep 至 $newKeep，'
            '以减少频繁压缩',
          );

          // 重置计数器，避免重复建议
          // （开发者收到建议后，会调整配置或接受当前频率）
          _frequentCompressionCount = 0;
        }
      } else {
        // ─── 压缩间隔正常（≥ 10 轮）→ 重置计数器 ───
        // 说明当前配置合理，或者已经调整过了
        _frequentCompressionCount = 0;
      }
    }

    // ─── 第四步：记录本次压缩轮数 ───
    // 供下次压缩时计算间隔
    _lastCompressionRound = currentRound;
  }
}

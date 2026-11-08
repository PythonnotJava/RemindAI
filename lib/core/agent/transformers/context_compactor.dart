import 'dart:math';

import '../../isolate/compute_service.dart';
import '../../llm/context_capacity.dart';
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
  /// 注意：比例是基于"可用输入空间"（有效上下文 - 输出预留），不是总上下文窗口。
  /// 数值整体从 0.60 下调到 0.45：压缩后还要放摘要 + 保真区 + 输出，
  /// 贴着上限触发会压完立刻再超。
  static const Map<String, double> _modelThresholds = {
    'claude-opus-4': 0.45,
    'claude-sonnet-4': 0.45,
    'claude-3-5-sonnet': 0.45,
    'claude-3-opus': 0.45,
    'gpt-5': 0.40, // 提前触发，预留更多空间
    'gpt-4': 0.45,
    'gpt-4-turbo': 0.45,
    'deepseek': 0.45,
    'gemini-1.5-pro': 0.45,
    'gemini-2.0': 0.45,
  };

  /// 基于"有效上下文"计算动态阈值的默认比例。
  ///
  /// 触发压缩 = (有效上下文 - 输出预留) * ratio。
  ///
  /// 用 0.45 而不是原来的 0.60：压缩后要同时容纳【摘要 + 保真区(最多 37.5%)
  /// + 输出预留】，贴着上限触发会导致"压完立刻又超"。
  static const double _defaultThresholdRatio = 0.45;

  /// 模型卡没配 maxOutputTokens 时的输出预留（token）
  static const int _defaultMaxOutputTokens = 12800;

  /// 摘要请求自身的输入上限（token）。超过就分块滚动摘要，
  /// 避免"用更大的请求去解决请求太大"。
  static const int _maxSummaryInputTokens = 24000;

  /// 分块摘要时每块的 token 预算
  static const int _summaryChunkTokens = 16000;

  /// 触发阈值之外必须留出的余量（token），防止比例被模型表/小上下文下限放大到贴边
  static const int _thresholdSafetyMargin = 8000;

  /// 动态计算出的实际阈值
  ///
  /// 计算公式：
  /// ```
  /// 有效上下文 = min(模型窗口, 接入实际上限)
  /// 可用输入空间 = 有效上下文 - 输出预留
  /// 触发阈值 = 可用输入空间 * ratio
  /// ```
  ///
  /// 为什么用"有效上下文"而不是模型窗口？
  /// - 1M 上下文模型按 0.6 算要 59 万 token 才压缩，第三方中转早就 400 了；
  /// - 真正限制请求大小的是接入方，不是模型理论值。
  ///
  /// 为什么要预留输出空间？
  /// - 避免压缩后 + LLM 输出 > 上下文上限导致溢出
  int get effectiveThreshold {
    if (tokenThreshold > 0) return tokenThreshold;

    final availableInput = max(
      1,
      effectiveContextWindow - effectiveOutputReserve,
    );

    // 1. 获取模型特定阈值（匹配任意子串）
    double ratio = _defaultThresholdRatio;
    for (final entry in _modelThresholds.entries) {
      if (modelName.toLowerCase().contains(entry.key.toLowerCase())) {
        ratio = entry.value;
        break;
      }
    }

    // 2. 运行时收紧（上游报过上下文超限后会打对折）
    ratio *= _ratioScale;

    var threshold = (availableInput * ratio).toInt();

    // 4. 安全夹紧：不管比例怎么算，都不能吃掉最后的输出余量
    final maxAllowed = availableInput - _thresholdSafetyMargin;
    if (maxAllowed > 0 && threshold > maxAllowed) {
      threshold = maxAllowed;
    }
    return threshold < 0 ? 0 : threshold;
  }

  /// 实际生效的输出预留：优先用模型卡配置
  int get outputReserve =>
      maxOutputTokens > 0 ? maxOutputTokens : _defaultMaxOutputTokens;

  /// 预算计算用的输出预留。
  ///
  /// 不允许超过有效上下文的一半：模型卡若填了不合理的大值（如 1M 窗口配
  /// 256K 输出），会把"可用输入"压成 0 → 每轮都触发压缩且压不出效果。
  int get effectiveOutputReserve {
    final raw = outputReserve;
    final cap = (effectiveContextWindow * 0.5).toInt();
    return raw > cap ? cap : raw;
  }

  /// 有效上下文 = min(模型卡窗口, 实际可用上限)
  ///
  /// 上限来源优先级：运行时学到的 > 显式传入 > 注册表推算 > 构建设时快照 > 不封顶。
  /// 直接查注册表（而不是只用构造时快照）是为了让"别的会话学到的容量"立刻生效。
  int get effectiveContextWindow {
    final modelCtx = contextWindow > 0
        ? contextWindow
        : _inferDefaultContextWindow(modelName);

    int? cap = _learnedCapacity;
    if (cap == null && relayContextCap != null && relayContextCap! > 0) {
      cap = relayContextCap;
    }
    final key = capacityKey;
    if (cap == null && key != null) {
      final auto = ContextCapacityRegistry.instance.resolveCapForKey(
        key,
        contextWindow,
      );
      if (auto > 0) cap = auto;
    }
    if (cap == null && autoCapacity != null && autoCapacity! > 0) {
      cap = autoCapacity;
    }

    if (cap != null && cap > 0 && cap < modelCtx) return cap;
    return modelCtx;
  }

  /// 运行时更新容量（AgentLoop 从上游报文学到后调用）
  void applyCapacity(int? cap) {
    if (cap == null || cap <= 0) return;
    if (_learnedCapacity == cap) return;
    _learnedCapacity = cap;
    // 容量变小意味着阈值要立刻按新口径重算，允许本轮再压一次
    _compactedThisRound = false;
    AppLogger.instance.log(
      '[Compactor] 🧭 容量更新为 $cap tokens，新阈值≈$effectiveThreshold',
    );
  }

  /// 运行时收紧压缩阈值 —— 上游报"上下文超限"后由 AgentLoop 调用。
  ///
  /// 静态推算永远猜不准各家中转的真实上限，这条才是自适应兜底。
  void tightenThreshold([double scale = 0.5]) {
    final next = max(0.2, _ratioScale * scale);
    _ratioScale = next;
    _compactedThisRound = false;
    _forceNextCompaction = true;
    AppLogger.instance.log(
      '[Compactor] ⏬ 阈值收紧: ratioScale=$_ratioScale, '
      '新阈值≈$effectiveThreshold tokens',
    );
  }

  /// 压缩后保留最近多少轮对话（一轮 = user + assistant）
  ///
  /// 可变：检测到"频繁压缩"时会自动下调（见 [_detectAndAdjustFrequentCompression]）。
  int keepRecentTurns;

  /// 摘要的目标最大 token 数
  final int summaryMaxTokens;

  /// 模型卡配置的最大输出 token（0 = 未配置，回落默认 12800）。
  ///
  /// 必须跟模型卡走：用户把"最大输出"改成 256K 后，阈值仍按 12.8K 预留
  /// 会让触发点偏晚，最后直接撞上游的上下文/输出上限。
  final int maxOutputTokens;

  /// 接入方（中转/网关）实际能接受的上下文上限。
  ///
  /// - `null`（默认）：自动推算（见 [autoCapacity] 与运行时学习的 `applyCapacity`）
  /// - `> 0`：用户/调用方显式指定，优先级高于自动值
  /// - `<= 0`：同样视为"不封顶"
  final int? relayContextCap;

  /// 自动推算出的容量（来自 ContextCapacityRegistry），null = 尚无线索
  final int? autoCapacity;

  /// 运行时从上游报文学到的容量（最高优先级，覆盖上面两者）
  int? _learnedCapacity;

  /// 容量学习标识（`baseUrl|modelId`）；null 表示不做学习（测试/未接线）
  final String? capacityKey;

  /// 从上游错误报文学习真实上下文上限，学到就立刻生效
  ///
  /// 返回学到的上限（null = 报文里没有可用的数字）。
  int? learnCapacityFromError(String errorText) {
    final key = capacityKey;
    if (key == null) return null;
    final parsed = ContextCapacityRegistry.instance.learnFromErrorForKey(
      key: key,
      errorText: errorText,
      cardContextWindow: contextWindow,
    );
    if (parsed != null) applyCapacity(parsed);
    return parsed;
  }

  /// 记录一次成功请求的实测输入量（用于向上校准容量）
  void observeUsage(int? promptTokens) {
    final key = capacityKey;
    if (key == null || promptTokens == null || promptTokens <= 0) return;
    ContextCapacityRegistry.instance.observeSuccessForKey(
      key: key,
      promptTokens: promptTokens,
      measured: true,
      cardContextWindow: contextWindow,
    );
    // 实测可能把容量抬高（模型卡填小了 / 起点猜低了）
    final cap = ContextCapacityRegistry.instance.resolveCapForKey(
      key,
      contextWindow,
    );
    if (_learnedCapacity == null || cap > _learnedCapacity!) {
      _learnedCapacity = cap;
    }
  }

  /// 摘要是否优先复用前缀（有机会命中 provider 的 prompt cache）。
  ///
  /// 上游不支持缓存时，复用前缀反而更贵，可关掉退回"只发可压缩文本"。
  final bool cacheAlignedSummary;

  /// 运行时阈值缩放（<1 表示更早压缩），由 [tightenThreshold] 调整
  double _ratioScale = 1.0;

  /// 下一次 pipeline 调用是否强制压缩（不看阈值，用于超限后的自适应重试）
  bool _forceNextCompaction = false;

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

  /// 上一次沉淀到记忆的批次指纹（防止同一批内容重复写入记忆）
  String? _lastSunkFingerprint;

  /// 工具结果压缩阈值（单个工具结果超过此大小时压缩）
  static const int _toolResultCompressionThreshold = 5000;

  /// 上下文压缩器构造函数
  ///
  /// 参数说明：
  /// - [tokenThreshold]: 手动指定的压缩触发阈值（0 表示自动计算）
  /// - [contextWindow]: 模型上下文窗口（模型卡的理论值）
  /// - [maxOutputTokens]: 模型卡配置的最大输出 token（0 = 用默认 12800）
  /// - [relayContextCap]: 接入方实际能接受的上限（0 = 不封顶，默认 128K）
  /// - [keepRecentTurns]: 保留最近 N 轮对话（默认 4 轮）
  /// - [summaryMaxTokens]: 总结的最大长度（默认 800 tokens）
  ///
  /// 阈值计算见 [effectiveThreshold]：基于 `min(模型窗口, 接入上限) - 输出预留`。
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
    this.maxOutputTokens = 0,
    this.relayContextCap,
    this.autoCapacity,
    this.capacityKey,
    this.cacheAlignedSummary = true,
  });

  @override
  String get name => 'ContextCompactor';

  @override
  bool shouldActivate(List<Map<String, dynamic>> messages) {
    // 上游报过"上下文超限"后会置位，本次强制压缩（不看阈值）
    if (_forceNextCompaction) {
      _forceNextCompaction = false;
      AppLogger.instance.log('[Compactor] ⚡ 强制压缩（上下文超限自适应重试）');
      return true;
    }
    // 消息太少不需要压缩
    if (messages.length < (keepRecentTurns * 2 + 3)) return false;
    // 估算 token 超阈值才激活
    final threshold = effectiveThreshold;
    final tokens = _estimateTokens(messages);
    if (tokens > threshold && !_compactedThisRound) {
      // 计算实际使用的比例（用于日志）
      final ctx = effectiveContextWindow;
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
      final ctx = effectiveContextWindow;
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

    // ─── 第一步：生成摘要（先摘要，后沉淀）───
    // 顺序很重要：摘要失败会走降级摘要，此时消息同样会被压缩掉，所以沉淀要在其后；
    // 反之先沉淀再摘要，若摘要失败则上下文其实仍在，记忆里却多一份 → 重复沉淀。
    final compressibleEnd = messages.length - recentCount;
    final summary = await _summarizeCacheAligned(messages, compressibleEnd);

    // ─── 第二步：沉淀到长期记忆（此时已确定原始消息要被丢弃）───
    await _sinkIfNeeded(compressible);

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
      final ctx = effectiveContextWindow;
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
    // 与 effectiveThreshold 用同一套口径：有效上下文 - 输出预留
    final availableInput = max(
      1,
      effectiveContextWindow - effectiveOutputReserve,
    );

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
  /// 带指纹去重的沉淀入口。
  ///
  /// 摘要失败重试、或同一批消息在相邻两次压缩里重复出现时，
  /// 不该把同样的内容反复写进长期记忆（会造成重复召回、虚增记忆库）。
  Future<void> _sinkIfNeeded(List<Map<String, dynamic>> compressible) async {
    if (memoryManager == null || memoryCollection == null) return;
    if (compressible.isEmpty) return;

    final last = compressible.last;
    final fingerprint =
        '${compressible.length}:${last['role']}:${(last['content'] ?? '').toString().hashCode}';
    if (fingerprint == _lastSunkFingerprint) {
      AppLogger.instance.log('[Compactor] 沉淀跳过: 与上次批次相同');
      return;
    }
    _lastSunkFingerprint = fingerprint;
    await _sinkToMemory(compressible);
  }

  Future<void> _sinkToMemory(List<Map<String, dynamic>> messages) async {
    AppLogger.instance.log('[Compactor] 开始记忆沉淀: ${messages.length}条消息');

    // 按 6 条为一组（约 3 轮对话）批量处理
    const batchSize = 6;
    int stored = 0;

    for (int i = 0; i < messages.length; i += batchSize) {
      final batch = messages.sublist(i, min(i + batchSize, messages.length));
      final text = messagesToText(batch);
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

  /// 摘要入口 —— 先按"摘要请求自身预算"决定单次还是分块。
  ///
  /// 压缩的本质是"上下文太大"，如果摘要请求把整个可压缩区再完整发一次，
  /// 就是"用更大的请求解决请求太大"：一旦接近上游上限，摘要必失败，
  /// 只能退到降级摘要（信息大量丢失）。所以这里先限流。
  Future<String> _summarizeCacheAligned(
    List<Map<String, dynamic>> allMessages,
    int compressibleEnd,
  ) async {
    final compressible = allMessages.sublist(1, compressibleEnd);
    if (compressible.isEmpty) return _previousSummary ?? '';

    final compressibleTokens = _estimateTokens(compressible);
    if (compressibleTokens > _maxSummaryInputTokens) {
      return _summarizeInChunks(compressible, compressibleTokens);
    }
    return _summarizeOnce(allMessages, compressibleEnd, compressible);
  }

  /// 分块滚动摘要：每块 ≤ [_summaryChunkTokens]，逐块合并进已有摘要。
  ///
  /// 好处：摘要请求大小恒定（不随历史长度增长），超长会话也能压。
  Future<String> _summarizeInChunks(
    List<Map<String, dynamic>> compressible,
    int totalTokens,
  ) async {
    final chunks = chunkByTokenBudget(compressible, _summaryChunkTokens);
    AppLogger.instance.log(
      '[Compactor] 🧩 分块摘要: 可压缩区约 $totalTokens tokens '
      '> 上限 $_maxSummaryInputTokens，切成 ${chunks.length} 块',
    );

    var merged = _previousSummary ?? '';
    for (var i = 0; i < chunks.length; i++) {
      final chunkText = messagesToText(chunks[i]);
      final prompt = <Map<String, dynamic>>[
        {'role': 'system', 'content': _summarySystemPrompt},
        {
          'role': 'user',
          'content':
              '${merged.isEmpty ? '' : '【已有摘要】\n$merged\n\n'}'
              '【本段对话】\n$chunkText\n\n'
              '请按固定小节输出"合并后"的最新摘要（不是本段的摘要）。',
        },
      ];
      try {
        final response = await llm.chat(prompt);
        final text = response.content?.trim() ?? '';
        _recordTokenUsage(prompt, text);
        if (text.isNotEmpty) {
          merged = text;
          _previousSummary = merged;
          _compressionFailures = 0;
          _lastFailureTime = null;
        }
        AppLogger.instance.log(
          '[Compactor] 🧩 第 ${i + 1}/${chunks.length} 块完成'
          '（累计摘要 ${merged.length} 字符）',
        );
      } catch (e) {
        _compressionFailures++;
        _lastFailureTime = DateTime.now();
        AppLogger.instance.log(
          '[Compactor] ❌ 分块摘要第 ${i + 1}/${chunks.length} 块失败: $e',
        );
        final fallback = buildFallbackSummary(chunks[i]);
        if (fallback.isNotEmpty) {
          merged = merged.isEmpty ? fallback : '$merged\n$fallback';
        }
      }
    }

    if (merged.isEmpty) return buildFallbackSummary(compressible);
    return merged;
  }

  /// 把消息按 token 预算切成若干块（保持原始顺序，单条超预算也单独成块）。
  List<List<Map<String, dynamic>>> chunkByTokenBudget(
    List<Map<String, dynamic>> messages,
    int budget,
  ) {
    final chunks = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    var used = 0;
    for (final msg in messages) {
      final tokens = _estimateTokens([msg]);
      if (current.isNotEmpty && used + tokens > budget) {
        chunks.add(current);
        current = <Map<String, dynamic>>[];
        used = 0;
      }
      current.add(msg);
      used += tokens;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  /// 摘要的固定小节（结构化，避免"要点格式"随手丢关键约束）
  static const String _summarySystemPrompt = '你是一个对话压缩器。只输出摘要正文，不要解释、不要寒暄。';

  /// 生成对话摘要（单次请求）
  ///
  /// [allMessages] 完整的原始消息列表（包含 system + 历史 + 保真区）
  /// [compressibleEnd] 可压缩区的结束位置索引
  Future<String> _summarizeOnce(
    List<Map<String, dynamic>> allMessages,
    int compressibleEnd,
    List<Map<String, dynamic>> compressible,
  ) async {
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
      return buildFallbackSummary(compressible);
    }

    try {
      // ─── 构造摘要指令（固定小节，避免随手丢关键约束）───
      final summaryInstruction = StringBuffer();
      if (_previousSummary != null && _previousSummary!.isNotEmpty) {
        summaryInstruction.write(
          '【已有摘要】\n$_previousSummary\n\n'
          '请把"本段新对话"合并进上面的摘要，输出更新后的完整摘要。\n\n',
        );
      }
      summaryInstruction.write(
        '把对话压成一份"交接摘要"，供后续继续工作时直接使用。'
        '严格按下面小节输出，没有内容写"无"，不要额外解释：\n'
        '## 目标与用户约束\n'
        '（用户要什么、明确禁止/必须遵守的约束）\n'
        '## 已完成\n'
        '## 涉及的文件 / 命令 / 配置\n'
        '（路径、关键参数，便于后续直接引用）\n'
        '## 未完成与待办\n'
        '## 关键决策与失败原因\n'
        '（做了哪些取舍、什么试过但失败了，避免重复踩坑）\n\n'
        '总长不超过 ${_previousSummary != null ? 800 : 600} 字，直接输出摘要正文。',
      );

      // ─── 两种请求形态 ───
      // cacheAligned：复用整个前缀（有机会命中 provider 的 prompt cache）
      // 传统：只发可压缩区文本（上游不支持缓存时更便宜、也更不容易超限）
      final List<Map<String, dynamic>> summaryRequest;
      if (cacheAlignedSummary) {
        summaryRequest = [
          ...allMessages.sublist(0, compressibleEnd), // 复用前缀，命中 cache
          {'role': 'user', 'content': summaryInstruction.toString()},
        ];
      } else {
        summaryRequest = [
          {'role': 'system', 'content': _summarySystemPrompt},
          {
            'role': 'user',
            'content':
                '${summaryInstruction.toString()}\n\n'
                '【本段对话】\n${messagesToText(compressible)}',
          },
        ];
      }

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

      return summary.isEmpty ? buildFallbackSummary(compressible) : summary;
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

      return buildFallbackSummary(compressible);
    }
  }

  /// 估算传统方式的摘要成本（不实际调用 LLM）
  int _estimateTraditionalSummaryCost(List<Map<String, dynamic>> messages) {
    final text = messagesToText(messages);
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

  /// 降级摘要 —— LLM 摘要不可用时的"结构化应急摘要"。
  ///
  /// 原实现只取前 20 条消息、每条 50 字，长任务里等于把历史烧成灰。
  /// 这里改为抽取"继续工作真正需要的东西"：用户需求/约束、出现过的文件路径、
  /// 最近几条结论，总长 ≤ 2000 字符。
  String buildFallbackSummary(List<Map<String, dynamic>> messages) {
    final userLines = <String>[];
    final assistantLines = <String>[];
    final paths = <String>{};
    final pathRe = RegExp(
      r'[A-Za-z]:\\[^\s<>|?*]+'
      r'|[\w\-.]+\.(?:dart|html|js|ts|py|json|md|ya?ml|css|txt|xlsx|docx|png|exe)\b',
    );

    for (final msg in messages) {
      final role = msg['role'] as String? ?? '';
      final content = msg['content'];
      final text = content is String ? content : '';
      if (text.isEmpty) continue;
      for (final match in pathRe.allMatches(text)) {
        if (paths.length >= 30) break;
        paths.add(match.group(0)!);
      }
      if (role == 'user') {
        userLines.add(_clipLine(text, 200));
      } else if (role == 'assistant') {
        assistantLines.add(_clipLine(text, 300));
      }
    }

    final buffer = StringBuffer('[自动降级摘要：LLM 摘要不可用，以下为结构化抽取，可能不完整]\n');
    if (userLines.isNotEmpty) {
      buffer.writeln('## 用户需求（节选）');
      for (final line in userLines.take(10)) {
        buffer.writeln('- $line');
      }
    }
    if (paths.isNotEmpty) {
      buffer.writeln('## 涉及的文件 / 路径');
      for (final path in paths.take(20)) {
        buffer.writeln('- $path');
      }
    }
    if (assistantLines.isNotEmpty) {
      buffer.writeln('## 最近结论（节选）');
      final tail = assistantLines.length > 3
          ? assistantLines.sublist(assistantLines.length - 3)
          : assistantLines;
      for (final line in tail) {
        buffer.writeln('- $line');
      }
    }

    final result = buffer.toString().trim();
    if (userLines.isEmpty && paths.isEmpty && assistantLines.isEmpty) return '';
    return result.length > 2000 ? '${result.substring(0, 2000)}…' : result;
  }

  static String _clipLine(String text, int max) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length > max
        ? '${normalized.substring(0, max)}…'
        : normalized;
  }

  /// 将消息列表格式化为可读文本（供 LLM 阅读）
  String messagesToText(
    List<Map<String, dynamic>> messages, {
    int maxCharsPerMessage = 500,
  }) {
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
      if (text.length > maxCharsPerMessage) {
        text = '${text.substring(0, maxCharsPerMessage)}...';
      }
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
          // ─── 头 + 尾保留 ───
          // 工具结果有用的部分常在尾部（测试失败列表、堆栈末尾、编译错误最后一行），
          // 只留开头会把这些全砍掉。
          const headChars = 400;
          const tailChars = 400;
          final head = content.substring(0, min(headChars, content.length));
          final tail = content.length > headChars + tailChars
              ? content.substring(content.length - tailChars)
              : '';
          final omitted = content.length - head.length - tail.length;

          final originalTokens = _estimateStringTokens(content);
          final replacement = StringBuffer(head);
          if (tail.isNotEmpty) {
            replacement
              ..write('\n\n…[中间省略 $omitted 字符]…\n\n')
              ..write(tail);
          }
          replacement.write(
            '\n\n[工具结果已自动压缩，原始 ${content.length} 字符 / '
            '约 ${(originalTokens / 1024).toStringAsFixed(1)}K tokens]',
          );

          final compressedTokens = _estimateStringTokens(
            replacement.toString(),
          );
          savedTokens += originalTokens - compressedTokens;
          compressedCount++;

          final compressed = Map<String, dynamic>.from(msg);
          compressed['content'] = replacement.toString();
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

        // ─── 第三步：连续频繁 → 真正下调保真区 ───
        // 连续 2 次频繁压缩 → 说明保真区偏大、释放空间不足，这里直接调小
        // （以前只打一条"建议"日志，从不生效，等于没有自适应）
        if (_frequentCompressionCount >= 2 && keepRecentTurns > 2) {
          final oldKeep = keepRecentTurns;
          keepRecentTurns = max(2, keepRecentTurns - 1);
          AppLogger.instance.log(
            '[Compactor] 🔧 已自动下调 keepRecentTurns: $oldKeep → $keepRecentTurns'
            '（缓解频繁压缩）',
          );
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

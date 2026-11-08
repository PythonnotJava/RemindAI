import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger/app_logger.dart';

/// 上下文容量估算器（自学习，无需用户配置）
///
/// 目标：不使用户手填"接入方实际上下文上限"，由代码自己推算。
///
/// 四个来源，按可信度从高到低：
/// 1. **失败报文**（最可信）：上游 400/413 里通常写着真实上限，
///    例如 `This model's maximum context length is 131072 tokens`。
/// 2. **成功实测**：请求成功且上游回传 `prompt_tokens`，说明至少能装这么多，
///    容量下限 = 实测值 × 1.15（留余量）。
/// 3. **模型卡**：用户填的 `context_window`；若明显是"理论值"（如 1M）则打折起步，
///    因为中转很少真给到理论值。
/// 4. **保守兜底**：都拿不到时 128K。
///
/// 容量状态按 `baseUrl|modelId` 存放并持久化（见 [toJson]/[load]），
/// 所以"学过一次"重启后依然有效。
class ContextCapacity {
  /// 学到的绝对上限（来自失败报文），null 表示还没撞过墙
  final int? rejectedCap;

  /// 实测成功过的最大输入 token 数
  final int observedMax;

  /// 从磁盘读到的、上次算出的容量（跨重启兜底）
  final int? cachedCap;

  const ContextCapacity({
    this.rejectedCap,
    this.observedMax = 0,
    this.cachedCap,
  });

  Map<String, dynamic> toJson() => {
    if (rejectedCap != null) 'rejected': rejectedCap,
    if (observedMax > 0) 'observed': observedMax,
    if (cachedCap != null) 'cap': cachedCap,
  };

  factory ContextCapacity.fromJson(Map<String, dynamic> json) =>
      ContextCapacity(
        rejectedCap: json['rejected'] as int?,
        observedMax: json['observed'] as int? ?? 0,
        cachedCap: json['cap'] as int?,
      );
}

/// 全局单例：按 (baseUrl, modelId) 记录并推算上下文容量
class ContextCapacityRegistry {
  ContextCapacityRegistry._();
  static final ContextCapacityRegistry instance = ContextCapacityRegistry._();

  final Map<String, ContextCapacity> _states = {};

  /// 与模型卡理论值相比，超过这个阈值就认为"是理论值不可信"，起步打折
  static const int _theoreticalWindowThreshold = 400000;

  /// 起步猜测：理论窗口偏大时，先假设这个值
  static const int _optimisticGuess = 256000;

  /// 实测成功后向上抬容量的余量系数
  static const double _observedHeadroom = 1.15;

  /// 完全无信息时的兜底
  static const int _unknownCardWindow = 128000;

  String _key(String baseUrl, String modelId) =>
      '${_normalize(baseUrl)}|$modelId';

  /// 外部构造容量标识（供 Agent/Compactor 层持久化自己的学习状态）
  static String keyOf(String baseUrl, String modelId) =>
      ContextCapacityRegistry.instance._key(baseUrl, modelId);

  String _normalize(String baseUrl) {
    var url = baseUrl.trim().toLowerCase();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// 读取当前状态（不存在则空状态）
  ContextCapacity stateOf(String baseUrl, String modelId) =>
      _states[_key(baseUrl, modelId)] ?? const ContextCapacity();

  /// 按 key 读取状态
  ContextCapacity stateOfKey(String key) =>
      _states[key] ?? const ContextCapacity();

  /// 推算"实际可用总上下文"（按 key）
  ///
  /// - 有失败报文 → 直接用它（最可信）
  /// - 否则有实测成功值 → 按实测放大
  /// - 否则有缓存值 → 用缓存
  /// - 否则按模型卡推断（大窗口打折）
  int resolveCapForKey(String key, int cardContextWindow) {
    final state = _states[key] ?? const ContextCapacity();

    if (state.rejectedCap != null) {
      return _withObservedFloor(state.rejectedCap!, state.observedMax);
    }
    if (state.observedMax > 0) {
      final fromObserved = (state.observedMax * _observedHeadroom).round();
      final guess = _guessFromCard(cardContextWindow);
      // 实测只向上抬，不向下压（向下只认失败报文）
      return max(fromObserved, guess);
    }
    final cached = state.cachedCap;
    if (cached != null && cached > 0) return cached;
    return _guessFromCard(cardContextWindow);
  }

  /// 推算"实际可用总上下文"
  int resolveCap({
    required String baseUrl,
    required String modelId,
    required int cardContextWindow,
  }) => resolveCapForKey(_key(baseUrl, modelId), cardContextWindow);

  /// 容量不能低于"已经成功用过的量"
  int _withObservedFloor(int cap, int observedMax) {
    if (observedMax <= 0) return cap;
    final floor = (observedMax * 1.02).round();
    return cap < floor ? floor : cap;
  }

  int _guessFromCard(int cardContextWindow) {
    if (cardContextWindow <= 0) return _unknownCardWindow;
    if (cardContextWindow <= _theoreticalWindowThreshold) {
      return cardContextWindow;
    }
    // 1M 这类"理论值"：中转极少真给到，先保守起步，靠实测/报错纠正
    return min(cardContextWindow, _optimisticGuess);
  }

  /// 记录一次成功请求（按 key）
  ///
  /// [measured] 为 true 表示来自上游真实 usage；估算值不参与向上抬容量，
  /// 避免"估算器偏大 → 容量被抬到不真实的高度 → 下次必 400"。
  void observeSuccessForKey({
    required String key,
    required int promptTokens,
    required bool measured,
    required int cardContextWindow,
  }) {
    if (promptTokens <= 0 || !measured) return;
    final prev = _states[key] ?? const ContextCapacity();
    final nextObserved = max(prev.observedMax, promptTokens);
    if (nextObserved == prev.observedMax) return;

    _states[key] = ContextCapacity(
      rejectedCap: prev.rejectedCap,
      observedMax: nextObserved,
      cachedCap: resolveCapForKey(key, cardContextWindow),
    );
    _persist();
    AppLogger.instance.log(
      '[Capacity] 📈 实测输入 $promptTokens tokens'
      '（历史最大 $nextObserved，容量≈${resolveCapForKey(key, cardContextWindow)}）',
    );
  }

  /// 记录一次成功请求（按 baseUrl + modelId）
  void observeSuccess({
    required String baseUrl,
    required String modelId,
    required int promptTokens,
    required bool measured,
    required int cardContextWindow,
  }) => observeSuccessForKey(
    key: _key(baseUrl, modelId),
    promptTokens: promptTokens,
    measured: measured,
    cardContextWindow: cardContextWindow,
  );

  /// 从上游错误报文里学习真实上限（按 key）
  ///
  /// 返回学到的上限（null = 报文里没提到数字）。
  int? learnFromErrorForKey({
    required String key,
    required String errorText,
    required int cardContextWindow,
  }) {
    final parsed = parseLimitFromError(errorText);
    if (parsed == null) return null;

    final prev = _states[key] ?? const ContextCapacity();
    // 多次报错取更小值（不同入口可能给出不同上限）
    final chosen = prev.rejectedCap == null
        ? parsed
        : min(prev.rejectedCap!, parsed);
    _states[key] = ContextCapacity(
      rejectedCap: chosen,
      observedMax: prev.observedMax,
      cachedCap: chosen,
    );
    _persist();
    AppLogger.instance.log(
      '[Capacity] 📉 从上游报文学到上下文上限: $chosen tokens（原文: '
      '${errorText.length > 160 ? '${errorText.substring(0, 160)}…' : errorText}）',
    );
    return chosen;
  }

  /// 从上游错误报文里学习真实上限（按 baseUrl + modelId）
  int? learnFromError({
    required String baseUrl,
    required String modelId,
    required String errorText,
    required int cardContextWindow,
  }) => learnFromErrorForKey(
    key: _key(baseUrl, modelId),
    errorText: errorText,
    cardContextWindow: cardContextWindow,
  );

  /// 从错误报文里解析上下文上限（多家措辞，宽匹配但只认"明确的数字"）
  ///
  /// 覆盖：OpenAI 新旧格式、DeepSeek、Anthropic、OpenRouter、vLLM、常见中文中转。
  static int? parseLimitFromError(String errorText) {
    if (errorText.isEmpty) return null;

    final patterns = <RegExp>[
      // "maximum context length is 131072 tokens"
      RegExp(
        r'max(?:imum)?\s+context\s+(?:length|window)[^\d]{0,40}(\d{3,})',
        caseSensitive: false,
      ),
      // "context length of only 65536 tokens"
      RegExp(
        r'context\s+(?:length|window)\s+of\s+(?:only\s+)?(\d{3,})',
        caseSensitive: false,
      ),
      // "prompt is too long: 210000 tokens > 200000 maximum"
      RegExp(
        r'\d{1,}\s*tokens?\s*>\s*(\d{3,})\s*(?:maximum|max|limit)',
        caseSensitive: false,
      ),
      // "exceeds the maximum allowed context of 128000"
      RegExp(
        r'(?:exceeds?|above|over)\s+(?:the\s+)?(?:maximum|max|limit)[^\d]{0,30}(\d{3,})',
        caseSensitive: false,
      ),
      // "max_tokens: 2000000 > 128000" / "limit of 128000"
      RegExp(r'limit\s+of\s+(\d{3,})', caseSensitive: false),
      // 中文中转常见："最大上下文长度 128000" / "超出 128000 tokens"
      RegExp(r'(?:最大|上限|限制)[^\d]{0,12}(\d{3,})'),
      RegExp(r'超出[^\d]{0,12}(\d{3,})'),
    ];

    for (final re in patterns) {
      final match = re.firstMatch(errorText);
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!);
      if (value == null) continue;
      // 太小的数字（如 HTTP 400、128）不是上下文上限
      if (value < 1000) continue;
      return value;
    }
    return null;
  }

  /// 从持久化数据恢复
  void load(Map<String, dynamic> json) {
    _states.clear();
    for (final entry in json.entries) {
      if (entry.value is! Map) continue;
      try {
        _states[entry.key] = ContextCapacity.fromJson(
          (entry.value as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // 单条损坏不影响其它
      }
    }
    if (_states.isNotEmpty) {
      AppLogger.instance.log('[Capacity] 已恢复 ${_states.length} 条容量记录');
    }
  }

  /// 导出给持久化层
  Map<String, dynamic> toJson() =>
      _states.map((key, value) => MapEntry(key, value.toJson()));

  // ─── 持久化 ────────────────────────────────────────────────

  bool _loaded = false;

  /// 启动时加载一次（幂等；失败只记日志，绝不影响主流程）
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _stateFile();
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) load(raw.cast<String, dynamic>());
    } catch (e) {
      AppLogger.instance.log('[Capacity] 读取状态失败（忽略）: $e');
    }
  }

  static Future<File> _stateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'context_capacity.json'));
  }

  void _persist() => unawaited(_saveNow());

  Future<void> _saveNow() async {
    try {
      final file = await _stateFile();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(toJson()),
      );
    } catch (e) {
      AppLogger.instance.log('[Capacity] 保存状态失败（忽略）: $e');
    }
  }

  /// 仅供测试：清空内存状态
  void resetForTest() => _states.clear();
}

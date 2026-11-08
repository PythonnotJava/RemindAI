import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// 任务分档 —— 同一套循环，用不同的预算档位驱动。
///
/// 过去的 UI 只有一个"最大轮次"滑块，用户很难判断"50 轮"到底是多还是少；
/// 分档把"这是一次简单问答 / 日常编码 / 大型重构"映射成一组具体预算，
/// 用户可以只看档位，具体数字仍然可见。
enum AgentTaskTier {
  /// 简单问答 / 单文件小改
  quick,

  /// 日常编码 / 多文件小功能
  coding,

  /// 大型重构 / 跨模块迁移
  refactor,

  /// 用户手动指定具体数字
  custom,
}

/// 预算终止原因 —— "说人话"的失败归因。
///
/// 归因必须可解释：用户看到"达到上限"时要能知道到底是哪种上限、
/// 更需要知道是"没进展"而不是"轮次不够"。
enum BudgetStopReason {
  /// 未触发
  none,

  /// 触软上限，且上一轮没有任何进展
  noProgress,

  /// 触软上限，且上一轮全是在重复已做过的调用（空转）
  repeatedOperations,

  /// 达到轮次硬上限
  hardRounds,

  /// 达到工具调用总数上限
  toolCalls,

  /// 达到墙钟时间上限
  wallClock,

  /// 达到 token 上限
  tokens,

  /// 外层重新规划次数达到上限
  planningBudget,

  /// 用户中断
  userCancelled,
}

extension BudgetStopReasonLocale on BudgetStopReason {
  bool get isNone => this == BudgetStopReason.none;

  /// 一句话归因（面向用户，直接进检查点摘要）。
  String get humanReason {
    switch (this) {
      case BudgetStopReason.none:
        return '未触发预算限制';
      case BudgetStopReason.noProgress:
        return '触到软上限后，连续多轮没有产生任何实质进展'
            '（没有新动作、没有新产物、没有文件改动）。'
            '注意这不是硬上限——补充一句方向后「追加预算继续」可以接着跑';
      case BudgetStopReason.repeatedOperations:
        return '触到软上限后，连续多轮都在重复之前做过的工具调用且结果没有变化（空转）。'
            '换个实现思路或指定文件后再「追加预算继续」';
      case BudgetStopReason.hardRounds:
        return '轮次达到硬上限';
      case BudgetStopReason.toolCalls:
        return '工具调用总数达到上限';
      case BudgetStopReason.wallClock:
        return '执行时间达到预算上限';
      case BudgetStopReason.tokens:
        return '累计 token 达到预算上限';
      case BudgetStopReason.planningBudget:
        return '重新规划次数达到上限（外层预算用完）';
      case BudgetStopReason.userCancelled:
        return '用户中断';
    }
  }

  /// 是否属于"执行预算"维度（而非规划预算）。
  bool get isExecution => switch (this) {
    BudgetStopReason.noProgress ||
    BudgetStopReason.repeatedOperations ||
    BudgetStopReason.hardRounds ||
    BudgetStopReason.toolCalls ||
    BudgetStopReason.wallClock ||
    BudgetStopReason.tokens => true,
    _ => false,
  };
}

/// 执行预算的四个维度上限。
///
/// - [softRounds] / [softToolCalls]：软上限。到线不是"停"，而是"检查一次进展"：
///   有进展 → 原地续预算（不消耗外层重规划轮）；无进展 → 停。
/// - [hardRounds] / [hardToolCalls]：硬上限，到了必停，不再自动续。
/// - [wallClock] / [tokens]：全局硬约束。
class ExecutionLimits {
  final int softRounds;
  final int hardRounds;
  final int softToolCalls;
  final int hardToolCalls;
  final Duration wallClock;
  final int tokens;

  const ExecutionLimits({
    required this.softRounds,
    required this.hardRounds,
    required this.softToolCalls,
    required this.hardToolCalls,
    required this.wallClock,
    required this.tokens,
  });

  /// 简单问答：软 8 轮 / 硬 20 轮（对应 ③ 的 10～20 轮）
  static const ExecutionLimits quick = ExecutionLimits(
    softRounds: 8,
    hardRounds: 20,
    softToolCalls: 12,
    hardToolCalls: 30,
    wallClock: Duration(minutes: 5),
    tokens: 1200000,
  );

  /// 日常编码：软 30 轮 / 硬 100 轮（① 的"软 30"，③ 的 60～100 轮）
  static const ExecutionLimits coding = ExecutionLimits(
    softRounds: 30,
    hardRounds: 100,
    softToolCalls: 60,
    hardToolCalls: 320,
    wallClock: Duration(minutes: 45),
    tokens: 6000000,
  );

  /// 大型重构：软 60 轮 / 硬 200 轮（① 的"硬 120～200"，③ 的 150～200 轮）
  static const ExecutionLimits refactor = ExecutionLimits(
    softRounds: 60,
    hardRounds: 200,
    softToolCalls: 150,
    hardToolCalls: 800,
    wallClock: Duration(minutes: 120),
    tokens: 15000000,
  );

  static ExecutionLimits of(AgentTaskTier tier) {
    switch (tier) {
      case AgentTaskTier.quick:
        return quick;
      case AgentTaskTier.coding:
        return coding;
      case AgentTaskTier.refactor:
        return refactor;
      case AgentTaskTier.custom:
        return coding;
    }
  }

  ExecutionLimits copyWith({
    int? softRounds,
    int? hardRounds,
    int? softToolCalls,
    int? hardToolCalls,
    Duration? wallClock,
    int? tokens,
  }) => ExecutionLimits(
    softRounds: softRounds ?? this.softRounds,
    hardRounds: hardRounds ?? this.hardRounds,
    softToolCalls: softToolCalls ?? this.softToolCalls,
    hardToolCalls: hardToolCalls ?? this.hardToolCalls,
    wallClock: wallClock ?? this.wallClock,
    tokens: tokens ?? this.tokens,
  );

  /// 追加预算（用户点"追加预算继续"时用）：按比例放大软/硬上限与其它维度。
  ///
  /// 传 [used]（停止那一刻的预算快照）时，token 维度会按**已观测的消耗速率**
  /// 重新投影，而不是简单乘一个系数。原因是：
  ///
  /// - 累计 token ≈ 轮次 × 每轮重发的上下文长度，而上下文本身随历史增长，
  ///   所以累计消耗近似 **轮次²** 增长。只按 1.6 倍抬 token，跑几十轮后
  ///   必然又出现"轮次还剩一大半、token 却先见底"。
  /// - 停止原因若正好是 token，抬完只是同一个数字，点一次就是"原地再停一次"
  ///   （线上现象：追加预算后第 1 轮立刻又被 token 掐断）。
  ///
  /// 因此 token 新上限用"已观测消耗"做平方增长投影：跑满新轮次上限大约
  /// 要花多少 token，就给多少，并保证它一定大于已用 token。
  ExecutionLimits extended({
    double roundFactor = 0.6,
    double toolCallFactor = 0.6,
    double timeFactor = 0.5,
    double tokenFactor = 0.6,
    BudgetSnapshot? used,
  }) {
    final addHardRounds = math.max(5, (hardRounds * roundFactor).round());
    final addHardCalls = math.max(10, (hardToolCalls * toolCallFactor).round());
    final newHardRounds = hardRounds + addHardRounds;
    final roundRatio = hardRounds <= 0 ? 1.0 : newHardRounds / hardRounds;

    // 轮次放大 r 倍 ⇒ token 至少按 r² 放大，才不会先于轮次上限触发。
    final tokenGrow = math.max(tokenFactor, roundRatio) * roundRatio;
    var newTokens = math.max(
      tokens + (tokens * tokenFactor).round(),
      (tokens * tokenGrow).round(),
    );

    final usedTokens = used?.tokens ?? 0;
    final usedRounds = used?.usedRounds ?? 0;
    if (usedTokens > 0 && usedRounds > 0) {
      // 平方增长投影：按当前"每轮真实开销"推算跑满新轮次上限要花多少。
      //
      // 关键：只乘**已用 token**，绝不乘上一版上限。乘上限会形成
      // "每次追加都在已膨胀的上限上再乘一次"的几何放大（连点三次就能
      // 把预算推到几亿 token，等于取消预算）。
      final projected = usedTokens * math.pow(newHardRounds / usedRounds, 2);
      newTokens = math.max(
        // 只增不减：抬完的额度不允许比上一次更小（否则用户会觉得"越追加越少"）。
        tokens,
        math.max(
          // 下限：必须比已用的多，否则点一次就是原地再停一次。
          usedTokens * 1.5,
          // 上限：只是兜底，最多给到已用 token 的 8 倍，避免异常放大。
          math.min(projected.toDouble(), usedTokens * 8),
        ),
      ).round();
    }

    return ExecutionLimits(
      softRounds: math.min(newHardRounds, softRounds + addHardRounds),
      hardRounds: newHardRounds,
      softToolCalls: math.min(
        hardToolCalls + addHardCalls,
        softToolCalls + addHardCalls,
      ),
      hardToolCalls: hardToolCalls + addHardCalls,
      wallClock: wallClock + wallClock * timeFactor,
      tokens: newTokens,
    );
  }

  /// 单行描述，供 UI/日志展示。
  String get summary =>
      '软 $softRounds轮/$softToolCalls调用，硬 $hardRounds轮/$hardToolCalls调用，'
      '${wallClock.inMinutes}分钟';
}

/// 执行预算 —— 管"这一轮任务本身还能跑多久"。
///
/// 与 [PlanningBudget] 的分工是这次改造的核心：
/// - 本类只管执行：轮次、工具调用数、墙钟、token。
/// - 软上限触发后由调用方（AgentLoop）检查"上一轮是否有进展"，有进展就
///   [grantSoftExtension] 原地续预算，**不**消耗外层重规划轮。
class ExecutionBudget {
  /// 当前生效的上限。原地续预算会就地抬高软上限（硬上限不动）。
  ExecutionLimits limits;
  int _usedRounds = 0;
  int _usedToolCalls = 0;
  int _tokens = 0;
  int _softExtensions = 0;

  /// 续跑（追加预算）时继承的已用时长。
  Duration _carriedElapsed = Duration.zero;

  final Stopwatch _wallClock;

  ExecutionBudget({required this.limits, Stopwatch? wallClock})
    : _wallClock = wallClock ?? Stopwatch() {
    if (!_wallClock.isRunning) _wallClock.start();
  }

  /// 从一次已结束的运行继续（"继续追加预算"入口）。
  factory ExecutionBudget.resume({
    required ExecutionLimits limits,
    required BudgetSnapshot snapshot,
  }) {
    final budget = ExecutionBudget(limits: limits);
    budget._usedRounds = snapshot.usedRounds;
    budget._usedToolCalls = snapshot.usedToolCalls;
    budget._tokens = snapshot.tokens;
    budget._carriedElapsed = snapshot.elapsed;
    // 原地续预算的次数也要继承，否则续跑后"已原地续 N 次"会被清零。
    budget._softExtensions = snapshot.softExtensions;
    return budget;
  }

  int get usedRounds => _usedRounds;
  int get usedToolCalls => _usedToolCalls;
  int get tokens => _tokens;
  int get softExtensions => _softExtensions;
  Duration get elapsed => _carriedElapsed + _wallClock.elapsed;
  int get remainingSoftRounds => math.max(0, limits.softRounds - _usedRounds);
  int get remainingHardRounds => math.max(0, limits.hardRounds - _usedRounds);

  /// 每进入一轮 tool_call 循环调用一次。
  void beginRound() => _usedRounds++;

  /// 记录工具调用。一次模型回复可能带多个 tool_call，一轮 ≠ 一次调用。
  void recordToolCalls([int count = 1]) {
    if (count <= 0) return;
    _usedToolCalls += count;
  }

  /// 记录本轮消耗的 token 估算。
  void addTokens(int count) {
    if (count <= 0) return;
    _tokens += count;
  }

  /// 硬约束检查（与"有没有进展"无关，先判）。
  BudgetStopReason hardStopReason() {
    if (_usedRounds >= limits.hardRounds) return BudgetStopReason.hardRounds;
    if (_usedToolCalls >= limits.hardToolCalls) {
      return BudgetStopReason.toolCalls;
    }
    if (elapsed >= limits.wallClock) return BudgetStopReason.wallClock;
    if (_tokens >= limits.tokens) return BudgetStopReason.tokens;
    return BudgetStopReason.none;
  }

  /// 软上限是否已到（到线后必须检查进展，而不是直接停）。
  bool get softExceeded =>
      _usedRounds >= limits.softRounds ||
      _usedToolCalls >= limits.softToolCalls;

  /// 原地续预算：只抬高软上限（硬上限保持不变），不消耗任何外层轮次。
  ///
  /// 返回本次实际新增的软轮次数（可能为 0 —— 软上限已经贴到硬上限）。
  int grantSoftExtension({int? rounds, int? toolCalls}) {
    final addRounds = rounds ?? math.max(3, (limits.softRounds * 0.3).ceil());
    final addCalls =
        toolCalls ?? math.max(4, (limits.softToolCalls * 0.3).ceil());

    final newSoftRounds = math.min(
      limits.hardRounds,
      limits.softRounds + addRounds,
    );
    final newSoftCalls = math.min(
      limits.hardToolCalls,
      limits.softToolCalls + addCalls,
    );

    final grantedRounds = newSoftRounds - limits.softRounds;
    final grantedCalls = newSoftCalls - limits.softToolCalls;
    if (grantedRounds <= 0 && grantedCalls <= 0) return 0;

    limits = limits.copyWith(
      softRounds: newSoftRounds,
      softToolCalls: newSoftCalls,
    );
    _softExtensions++;
    return grantedRounds;
  }

  BudgetSnapshot snapshot({int plansUsed = 0, int planLimit = 0}) =>
      BudgetSnapshot(
        usedRounds: _usedRounds,
        softRounds: limits.softRounds,
        hardRounds: limits.hardRounds,
        usedToolCalls: _usedToolCalls,
        softToolCalls: limits.softToolCalls,
        hardToolCalls: limits.hardToolCalls,
        tokens: _tokens,
        tokenLimit: limits.tokens,
        elapsed: elapsed,
        wallClock: limits.wallClock,
        softExtensions: _softExtensions,
        plansUsed: plansUsed,
        planLimit: planLimit,
      );
}

/// 预算快照 —— 不可变，供 UI 实时显示"已用工具轮 / 预算"。
class BudgetSnapshot {
  final int usedRounds;
  final int softRounds;
  final int hardRounds;
  final int usedToolCalls;
  final int softToolCalls;
  final int hardToolCalls;
  final int tokens;
  final int tokenLimit;
  final Duration elapsed;
  final Duration wallClock;
  final int softExtensions;

  /// 外层重新规划预算（0 表示当前不是 Loop 模式 / 未启用）
  final int plansUsed;
  final int planLimit;

  const BudgetSnapshot({
    required this.usedRounds,
    required this.softRounds,
    required this.hardRounds,
    required this.usedToolCalls,
    required this.softToolCalls,
    required this.hardToolCalls,
    required this.tokens,
    required this.tokenLimit,
    required this.elapsed,
    required this.wallClock,
    this.softExtensions = 0,
    this.plansUsed = 0,
    this.planLimit = 0,
  });

  BudgetSnapshot copyWith({int? plansUsed, int? planLimit}) => BudgetSnapshot(
    usedRounds: usedRounds,
    softRounds: softRounds,
    hardRounds: hardRounds,
    usedToolCalls: usedToolCalls,
    softToolCalls: softToolCalls,
    hardToolCalls: hardToolCalls,
    tokens: tokens,
    tokenLimit: tokenLimit,
    elapsed: elapsed,
    wallClock: wallClock,
    softExtensions: softExtensions,
    plansUsed: plansUsed ?? this.plansUsed,
    planLimit: planLimit ?? this.planLimit,
  );

  /// 还原"此刻真实生效"的执行上限。
  ///
  /// 追加预算必须以它为基准继续放大。历史 bug：调用方拿分档基准
  /// （[ExecutionLimits.of] 的固定值）去 `extended()`，于是每次点
  /// "追加预算继续"都重算出**同一个**上限（日志里反复出现
  /// 「追加预算：软 90/硬 160 轮」），而已用轮次/token 却在继承——
  /// 第二、三次追加等于没加，点一下就是原地再停一次。
  ExecutionLimits toLimits() => ExecutionLimits(
    softRounds: softRounds,
    hardRounds: hardRounds,
    softToolCalls: softToolCalls,
    hardToolCalls: hardToolCalls,
    wallClock: wallClock,
    tokens: tokenLimit,
  );

  /// 追加预算：从"在跑的那套上限"继续放大（而不是回到分档基准重算）。
  ///
  /// [ExecutionLimits.extended] 会带着本快照的已用 token 做投影，
  /// 保证抬完之后的 token 上限不会先于轮次上限触发。
  ExecutionLimits extendedLimits({
    double roundFactor = 0.6,
    double toolCallFactor = 0.6,
    double timeFactor = 0.5,
    double tokenFactor = 0.6,
  }) => toLimits().extended(
    roundFactor: roundFactor,
    toolCallFactor: toolCallFactor,
    timeFactor: timeFactor,
    tokenFactor: tokenFactor,
    used: this,
  );

  /// 轮次进度（0~1），按硬上限算，给进度条用。
  double get roundFraction =>
      hardRounds <= 0 ? 0 : (usedRounds / hardRounds).clamp(0.0, 1.0);

  /// 已用软上限的比例：超过 1 表示已经续过预算。
  double get softRoundFraction =>
      softRounds <= 0 ? 0 : (usedRounds / softRounds).clamp(0.0, 2.0);

  double get toolCallFraction =>
      hardToolCalls <= 0 ? 0 : (usedToolCalls / hardToolCalls).clamp(0.0, 1.0);

  double get timeFraction => wallClock.inMilliseconds <= 0
      ? 0
      : (elapsed.inMilliseconds / wallClock.inMilliseconds).clamp(0.0, 1.0);

  double get tokenFraction =>
      tokenLimit <= 0 ? 0 : (tokens / tokenLimit).clamp(0.0, 1.0);

  /// 是否已进入"续过预算"的状态（UI 可以给个不同颜色）。
  bool get hasBeenExtended => softExtensions > 0 || usedRounds > softRounds;

  String get roundText => '$usedRounds/$hardRounds';
  String get toolCallText => '$usedToolCalls/$hardToolCalls';
  String get planText => '$plansUsed/$planLimit';

  String get elapsedText {
    final d = elapsed;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60}h${minutes % 60}m';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 规划预算 —— 只管"外层重新规划"的次数。
///
/// 旧实现把内层 tool_call 轮次上限和外层 Loop 迭代混在一起，
/// 内层 50 次用完就白白吃掉一次外层轮。现在两者彻底分开：
/// - 内层触软上限且有进展 → 原地续预算，**不**动这里；
/// - 只有真正"重新规划"（上一轮跑完但任务没完成）才消耗一次。
class PlanningBudget {
  /// 外层重新规划次数上限（追加预算会就地放大）
  int maxPlans;
  int _plansUsed = 0;

  /// 原地续跑次数上限（用户点"追加预算继续"时消耗）
  int maxContinuations;
  int _continuationsUsed = 0;

  PlanningBudget({required this.maxPlans, this.maxContinuations = 6});

  int get plansUsed => _plansUsed;
  int get remaining => math.max(0, maxPlans - _plansUsed);
  int get continuationsUsed => _continuationsUsed;
  bool get canReplan => _plansUsed < maxPlans;
  bool get canContinue => _continuationsUsed < maxContinuations;

  /// 消耗一次重新规划预算，返回本次是第几次。
  int consumePlan() => ++_plansUsed;

  /// 消耗一次"原地续跑"（用于硬上限被用户追加预算后续跑）。
  bool consumeContinuation() {
    if (!canContinue) return false;
    _continuationsUsed++;
    return true;
  }

  /// 追加预算：额外给几次重新规划与续跑机会。
  void grantBonus({int plans = 2, int continuations = 2}) {
    maxPlans += plans;
    maxContinuations += continuations;
  }

  BudgetSnapshot attachTo(BudgetSnapshot base) =>
      base.copyWith(plansUsed: _plansUsed, planLimit: maxPlans);
}

/// 任务分档对应的完整预算策略。
class TaskTierPolicy {
  final AgentTaskTier tier;
  final ExecutionLimits limits;

  /// 外层"重新规划"次数上限。
  final int maxPlans;

  /// 硬上限被追加预算后允许的原地续跑次数。
  final int maxContinuations;

  const TaskTierPolicy({
    required this.tier,
    required this.limits,
    required this.maxPlans,
    this.maxContinuations = 6,
  });

  static const TaskTierPolicy quick = TaskTierPolicy(
    tier: AgentTaskTier.quick,
    limits: ExecutionLimits.quick,
    maxPlans: 2,
    maxContinuations: 2,
  );

  static const TaskTierPolicy coding = TaskTierPolicy(
    tier: AgentTaskTier.coding,
    limits: ExecutionLimits.coding,
    maxPlans: 5,
  );

  static const TaskTierPolicy refactor = TaskTierPolicy(
    tier: AgentTaskTier.refactor,
    limits: ExecutionLimits.refactor,
    maxPlans: 8,
    maxContinuations: 10,
  );

  static TaskTierPolicy of(AgentTaskTier tier) {
    switch (tier) {
      case AgentTaskTier.quick:
        return quick;
      case AgentTaskTier.coding:
        return coding;
      case AgentTaskTier.refactor:
        return refactor;
      case AgentTaskTier.custom:
        return coding;
    }
  }

  TaskTierPolicy withLimits(ExecutionLimits limits) => TaskTierPolicy(
    tier: tier,
    limits: limits,
    maxPlans: maxPlans,
    maxContinuations: maxContinuations,
  );
}

/// 单轮进展报告。
class RoundProgress {
  /// 本轮工具调用次数
  final int calls;

  /// 本轮从未出现过的新调用（工具名+参数签名）
  final int newSignatures;

  /// 完全重复的调用（签名相同且结果哈希相同）—— 空转信号
  final int repeats;

  /// 参数相同但结果变化的调用（仍在探索）
  final int changedResults;

  /// 失败的调用
  final int errors;

  /// 本轮新增产物文件数
  final int newArtifacts;

  /// 本轮写入/修改的文件数
  final int filesChanged;

  /// 测试通过数增量（能解析出来时才有意义）
  final int testsPassedDelta;

  const RoundProgress({
    required this.calls,
    required this.newSignatures,
    required this.repeats,
    required this.changedResults,
    required this.errors,
    required this.newArtifacts,
    required this.filesChanged,
    required this.testsPassedDelta,
  });

  /// 空转：本轮所有调用都在重复之前做过的事，且结果一模一样。
  bool get isSpinning => calls > 0 && repeats == calls;

  /// 有进展的最小证据集。
  ///
  /// 优先看"外部可观测结果"（产物 / 文件改动 / 测试变好），
  /// 其次看"结果是否变了"（重跑同一命令但输出不同 = 状态在推进），
  /// 最后才是"是否尝试了新动作且没全军覆没"。
  bool get hasProgress {
    if (newArtifacts > 0 || filesChanged > 0 || testsPassedDelta > 0) {
      return true;
    }
    if (changedResults > 0) return true;
    return newSignatures > 0 && errors < newSignatures;
  }

  /// 明确的"没有实质进展"：全在重复同签名同结果，或整轮全失败。
  ///
  /// 停止判定要求这个信号**连续多轮**成立（见 AgentLoop 的
  /// `_noProgressRoundsToStop`）——单轮的验证型重复（重跑同样的测试看结果）
  /// 不该立刻掐断任务，历史 bug 就是这么把"其实快做完了"的任务停掉的。
  bool get isNoProgress => calls > 0 && (isSpinning || errors == calls);

  String get summary =>
      '本轮调用 $calls 次（新动作 $newSignatures，重复 $repeats，'
      '结果变化 $changedResults，失败 $errors），新增产物 $newArtifacts，'
      '文件改动 $filesChanged，测试 +$testsPassedDelta';
}

/// 工具级进展追踪 —— 记录 (工具名, 参数, 结果哈希)。
///
/// 为什么不用文本相似度判断"有没有进展"：模型每轮都会重新组织措辞，
/// 文本相似度既会误报"有变化"（其实什么都没做），也会漏报"卡在同一处"。
/// 工具调用签名 + 结果哈希是确定性证据：
/// - 同签名 + 同结果 → 这一轮等于什么都没做（空转）；
/// - 同签名 + 不同结果 → 还在试探（例如读到的内容变了）；
/// - 新签名 → 走了新路。
///
/// 另外统计三类"外部证据"：新增产物、文件改动、测试通过数，
/// 它们比"模型说它完成了"可靠得多。
class ToolProgressTracker {
  ToolProgressTracker({this.maxSignatures = 4000, this.workspaceRoot});

  /// 保留的签名上限，防止长任务把内存吃满。
  final int maxSignatures;

  /// 工作区根目录（可选）：设了之后只有落在它里面的文件才算"产物"。
  ///
  /// 为什么需要：工具结果里到处是"存在的文件路径"（比如 system_probe 会报出
  /// python.exe / node.exe 这些系统里本来就有的可执行文件），以前会被误判成
  /// "新增产物"，既灌水进展判定，又让检查点列出 node.exe 这种噪音。
  final String? workspaceRoot;

  /// 这些工具不会"生产"文件，扫描它们的返回结果只会带来误报。
  static const Set<String> _nonProducingTools = {
    'toolshell_read',
    'toolshell_search',
    'system_probe',
    'toolshell_memory_search',
    'toolshell_memory_recall',
  };

  /// 系统二进制/库扩展名：永远不算产物。
  static const Set<String> _binaryExtensions = {
    'exe',
    'dll',
    'so',
    'dylib',
    'msi',
    'bat',
    'cmd',
    'sys',
    'ocx',
    'lib',
    'pdb',
    'node',
  };

  /// 签名 → 结果哈希
  final Map<String, String> _seen = <String, String>{};

  /// 首次出现的签名顺序（用于淘汰）
  final List<String> _order = <String>[];

  /// 所有出现过的产物路径（只含非临时目录的真实产物）
  final Set<String> _artifacts = <String>{};

  /// 临时目录产物：文件名 → 出现次数（中间文件，不计入"进展"）
  final Map<String, int> _tempArtifacts = <String, int>{};

  /// 工具调用次数统计
  final Map<String, int> _toolCallCounts = <String, int>{};

  int _totalCalls = 0;
  int _duplicateCalls = 0;
  int _changedResultCalls = 0;
  int _errorCalls = 0;
  int _filesChanged = 0;
  int _testsPassed = 0;

  // ─── 本轮计数 ───
  int _roundCalls = 0;
  int _roundNewSignatures = 0;
  int _roundRepeats = 0;
  int _roundChangedResults = 0;
  int _roundErrors = 0;
  int _roundNewArtifacts = 0;
  int _roundFilesChanged = 0;
  int _roundTestsBaseline = 0;

  RoundProgress? _lastRound;

  int get totalCalls => _totalCalls;
  int get duplicateCalls => _duplicateCalls;
  int get changedResultCalls => _changedResultCalls;
  int get errorCalls => _errorCalls;
  int get filesChanged => _filesChanged;
  int get testsPassed => _testsPassed;
  List<String> get artifacts => List.unmodifiable(_artifacts);
  Map<String, int> get toolCallCounts => Map.unmodifiable(_toolCallCounts);

  /// 上一轮的进展报告（软上限判定要用）。
  RoundProgress? get lastRound => _lastRound;

  /// 开始新的一轮（重置本轮计数）。
  void beginRound() {
    _roundCalls = 0;
    _roundNewSignatures = 0;
    _roundRepeats = 0;
    _roundChangedResults = 0;
    _roundErrors = 0;
    _roundNewArtifacts = 0;
    _roundFilesChanged = 0;
    _roundTestsBaseline = _testsPassed;
  }

  /// 结束一轮，产出进展报告。
  RoundProgress endRound() {
    final progress = RoundProgress(
      calls: _roundCalls,
      newSignatures: _roundNewSignatures,
      repeats: _roundRepeats,
      changedResults: _roundChangedResults,
      errors: _roundErrors,
      newArtifacts: _roundNewArtifacts,
      filesChanged: _roundFilesChanged,
      testsPassedDelta: math.max(0, _testsPassed - _roundTestsBaseline),
    );
    _lastRound = progress;
    return progress;
  }

  /// 记录一次工具调用（在 ToolPipeline 里对每次真实执行调用）。
  void record(String toolName, Map<String, dynamic> args, String result) {
    final signature = _signature(toolName, args);
    final resultHash = _hash(_normalizeResult(result));

    _totalCalls++;
    _roundCalls++;
    _toolCallCounts[toolName] = (_toolCallCounts[toolName] ?? 0) + 1;

    final isError = _looksLikeError(result);
    if (isError) {
      _errorCalls++;
      _roundErrors++;
    }

    final previousHash = _seen[signature];
    if (previousHash == null) {
      _roundNewSignatures++;
      _remember(signature, resultHash);
    } else if (previousHash == resultHash) {
      _duplicateCalls++;
      _roundRepeats++;
    } else {
      _changedResultCalls++;
      _roundChangedResults++;
      _seen[signature] = resultHash;
    }

    // ─── 外部证据 1：新增产物 ───
    // 系统临时目录里的东西（run_python 每轮新建 remindai_python_xxx/output/…）
    // 属于中间文件：只按文件名计数，不算"进展"，否则每次跑脚本都像有产出。
    // 只读/探测类工具不扫描（否则会把系统里已有的可执行文件当成本次产物）。
    if (!_nonProducingTools.contains(toolName)) {
      for (final path in _extractArtifacts(result)) {
        if (_isTempPath(path)) {
          final name = _basename(path);
          _tempArtifacts[name] = (_tempArtifacts[name] ?? 0) + 1;
        } else if (_artifacts.add(path)) {
          _roundNewArtifacts++;
        }
      }
    }

    // ─── 外部证据 2：文件改动（写类工具落地） ───
    if (!isError && _isWriteTool(toolName)) {
      final wrote = _extractArtifacts(result).any((path) => !_isTempPath(path));
      if (wrote) {
        _filesChanged++;
        _roundFilesChanged++;
      }
    }

    // ─── 外部证据 3：测试通过数 ───
    final passed = _extractTestsPassed(result);
    if (passed != null && passed > _testsPassed) {
      _testsPassed = passed;
    }
  }

  /// 是否见过这个调用（同签名）。
  bool hasSeen(String toolName, Map<String, dynamic> args) =>
      _seen.containsKey(_signature(toolName, args));

  /// 每次 run（一次 chat）入口调用：清零"本次"统计。
  ///
  /// 为什么必须清：追踪器由 AgentContext 持有，而 AgentContext 是**会话级缓存**，
  /// 会跨多条用户消息累积；预算（ExecutionBudget）却是每次 run 新建的。
  /// 不清零就会出现"检查点说用了 211 次调用、预算却说 93/320"的口径打架。
  ///
  /// 保留 [_seen]（签名记忆）：跨 run 仍能识别"又跑了一遍同样的命令"。
  void resetRun() {
    _totalCalls = 0;
    _duplicateCalls = 0;
    _changedResultCalls = 0;
    _errorCalls = 0;
    _filesChanged = 0;
    _testsPassed = 0;
    _artifacts.clear();
    _tempArtifacts.clear();
    _toolCallCounts.clear();
    _lastRound = null;
  }

  /// 生成检查点摘要（⑤ 失败时"说人话"用）。
  LoopCheckpoint checkpoint({
    String lastOutput = '',
    int roundsUsed = 0,
    Duration elapsed = Duration.zero,
    int? toolCallsOverride,
    int softRounds = 0,
    int hardRounds = 0,
    int softExtensions = 0,
  }) => LoopCheckpoint(
    roundsUsed: roundsUsed,
    // 预算才是"本次 run"的权威口径，追踪器可能含跨 run 残留
    toolCalls: toolCallsOverride ?? _totalCalls,
    repeatedCalls: _duplicateCalls,
    errorCalls: _errorCalls,
    toolStats: Map<String, int>.from(_toolCallCounts),
    artifacts: artifactDisplayNames,
    filesChanged: _filesChanged,
    testsPassed: _testsPassed,
    elapsed: elapsed,
    lastOutput: lastOutput,
    softRounds: softRounds,
    hardRounds: hardRounds,
    softExtensions: softExtensions,
  );

  /// 产物展示名：真实产物给文件名，临时中间产物折叠成"文件名（临时 ×N）"。
  List<String> get artifactDisplayNames {
    final names = <String>{};
    for (final path in _artifacts) {
      names.add(_basename(path));
    }
    for (final entry in _tempArtifacts.entries) {
      names.add('${entry.key}（临时 ×${entry.value}）');
    }
    return names.toList();
  }

  /// 是否为系统临时目录下的路径（这类路径每次运行都不一样，不能当产物）。
  static bool _isTempPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final systemTemp = Directory.systemTemp.path
        .replaceAll('\\', '/')
        .toLowerCase();
    if (systemTemp.isNotEmpty && normalized.startsWith(systemTemp)) return true;
    return normalized.startsWith('/tmp/') ||
        normalized.contains('/appdata/local/temp/');
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? path : name;
  }

  void _remember(String signature, String resultHash) {
    if (_seen.length >= maxSignatures) {
      final oldest = _order.removeAt(0);
      _seen.remove(oldest);
    }
    _seen[signature] = resultHash;
    _order.add(signature);
  }

  // ─── 签名 / 哈希 ───

  static String _signature(String toolName, Map<String, dynamic> args) {
    final canonical = _canonicalJson(args);
    return '$toolName\u0000$canonical';
  }

  /// 参数规范化：key 排序后序列化，避免"同一组参数、不同顺序"被当成新调用。
  static String _canonicalJson(Object? value) {
    if (value == null || value is num || value is bool) {
      return jsonEncode(value);
    }
    if (value is String) return jsonEncode(value);
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final buffer = StringBuffer('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buffer.write(',');
        final key = keys[i];
        buffer.write(jsonEncode(key));
        buffer.write(':');
        buffer.write(_canonicalJson(value[key]));
      }
      buffer.write('}');
      return buffer.toString();
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value.toString());
  }

  /// 结果规范化：忽略空白差异，避免"只差换行"被当成新结果。
  static String _normalizeResult(String result) {
    if (result.length > 20000) {
      // 超长结果只取头尾，避免哈希代价过高
      return '${result.substring(0, 10000)}\u0000${result.substring(result.length - 10000)}';
    }
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// FNV-1a 64 位哈希（够用、稳定、无依赖）。
  static String _hash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  static bool _looksLikeError(String result) {
    final trimmed = result.trimLeft();
    if (trimmed.startsWith('Error') || trimmed.startsWith('Exception')) {
      return true;
    }
    final lower = result.length > 4000
        ? result.substring(0, 4000).toLowerCase()
        : result.toLowerCase();
    if (lower.contains('"status":"error"') ||
        lower.contains('"status": "error"')) {
      return true;
    }
    if (lower.contains('traceback (most recent call last)')) return true;
    return false;
  }

  static const Set<String> _writeTools = {
    'toolshell_write',
    'toolshell_delete',
    'office_word_create',
    'office_word_edit',
    'office_excel_create',
    'office_excel_edit',
    'office_word_file',
    'office_excel_file',
  };

  static bool _isWriteTool(String name) => _writeTools.contains(name);

  /// 从工具结果里提取"落地产物"路径。
  ///
  /// 只认两类信号，避免误报：
  /// 1. 结果 JSON 里明确的路径字段（path/output/image_path/...）；
  /// 2. 形如 `xxx.ext` 且文件真实存在的字符串。
  List<String> _extractArtifacts(String result) {
    final trimmed = result.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(result);
    } catch (_) {
      return const [];
    }
    final found = <String>{};
    _walkForArtifacts(decoded, found, 0);
    return found.toList();
  }

  static const Set<String> _pathKeys = {
    'path',
    'file',
    'file_path',
    'output',
    'output_path',
    'output_dir',
    'image_path',
    'document_md',
    'dest',
    'target',
    'saved_to',
    'zip',
    'docx',
    'xlsx',
  };

  static final RegExp _fileLike = RegExp(
    r'^(?:[A-Za-z]:[\\/]|\.{0,2}[\\/])?[^\s"*?<>|]{1,300}\.[A-Za-z0-9]{1,6}$',
  );

  void _walkForArtifacts(Object? node, Set<String> out, int depth) {
    if (depth > 4 || out.length >= 20) return;
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is String && _pathKeys.contains(key) && value.isNotEmpty) {
          _addIfFile(value, out);
        } else {
          _walkForArtifacts(value, out, depth + 1);
        }
      }
      return;
    }
    if (node is List) {
      for (final item in node) {
        _walkForArtifacts(item, out, depth + 1);
      }
      return;
    }
    if (node is String && _fileLike.hasMatch(node)) {
      _addIfFile(node, out);
    }
  }

  void _addIfFile(String candidate, Set<String> out) {
    if (candidate.length > 300) return;
    if (candidate.startsWith('http')) return;
    final path = candidate.trim();
    if (path.isEmpty) return;
    if (!_acceptAsArtifact(path)) return;
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.file) out.add(path);
    } catch (_) {
      // 探测失败（非法路径 / 权限）时忽略
    }
  }

  /// 产物准入：排除系统二进制、系统目录，以及（设了工作区时）工作区外的文件。
  bool _acceptAsArtifact(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();

    // 0. 系统临时目录：交给 record() 单独折叠成"临时 ×N"，这里放行
    if (_isTempPath(path)) return true;

    // 1. 二进制/系统库扩展名
    final dot = normalized.lastIndexOf('.');
    if (dot > 0) {
      final ext = normalized.substring(dot + 1);
      if (_binaryExtensions.contains(ext)) return false;
    }

    // 2. 系统目录里的东西（装好的 python.exe / node.exe 等）
    if (normalized.contains('/windows/') ||
        normalized.contains('/program files') ||
        normalized.contains('/programdata/') ||
        normalized.contains('/appdata/')) {
      return false;
    }

    // 3. 设了工作区就只认工作区内的产物
    final root = workspaceRoot;
    if (root != null && root.trim().isNotEmpty) {
      final normalizedRoot = root.replaceAll('\\', '/').toLowerCase();
      final rootNoSlash = normalizedRoot.endsWith('/')
          ? normalizedRoot.substring(0, normalizedRoot.length - 1)
          : normalizedRoot;
      if (!normalized.startsWith(rootNoSlash)) return false;
    }
    return true;
  }

  /// 从测试输出里解析"通过数"。
  ///
  /// 支持 `+12 -1`、`12 passed`、`Tests: 12 passed, 1 failed`、
  /// `All tests passed`（按 +1 处理，只用于"变好了没有"的增量判断）。
  static int? _extractTestsPassed(String result) {
    if (result.isEmpty) return null;
    var best = -1;
    final patterns = <RegExp>[
      RegExp(r'(\d+)\s+(?:tests?\s+)?passed', caseSensitive: false),
      RegExp(r'\+(\d+)\s*(?:-|~)\s*\d+'),
      RegExp(r'(\d+)\s+passing', caseSensitive: false),
      RegExp(r'Tests:\s*(\d+)\s+passed', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(result)) {
        final value = int.tryParse(match.group(1) ?? '');
        if (value != null && value > best) best = value;
      }
      if (best >= 0) break;
    }
    if (best >= 0) return best;
    if (result.toLowerCase().contains('all tests passed')) return 1;
    return null;
  }
}

/// 预算耗尽时的检查点 —— 让"失败"也能给出可续跑的交付物。
class LoopCheckpoint {
  final int roundsUsed;
  final int toolCalls;
  final int repeatedCalls;
  final int errorCalls;
  final Map<String, int> toolStats;
  final List<String> artifacts;
  final int filesChanged;
  final int testsPassed;
  final Duration elapsed;
  final String lastOutput;

  /// 软/硬轮次上限与已续预算次数（仅用于把"88/100"讲清楚）
  final int softRounds;
  final int hardRounds;
  final int softExtensions;

  const LoopCheckpoint({
    this.roundsUsed = 0,
    this.toolCalls = 0,
    this.repeatedCalls = 0,
    this.errorCalls = 0,
    this.toolStats = const {},
    this.artifacts = const [],
    this.filesChanged = 0,
    this.testsPassed = 0,
    this.elapsed = Duration.zero,
    this.lastOutput = '',
    this.softRounds = 0,
    this.hardRounds = 0,
    this.softExtensions = 0,
  });

  bool get isEmpty => toolCalls == 0 && artifacts.isEmpty && filesChanged == 0;

  /// 检查点摘要（Markdown），直接贴进聊天记录。
  String toMarkdown({
    BudgetStopReason reason = BudgetStopReason.none,
    int maxArtifacts = 8,
    int maxOutput = 400,
  }) {
    // 注意：Markdown 段落内的"单换行"会被渲染成空格，
    // 列表必须与前面的段落用空行隔开，否则整块会挤成一行（历史 bug）。
    final buffer = StringBuffer();
    buffer.writeln('📊 **检查点摘要**');
    buffer.writeln();
    final budgetNote = hardRounds > 0
        ? '（软上限 $softRounds'
              '${softExtensions > 0 ? '，已原地续 $softExtensions 次' : ''}'
              '／硬上限 $hardRounds）'
        : '';
    buffer.writeln(
      '- 已用工具轮：$roundsUsed 轮$budgetNote / 工具调用 $toolCalls 次'
      '（重复 $repeatedCalls，失败 $errorCalls）',
    );
    if (elapsed > Duration.zero) {
      final minutes = elapsed.inMinutes;
      final seconds = elapsed.inSeconds % 60;
      buffer.writeln(
        '- 执行时长：$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒',
      );
    }
    if (filesChanged > 0) buffer.writeln('- 文件改动：$filesChanged 处');
    if (testsPassed > 0) buffer.writeln('- 测试通过：$testsPassed 个');
    if (artifacts.isNotEmpty) {
      buffer.writeln(
        '- 新增产物（${artifacts.length} 个）：${_artifactSummary(maxArtifacts)}',
      );
    }
    buffer.writeln();
    if (reason.isNone == false) {
      buffer.writeln('**停止原因**：${reason.humanReason}');
      buffer.writeln();
    }
    if (toolStats.isNotEmpty) {
      final entries = toolStats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = entries.take(6).map((e) => '${e.key} ×${e.value}').join('、');
      buffer.writeln('**工具分布**：$top');
      buffer.writeln();
    }
    final output = lastOutput.trim();
    if (output.isNotEmpty) {
      final preview = output.length > maxOutput
          ? '${output.substring(output.length - maxOutput)}…'
          : output;
      buffer.writeln('**最近一次输出（尾部）**');
      buffer.writeln();
      buffer.writeln(preview);
    }
    return buffer.toString().trim();
  }

  /// 产物展示：只给文件名（Windows 长路径在这里是噪音），
  /// 同名折叠成 ×N，超出 [_maxArtifactNames] 个就省略。
  String _artifactSummary(int maxShown) {
    final counts = <String, int>{};
    for (final artifact in artifacts) {
      final name = _displayName(artifact);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = entries
        .take(maxShown)
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .join('、');
    final rest = entries.length - maxShown;
    return rest > 0 ? '$shown 等 ${entries.length} 项' : shown;
  }

  static String _displayName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    return name.isEmpty ? path : name;
  }
}

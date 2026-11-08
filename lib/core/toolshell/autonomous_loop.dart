import 'dart:async';

import '../llm/llm_client.dart';
import '../agent/agent_hook.dart';
import '../agent/message_pipeline.dart';
import '../logger/app_logger.dart';
import 'agent_loop.dart';
import 'budget.dart';
import 'executor.dart';

/// Loop 模式配置
///
/// 现在由"任务分档"驱动：档位决定执行预算（轮次/调用/墙钟/token）和
/// 外层重规划次数。旧的"最大轮次"滑块语义被 [maxPlansOverride] 兼容保留。
class LoopConfig {
  /// 任务分档
  final AgentTaskTier tier;

  /// 覆盖执行预算（自定义档位时用）
  final ExecutionLimits? limitsOverride;

  /// 覆盖外层重规划次数（旧 API 兼容）
  final int? maxPlansOverride;

  /// 是否自动批准工具操作（Loop 模式默认 true）
  final bool autoApprove;

  const LoopConfig({
    this.tier = AgentTaskTier.coding,
    this.limitsOverride,
    this.maxPlansOverride,
    this.autoApprove = true,
  });

  /// 解析成具体的预算策略
  TaskTierPolicy get policy {
    final base = TaskTierPolicy.of(tier);
    final withLimits = limitsOverride == null
        ? base
        : base.withLimits(limitsOverride!);
    if (maxPlansOverride == null) return withLimits;
    return TaskTierPolicy(
      tier: withLimits.tier,
      limits: withLimits.limits,
      maxPlans: maxPlansOverride!,
      maxContinuations: withLimits.maxContinuations,
    );
  }
}

/// Loop 事件 (驱动 UI 更新)
sealed class LoopEvent {}

/// 新的一次"重新规划"开始（外层轮）
class LoopPlanStart extends LoopEvent {
  final int plan;
  final int maxPlans;
  final BudgetSnapshot snapshot;
  LoopPlanStart(this.plan, this.maxPlans, this.snapshot);
}

/// 兼容旧命名（等价于 [LoopPlanStart]）
class LoopIterStart extends LoopEvent {
  final int iteration;
  final int maxIterations;
  final BudgetSnapshot? snapshot;
  LoopIterStart(this.iteration, this.maxIterations, [this.snapshot]);
}

/// 迭代中的 Agent 事件（透传 AgentLoop 的事件）
class LoopAgentEvent extends LoopEvent {
  final AgentEvent event;
  LoopAgentEvent(this.event);
}

/// 预算心跳：已用工具轮 / 工具调用 / 时间 / token
class LoopBudgetTick extends LoopEvent {
  final BudgetSnapshot snapshot;
  LoopBudgetTick(this.snapshot);
}

/// 内层触软上限但有进展 → 原地续预算（不消耗外层重规划轮）
class LoopBudgetExtended extends LoopEvent {
  final BudgetSnapshot snapshot;
  final int grantedRounds;
  LoopBudgetExtended(this.snapshot, this.grantedRounds);
}

/// Loop 正常完成（Agent 声明完成）
class LoopDone extends LoopEvent {
  final int totalIterations;
  final String summary;
  final BudgetSnapshot? snapshot;
  LoopDone({
    required this.totalIterations,
    required this.summary,
    this.snapshot,
  });
}

/// Loop 终止（预算耗尽 / 无进展 / 达到硬上限）
///
/// 与旧版只带 `maxIterations` 不同，这里带完整的归因、预算快照和检查点，
/// UI 可以直接渲染"为什么停 + 做了什么 + 追加预算继续"。
class LoopExhausted extends LoopEvent {
  /// 归因：[BudgetStopReason.none] 表示只是普通的"计划用完"
  final BudgetStopReason reason;
  final BudgetSnapshot snapshot;
  final LoopCheckpoint checkpoint;
  final String lastOutput;

  /// 停止时是否还在推进
  final bool hadProgress;

  /// 兼容旧字段：外层重新规划上限
  final int maxIterations;

  LoopExhausted({
    required this.reason,
    required this.snapshot,
    required this.checkpoint,
    required this.lastOutput,
    this.hadProgress = false,
    this.maxIterations = 0,
  });
}

/// Loop 被 Agent 主动放弃
class LoopAbort extends LoopEvent {
  final int iteration;
  final String reason;
  LoopAbort({required this.iteration, required this.reason});
}

/// Loop 出错
class LoopError extends LoopEvent {
  final int iteration;
  final String message;
  LoopError({required this.iteration, required this.message});
}

/// 无进展检测触发
class LoopStalled extends LoopEvent {
  final int iteration;
  final LoopCheckpoint? checkpoint;
  final BudgetSnapshot? snapshot;
  LoopStalled(this.iteration, {this.checkpoint, this.snapshot});
}

/// 自治循环 — 让 Agent 自主执行、验证、修复直到完成。
///
/// 包裹 [AgentLoop]，在每轮结束后检查 Agent 输出：
/// - 包含 [LOOP_DONE] → 提取总结，结束循环
/// - 包含 [LOOP_ABORT] → 提取原因，放弃循环
/// - 否则 → 自动发起下一轮（将上一轮结果作为上下文）
///
/// 上下文策略：保留完整历史，依赖 MessagePipeline 的 ContextCompactor
/// 在 token 超限时自动压缩。这保证了 Agent 在早期轮次的操作不会丢失。
class AutonomousLoop {
  final LlmClient llm;
  final Executor executor;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, dynamic>> messages;
  final MessagePipeline messagePipeline;
  final List<AgentHook> hooks;
  final LoopConfig config;

  /// 模型的上下文窗口大小（token 数）。用于对话中压缩的阈值计算。
  final int contextWindow;

  /// 追踪每轮是否包含失败标记，用于连续失败检测
  final List<bool> _roundFailures = [];

  AutonomousLoop({
    required this.llm,
    required this.executor,
    required this.tools,
    required this.messages,
    required this.config,
    this.messagePipeline = const MessagePipeline(),
    this.hooks = const [],
    this.contextWindow = 0,
  });

  /// Loop 模式注入到 system prompt 的指令
  static const String loopSystemInstruction = '''

[LOOP MODE ACTIVE]
你当前处于 Loop 模式 — 你可以自主迭代直到任务完成。

每一轮必须遵循以下流程，使用清晰的分段标记：

【第 1 轮】
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 分析目标
理解任务需求，制定初步计划

🛠️ 实现操作
执行具体的工具调用或代码修改

✅ 测试验证
运行测试、检查输出、验证结果

📊 评估结果
本轮完成了什么、是否符合预期、是否需要继续
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【第 2+ 轮】
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 评估上一轮
- 上一轮做了什么？
- 结果如何？（成功/失败/部分完成）
- 问题在哪里？（如果失败）

📋 调整计划
基于评估结果，决定下一步行动

🛠️ 实现操作
执行新的工具调用或修改

✅ 测试验证
验证本轮的修改是否有效

📊 评估结果
是否完成任务或需要继续
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

输出格式要求：
1. 每个阶段单独成段，使用对应的 emoji 标记开头
2. 阶段之间用空行分隔，保持清晰层次
3. 不要把多个阶段混在一句话里

示例（正确格式）：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 评估上一轮
上一轮修复了文件 A，但测试仍然失败。
错误信息显示配置文件 B 中缺少必要的参数。

📋 调整计划
需要修改配置文件 B，添加缺失的参数。

🛠️ 实现操作
（调用工具修改配置文件 B）

✅ 测试验证
重新运行测试套件...

📊 评估结果
所有测试通过。[LOOP_DONE] 完成任务：修复了配置错误并通过验证。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

关键规则：
- ⚠️ 不要重复上一轮已经成功的操作
- ⚠️ 如果连续2轮失败，必须换一个完全不同的方案
- ⚠️ 先分析为什么失败，再尝试修复（不要盲目重试）
- ✅ 每轮必须实际验证结果（运行测试、检查输出、编译代码等）
- ✅ 任务完成且验证通过时，输出 [LOOP_DONE] + 总结
- ✅ 对于大型任务，可以分阶段完成。只要当前阶段成功，就输出 [LOOP_DONE] + 已完成的部分
- ❌ 只有遇到无法解决的技术障碍时，才输出 [LOOP_ABORT] + 原因
- ❌ 不要因为"任务还有后续步骤"就放弃，分步完成是允许的

[预算与效率]
- 💰 执行预算按"工具轮 / 工具调用 / 墙钟 / token"四维计算。soft 上限到线时
  系统会检查你上一轮有没有真实进展：有进展自动续预算，没进展直接停。
  所以"磨轮次"不会换来更多机会，只会更快被判为空转。
- ⚡ 互不依赖的多个操作放进同一次回复（同一轮多个 tool_call，或用
  toolshell_run_parallel 一次发起一批），不要"读一个文件问一次"。
- 📚 读文件批量读、按需取片段，不要整文件反复全量读取。
- 🧭 探索性检索先精确定位，再把读取压成一次并行批（toolshell_run_parallel 里
  放多个 search/read 子调用），主循环只保留决策与落地，别用"读一个猜一个"磨预算。
''';

  /// 执行自治循环
  ///
  /// [budget] / [planning] / [progress] 由调用方注入，用于"追加预算继续"时
  /// 带着已用额度接着跑；不传则按 [config] 的分档新建。
  Stream<LoopEvent> run(
    String userInput, {
    ExecutionBudget? budget,
    PlanningBudget? planning,
    ToolProgressTracker? progress,
  }) async* {
    // 注入 Loop 指令到 system prompt
    _injectLoopInstruction();

    final policy = config.policy;
    final execBudget = budget ?? ExecutionBudget(limits: policy.limits);
    final progression =
        planning ??
        PlanningBudget(
          maxPlans: policy.maxPlans,
          maxContinuations: policy.maxContinuations,
        );
    final tracker = progress ?? ToolProgressTracker();

    String? lastOutput;
    var consecutiveStalledRounds = 0;

    AppLogger.instance.log(
      '[Loop] 启动：档位=${policy.tier.name}，'
      '执行预算(${execBudget.limits.summary})，'
      '重规划 ${progression.plansUsed}/${progression.maxPlans}',
    );

    while (progression.canReplan) {
      final planIndex = progression.consumePlan();
      final planSnapshot = progression.attachTo(execBudget.snapshot());
      yield LoopPlanStart(planIndex, progression.maxPlans, planSnapshot);
      AppLogger.instance.log(
        '[Loop] 第 $planIndex/${progression.maxPlans} 次规划开始 '
        '(已用 ${execBudget.usedRounds} 轮 / ${execBudget.usedToolCalls} 次调用)',
      );

      // 构建本轮输入
      final String input;
      if (planIndex == 1 && lastOutput == null) {
        input = userInput;
      } else {
        // 后续轮次：提醒 Agent 继续（附带上一轮输出摘要与预算余量）
        input = _buildContinuePrompt(planIndex, lastOutput, execBudget);
      }

      // 执行 AgentLoop — 预算与进展追踪器在内外层之间共享
      final agentLoop = AgentLoop(
        llm: llm,
        executor: executor,
        tools: tools,
        messages: messages,
        messagePipeline: messagePipeline,
        hooks: hooks,
        contextWindow: contextWindow,
        budget: execBudget,
        progressTracker: tracker,
        maxToolCallRounds: execBudget.limits.hardRounds,
      );

      final buffer = StringBuffer();
      var hasError = false;
      AgentBudgetStop? budgetStop;

      await for (final event in agentLoop.chat(input)) {
        switch (event) {
          case final AgentBudgetStop stop:
            // 执行预算耗尽：不立刻返回，先让本轮输出落袋，再统一收尾
            budgetStop = stop;
          case final AgentBudgetTick tick:
            yield LoopBudgetTick(progression.attachTo(tick.snapshot));
            yield LoopAgentEvent(event);
          case final AgentBudgetExtended extended:
            // 内层触软上限但有进展 → 原地续预算，不消耗外层重规划轮
            yield LoopBudgetExtended(
              progression.attachTo(extended.snapshot),
              extended.grantedRounds,
            );
            yield LoopAgentEvent(event);
          case AgentReasoningToken():
            // 推理过程仅透传给 UI，不计入本轮最终输出和停滞判断。
            yield LoopAgentEvent(event);
          case AgentToken(text: final text):
            buffer.write(text);
            yield LoopAgentEvent(event);
          case AgentToolStart():
          case AgentToolResult():
          case AgentHtmlGenerated():
          case AgentSvgGenerated():
          case AgentVideoGenerated():
          case AgentImageGenerated():
            // 工具/可视化事件，仅透传给 UI，不影响 loop 逻辑
            yield LoopAgentEvent(event);
          case AgentDone(content: final content):
            if (content.isNotEmpty) {
              buffer.clear();
              buffer.write(content);
            }
            yield LoopAgentEvent(event);
          case AgentError(message: final msg):
            hasError = true;
            yield LoopAgentEvent(event);
            yield LoopError(iteration: planIndex, message: msg);
            return;
          case AgentLoopLimitReached(rounds: final rounds):
            // 仅在未配置预算的旧路径出现
            AppLogger.instance.log(
              '[Loop] 第 $planIndex 次规划内 tool_call 达上限($rounds)，交给下一轮规划',
            );
            buffer.write('\n[系统提示] 本轮工具调用达到上限($rounds次)，请在下一轮基于已执行结果继续推进');
        }
      }

      final output = buffer.toString();
      final previousOutput = lastOutput;
      lastOutput = output;

      AppLogger.instance.log(
        '[Loop] 第 $planIndex 次规划完成, 输出长度=${output.length}',
      );

      final snapshot = progression.attachTo(execBudget.snapshot());
      yield LoopBudgetTick(snapshot);

      // ─── 执行预算耗尽：带完整归因与检查点收尾 ───
      if (budgetStop != null) {
        final checkpoint = _checkpoint(tracker, execBudget, output);
        AppLogger.instance.log(
          '[Loop] 执行预算停止: ${budgetStop.reason.name} '
          '(已用 ${execBudget.usedRounds} 轮 / ${execBudget.usedToolCalls} 次调用)',
        );
        yield LoopExhausted(
          reason: budgetStop.reason,
          snapshot: snapshot,
          checkpoint: checkpoint,
          lastOutput: output,
          hadProgress: budgetStop.hadProgress,
          maxIterations: progression.maxPlans,
        );
        return;
      }

      // 连续失败检测：检查输出中是否包含失败标记
      final hasFailed = _containsFailureMarkers(output);
      _roundFailures.add(hasFailed);

      // 连续3轮失败 → 注入强制反思提示
      if (_roundFailures.length >= 3 &&
          _roundFailures.sublist(_roundFailures.length - 3).every((f) => f)) {
        AppLogger.instance.log('[Loop] 检测到连续3轮失败，注入反思提示');
        messages.add({
          'role': 'system',
          'content': '⚠️ 系统提示：已连续3轮出现失败。请停下来深入分析根本原因，尝试完全不同的方案。不要再重复相同的失败操作。',
        });
      }

      // 检查终止条件
      if (_isDone(output)) {
        final summary = _extractSummary(output, '[LOOP_DONE]');
        AppLogger.instance.log('[Loop] Agent 声明完成: $summary');
        yield LoopDone(
          totalIterations: planIndex,
          summary: summary,
          snapshot: snapshot,
        );
        return;
      }

      if (_isAbort(output)) {
        final reason = _extractSummary(output, '[LOOP_ABORT]');
        AppLogger.instance.log('[Loop] Agent 放弃: $reason');
        yield LoopAbort(iteration: planIndex, reason: reason);
        return;
      }

      // ─── 无进展检测：优先看工具级证据，文本相似度只作为兜底 ───
      //
      // 文本相似度既会误报（换个说法就算"有变化"）也会漏报（卡在同一处），
      // 所以先用 ToolProgressTracker 判定：全部调用重复 = 空转，
      // 没有任何新动作/产物/文件改动/测试变好 = 无进展。
      final lastProgress = tracker.lastRound;
      final bool stalled;
      if (lastProgress != null) {
        stalled = lastProgress.isSpinning || !lastProgress.hasProgress;
      } else {
        stalled =
            previousOutput != null && _isStalledOutput(previousOutput, output);
      }

      if (planIndex >= 2 && stalled) {
        if (lastProgress != null) {
          AppLogger.instance.log('[Loop] 无进展判定：${lastProgress.summary}');
        } else {
          AppLogger.instance.log('[Loop] 无进展判定：文本相似度兜底命中');
        }
        consecutiveStalledRounds++;
        if (consecutiveStalledRounds >= 2) {
          final reason = (lastProgress?.isSpinning ?? false)
              ? BudgetStopReason.repeatedOperations
              : BudgetStopReason.noProgress;
          final checkpoint = _checkpoint(tracker, execBudget, output);
          AppLogger.instance.log('[Loop] 连续两次无实质进展，终止 (${reason.name})');
          yield LoopStalled(
            planIndex,
            checkpoint: checkpoint,
            snapshot: snapshot,
          );
          yield LoopExhausted(
            reason: reason,
            snapshot: snapshot,
            checkpoint: checkpoint,
            lastOutput: output,
            hadProgress: false,
            maxIterations: progression.maxPlans,
          );
          return;
        }
      } else {
        consecutiveStalledRounds = 0;
      }

      if (hasError) return;
    }

    // 外层重新规划预算用完
    AppLogger.instance.log(
      '[Loop] 重新规划预算用完 (${progression.plansUsed}/${progression.maxPlans})',
    );
    yield LoopExhausted(
      reason: BudgetStopReason.planningBudget,
      snapshot: progression.attachTo(execBudget.snapshot()),
      checkpoint: _checkpoint(tracker, execBudget, lastOutput ?? ''),
      lastOutput: lastOutput ?? '',
      hadProgress: tracker.lastRound?.hasProgress ?? true,
      maxIterations: progression.maxPlans,
    );
  }

  /// 生成检查点摘要
  ///
  /// 轮次/调用数一律取 [ExecutionBudget] 的累计口径：追踪器每次 `chat()`
  /// 入口会被 `resetRun()` 清零，而预算跨多次续跑累计。续跑后如果预算在
  /// 第 1 轮就停（典型：token 已见底），追踪器还没来得及记录任何调用，
  /// 摘要就会输出"已用工具轮 136 轮 / 工具调用 0 次"这种自相矛盾的结论。
  LoopCheckpoint _checkpoint(
    ToolProgressTracker tracker,
    ExecutionBudget budget,
    String output,
  ) => tracker.checkpoint(
    lastOutput: output,
    roundsUsed: budget.usedRounds,
    elapsed: budget.elapsed,
    toolCallsOverride: budget.usedToolCalls,
    softRounds: budget.limits.softRounds,
    hardRounds: budget.limits.hardRounds,
    softExtensions: budget.softExtensions,
  );

  // ─── 内部方法 ─────────────────────────────────────────────

  /// 注入 Loop 指令到第一条 system message
  void _injectLoopInstruction() {
    if (messages.isNotEmpty && messages.first['role'] == 'system') {
      final existing = messages.first['content'] as String;
      if (!existing.contains('[LOOP MODE ACTIVE]')) {
        messages.first['content'] = existing + loopSystemInstruction;
      }
    }
  }

  /// 构建后续轮次的 continue prompt
  String _buildContinuePrompt(
    int iteration,
    String? lastOutput,
    ExecutionBudget budget,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('═══ Loop 第 $iteration 轮 ═══');
    buffer.writeln();
    buffer.writeln('⚠️ 上一轮尚未完成任务。请按照以下步骤继续：');
    buffer.writeln();
    buffer.writeln('步骤 0: 【评估上一轮】');
    buffer.writeln('  - 上一轮做了什么操作？');
    buffer.writeln('  - 结果如何？哪些成功了？哪些失败了？');
    buffer.writeln('  - 如果失败，根本原因是什么？');
    buffer.writeln();

    if (lastOutput != null && lastOutput.trim().isNotEmpty) {
      final compact = lastOutput.length > 800
          ? '...${lastOutput.substring(lastOutput.length - 800)}'
          : lastOutput;
      buffer.writeln('【上一轮输出摘要】：');
      buffer.writeln(compact);
      buffer.writeln();
    }

    // 把剩余预算摊在桌面上：让模型自己决定"还要不要继续磨"，
    // 而不是等到被硬上限掐断才发现没有余量了。
    buffer.writeln('【预算余量】：');
    buffer.writeln(
      '  - 工具轮：已用 ${budget.usedRounds} / 硬上限 ${budget.limits.hardRounds}',
    );
    buffer.writeln(
      '  - 工具调用：已用 ${budget.usedToolCalls} / 硬上限 ${budget.limits.hardToolCalls}',
    );
    buffer.writeln('  - 用时：${budget.elapsed.inMinutes} 分钟');
    buffer.writeln('  - 余量紧张时优先"一次把该做的做完"，不要用多轮试探同一个方向。');
    buffer.writeln();

    buffer.writeln('步骤 1: 【调整计划】基于评估结果，决定本轮的行动');
    buffer.writeln('步骤 2: 【实现】执行具体操作');
    buffer.writeln('步骤 3: 【测试】验证结果是否符合预期');
    buffer.writeln('步骤 4: 【评估】判断任务是否完成');
    buffer.writeln();
    buffer.writeln('⚠️ 注意：');
    buffer.writeln('- 不要重复已经成功的操作（重复调用会被判定为空转并直接停止）');
    buffer.writeln('- 必须实际验证结果（运行测试/检查输出）');
    buffer.writeln('- 只有整体完成且验证通过时，才输出 [LOOP_DONE]');
    buffer.writeln(
      '- 互不依赖的多个操作尽量放进同一次回复（并行 tool_call / toolshell_run_parallel），不要一问一答地磨轮次',
    );

    return buffer.toString();
  }

  /// 检查是否真正完成（避免误判）
  bool _isDone(String output) {
    if (!output.contains('[LOOP_DONE]')) return false;

    // 必须在输出的后半部分出现（避免在规划/示例中提到）
    final index = output.indexOf('[LOOP_DONE]');
    final position = index / output.length;

    // [LOOP_DONE] 必须出现在输出的后 40% 位置
    return position >= 0.6;
  }

  /// 检查是否放弃（避免误判）
  bool _isAbort(String output) {
    if (!output.contains('[LOOP_ABORT]')) return false;

    // 必须在输出的后半部分出现
    final index = output.indexOf('[LOOP_ABORT]');
    final position = index / output.length;

    // [LOOP_ABORT] 必须出现在输出的后 40% 位置
    return position >= 0.6;
  }

  /// 检测输出中是否包含失败标记
  bool _containsFailureMarkers(String output) {
    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('失败') ||
        lowerOutput.contains('错误') ||
        lowerOutput.contains('error') ||
        lowerOutput.contains('failed') ||
        lowerOutput.contains('failure') ||
        lowerOutput.contains('not found') ||
        lowerOutput.contains('无法') ||
        lowerOutput.contains('不能');
  }

  /// 从输出中提取标记后的内容作为总结
  String _extractSummary(String output, String marker) {
    final idx = output.indexOf(marker);
    if (idx < 0) return output;
    final after = output.substring(idx + marker.length).trim();
    // 也包含标记前的最后一句话（通常是验证结果）
    final before = output.substring(0, idx).trim();
    final lastSentence = before
        .split('\n')
        .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (lastSentence.isNotEmpty && after.isNotEmpty) {
      return '$lastSentence\n$after';
    }
    return after.isNotEmpty ? after : lastSentence;
  }

  /// 简单的无进展检测：两次输出相似度 > 80%
  bool _isStalledOutput(String prev, String current) {
    if (prev.isEmpty || current.isEmpty) return false;
    // 比较前 500 字符
    final a = prev.length > 500 ? prev.substring(0, 500) : prev;
    final b = current.length > 500 ? current.substring(0, 500) : current;
    if (a == b) return true;
    // 简单 Jaccard: 按行比较
    final setA = a.split('\n').toSet();
    final setB = b.split('\n').toSet();
    if (setA.isEmpty || setB.isEmpty) return false;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union > 0 && (intersection / union) > 0.8;
  }
}

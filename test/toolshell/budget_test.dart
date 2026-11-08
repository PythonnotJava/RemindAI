import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/toolshell/budget.dart';

/// 预算改造（① ② ③ ⑤）的单元测试。
///
/// 覆盖：
/// - ① ExecutionBudget 与 PlanningBudget 的职责分离：软上限看进展、硬上限必停、
///   原地续预算不消耗外层重规划轮。
/// - ② ToolProgressTracker 的"空转/无进展"证据：同签名+同结果 = 重复，
///   新签名/新产物/测试变好 = 有进展。
/// - ③ 任务分档的预算数字。
/// - ⑤ 归因与检查点摘要。
void main() {
  group('③ 任务分档', () {
    test('简单问答 10～20 轮、日常编码 60～100、大型重构 150～200', () {
      expect(ExecutionLimits.of(AgentTaskTier.quick).hardRounds, 20);
      expect(ExecutionLimits.of(AgentTaskTier.coding).hardRounds, 100);
      expect(ExecutionLimits.of(AgentTaskTier.refactor).hardRounds, 200);
      // 软上限必须严格早于硬上限，否则"到线检查进展"就没意义了
      for (final tier in [
        AgentTaskTier.quick,
        AgentTaskTier.coding,
        AgentTaskTier.refactor,
      ]) {
        final limits = ExecutionLimits.of(tier);
        expect(limits.softRounds, lessThan(limits.hardRounds));
        expect(limits.softToolCalls, lessThan(limits.hardToolCalls));
      }
      // ① 的"软 30 轮"落在日常编码档
      expect(ExecutionLimits.of(AgentTaskTier.coding).softRounds, 30);
    });

    test('分档带重规划预算，且自定义档位可覆盖执行预算', () {
      expect(TaskTierPolicy.of(AgentTaskTier.quick).maxPlans, 2);
      expect(TaskTierPolicy.of(AgentTaskTier.coding).maxPlans, 5);
      expect(TaskTierPolicy.of(AgentTaskTier.refactor).maxPlans, 8);

      final custom = TaskTierPolicy.of(AgentTaskTier.coding).withLimits(
        const ExecutionLimits(
          softRounds: 40,
          hardRounds: 80,
          softToolCalls: 60,
          hardToolCalls: 160,
          wallClock: Duration(minutes: 30),
          tokens: 1000000,
        ),
      );
      expect(custom.limits.hardRounds, 80);
      expect(custom.maxPlans, 5);
    });
  });

  group('① 执行预算', () {
    test('软上限只标记"该检查进展"，不是停止', () {
      final budget = ExecutionBudget(limits: ExecutionLimits.quick);
      for (var i = 0; i < ExecutionLimits.quick.softRounds; i++) {
        budget.beginRound();
      }
      expect(budget.softExceeded, isTrue);
      expect(budget.hardStopReason(), BudgetStopReason.none);
    });

    test('原地续预算只抬高软上限，不越过硬上限、不计入重规划', () {
      final limits = ExecutionLimits.quick;
      final budget = ExecutionBudget(limits: limits);
      for (var i = 0; i < limits.softRounds; i++) {
        budget.beginRound();
      }
      final granted = budget.grantSoftExtension();
      expect(granted, greaterThan(0));
      expect(budget.limits.hardRounds, limits.hardRounds);
      expect(budget.limits.softRounds, greaterThan(limits.softRounds));
      expect(budget.softExceeded, isFalse);
      expect(budget.softExtensions, 1);

      // 一直续到贴住硬上限后不能再续
      var guard = 0;
      while (budget.grantSoftExtension() > 0 && guard++ < 100) {}
      expect(budget.limits.softRounds, lessThanOrEqualTo(limits.hardRounds));
    });

    test('硬上限/工具调用总数/墙钟/token 四个维度都能独立触发', () {
      final limits = ExecutionLimits.quick;

      final rounds = ExecutionBudget(limits: limits);
      for (var i = 0; i < limits.hardRounds; i++) {
        rounds.beginRound();
      }
      expect(rounds.hardStopReason(), BudgetStopReason.hardRounds);

      final calls = ExecutionBudget(limits: limits);
      calls.recordToolCalls(limits.hardToolCalls);
      expect(calls.hardStopReason(), BudgetStopReason.toolCalls);

      final tokens = ExecutionBudget(limits: limits);
      tokens.addTokens(limits.tokens);
      expect(tokens.hardStopReason(), BudgetStopReason.tokens);

      final wall = ExecutionBudget(
        limits: limits.copyWith(wallClock: Duration.zero),
      );
      expect(wall.hardStopReason(), BudgetStopReason.wallClock);
    });

    test('一轮可含多次调用：轮次与调用数分别计数', () {
      final budget = ExecutionBudget(limits: ExecutionLimits.quick);
      budget.beginRound();
      budget.recordToolCalls(4);
      expect(budget.usedRounds, 1);
      expect(budget.usedToolCalls, 4);
    });

    test('快照按硬上限给出进度，供 UI 显示"已用/预算"', () {
      final budget = ExecutionBudget(limits: ExecutionLimits.coding);
      for (var i = 0; i < 30; i++) {
        budget.beginRound();
      }
      budget.recordToolCalls(10);
      final snapshot = budget.snapshot(plansUsed: 1, planLimit: 5);
      expect(snapshot.roundText, '30/100');
      expect(snapshot.toolCallText, '10/320');
      expect(snapshot.roundFraction, closeTo(0.3, 1e-9));
      expect(snapshot.planText, '1/5');
    });
  });

  group('① 规划预算与执行预算分离', () {
    test('只有"重新规划"消耗计划额度，续跑单独计数', () {
      final planning = PlanningBudget(maxPlans: 2, maxContinuations: 1);
      expect(planning.consumePlan(), 1);
      expect(planning.canReplan, isTrue);
      expect(planning.consumePlan(), 2);
      expect(planning.canReplan, isFalse);
      // 规划预算耗尽不影响"续跑"额度
      expect(planning.consumeContinuation(), isTrue);
      expect(planning.consumeContinuation(), isFalse);
    });

    test('追加预算能恢复额度', () {
      final planning = PlanningBudget(maxPlans: 1);
      planning.consumePlan();
      expect(planning.canReplan, isFalse);
      planning.grantBonus(plans: 2);
      expect(planning.canReplan, isTrue);
      expect(planning.maxPlans, 3);
    });
  });

  group('② 工具级进展追踪', () {
    test('新签名视为进展，完全重复视为空转', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('toolshell_read', {'path': 'a'}, '{"status":"ok"}');
      tracker.record('toolshell_read', {'path': 'b'}, '{"status":"ok"}');
      var round = tracker.endRound();
      expect(round.calls, 2);
      expect(round.newSignatures, 2);
      expect(round.isSpinning, isFalse);
      expect(round.hasProgress, isTrue);

      tracker.beginRound();
      tracker.record('toolshell_read', {'path': 'a'}, '{"status":"ok"}');
      tracker.record('toolshell_read', {'path': 'a'}, '{"status":"ok"}');
      round = tracker.endRound();
      expect(round.repeats, 2);
      expect(round.isSpinning, isTrue);
      expect(round.hasProgress, isFalse);
    });

    test('参数顺序不同不算新调用；结果变化算"仍在探索"', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('x', {'a': 1, 'b': 2}, 'ok');
      tracker.record('x', {'b': 2, 'a': 1}, 'ok');
      expect(tracker.endRound().repeats, 1);

      tracker.beginRound();
      tracker.record('x', {'a': 1, 'b': 2}, 'changed');
      final round = tracker.endRound();
      expect(round.changedResults, 1);
      expect(round.repeats, 0);
    });

    test('产物/文件改动/测试通过数都能被识别', () {
      // 用工作区内的真实目录（系统临时目录里的产物按设计不计为"进展"）
      final dir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}.tmp_budget_test',
      )..createSync(recursive: true);
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final file = File('${dir.path}${Platform.pathSeparator}out.md')
        ..writeAsStringSync('hi');

      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record(
        'toolshell_write',
        {'path': file.path},
        '{"status":"ok","path":"${file.path.replaceAll('\\', '\\\\')}"}',
      );
      tracker.record('toolshell_exec', {
        'command': 'flutter test',
      }, 'Tests: 12 passed, 0 failed');
      final round = tracker.endRound();
      expect(round.newArtifacts, 1);
      expect(round.filesChanged, 1);
      expect(tracker.testsPassed, 12);
    });

    test('全失败不算进展', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('boom', {'x': 1}, '{"status":"error","detail":"nope"}');
      expect(tracker.endRound().hasProgress, isFalse);
    });

    test('系统临时目录里的中间产物不算进展、也不刷屏', () {
      // run_python 每轮新建 remindai_python_xxx/output/…，路径每次不同，
      // 以前会被当成"新增产物"，让"有没有进展"永远为真。
      final dir = Directory.systemTemp.createTempSync('remindai_python_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final outDir = Directory('${dir.path}${Platform.pathSeparator}output')
        ..createSync();
      final fig = File('${outDir.path}${Platform.pathSeparator}fig_1.png')
        ..writeAsStringSync('png');

      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record(
        'toolshell_run_python',
        {'code': 'draw()'},
        '{"status":"ok","output":"${fig.path.replaceAll('\\', '\\\\')}"}',
      );
      final round = tracker.endRound();
      expect(round.newArtifacts, 0, reason: '临时目录产物不应计为新增产物');
      expect(
        tracker.artifactDisplayNames.any((n) => n.contains('fig_1.png')),
        isTrue,
        reason: '仍应出现在展示列表里（标注为临时）',
      );
      expect(
        tracker.artifactDisplayNames.every(
          (n) => !n.contains('AppData') && !n.contains('Temp'),
        ),
        isTrue,
        reason: '展示名不应带完整长路径',
      );
    });
  });

  group('⑤ 归因与检查点', () {
    test('归因是"人话"，且区分执行预算与规划预算', () {
      expect(BudgetStopReason.repeatedOperations.humanReason, contains('重复'));
      expect(BudgetStopReason.noProgress.isExecution, isTrue);
      expect(BudgetStopReason.hardRounds.isExecution, isTrue);
      expect(BudgetStopReason.planningBudget.isExecution, isFalse);
    });

    test('检查点摘要包含轮次、产物、归因与尾部输出', () {
      const checkpoint = LoopCheckpoint(
        roundsUsed: 12,
        toolCalls: 34,
        repeatedCalls: 3,
        errorCalls: 2,
        toolStats: {'toolshell_read': 20, 'toolshell_write': 14},
        artifacts: ['out.md'],
        filesChanged: 3,
        testsPassed: 12,
        elapsed: Duration(minutes: 3, seconds: 12),
        lastOutput: '最后一行输出',
      );
      final md = checkpoint.toMarkdown(reason: BudgetStopReason.hardRounds);
      expect(md, contains('检查点摘要'));
      expect(md, contains('已用工具轮：12'));
      expect(md, contains('out.md'));
      expect(md, contains('硬上限'));
      expect(md, contains('最后一行输出'));
      // Markdown 段落内单换行会被渲染成空格：列表前必须有空行，
      // 否则整块挤成一行（线上 bug 复现点）。
      expect(md, contains('📊 **检查点摘要**\n\n- 已用工具轮'));
      expect(md, contains('\n\n**停止原因**：'));
    });
  });

  group('追加预算续跑', () {
    test('续跑继承已用额度并放大上限', () {
      final limits = ExecutionLimits.quick;
      final budget = ExecutionBudget(limits: limits);
      for (var i = 0; i < limits.hardRounds; i++) {
        budget.beginRound();
      }
      final snapshot = budget.snapshot();

      final resumed = ExecutionBudget.resume(
        limits: limits.extended(),
        snapshot: snapshot,
      );
      expect(resumed.usedRounds, limits.hardRounds);
      expect(resumed.limits.hardRounds, greaterThan(limits.hardRounds));
      expect(resumed.hardStopReason(), BudgetStopReason.none);
    });

    test('token 上限与轮次同比例放大（否则追加预算后仍被 token 卡死）', () {
      final base = ExecutionLimits.refactor;
      final extended = base.extended();
      final roundRatio = extended.hardRounds / base.hardRounds;
      final tokenRatio = extended.tokens / base.tokens;
      expect(roundRatio, greaterThan(1));
      expect(
        tokenRatio,
        greaterThanOrEqualTo(roundRatio - 0.01),
        reason: '累计 token ≈ 轮次 × 每轮上下文，token 必须跟着轮次一起涨',
      );
    });

    test('反复追加预算必须持续放大（回归：每次都回到分档基准重算）', () {
      // 线上现象：连点三次"追加预算继续"，日志里三次都是
      // 「追加预算：软 90/硬 160 轮」，而已用轮次一路继承到 136——
      // 也就是说第二次之后的追加几乎没有新增额度，点一次只是原地再停一次。
      var budget = ExecutionBudget(limits: ExecutionLimits.coding);
      for (var i = 0; i < 100; i++) {
        budget.beginRound();
      }

      final first = budget.snapshot().extendedLimits();
      expect(first.hardRounds, greaterThan(100));

      final second = ExecutionBudget.resume(
        limits: first,
        snapshot: budget.snapshot(),
      );
      for (var i = 0; i < 60; i++) {
        second.beginRound();
        second.recordToolCalls(1);
      }
      final third = second.snapshot().extendedLimits();
      expect(
        third.hardRounds,
        greaterThan(first.hardRounds),
        reason: '第二次追加必须在上一次的基础上继续涨，而不是退回分档基准',
      );
      expect(third.hardToolCalls, greaterThan(first.hardToolCalls));
      expect(third.wallClock, greaterThan(first.wallClock));
      expect(third.tokens, greaterThan(first.tokens));
    });

    test('追加预算后 token 上限一定高于已用 token（否则点一下又立刻停）', () {
      // 线上现象：token 已经吃到上限 → 点"追加预算继续" → 第 1 轮就被
      // tokens 硬上限再掐断，检查点因此显示"136 轮 / 工具调用 0 次"。
      // 这里复刻当时的真实处境：在跑的上限已被追加过一次（软 90 / 硬 160）。
      final inForce = ExecutionLimits.coding.extended();
      final budget = ExecutionBudget(limits: inForce);
      for (var i = 0; i < 134; i++) {
        budget.beginRound();
      }
      // 把 token 吃到刚好打满（模拟 1 小时长任务把 token 烧光）
      budget.addTokens(inForce.tokens);

      final snapshot = budget.snapshot();
      expect(budget.hardStopReason(), BudgetStopReason.tokens);

      final extended = snapshot.extendedLimits();
      expect(
        extended.tokens,
        greaterThan(snapshot.tokens),
        reason: '新上限必须严格大于已用 token',
      );

      final resumed = ExecutionBudget.resume(
        limits: extended,
        snapshot: snapshot,
      );
      expect(resumed.hardStopReason(), BudgetStopReason.none);
      // 软上限也必须真的留出余量
      expect(resumed.softExceeded, isFalse);
    });

    test('token 按已观测消耗投影：跑满新轮次也不会先被 token 卡住', () {
      final inForce = ExecutionLimits.coding.extended();
      final budget = ExecutionBudget(limits: inForce);
      const usedRounds = 134;
      for (var i = 0; i < usedRounds; i++) {
        budget.beginRound();
      }
      budget.addTokens(9000000); // 134 轮烧掉 9M（≈ 平方增长）

      final extended = budget.snapshot().extendedLimits();
      final projectedFullRun =
          9000000 * math.pow(extended.hardRounds / usedRounds, 2);
      expect(
        extended.tokens.toDouble(),
        greaterThanOrEqualTo(projectedFullRun * 0.95),
        reason: 'token 上限要覆盖"跑满新轮次上限"的用量，否则又会被 token 先掐断',
      );
    });

    test('连点多次追加预算：token 额度只增不减且不失控', () {
      // 防两个方向的坑：
      // ① 越追加越少（第二次追加比第一次的额度还小，点了等于白点）；
      // ② 在已膨胀的上限上再乘一次 → 连点三次就把预算抬到几亿 token。
      var limits = ExecutionLimits.coding.extended();
      var usedTokens = 9600000;
      var usedRounds = 136;
      var previousCap = limits.tokens;

      for (var click = 1; click <= 3; click++) {
        final snapshot = BudgetSnapshot(
          usedRounds: usedRounds,
          softRounds: limits.softRounds,
          hardRounds: limits.hardRounds,
          usedToolCalls: 176,
          softToolCalls: limits.softToolCalls,
          hardToolCalls: limits.hardToolCalls,
          tokens: usedTokens,
          tokenLimit: limits.tokens,
          elapsed: const Duration(minutes: 65),
          wallClock: limits.wallClock,
        );
        limits = snapshot.extendedLimits();

        expect(
          limits.tokens,
          greaterThan(usedTokens),
          reason: '第 $click 次追加后仍必须比已用 token 多',
        );
        expect(
          limits.tokens,
          lessThanOrEqualTo(usedTokens * 8),
          reason: '第 $click 次追加不允许把额度放大到已用 token 的 8 倍以上',
        );
        expect(limits.tokens, greaterThanOrEqualTo(previousCap));
        expect(limits.hardRounds, greaterThan(usedRounds));

        previousCap = limits.tokens;
        // 假设这次真的把新增轮次跑完（按平方增长的消耗继续往上走）
        usedTokens = limits.tokens;
        usedRounds = limits.hardRounds;
      }
    });

    test('快照可还原"真实生效的上限"（软上限被原地续过也不失真）', () {
      final budget = ExecutionBudget(limits: ExecutionLimits.coding);
      for (var i = 0; i < 31; i++) {
        budget.beginRound();
      }
      budget.grantSoftExtension();

      final snapshot = budget.snapshot();
      final limits = snapshot.toLimits();
      expect(limits.softRounds, budget.limits.softRounds);
      expect(limits.hardRounds, budget.limits.hardRounds);
      expect(limits.tokens, budget.limits.tokens);
      expect(limits.wallClock, budget.limits.wallClock);
    });
  });

  // ─── 回归：用户反馈的两个 bug ───────────────────────────────
  // ① 检查点说"工具调用 211 次"，预算却说"93/320"（追踪器跨 run 累积）；
  // ② 88/100 轮就因"最近一轮无进展"停止，且检查点把 node.exe 等
  //    系统可执行文件列成"新增产物"。
  group('⑥ 计数口径与停止判定（回归）', () {
    test('resetRun 清零本次统计，但保留"重复调用"的识别能力', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('toolshell_exec', {'cmd': 'ls'}, '{"status":"ok"}');
      tracker.endRound();
      expect(tracker.checkpoint().toolCalls, 1);

      tracker.resetRun();
      expect(tracker.checkpoint().toolCalls, 0);
      expect(tracker.checkpoint().artifacts, isEmpty);

      // 记忆保留：同样的调用再来一次仍判为重复/空转
      tracker.beginRound();
      tracker.record('toolshell_exec', {'cmd': 'ls'}, '{"status":"ok"}');
      final round = tracker.endRound();
      expect(round.repeats, 1);
      expect(round.isSpinning, isTrue);
      expect(round.isNoProgress, isTrue);
    });

    test('系统可执行文件与工作区外文件都不算产物', () {
      final base = Directory('${Directory.current.path}/.tmp_prog_artifact');
      if (base.existsSync()) base.deleteSync(recursive: true);
      final ws = Directory('${base.path}/ws')..createSync(recursive: true);
      final other = Directory('${base.path}/other')
        ..createSync(recursive: true);
      final insideFile = File('${ws.path}/result.txt')..writeAsStringSync('产物');
      final outsideFile = File('${other.path}/noise.txt')
        ..writeAsStringSync('噪音');
      addTearDown(() {
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      final tracker = ToolProgressTracker(workspaceRoot: ws.path);

      // 工作区内 → 算产物
      tracker.beginRound();
      tracker.record('toolshell_write', {
        'path': insideFile.path,
      }, jsonEncode({'status': 'ok', 'path': insideFile.path}));
      expect(tracker.endRound().newArtifacts, 1);

      // 工作区外 → 不算
      tracker.beginRound();
      tracker.record('toolshell_exec', {
        'cmd': 'where python',
      }, jsonEncode({'status': 'ok', 'path': outsideFile.path}));
      expect(tracker.endRound().newArtifacts, 0);

      // 只读/探测类工具完全不扫产物（历史 bug：列出 20 个 .exe）
      final probeOnly = ToolProgressTracker(workspaceRoot: ws.path);
      probeOnly.beginRound();
      probeOnly.record(
        'system_probe',
        {},
        jsonEncode({
          'status': 'ok',
          'tools': [
            {'path': insideFile.path},
          ],
        }),
      );
      expect(probeOnly.endRound().newArtifacts, 0);
    });

    test('重跑同一命令但结果变了 = 有进展（不算空转）', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('toolshell_exec', {'cmd': 'npm test'}, '3 passed');
      tracker.endRound();

      tracker.beginRound();
      tracker.record('toolshell_exec', {'cmd': 'npm test'}, '7 passed');
      final round = tracker.endRound();
      expect(round.changedResults, 1);
      expect(round.hasProgress, isTrue);
      expect(round.isNoProgress, isFalse);
    });

    test('整轮全部失败 = 明确的"无进展"信号', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('toolshell_exec', {
        'cmd': 'a',
      }, jsonEncode({'status': 'error', 'message': 'boom-a'}));
      tracker.record('toolshell_exec', {
        'cmd': 'b',
      }, jsonEncode({'status': 'error', 'message': 'boom-b'}));
      final round = tracker.endRound();
      expect(round.errors, 2);
      expect(round.isNoProgress, isTrue);
    });

    test('检查点用预算口径覆盖调用数，并标明软上限/续预算次数', () {
      final tracker = ToolProgressTracker();
      tracker.beginRound();
      tracker.record('toolshell_exec', {'c': '1'}, '{"status":"ok"}');
      tracker.endRound();

      final checkpoint = tracker.checkpoint(
        roundsUsed: 88,
        toolCallsOverride: 93,
        softRounds: 30,
        hardRounds: 100,
        softExtensions: 4,
      );
      // 预算口径优先，两个数字必须一致
      expect(checkpoint.toolCalls, 93);

      final markdown = checkpoint.toMarkdown(
        reason: BudgetStopReason.noProgress,
      );
      expect(markdown, contains('88 轮'));
      expect(markdown, contains('93 次'));
      expect(markdown, contains('软上限 30'));
      expect(markdown, contains('已原地续 4 次'));
      expect(markdown, contains('硬上限 100'));
    });
  });
}

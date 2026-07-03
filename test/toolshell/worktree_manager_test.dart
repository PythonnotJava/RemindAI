import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/agent/tool_middleware.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';
import 'package:remind_ai/core/toolshell/worktree_manager.dart';

/// 验证 Worktree 隔离功能 (toolshell_worktree_start/finish 背后的核心逻辑)。
///
/// 测试对象是真实克隆的大型开源项目 Express.js:
///   C:\Users\25654\Desktop\test\worktree_demo_project
/// 之所以用真实项目而不是临时合成的小仓库，是为了在有意义的提交历史/
/// 文件规模下验证 worktree add/merge/discard 的实际行为——这与
/// toolshell_run_parallel 那次"效果不明显"的反馈是同一个教训:
/// 简单的玩具场景验证不出真实价值，真实项目才有说服力。
///
/// 测试完成后不清理 worktree_demo_project 仓库本身，保留代码与产物供人工检查。
/// 但每个测试内部产生的临时 worktree/分支会按各自场景收尾(merge 或 discard)，
/// 避免反复运行本文件时在 git 历史里无限堆积孤立分支。
void main() {
  const projectRoot = r'C:\Users\25654\Desktop\test\worktree_demo_project';

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', ['-C', cwd ?? projectRoot, ...args]);

  Future<bool> hasUncommittedChanges(String dir) async {
    final r = await git(['status', '--porcelain'], cwd: dir);
    return r.stdout.toString().trim().isNotEmpty;
  }

  setUpAll(() {
    expect(
      Directory(projectRoot).existsSync(),
      isTrue,
      reason: '需要先准备好真实的大型 git 项目: $projectRoot (已通过 git clone express.js 准备)',
    );
  });

  setUp(() async {
    // 每个测试开始前确认主仓库处于干净状态，避免上一个测试的残留状态互相干扰。
    final dirty = await hasUncommittedChanges(projectRoot);
    if (dirty) {
      await git(['reset', '--hard', 'HEAD']);
      await git(['clean', '-fd']);
    }
  });

  group('kApprovalRequiredTools 权限收口', () {
    test('worktree_start/finish 已纳入需确认工具集合', () {
      expect(
        kApprovalRequiredTools.contains('toolshell_worktree_start'),
        isTrue,
      );
      expect(
        kApprovalRequiredTools.contains('toolshell_worktree_finish'),
        isTrue,
      );
    });
  });

  group('WorktreeManager - 真实大型项目场景', () {
    test('场景1: start() 在 .toolshell/worktrees/ 下创建隔离工作树', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final result = await manager.start(name: 'scenario1-inspect');

      print('[场景1] start() 结果: ${jsonEncode(result)}');

      expect(result['status'], 'ok');
      final worktreePath = result['worktree_path'] as String;
      final branch = result['branch'] as String;

      expect(branch, startsWith('toolshell-wt/scenario1-inspect'));
      expect(
        p.isWithin(
          p.join(projectRoot, '.toolshell', 'worktrees'),
          worktreePath,
        ),
        isTrue,
        reason: '工作树必须落在 .toolshell/worktrees/ 下',
      );
      expect(await Directory(worktreePath).exists(), isTrue);

      // 工作树内应该能看到主仓库的文件 (从 HEAD 派生)
      expect(await File(p.join(worktreePath, 'package.json')).exists(), isTrue);

      // 验证 git worktree list 确实登记了它 (git 输出可能用 / 也可能用 \，两种都接受)
      final listResult = await git(['worktree', 'list']);
      final listOutput = listResult.stdout.toString();
      print('[场景1] git worktree list:\n$listOutput');
      final registered =
          listOutput.contains(worktreePath) ||
          listOutput.contains(worktreePath.replaceAll('\\', '/'));
      expect(
        registered,
        isTrue,
        reason: 'worktree 应该出现在 git worktree list 输出中',
      );

      // 收尾: 丢弃这个纯验证用的工作树，不留痕迹
      final finishResult = await manager.finish(
        worktreePath: worktreePath,
        action: 'discard',
      );
      print('[场景1] 收尾 discard: ${jsonEncode(finishResult)}');
      expect(finishResult['status'], 'ok');
      expect(await Directory(worktreePath).exists(), isFalse);
    });

    test('场景2: 隔离期间的文件改动完全不影响主工作目录，merge 后才落地', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final startResult = await manager.start(name: 'scenario2-isolated-write');
      expect(startResult['status'], 'ok');
      final worktreePath = startResult['worktree_path'] as String;

      // 模拟 Executor 的 projectRoot 已被重定向到隔离工作树 —— 这正是
      // agent_context.dart 里 effectiveRoot 重定向逻辑要达到的效果。
      final isolatedExecutor = Executor(
        projectRoot: worktreePath,
        permissionMode: PermissionMode.auto,
      );
      final writeRaw = await isolatedExecutor.run('toolshell_write', {
        'path': 'WORKTREE_EXPERIMENT.md',
        'content': '# 隔离实验\n这个文件只应该出现在隔离工作树里，直到 merge。\n',
        'mode': 'create',
      });
      final writeResult = jsonDecode(writeRaw) as Map<String, dynamic>;
      print('[场景2] 隔离工作树内写入结果: ${jsonEncode(writeResult)}');
      expect(writeResult['status'], 'ok');

      // 关键验证: 主工作目录此时看不到这个文件 (隔离生效)
      final mainSideFile = File(p.join(projectRoot, 'WORKTREE_EXPERIMENT.md'));
      expect(
        await mainSideFile.exists(),
        isFalse,
        reason: '隔离期间的改动不应该出现在主工作目录',
      );

      // merge 回主分支
      final finishResult = await manager.finish(
        worktreePath: worktreePath,
        action: 'merge',
        commitMessage: '[worktree测试] 场景2实验性改动',
      );
      print('[场景2] merge 结果: ${jsonEncode(finishResult)}');
      expect(finishResult['status'], 'ok');
      expect(finishResult['action'], 'merge');

      // merge 之后，主工作目录应该能看到这个文件了
      expect(
        await mainSideFile.exists(),
        isTrue,
        reason: 'merge 后文件应该出现在主工作目录',
      );
      final content = await mainSideFile.readAsString();
      expect(content, contains('隔离实验'));

      // 工作树已被 finish 清理
      expect(await Directory(worktreePath).exists(), isFalse);

      print('[场景2] 结论: 隔离期间改动对主目录不可见，merge 后才正确落地，工作树自动清理');
    });

    test('场景3: discard 丢弃改动，主工作目录和 git 历史完全不受影响', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final beforeLog = await git(['log', '--oneline', '-1']);
      final beforeHead = beforeLog.stdout.toString().trim();

      final startResult = await manager.start(name: 'scenario3-discard-me');
      expect(startResult['status'], 'ok');
      final worktreePath = startResult['worktree_path'] as String;
      final branch = startResult['branch'] as String;

      final isolatedExecutor = Executor(
        projectRoot: worktreePath,
        permissionMode: PermissionMode.auto,
      );
      await isolatedExecutor.run('toolshell_write', {
        'path': 'SHOULD_NEVER_PERSIST.txt',
        'content': '这个实验失败了，应该被完全丢弃',
        'mode': 'create',
      });

      final finishResult = await manager.finish(
        worktreePath: worktreePath,
        action: 'discard',
      );
      print('[场景3] discard 结果: ${jsonEncode(finishResult)}');
      expect(finishResult['status'], 'ok');
      expect(finishResult['action'], 'discard');

      // 工作树目录彻底消失
      expect(await Directory(worktreePath).exists(), isFalse);
      // 分支被删除
      final branchList = await git(['branch', '--list', branch]);
      expect(branchList.stdout.toString().trim(), isEmpty);
      // 主目录没有多出文件
      expect(
        await File(p.join(projectRoot, 'SHOULD_NEVER_PERSIST.txt')).exists(),
        isFalse,
      );
      // 主分支 HEAD 没有变化 (没有产生任何新提交)
      final afterLog = await git(['log', '--oneline', '-1']);
      expect(afterLog.stdout.toString().trim(), beforeHead);

      print('[场景3] 结论: discard 后工作树/分支/文件全部消失，主分支历史零变化');
    });

    test('场景4: 非 git 仓库调用 start() 返回 NOT_GIT_REPO', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'worktree_not_git_',
      );
      try {
        final manager = WorktreeManager(workDir: tempDir.path);
        final result = await manager.start(name: 'should-fail');
        print('[场景4] 非 git 目录结果: ${jsonEncode(result)}');
        expect(result['status'], 'error');
        expect(result['code'], 'NOT_GIT_REPO');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('场景5: 主工作目录存在未提交改动时，merge 被拒绝且工作树保留不丢失', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final startResult = await manager.start(name: 'scenario5-main-dirty');
      expect(startResult['status'], 'ok');
      final worktreePath = startResult['worktree_path'] as String;

      // 故意弄脏主工作目录 (模拟用户正在进行中的、尚未提交的工作)
      final dirtyMarker = File(p.join(projectRoot, 'USER_WIP.txt'));
      await dirtyMarker.writeAsString('用户正在写的、还没提交的内容');

      final finishResult = await manager.finish(
        worktreePath: worktreePath,
        action: 'merge',
      );
      print('[场景5] 主目录脏时尝试 merge: ${jsonEncode(finishResult)}');
      expect(finishResult['status'], 'error');
      expect(finishResult['code'], 'MAIN_DIRTY');

      // 工作树应该还在，改动没有丢失
      expect(await Directory(worktreePath).exists(), isTrue);

      // 清理: 恢复主目录干净状态，再丢弃这个验证用的工作树
      await dirtyMarker.delete();
      final cleanupResult = await manager.finish(
        worktreePath: worktreePath,
        action: 'discard',
      );
      expect(cleanupResult['status'], 'ok');

      print('[场景5] 结论: 主目录脏时拒绝自动合并，避免冲突；工作树内容不会因此丢失');
    });

    test('场景6: finish() 对不存在的工作树路径返回 WORKTREE_NOT_FOUND', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final fakePath = p.join(
        projectRoot,
        '.toolshell',
        'worktrees',
        'does_not_exist_at_all',
      );
      final result = await manager.finish(
        worktreePath: fakePath,
        action: 'discard',
      );
      print('[场景6] 结果: ${jsonEncode(result)}');
      expect(result['status'], 'error');
      expect(result['code'], 'WORKTREE_NOT_FOUND');
    });

    test('场景7: finish() action 非法值被拒绝', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final startResult = await manager.start(name: 'scenario7-bad-action');
      final worktreePath = startResult['worktree_path'] as String;

      final result = await manager.finish(
        worktreePath: worktreePath,
        action: 'delete_everything',
      );
      print('[场景7] 非法 action 结果: ${jsonEncode(result)}');
      expect(result['status'], 'error');
      expect(result['code'], 'INVALID_ARGS');

      // 工作树未被误动，正常丢弃收尾
      expect(await Directory(worktreePath).exists(), isTrue);
      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });
  });
}

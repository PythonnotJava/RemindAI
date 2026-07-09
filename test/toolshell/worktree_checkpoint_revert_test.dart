import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/toolshell/worktree_manager.dart';

/// 验证 checkpoint/revert/listCheckpoints — "实验分支内部存档/读档"能力。
///
/// 与 worktree_manager_test.dart 不同，这里不依赖外部预先准备好的大型
/// 仓库，而是在临时目录里自建一个最小 git 仓库(init + 一次初始提交)，
/// 保证测试在任何机器上都能独立运行，不因外部路径缺失而失败。
void main() {
  late Directory tempRoot;
  late String projectRoot;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', ['-C', cwd ?? projectRoot, ...args]);

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('worktree_cp_test_');
    projectRoot = tempRoot.path;

    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await File(
      p.join(projectRoot, 'README.md'),
    ).writeAsString('# demo\n初始内容\n');
    await git(['add', '-A']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {
      // Windows 上有时文件句柄未及时释放，删除失败不影响测试结论，忽略。
    }
  });

  group('WorktreeManager.checkpoint/revert/listCheckpoints', () {
    test('checkpoint() 在无未提交改动时仍能在当前 HEAD 创建存档点', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'cp-basic');
      expect(start['status'], 'ok');
      final worktreePath = start['worktree_path'] as String;

      final cp = await manager.checkpoint(worktreePath: worktreePath);
      print('[存档-基础] ${cp.toString()}');
      expect(cp['status'], 'ok');
      expect(cp['had_uncommitted_changes'], isFalse);
      expect(cp['checkpoint'], isNotEmpty);

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('checkpoint() 有未提交改动时自动提交后再打存档点标记', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'cp-dirty');
      final worktreePath = start['worktree_path'] as String;

      await File(
        p.join(worktreePath, 'feature.txt'),
      ).writeAsString('实验性改动 v1');

      final cp = await manager.checkpoint(
        worktreePath: worktreePath,
        label: 'v1-done',
      );
      print('[存档-脏改动] ${cp.toString()}');
      expect(cp['status'], 'ok');
      expect(cp['had_uncommitted_changes'], isTrue);

      // 存档后应该没有未提交改动了(已被自动 commit)
      final dirtyCheck = await git(['status', '--porcelain'], cwd: worktreePath);
      expect(dirtyCheck.stdout.toString().trim(), isEmpty);

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('revert() 能把工作树退回到之前的存档点，之后的改动被清除', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'cp-revert');
      final worktreePath = start['worktree_path'] as String;
      final featureFile = File(p.join(worktreePath, 'feature.txt'));

      // 第一步改动 + 存档
      await featureFile.writeAsString('第一步的内容');
      final cp1 = await manager.checkpoint(
        worktreePath: worktreePath,
        label: 'step1',
      );
      expect(cp1['status'], 'ok');
      final checkpoint1 = cp1['checkpoint'] as String;

      // 第二步改动(这一步"走偏了")
      await featureFile.writeAsString('第二步的内容(错误的方向)');
      await File(
        p.join(worktreePath, 'oops.txt'),
      ).writeAsString('这个文件不该存在');

      // 退回第一步存档点
      final revertResult = await manager.revert(
        worktreePath: worktreePath,
        checkpoint: checkpoint1,
      );
      print('[回退] ${revertResult.toString()}');
      expect(revertResult['status'], 'ok');

      // feature.txt 应该恢复成第一步内容
      expect(await featureFile.readAsString(), '第一步的内容');
      // 第二步新增的未跟踪文件应该被清理掉
      expect(
        await File(p.join(worktreePath, 'oops.txt')).exists(),
        isFalse,
        reason: 'revert 应清除存档点之后产生的未跟踪文件，语义上完全变回存档那一刻',
      );

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('listCheckpoints() 按创建顺序列出全部存档点', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'cp-list');
      final worktreePath = start['worktree_path'] as String;

      await File(p.join(worktreePath, 'a.txt')).writeAsString('a');
      final cp1 = await manager.checkpoint(
        worktreePath: worktreePath,
        label: 'first',
      );
      await File(p.join(worktreePath, 'b.txt')).writeAsString('b');
      final cp2 = await manager.checkpoint(
        worktreePath: worktreePath,
        label: 'second',
      );

      final listResult = await manager.listCheckpoints(worktreePath);
      print('[存档列表] ${listResult.toString()}');
      expect(listResult['status'], 'ok');
      final names = (listResult['checkpoints'] as List).cast<String>();
      expect(names, contains(cp1['checkpoint']));
      expect(names, contains(cp2['checkpoint']));
      // 创建顺序: first 应该排在 second 之前
      expect(
        names.indexOf(cp1['checkpoint']) < names.indexOf(cp2['checkpoint']),
        isTrue,
      );

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('checkpoint()/revert() 拒绝作用于主工作目录(路径边界保护)', () async {
      final manager = WorktreeManager(workDir: projectRoot);

      final cpResult = await manager.checkpoint(worktreePath: projectRoot);
      print('[边界保护-checkpoint] ${cpResult.toString()}');
      expect(cpResult['status'], 'error');
      expect(cpResult['code'], 'PATH_OUT_OF_SCOPE');

      final revertResult = await manager.revert(
        worktreePath: projectRoot,
        checkpoint: 'HEAD',
      );
      print('[边界保护-revert] ${revertResult.toString()}');
      expect(revertResult['status'], 'error');
      expect(revertResult['code'], 'PATH_OUT_OF_SCOPE');
    });

    test('revert() 对不存在的存档点名返回 CHECKPOINT_NOT_FOUND', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'cp-badref');
      final worktreePath = start['worktree_path'] as String;

      final result = await manager.revert(
        worktreePath: worktreePath,
        checkpoint: 'this-checkpoint-does-not-exist',
      );
      print('[无效存档点] ${result.toString()}');
      expect(result['status'], 'error');
      expect(result['code'], 'CHECKPOINT_NOT_FOUND');

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });
  });

  group('WorktreeManager.diff', () {
    test('diff(detail=false) 返回 --stat 摘要(文件级)', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'diff-stat');
      final worktreePath = start['worktree_path'] as String;

      await File(p.join(worktreePath, 'new_file.txt')).writeAsString('hello');
      await File(p.join(worktreePath, 'README.md')).writeAsString('# changed\n');
      // 需要 add 才能让 diff 看到新文件(对比的是 base..worktree 工作目录)
      await git(['add', '-A'], cwd: worktreePath);

      final result = await manager.diff(worktreePath: worktreePath);
      print('[diff-stat] ${result.toString()}');
      expect(result['status'], 'ok');
      expect(result['mode'], 'stat');
      final diffText = result['diff'] as String;
      expect(diffText, contains('new_file.txt'));
      expect(diffText, contains('README.md'));

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('diff(detail=true) 返回逐行完整差异', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'diff-full');
      final worktreePath = start['worktree_path'] as String;

      // 使用纯 ASCII 内容避免 Windows git diff 输出中文乱码导致断言失败
      await File(
        p.join(worktreePath, 'README.md'),
      ).writeAsString('# brand-new content\ncompletely replaced\n');
      await git(['add', '-A'], cwd: worktreePath);

      final result = await manager.diff(
        worktreePath: worktreePath,
        detail: true,
      );
      print('[diff-full] mode=${result['mode']}');
      expect(result['status'], 'ok');
      expect(result['mode'], 'full');
      final diffText = result['diff'] as String;
      // 完整 diff 应该包含 +/- 行标记
      expect(diffText, contains('+'));
      expect(diffText, contains('brand-new content'));

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('diff(paths: [...]) 只返回指定文件的差异', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'diff-paths');
      final worktreePath = start['worktree_path'] as String;

      await File(p.join(worktreePath, 'a.txt')).writeAsString('aaa');
      await File(p.join(worktreePath, 'b.txt')).writeAsString('bbb');
      await git(['add', '-A'], cwd: worktreePath);

      final result = await manager.diff(
        worktreePath: worktreePath,
        detail: true,
        paths: ['a.txt'],
      );
      print('[diff-paths] ${result.toString().substring(0, 200)}');
      expect(result['status'], 'ok');
      final diffText = result['diff'] as String;
      expect(diffText, contains('a.txt'));
      expect(diffText, isNot(contains('b.txt')));

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });

    test('diff() 无改动时返回无差异提示', () async {
      final manager = WorktreeManager(workDir: projectRoot);
      final start = await manager.start(name: 'diff-empty');
      final worktreePath = start['worktree_path'] as String;

      // 不做任何改动直接 diff
      final result = await manager.diff(worktreePath: worktreePath);
      print('[diff-empty] ${result.toString()}');
      expect(result['status'], 'ok');
      expect(result['diff'], '(无差异)');

      await manager.finish(worktreePath: worktreePath, action: 'discard');
    });
  });
}

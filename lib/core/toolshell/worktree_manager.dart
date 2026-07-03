import 'dart:io';

import 'package:path/path.dart' as p;

/// Worktree 隔离管理器 — 纯 Git 操作逻辑，不依赖 Riverpod。
///
/// 设计背景：LLM 有时想做"实验性"的大改动(重构/升级依赖/尝试性方案)，
/// 但又不希望这些改动在验证通过之前弄乱用户的主工作目录。Git worktree
/// 天然适合这个场景——在同一个仓库上开一个独立分支的工作树，改动
/// 完全隔离，验证通过后 merge 回主分支，不满意就直接丢弃整个工作树。
///
/// 这个类只负责"怎么做"（git 命令的组合与容错），"什么时候用"完全是
/// LLM 的判断——框架不做任何自动触发或风险探测。
///
/// 工作树统一放在 `<workDir>/.toolshell/worktrees/<folder>/`，与
/// `.toolshell/skills/`、`.toolshell/_staging/` 保持同一约定。
class WorktreeManager {
  /// 真正的项目根目录 (main workdir)，worktree 始终从这里的 git 仓库派生。
  final String workDir;

  WorktreeManager({required this.workDir});

  String get _worktreesRoot => p.join(workDir, '.toolshell', 'worktrees');

  /// 启动一个隔离工作树：
  /// 1. 校验 workDir 处于一个 git 工作区内
  /// 2. 在 `.toolshell/worktrees/<folder>/` 新建工作树 + 新分支(基于当前 HEAD)
  ///
  /// [name] 可选，用作分支/目录名的可读前缀；不传则用 `exp`。
  Future<Map<String, dynamic>> start({String? name}) async {
    final isRepo = await _isInsideGitWorkTree(workDir);
    if (!isRepo) {
      return {
        'status': 'error',
        'code': 'NOT_GIT_REPO',
        'detail':
            '当前工作目录不是 git 仓库(或未初始化)，worktree 隔离需要 git 仓库支持。'
            '可先执行 `git init` 后重试。',
      };
    }

    await _ensureToolshellExcluded();

    final slug = _slugify(name) ?? 'exp';
    final stamp = _timestamp();
    final folderName = '${slug}_$stamp';
    final branch = 'toolshell-wt/$folderName';
    final worktreePath = p.join(_worktreesRoot, folderName);

    // 确保父目录存在 (git worktree add 会创建叶子目录，但保险起见先建好父级)
    await Directory(_worktreesRoot).create(recursive: true);

    final result = await Process.run('git', [
      '-C',
      workDir,
      'worktree',
      'add',
      '-b',
      branch,
      worktreePath,
    ]);

    if (result.exitCode != 0) {
      return {
        'status': 'error',
        'code': 'WORKTREE_ADD_FAILED',
        'detail': '创建工作树失败: ${_stderr(result)}',
      };
    }

    return {
      'status': 'ok',
      'worktree_path': p.normalize(worktreePath),
      'branch': branch,
      'message':
          '隔离工作树已就绪，分支 "$branch"。从现在起，你的文件读写/命令执行会'
          '自动落在这个隔离工作树里，不会影响主工作目录。改完并验证通过后，'
          '调用 toolshell_worktree_finish(action="merge") 合并回主分支；'
          '不满意则调用 toolshell_worktree_finish(action="discard") 直接丢弃。',
    };
  }

  /// 结束一个隔离工作树。
  ///
  /// [action] = "merge": 若工作树有未提交改动先自动提交，再合并回主分支，
  ///            成功后移除工作树、删除分支(已合并，安全删除)。
  /// [action] = "discard": 直接强制移除工作树 + 强制删除分支，不保留任何改动。
  Future<Map<String, dynamic>> finish({
    required String worktreePath,
    required String action,
    String? commitMessage,
  }) async {
    if (action != 'merge' && action != 'discard') {
      return {
        'status': 'error',
        'code': 'INVALID_ARGS',
        'detail': 'action 必须是 "merge" 或 "discard"，收到: $action',
      };
    }

    final dir = Directory(worktreePath);
    if (!await dir.exists()) {
      return {
        'status': 'error',
        'code': 'WORKTREE_NOT_FOUND',
        'detail': '工作树目录不存在: $worktreePath (可能已被手动删除)',
      };
    }

    final branch = await _currentBranch(worktreePath);
    if (branch == null) {
      return {
        'status': 'error',
        'code': 'BRANCH_RESOLVE_FAILED',
        'detail': '无法确定工作树 $worktreePath 当前所在分支',
      };
    }

    if (action == 'discard') {
      final removed = await _removeWorktree(worktreePath, force: true);
      if (!removed) {
        return {
          'status': 'error',
          'code': 'WORKTREE_REMOVE_FAILED',
          'detail': '丢弃工作树失败，请检查是否有其他进程占用该目录',
        };
      }
      await Process.run('git', ['-C', workDir, 'branch', '-D', branch]);
      return {
        'status': 'ok',
        'action': 'discard',
        'branch': branch,
        'message': '已丢弃隔离工作树及分支 "$branch"，主工作目录未受影响。',
      };
    }

    // ── action == merge ──
    final dirty = await _hasUncommittedChanges(worktreePath);
    if (dirty) {
      final msg = (commitMessage != null && commitMessage.trim().isNotEmpty)
          ? commitMessage.trim()
          : 'toolshell worktree: 自动提交(合并前)';
      final addResult = await Process.run('git', [
        '-C',
        worktreePath,
        'add',
        '-A',
      ]);
      if (addResult.exitCode != 0) {
        return {
          'status': 'error',
          'code': 'AUTO_COMMIT_FAILED',
          'detail': '合并前自动提交失败(git add): ${_stderr(addResult)}',
        };
      }
      final commitResult = await Process.run('git', [
        '-C',
        worktreePath,
        'commit',
        '-m',
        msg,
      ]);
      if (commitResult.exitCode != 0) {
        return {
          'status': 'error',
          'code': 'AUTO_COMMIT_FAILED',
          'detail': '合并前自动提交失败(git commit): ${_stderr(commitResult)}',
        };
      }
    }

    // 主工作目录若有未提交改动，拒绝自动合并——不代替用户处理主目录的
    // 未提交内容，避免合并冲突把用户正在进行中的工作弄乱。
    // 注意：.toolshell/ 本身已通过 _ensureToolshellExcluded() 写入
    // .git/info/exclude，不会被 git status 误判为"未提交改动"。
    await _ensureToolshellExcluded();
    final mainDirty = await _hasUncommittedChanges(workDir);
    if (mainDirty) {
      return {
        'status': 'error',
        'code': 'MAIN_DIRTY',
        'detail':
            '主工作目录存在未提交的改动，为避免冲突不会自动合并。'
            '请先在主工作目录提交或清理改动，再重新调用 finish(action="merge")；'
            '工作树 "$worktreePath" 的改动已安全保留，未丢失。',
      };
    }

    final mergeResult = await Process.run('git', [
      '-C',
      workDir,
      'merge',
      '--no-ff',
      branch,
      '-m',
      'Merge toolshell worktree: $branch',
    ]);
    if (mergeResult.exitCode != 0) {
      return {
        'status': 'error',
        'code': 'MERGE_FAILED',
        'detail':
            '合并失败(可能存在冲突): ${_stderr(mergeResult)}。'
            '工作树 "$worktreePath" 保留未动，可手动处理冲突后重试，'
            '或调用 finish(action="discard") 放弃。',
      };
    }

    final removed = await _removeWorktree(worktreePath, force: true);
    if (removed) {
      // 已合并，分支可安全删除 (-d 而非 -D，合并未完成时会拒绝，双重保险)
      await Process.run('git', ['-C', workDir, 'branch', '-d', branch]);
    }

    return {
      'status': 'ok',
      'action': 'merge',
      'branch': branch,
      'worktree_removed': removed,
      'message':
          '已合并分支 "$branch" 到主分支${removed ? "，并清理了隔离工作树" : "(工作树清理失败，可忽略或手动删除)"}。',
    };
  }

  // ─── 内部辅助 ─────────────────────────────────────────────

  Future<bool> _isInsideGitWorkTree(String dir) async {
    try {
      final result = await Process.run('git', [
        '-C',
        dir,
        'rev-parse',
        '--is-inside-work-tree',
      ]);
      return result.exitCode == 0 && result.stdout.toString().trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<String?> _currentBranch(String dir) async {
    try {
      final result = await Process.run('git', [
        '-C',
        dir,
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]);
      if (result.exitCode != 0) return null;
      final branch = result.stdout.toString().trim();
      return branch.isEmpty ? null : branch;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasUncommittedChanges(String dir) async {
    final result = await Process.run('git', [
      '-C',
      dir,
      'status',
      '--porcelain',
    ]);
    return result.stdout.toString().trim().isNotEmpty;
  }

  Future<bool> _removeWorktree(
    String worktreePath, {
    bool force = false,
  }) async {
    final result = await Process.run('git', [
      '-C',
      workDir,
      'worktree',
      'remove',
      if (force) '--force',
      worktreePath,
    ]);
    if (result.exitCode == 0) return true;

    // 目录可能已被外部删除，先 prune 再确认
    await Process.run('git', ['-C', workDir, 'worktree', 'prune']);
    return !await Directory(worktreePath).exists();
  }

  String _stderr(ProcessResult result) {
    final err = result.stderr.toString().trim();
    return err.isEmpty ? result.stdout.toString().trim() : err;
  }

  /// 确保 `.toolshell/` 被写入本地 `.git/info/exclude`，避免它作为
  /// 未跟踪目录污染 `git status` —— 否则只要有隔离工作树/技能缓存存在，
  /// 主工作目录就会被误判为"有未提交改动"(参见 finish 的 MAIN_DIRTY 判断)。
  ///
  /// 用 `.git/info/exclude` 而不是仓库的 `.gitignore`：这是纯本地规则，
  /// 不会被提交、不会影响用户仓库内容或协作者，符合"框架内部约定目录，
  /// 对用户仓库零侵入"的原则。重复调用是安全的(先检查是否已存在该行)。
  Future<void> _ensureToolshellExcluded() async {
    try {
      final gitDirResult = await Process.run('git', [
        '-C',
        workDir,
        'rev-parse',
        '--git-dir',
      ]);
      if (gitDirResult.exitCode != 0) return;
      final gitDirRaw = gitDirResult.stdout.toString().trim();
      final gitDir = p.isAbsolute(gitDirRaw)
          ? gitDirRaw
          : p.join(workDir, gitDirRaw);

      final excludeFile = File(p.join(gitDir, 'info', 'exclude'));
      const marker = '/.toolshell/';
      if (await excludeFile.exists()) {
        final content = await excludeFile.readAsString();
        if (content.split('\n').map((l) => l.trim()).contains(marker)) {
          return; // 已存在，无需重复写入
        }
        final updated = content.endsWith('\n')
            ? '$content$marker\n'
            : '$content\n$marker\n';
        await excludeFile.writeAsString(updated);
      } else {
        await excludeFile.create(recursive: true);
        await excludeFile.writeAsString('$marker\n');
      }
    } catch (_) {
      // 静默失败：即便排除规则没写成功，也不应阻断 worktree 核心功能，
      // 只是退化为可能出现 MAIN_DIRTY 误报，风险自担但不 crash。
    }
  }

  String? _slugify(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final cleaned = trimmed
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u4e00-\u9fa5]'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return cleaned.isEmpty ? null : cleaned;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}

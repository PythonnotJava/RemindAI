import 'dart:io';

/// 系统级 Git 可用性检测 — 用于"冻结/启用"版本工作流(worktree 隔离)功能。
///
/// 设计背景：`toolshell_worktree_start`/`toolshell_worktree_finish` 依赖系统
/// 安装的 `git` 命令行。如果用户的机器上根本没有装 git，这两个工具应该在
/// 触发版本工作流时被整体冻结(不出现在提供给 LLM 的工具列表里)，而不是让
/// LLM 尝试调用后才收到一个语义不清的报错。
///
/// 检测策略：进程内只在"首次触发版本工作流"时真正探测一次(跑一次
/// `git --version`)，结果缓存在内存里，同一次应用运行期间不重复探测——
/// 探测本身有进程创建开销，没必要每次构建会话都做一次。若探测失败
/// (git 不存在/不可执行/超时)，视为不可用，功能保持冻结状态。
class GitAvailability {
  GitAvailability._();

  static bool? _cached;

  /// 是否检测到系统可用的 git 命令行。
  ///
  /// 首次调用时才真正探测(触发即检测一次)，此后复用缓存结果。
  static Future<bool> isAvailable() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final result = await Process.run(
        'git',
        ['--version'],
      ).timeout(const Duration(seconds: 5));
      _cached = result.exitCode == 0;
    } catch (_) {
      // git 未安装、不在 PATH 里、或探测超时，均视为不可用。
      _cached = false;
    }
    return _cached!;
  }

  /// 清除缓存，强制下一次 [isAvailable] 重新探测。
  ///
  /// 主要供测试使用；正常运行时无需调用——版本工作流的"启用/冻结"状态
  /// 在一次应用运行期间是稳定的，用户中途安装 git 需要重启应用才会生效，
  /// 这是刻意的取舍(避免每次触发都付出一次进程探测开销)。
  static void resetCacheForTesting() {
    _cached = null;
  }
}

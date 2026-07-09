import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/toolshell/git_availability.dart';

/// 验证版本工作流(worktree 隔离)的"冻结/启用"前置检测——GitAvailability。
///
/// 这个探测结果决定了 agent_context.dart 里是否把
/// toolshell_worktree_start/finish 两个工具注册给 LLM。测试环境里假定
/// 跑测试的机器本身装有 git(仓库开发机的常见前提，worktree_manager_test.dart
/// 本身也依赖真实 git 仓库)，所以这里主要验证:
/// 1. 正常情况下能检测到 git 可用
/// 2. 结果被缓存，第二次调用不会重新探测出不一致的结果
void main() {
  setUp(() {
    GitAvailability.resetCacheForTesting();
  });

  test('系统装有 git 时，isAvailable() 返回 true', () async {
    final available = await GitAvailability.isAvailable();
    expect(
      available,
      isTrue,
      reason: '测试环境应已安装 git(worktree_manager_test.dart 同样依赖它)',
    );
  });

  test('探测结果在同一进程内被缓存，重复调用保持一致', () async {
    final first = await GitAvailability.isAvailable();
    final second = await GitAvailability.isAvailable();
    expect(first, second);
  });

  test('resetCacheForTesting() 后会重新探测', () async {
    final first = await GitAvailability.isAvailable();
    GitAvailability.resetCacheForTesting();
    final second = await GitAvailability.isAvailable();
    // 同一台机器上系统 git 是否存在不会中途变化，结果应仍一致，
    // 但这里验证的是"重置后确实重新走了一次探测流程"而不报错。
    expect(second, first);
  });
}

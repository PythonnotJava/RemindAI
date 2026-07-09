/// 写/删/执行类工具名集合 — 需要用户确认才能执行 (normal 模式)。
///
/// 这是唯一权威来源，[PermissionMiddleware]、[Executor]、
/// [ToolPipeline._runParallel] 均引用此集合，避免各处各写一份导致不一致
/// (曾经 PermissionMiddleware 漏收 toolshell_run_js)。
/// Worktree 隔离(版本工作流)相关的全部工具名 — 权威集合。
///
/// 用于 GitAvailability 检测到系统无 git 时，从提供给 LLM 的工具列表中
/// 统一摘除(见 agent_context.dart 的冻结逻辑)，避免两处各写一份工具名
/// 列表导致遗漏。
const Set<String> kWorktreeWorkflowToolNames = {
  'toolshell_worktree_start',
  'toolshell_worktree_finish',
  'toolshell_worktree_checkpoint',
  'toolshell_worktree_list_checkpoints',
  'toolshell_worktree_revert',
  'toolshell_worktree_diff',
  'toolshell_worktree_list',
};

const Set<String> kApprovalRequiredTools = {
  'toolshell_write',
  'toolshell_delete',
  'toolshell_exec',
  'toolshell_run_python',
  'toolshell_run_js',
  // finish(action=merge) 会把隔离分支合并进主分支、discard 会强删分支，
  // 均直接改动 git 历史，与写/删同级别，需要确认。start 本身无损(只加新
  // 分支+新目录)，但一并要求确认以保持"开始隔离"这个决策对用户可见。
  'toolshell_worktree_start',
  'toolshell_worktree_finish',
  // revert 是 `git reset --hard` + `clean -fd`，会不可逆地丢弃工作树内
  // 未存档的改动，同样需要用户确认。checkpoint/list_checkpoints 只是
  // "存档/查看"，无损操作，不需要确认。
  'toolshell_worktree_revert',
};

/// 工具执行中间件抽象接口
///
/// 中间件按注册顺序形成链式调用:
/// request → Middleware1 → Middleware2 → ... → 实际执行器 → response
///
/// 每个中间件可以:
/// - 在执行前修改参数
/// - 决定是否调用 next (短路)
/// - 在执行后修改结果
/// - 记录日志/计时/缓存
abstract class ToolMiddleware {
  /// 处理工具调用
  ///
  /// [toolName] 工具名
  /// [args] 调用参数
  /// [next] 调用链的下一层 (最终是实际执行器)
  ///
  /// 必须调用 next 才会继续往下走,不调用即短路。
  Future<String> handle(
    String toolName,
    Map<String, dynamic> args,
    Future<String> Function(String toolName, Map<String, dynamic> args) next,
  );
}

/// 内置工具名清单 —— 「这个名字到底谁来执行」的唯一权威表。
///
/// 用途有两个：
/// 1. **技能工具校验**：技能 `tools.json` 只是声明，声明完必须有执行者。
///    不在本表（也不属于 MCP / Capability）的工具名，调用时只会在
///    `Executor.run` 的 switch 里落到 `UNKNOWN_TOOL`，所以
///    [AgentContextBuilder] 在装配阶段就会把它们从工具列表里摘掉并告警，
///    避免"模型看得见工具、调了必失败"。
/// 2. **MCP 工具命名空间**：MCP 服务器暴露的工具若与本表同名（或两台服务器
///    同名），会被重命名为 `mcp__<serverId>__<name>` 以避免歧义。
///
/// 维护约定：新增内置工具时，除了 [Executor.run] 的 switch 分支，必须同步
/// 本文件的集合，否则该工具会被当成"无执行者"而被过滤。
library;

/// 由 `Executor.run` 的 switch 直接分发的工具。
const Set<String> kExecutorToolNames = <String>{
  'toolshell_read',
  'toolshell_write',
  'toolshell_delete',
  'toolshell_search',
  'toolshell_exec',
  'toolshell_exec_background',
  'toolshell_job_output',
  'toolshell_job_kill',
  'toolshell_job_list',
  'toolshell_run_python',
  'toolshell_run_js',
  'toolshell_memory_store',
  'toolshell_memory_recall',
  'office_word_read',
  'office_word_create',
  'office_word_edit',
  'office_word_file',
  'office_excel_read',
  'office_excel_file',
};

/// Schedule 元技能工具（`Executor.run` 按 `schedule_` 前缀转给 ScheduleExecutor）。
const Set<String> kScheduleToolNames = <String>{
  'schedule_load',
  'schedule_add_task',
  'schedule_complete',
  'schedule_update',
  'schedule_delete',
  'schedule_review',
  'schedule_archive',
};

/// System 元技能工具（按 `system_` 前缀转给 SystemExecutor）。
const Set<String> kSystemToolNames = <String>{
  'system_probe',
  'system_env',
};

/// Android 设备自动化工具（`Executor.run` 的 switch 分发，走 AndroidExecutor）。
const Set<String> kAndroidToolNames = <String>{
  'android_ui_dump',
  'android_tap',
  'android_install_apk',
};

/// 由 `ToolPipeline._customHandlers` / `AgentContextBuilder` 注册执行体的工具
/// （不经过 `Executor.run` 的 switch）。
const Set<String> kRuntimeToolNames = <String>{
  'toolshell_run_parallel',
  'toolshell_install_skill',
  'toolshell_worktree_start',
  'toolshell_worktree_finish',
  'toolshell_worktree_checkpoint',
  'toolshell_worktree_list_checkpoints',
  'toolshell_worktree_revert',
  'toolshell_worktree_diff',
  'toolshell_worktree_list',
};

/// 内建 Capability 提供的工具（随能力开关注册，见 AgentCapability）。
///
/// 这类工具由 `AgentContextBuilder._collectCapabilities()` 按会话开关动态装配，
/// 这里登记的是"存在执行者的名字空间"，用于 MCP 命名冲突判定与技能校验。
const Set<String> kCapabilityToolNames = <String>{
  'web_search',
  'image_generate',
};

/// 全部「有执行者」的内置工具名。
Set<String> get kBuiltinToolNames => <String>{
  ...kExecutorToolNames,
  ...kScheduleToolNames,
  ...kSystemToolNames,
  ...kAndroidToolNames,
  ...kRuntimeToolNames,
  ...kCapabilityToolNames,
};

/// [name] 是否有一个确定的执行者（Executor / 自定义 handler / Capability）。
///
/// 注意：这里回答的是"名字是否被框架接管"，不判断该执行者本次会话是否装配
/// （例如 Capability 未启用时 `web_search` 仍算已知名字，只是不可调用）。
bool isKnownBuiltinTool(String name) => kBuiltinToolNames.contains(name);

/// 取工具定义里的函数名（兼容 OpenAI 嵌套格式与扁平格式）。
String? toolDefName(Map<String, dynamic> def) {
  final fn = def['function'];
  if (fn is Map) {
    final name = fn['name'];
    if (name is String && name.isNotEmpty) return name;
  }
  final flat = def['name'];
  if (flat is String && flat.isNotEmpty) return flat;
  return null;
}

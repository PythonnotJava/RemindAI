import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/search/search_config.dart';

/// Session 级记忆开关 — 独立于 memory.json，由 UI 记忆按钮控制
/// null = 跟随 memory.json 配置; true/false = 强制覆盖
final sessionMemoryRecallProvider = StateProvider<bool?>((ref) => null);
final sessionMemoryStoreProvider = StateProvider<bool?>((ref) => null);

/// 本次对话指定的 Python 解释器路径 (可执行文件路径)。空表示用系统默认。
final sessionPythonProvider = StateProvider<String>((ref) => '');

/// 本次对话指定的 Node/npm 路径 (可执行文件路径)。空表示用系统默认。
final sessionNpmProvider = StateProvider<String>((ref) => '');

/// 本次对话选中的搜索 provider (none = 关闭搜索)
final sessionSearchProvider = StateProvider<SearchProvider>((ref) {
  return SearchProvider.none;
});

/// 本次对话选中的知识库 ID 列表 (多选，空列表 = 未接入知识库)
final sessionKnowledgeBasesProvider = StateProvider<List<String>>((ref) => []);

/// 当前活跃的隔离工作树绝对路径。空字符串 = 未处于隔离状态(正常操作主工作目录)。
///
/// 由 LLM 通过 `toolshell_worktree_start` / `toolshell_worktree_finish` 工具
/// 读写，框架本身不做任何自动触发判断。非用户可见设置，纯内部会话状态——
/// 不写入 memory.json，不出现在任何设置界面。
///
/// 构建 AgentContext 时若此值非空且校验通过(仍在当前工作目录的
/// `.toolshell/worktrees/` 下、目录仍存在)，Executor 的 projectRoot 会被
/// 重定向到这里，后续文件操作/命令执行自动落在隔离工作树内。
final activeWorktreeProvider = StateProvider<String>((ref) => '');

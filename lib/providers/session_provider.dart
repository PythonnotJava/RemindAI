import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/image/session_image_registry.dart';
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

/// 本次对话选中的子画图模型卡 ID。
///
/// 空字符串 = 未启用画图子 Agent（不向 LLM 注册 image_generate 工具）。
/// 选中后，Agent 判断用户要画图时会优先调用该模型；失败自动用主模型兜底。
final sessionImageAgentModelIdProvider = StateProvider<String>((ref) => '');

/// 子画图模型失败时，是否用当前对话的主模型兜底画图。
///
/// 默认 false：主模型是纯文本模型（DeepSeek / Claude 等）时它根本不能出图，
/// 强行兜底只会得到一段文本。只有主模型本身支持图片输出时才应开启。
final sessionImageFallbackToMainProvider = StateProvider<bool>((ref) => false);

/// 会话级图片注册表。
///
/// 负责给「用户上传的图」和「画图生成的图」分配稳定 ID（A1/G1…），
/// 让 LLM 通过 ID 引用图片，而不是复制磁盘路径。
final sessionImageRegistryProvider = Provider<SessionImageRegistry>((ref) {
  return SessionImageRegistry();
});

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

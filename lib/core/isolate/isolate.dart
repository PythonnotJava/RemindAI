/// RemindAI Isolate 并行化系统
///
/// 提供 Isolate 池和各类计算任务，将 CPU 密集操作从主 Isolate 移出，
/// 避免长文聊天、大文件导出、记忆搜索等场景下的 UI 卡顿。
///
/// 架构:
/// - [IsolatePool]: 常驻 worker isolate 池，round-robin 调度
/// - tasks/: 各领域的纯计算任务（顶层函数，可跨 isolate 传递）
///
/// 用法:
/// ```dart
/// import 'package:remind_ai/core/isolate/isolate.dart';
///
/// // 在 main() 中初始化
/// await IsolatePool.instance.init();
///
/// // JSON 序列化
/// final json = await ComputeService.jsonEncode(bigData);
///
/// // Markdown 预处理
/// final result = await ComputeService.markdownPreprocess(longText);
/// ```
library;

export 'isolate_pool.dart';
export 'compute_service.dart';
export 'tasks/json_task.dart';
export 'tasks/markdown_task.dart';
export 'tasks/highlight_task.dart';
export 'tasks/export_task.dart';
export 'tasks/memory_task.dart';
export 'tasks/skill_task.dart';
export 'tasks/context_task.dart';

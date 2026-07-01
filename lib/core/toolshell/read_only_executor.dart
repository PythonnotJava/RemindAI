import 'dart:convert';

import '../memory/project_config.dart';
import 'executor.dart';

/// 只读执行器 — 供 `/sub-readers` 派生的并行只读子 Agent 使用。
///
/// 只允许纯读取类工具（读文件 / 搜索 / 记忆召回），其余一切工具
/// （写文件、删除、执行 shell、跑 Python/JS、安装技能、写记忆等）
/// 一律直接拒绝，不会转发给底层 [Executor]。
///
/// 这是 `/sub-readers` 并行安全性的根本保证：多个子 Agent 可能同时
/// 指向同一个 projectRoot，但因为它们压根没有写权限，不存在文件写入
/// 覆盖或 shell 执行竞态的风险——不需要引入锁机制。
class ReadOnlyExecutor extends Executor {
  ReadOnlyExecutor({
    required super.projectRoot,
    super.readableExtraPaths,
    super.allowOutsideRoot,
  }) : super(permissionMode: PermissionMode.auto);

  /// 允许直接放行的只读工具白名单（精确匹配）。
  /// 有意不包含 toolshell_memory_recall——`/sub-readers` 场景下子 Agent
  /// 通常没有配置 memoryManager，保持工具集合与实际可用能力一致。
  static const Set<String> allowedTools = {
    'toolshell_read',
    'toolshell_search',
  };

  /// 对应 [allowedTools] 的 OpenAI function 格式工具定义，
  /// 直接喂给子 Agent 的 [AgentLoop]。与 assets/default_skills/toolshell/tools.json
  /// 中 toolshell_read / toolshell_search 的定义保持一致。
  static const List<Map<String, dynamic>> toolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'toolshell_read',
        'description': '读取文件内容。支持指定行范围。',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': '文件路径(相对于项目根目录)'},
            'encoding': {'type': 'string', 'default': 'utf-8'},
            'start_line': {'type': 'integer', 'description': '起始行号(从1开始)'},
            'end_line': {'type': 'integer', 'description': '结束行号'},
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'toolshell_search',
        'description': '搜索文件。按文件名glob匹配，可选按内容过滤。',
        'parameters': {
          'type': 'object',
          'properties': {
            'pattern': {
              'type': 'string',
              'description': 'glob模式(如 *.py, **/*.dart)',
            },
            'scope': {'type': 'string', 'description': '搜索目录(默认项目根)'},
            'content': {'type': 'string', 'description': '内容正则'},
            'max_results': {'type': 'integer', 'default': 20},
          },
          'required': ['pattern'],
        },
      },
    },
  ];

  @override
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    if (!allowedTools.contains(toolName)) {
      return jsonEncode({
        'status': 'error',
        'code': 'READONLY_MODE',
        'detail':
            '/sub-readers 只读模式下不允许调用 $toolName，仅可使用: '
            '${allowedTools.join(", ")}',
      });
    }
    return super.run(toolName, args);
  }
}

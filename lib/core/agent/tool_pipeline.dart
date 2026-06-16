import 'dart:convert';

import '../mcp/mcp_client.dart';
import '../toolshell/executor.dart';
import 'tool_middleware.dart';

/// 自定义工具处理器类型
typedef CustomToolHandler = Future<String> Function(Map<String, dynamic> args);

/// 工具执行管线 — 替代 CombinedExecutor
///
/// 职责:
/// 1. 维护中间件链
/// 2. 路由工具调用 (Custom → MCP → ToolShell)
/// 3. 提供统一的 run() 入口
class ToolPipeline {
  final Executor _executor;
  final List<ToolMiddleware> _middlewares;

  /// MCP 客户端映射
  final Map<String, McpClient> _mcpClients;

  /// toolName → serverId 映射
  final Map<String, String> _mcpToolMapping;

  /// 自定义工具处理器 (如搜索工具)
  final Map<String, CustomToolHandler> _customHandlers;

  ToolPipeline({
    required this._executor,
    this._middlewares = const [],
    this._mcpClients = const {},
    Map<String, List<Map<String, dynamic>>> mcpToolsCache = const {},
    this._customHandlers = const {},
  }) : _mcpToolMapping = _buildMapping(mcpToolsCache);

  static Map<String, String> _buildMapping(
    Map<String, List<Map<String, dynamic>>> cache,
  ) {
    final mapping = <String, String>{};
    for (final entry in cache.entries) {
      for (final tool in entry.value) {
        final fn = tool['function'] as Map<String, dynamic>?;
        final name = fn?['name'] as String?;
        if (name != null) mapping[name] = entry.key;
      }
    }
    return mapping;
  }

  /// 执行工具调用 — 经过中间件链后路由到实际执行器
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    // 构建中间件调用链 (从后往前包裹)
    Future<String> Function(String, Map<String, dynamic>) chain = _route;
    for (var i = _middlewares.length - 1; i >= 0; i--) {
      final mw = _middlewares[i];
      final nextFn = chain;
      chain = (name, a) => mw.handle(name, a, nextFn);
    }
    return chain(toolName, args);
  }

  /// 最终路由: Custom → MCP → ToolShell
  Future<String> _route(String toolName, Map<String, dynamic> args) async {
    // 自定义工具 (搜索等)
    final customHandler = _customHandlers[toolName];
    if (customHandler != null) {
      return customHandler(args);
    }

    // MCP 工具
    final serverId = _mcpToolMapping[toolName];
    if (serverId != null) {
      final client = _mcpClients[serverId];
      if (client != null && client.isConnected) {
        try {
          final result = await client.callTool(toolName, args);
          return jsonEncode({'status': 'ok', 'content': result});
        } catch (e) {
          return jsonEncode({
            'status': 'error',
            'code': 'MCP_ERROR',
            'detail': e.toString(),
          });
        }
      }
      return jsonEncode({
        'status': 'error',
        'code': 'MCP_DISCONNECTED',
        'detail': 'MCP 服务器未连接: $serverId',
      });
    }

    // ToolShell 内置工具
    return _executor.run(toolName, args);
  }
}

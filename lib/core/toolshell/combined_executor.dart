import 'dart:convert';

import '../logger/app_logger.dart';
import '../mcp/mcp_client.dart';
import 'executor.dart';

/// 组合执行器 - 先尝试 MCP，再尝试 ToolShell
/// 执行时输出工具来源日志，方便调试技能/MCP 调用情况
class CombinedExecutor extends Executor {
  final Map<String, McpClient> _mcpClients;
  final Map<String, List<String>> _mcpToolMapping; // toolName → [serverId]
  final Map<String, String> _toolSourceMapping; // toolName → 来源描述

  CombinedExecutor({
    required super.projectRoot,
    super.pythonPath,
    super.npmPath,
    super.permissionMode,
    super.onPermissionRequest,
    super.memoryManager,
    super.memoryCollection,
    super.readableExtraPaths,
    required Map<String, McpClient> mcpClients,
    required Map<String, List<Map<String, dynamic>>> mcpToolsCache,
    this._toolSourceMapping = const {},
  }) : _mcpClients = mcpClients,
       _mcpToolMapping = _buildToolMapping(mcpClients, mcpToolsCache);

  static Map<String, List<String>> _buildToolMapping(
    Map<String, McpClient> clients,
    Map<String, List<Map<String, dynamic>>> toolsCache,
  ) {
    final mapping = <String, List<String>>{};
    for (final entry in toolsCache.entries) {
      final serverId = entry.key;
      for (final tool in entry.value) {
        final fn = tool['function'] as Map<String, dynamic>?;
        final name = fn?['name'] as String?;
        if (name != null) {
          mapping.putIfAbsent(name, () => []).add(serverId);
        }
      }
    }
    return mapping;
  }

  @override
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    // 打印工具调用来源
    final source = _toolSourceMapping[toolName];
    if (source != null) {
      AppLogger.instance.log('[ToolCall] $toolName ← $source');
    }

    // 先检查是否是 MCP 工具
    final serverIds = _mcpToolMapping[toolName];
    if (serverIds != null && serverIds.isNotEmpty) {
      final serverId = serverIds.first;
      final client = _mcpClients[serverId];
      if (source == null) {
        AppLogger.instance.log('[ToolCall] $toolName ← MCP:$serverId');
      }
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
        'detail': 'MCP 服务器未连接',
      });
    }

    // ToolShell 内置工具
    if (source == null) {
      AppLogger.instance.log('[ToolCall] $toolName ← ToolShell(内置)');
    }
    return super.run(toolName, args);
  }
}

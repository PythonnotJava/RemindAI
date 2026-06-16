import 'dart:convert';

import 'transports/mcp_transport.dart';
import 'transports/stdio_transport.dart';
import 'transports/sse_transport.dart';
import 'transports/streamable_http_transport.dart';

/// MCP 客户端 - 基于 Transport 抽象的统一接口
///
/// 支持三种传输方式：
/// - stdio: 子进程 stdin/stdout (JSON-RPC 行分隔)
/// - SSE: HTTP GET 建立 SSE + POST 发送消息
/// - Streamable HTTP: 单 POST endpoint (MCP 2025-03-26)
class McpClient {
  McpTransport? _transport;

  bool get isConnected => _transport?.isConnected ?? false;

  /// 通过 stdio 连接 MCP 服务器
  Future<void> connectStdio({
    required String command,
    required List<String> args,
    Map<String, String>? env,
    String? workingDirectory,
  }) async {
    _transport = StdioTransport(
      command: command,
      args: args,
      env: env,
      workingDirectory: workingDirectory,
    );
    await _transport!.connect();
  }

  /// 通过 SSE 连接 MCP 服务器
  Future<void> connectSse({
    required String url,
    Map<String, String>? headers,
  }) async {
    _transport = SseTransport(url: url, headers: headers);
    await _transport!.connect();
  }

  /// 通过 Streamable HTTP 连接 MCP 服务器
  Future<void> connectStreamableHttp({
    required String url,
    Map<String, String>? headers,
  }) async {
    _transport = StreamableHttpTransport(url: url, headers: headers);
    await _transport!.connect();
  }

  /// 向后兼容：旧的 connect 方法 (stdio)
  Future<void> connect({
    required String command,
    required List<String> args,
    Map<String, String>? env,
    String? workingDirectory,
  }) async {
    await connectStdio(
      command: command,
      args: args,
      env: env,
      workingDirectory: workingDirectory,
    );
  }

  /// 初始化握手
  Future<Map<String, dynamic>> initialize() async {
    if (_transport == null) throw Exception('MCP 未连接');

    final result = await _transport!.sendRequest('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'RemindAI', 'version': '1.0.0'},
    });

    // 发送 initialized 通知
    _transport!.sendNotification('notifications/initialized', {});

    return result as Map<String, dynamic>;
  }

  /// 获取工具列表
  Future<List<Map<String, dynamic>>> listTools() async {
    if (_transport == null) throw Exception('MCP 未连接');

    final result = await _transport!.sendRequest('tools/list', {});
    final tools = (result as Map<String, dynamic>)['tools'] as List? ?? [];

    return tools.map<Map<String, dynamic>>((tool) {
      final t = tool as Map<String, dynamic>;
      return {
        'type': 'function',
        'function': {
          'name': t['name'],
          'description': t['description'] ?? '',
          'parameters':
              t['inputSchema'] ?? {'type': 'object', 'properties': {}},
        },
      };
    }).toList();
  }

  /// 调用工具
  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    if (_transport == null) throw Exception('MCP 未连接');

    final result = await _transport!.sendRequest('tools/call', {
      'name': name,
      'arguments': arguments,
    });

    final content = (result as Map<String, dynamic>)['content'] as List? ?? [];
    final textParts = content
        .where((c) => (c as Map<String, dynamic>)['type'] == 'text')
        .map((c) => (c as Map<String, dynamic>)['text'] as String)
        .toList();

    if (textParts.isEmpty) {
      return jsonEncode(result);
    }
    return textParts.join('\n');
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _transport?.disconnect();
    _transport = null;
  }
}

/// MCP 错误
class McpError implements Exception {
  final int code;
  final String message;

  McpError({required this.code, required this.message});

  @override
  String toString() => 'McpError($code): $message';
}

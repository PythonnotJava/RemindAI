import 'dart:async';

/// MCP 传输类型枚举
enum McpTransportType {
  /// 子进程 stdin/stdout (JSON-RPC 行分隔)
  stdio,

  /// SSE (Server-Sent Events) 传输
  /// GET endpoint 建立 SSE 连接接收消息，POST endpoint 发送消息
  sse,

  /// Streamable HTTP 传输 (MCP 2025-03-26 规范)
  /// 单 POST endpoint，响应可以是 SSE 流或 JSON
  streamableHttp,
}

/// MCP 传输层抽象接口
///
/// 所有传输实现（stdio / SSE / Streamable HTTP）遵循此接口，
/// 上层 McpClient 只通过此接口收发 JSON-RPC 消息。
abstract class McpTransport {
  /// 当前是否已连接
  bool get isConnected;

  /// 建立连接
  Future<void> connect();

  /// 发送 JSON-RPC 请求并等待响应
  Future<dynamic> sendRequest(String method, Map<String, dynamic> params);

  /// 发送 JSON-RPC 通知（不等待响应）
  void sendNotification(String method, Map<String, dynamic> params);

  /// 断开连接
  Future<void> disconnect();

  /// 连接断开事件流（供上层监听异常断开）
  Stream<String> get onDisconnected;
}

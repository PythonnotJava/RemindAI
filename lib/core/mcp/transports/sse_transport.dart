import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../logger/app_logger.dart';
import 'mcp_transport.dart';

/// MCP SSE 传输实现
///
/// 遵循 MCP SSE 规范：
/// - GET [url] → 建立 SSE 连接，接收 JSON-RPC 消息
/// - POST [messageUrl] → 发送 JSON-RPC 消息 (url 由服务端通过 endpoint 事件通知)
class SseTransport implements McpTransport {
  final String url;
  final Map<String, String>? headers;

  final Dio _dio = Dio();
  int _requestId = 0;
  final Map<int, Completer<dynamic>> _pending = {};
  final _disconnectedController = StreamController<String>.broadcast();

  StreamSubscription? _sseSub;
  CancelToken? _sseCancelToken;

  /// 服务端通过 SSE 'endpoint' 事件通知的消息发送 URL
  String? _messageUrl;
  bool _connected = false;

  /// SSE 解析状态
  String? _currentEvent;
  final StringBuffer _dataBuffer = StringBuffer();

  SseTransport({required this.url, this.headers});

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onDisconnected => _disconnectedController.stream;

  @override
  Future<void> connect() async {
    AppLogger.instance.log('[MCP/sse] 连接: $url');
    _sseCancelToken = CancelToken();
    final connectCompleter = Completer<void>();

    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            ...?headers,
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: _sseCancelToken,
      );

      final stream = response.data!.stream;
      final lineBuffer = StringBuffer();

      _sseSub = stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              lineBuffer.write(chunk);
              while (true) {
                final text = lineBuffer.toString();
                final idx = text.indexOf('\n');
                if (idx == -1) break;
                final line = text.substring(0, idx);
                lineBuffer.clear();
                lineBuffer.write(text.substring(idx + 1));
                _processLine(line.trimRight(), connectCompleter);
              }
            },
            onError: (error) {
              _connected = false;
              final msg = 'SSE 连接异常: $error';
              AppLogger.instance.log('[MCP/sse] $msg');
              if (!connectCompleter.isCompleted) {
                connectCompleter.completeError(Exception(msg));
              }
              _failAllPending(msg);
              _disconnectedController.add(msg);
            },
            onDone: () {
              _connected = false;
              const msg = 'SSE 连接已关闭';
              AppLogger.instance.log('[MCP/sse] $msg');
              if (!connectCompleter.isCompleted) {
                connectCompleter.completeError(Exception(msg));
              }
              _failAllPending(msg);
              _disconnectedController.add(msg);
            },
          );

      await connectCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('SSE 连接超时：未收到 endpoint 事件');
        },
      );
    } catch (e) {
      _connected = false;
      if (e is TimeoutException) rethrow;
      throw Exception('SSE 连接失败: $e');
    }
  }

  @override
  Future<dynamic> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!_connected || _messageUrl == null) {
      throw Exception('MCP SSE 未连接');
    }

    final id = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<dynamic>();
    _pending[id] = completer;

    AppLogger.instance.log('[MCP/sse] 发送: $method (id=$id)');

    try {
      await _dio.post(
        _messageUrl!,
        data: jsonEncode(request),
        options: Options(
          headers: {'Content-Type': 'application/json', ...?headers},
        ),
      );
    } catch (e) {
      _pending.remove(id);
      completer.completeError(Exception('发送失败: $e'));
    }

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('MCP 请求超时: $method');
      },
    );
  }

  @override
  void sendNotification(String method, Map<String, dynamic> params) {
    if (!_connected || _messageUrl == null) return;
    final notification = {'jsonrpc': '2.0', 'method': method, 'params': params};
    _dio.post(
      _messageUrl!,
      data: jsonEncode(notification),
      options: Options(
        headers: {'Content-Type': 'application/json', ...?headers},
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _sseCancelToken?.cancel();
    _sseSub?.cancel();
    _sseSub = null;
    _failAllPending('连接已断开');
    _dio.close();
  }

  // ─── 私有方法 ─────────────────────────────────────────────

  void _processLine(String line, Completer<void> connectCompleter) {
    if (line.isEmpty) {
      // 空行 → 事件边界
      final data = _dataBuffer.toString().trim();
      _dataBuffer.clear();
      if (data.isNotEmpty) {
        _handleEvent(_currentEvent, data, connectCompleter);
      }
      _currentEvent = null;
      return;
    }
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (_dataBuffer.isNotEmpty) _dataBuffer.write('\n');
      _dataBuffer.write(line.substring(5).trim());
    }
    // 忽略 id: / retry: / 注释 (:)
  }

  void _handleEvent(
    String? event,
    String data,
    Completer<void> connectCompleter,
  ) {
    if (event == 'endpoint') {
      _messageUrl = _resolveUrl(data);
      _connected = true;
      AppLogger.instance.log('[MCP/sse] 收到 endpoint: $_messageUrl');
      if (!connectCompleter.isCompleted) connectCompleter.complete();
      return;
    }
    // message 事件或无 event 名 → JSON-RPC
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      _handleJsonRpc(json);
    } catch (e) {
      AppLogger.instance.log('[MCP/sse] 解析消息失败: $e');
    }
  }

  void _handleJsonRpc(Map<String, dynamic> message) {
    if (message.containsKey('id') && message['id'] != null) {
      final rawId = message['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer == null) return;

      if (message.containsKey('error')) {
        final error = message['error'] as Map<String, dynamic>;
        completer.completeError(
          Exception(
            'MCP Error(${error['code']}): ${error['message'] ?? '未知错误'}',
          ),
        );
      } else {
        completer.complete(message['result']);
      }
    }
  }

  String _resolveUrl(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return endpoint;
    }
    return Uri.parse(url).resolve(endpoint).toString();
  }

  void _failAllPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception(reason));
      }
    }
    _pending.clear();
  }
}

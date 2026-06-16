import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../logger/app_logger.dart';
import 'mcp_transport.dart';

/// MCP Streamable HTTP 传输实现 (MCP 2025-03-26 规范)
///
/// 特点：
/// - 单 POST endpoint，请求和响应都通过同一 URL
/// - 响应可以是普通 JSON (单次响应) 或 SSE 流 (流式响应)
/// - 支持服务端主动推送（通过 GET 建立 SSE 监听通道，可选）
class StreamableHttpTransport implements McpTransport {
  final String url;
  final Map<String, String>? headers;

  final Dio _dio = Dio();
  int _requestId = 0;
  final Map<int, Completer<dynamic>> _pending = {};
  final _disconnectedController = StreamController<String>.broadcast();

  bool _connected = false;

  /// 可选的 SSE 监听通道（用于接收服务端主动推送的通知）
  StreamSubscription? _listenSub;
  CancelToken? _listenCancelToken;

  StreamableHttpTransport({required this.url, this.headers});

  @override
  bool get isConnected => _connected;

  @override
  Stream<String> get onDisconnected => _disconnectedController.stream;

  @override
  Future<void> connect() async {
    AppLogger.instance.log('[MCP/streamable-http] 连接: $url');
    _connected = true;

    // 尝试建立 GET SSE 监听通道（非必须，部分服务器不支持）
    _tryEstablishListener();
  }

  @override
  Future<dynamic> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (!_connected) throw Exception('MCP Streamable HTTP 未连接');

    final id = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    AppLogger.instance.log('[MCP/streamable-http] 发送: $method (id=$id)');

    try {
      final response = await _dio.post(
        url,
        data: jsonEncode(request),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            ...?headers,
          },
          // 让 Dio 返回原始响应，我们手动判断 content-type
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 202) {
        // 202 Accepted = 通知被接受，无响应体
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.data}');
      }

      final contentType = response.headers.value('content-type') ?? '';

      if (contentType.contains('text/event-stream')) {
        // SSE 流式响应 — 解析到对应 id 的响应
        return _parseStreamResponse(response.data as String, id);
      } else {
        // 普通 JSON 响应
        final json =
            jsonDecode(response.data as String) as Map<String, dynamic>;
        if (json.containsKey('error')) {
          final error = json['error'] as Map<String, dynamic>;
          throw Exception(
            'MCP Error(${error['code']}): ${error['message'] ?? '未知错误'}',
          );
        }
        return json['result'];
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        _connected = false;
        _disconnectedController.add('连接失败: $e');
      }
      rethrow;
    }
  }

  @override
  void sendNotification(String method, Map<String, dynamic> params) {
    if (!_connected) return;
    final notification = {'jsonrpc': '2.0', 'method': method, 'params': params};
    _dio.post(
      url,
      data: jsonEncode(notification),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          ...?headers,
        },
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _listenCancelToken?.cancel();
    _listenSub?.cancel();
    _listenSub = null;
    _failAllPending('连接已断开');
    _dio.close();
  }

  // ─── 私有方法 ─────────────────────────────────────────────

  /// 解析 SSE 流式响应中目标 id 的结果
  dynamic _parseStreamResponse(String sseBody, int targetId) {
    final dataBuffer = StringBuffer();
    dynamic result;

    for (final line in sseBody.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        // 事件边界
        final data = dataBuffer.toString().trim();
        dataBuffer.clear();
        if (data.isNotEmpty) {
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json['id'] == targetId) {
              if (json.containsKey('error')) {
                final error = json['error'] as Map<String, dynamic>;
                throw Exception(
                  'MCP Error(${error['code']}): ${error['message'] ?? '未知错误'}',
                );
              }
              result = json['result'];
            }
          } catch (e) {
            if (e is Exception && e.toString().contains('MCP Error')) rethrow;
          }
        }
        continue;
      }
      if (trimmed.startsWith('event:')) {
        // 忽略 event 名称，只关注 data
      } else if (trimmed.startsWith('data:')) {
        if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
        dataBuffer.write(trimmed.substring(5).trim());
      }
    }

    // 处理最后一个未以空行结尾的事件
    final remaining = dataBuffer.toString().trim();
    if (remaining.isNotEmpty && result == null) {
      try {
        final json = jsonDecode(remaining) as Map<String, dynamic>;
        if (json['id'] == targetId) {
          if (json.containsKey('error')) {
            final error = json['error'] as Map<String, dynamic>;
            throw Exception(
              'MCP Error(${error['code']}): ${error['message'] ?? '未知错误'}',
            );
          }
          result = json['result'];
        }
      } catch (_) {}
    }

    if (result == null) {
      throw Exception('未收到 id=$targetId 的响应');
    }
    return result;
  }

  /// 尝试建立 GET SSE 监听通道（接收服务端主动推送）
  void _tryEstablishListener() async {
    _listenCancelToken = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {'Accept': 'text/event-stream', ...?headers},
          responseType: ResponseType.stream,
        ),
        cancelToken: _listenCancelToken,
      );

      final lineBuffer = StringBuffer();
      _listenSub = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              lineBuffer.write(chunk);
              while (true) {
                final text = lineBuffer.toString();
                final idx = text.indexOf('\n');
                if (idx == -1) break;
                lineBuffer.clear();
                lineBuffer.write(text.substring(idx + 1));
                // 监听通道的事件暂不做特殊处理（可扩展为处理服务端推送通知）
              }
            },
            onError: (_) {
              // 监听通道是可选的，失败不影响主流程
              AppLogger.instance.log('[MCP/streamable-http] 监听通道异常（忽略）');
            },
            onDone: () {
              AppLogger.instance.log('[MCP/streamable-http] 监听通道关闭');
            },
          );
    } catch (_) {
      // GET 不支持 → 服务端不支持主动推送，正常
      AppLogger.instance.log('[MCP/streamable-http] 服务器不支持 GET 监听通道（正常）');
    }
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

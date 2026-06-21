import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../logger/app_logger.dart';
import 'mcp_transport.dart';

/// MCP stdio 传输实现 - JSON-RPC 2.0 over stdin/stdout
///
/// 从原 McpClient 提取的 stdio 逻辑。
class StdioTransport implements McpTransport {
  final String command;
  final List<String> args;
  final Map<String, String>? env;
  final String? workingDirectory;

  Process? _process;
  int _requestId = 0;
  final Map<int, Completer<dynamic>> _pending = {};
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final StringBuffer _stderrBuffer = StringBuffer();
  final _disconnectedController = StreamController<String>.broadcast();

  StdioTransport({
    required this.command,
    required this.args,
    this.env,
    this.workingDirectory,
  });

  @override
  bool get isConnected => _process != null;

  @override
  Stream<String> get onDisconnected => _disconnectedController.stream;

  @override
  Future<void> connect() async {
    final cleanCommand = _stripInvisible(command);
    final cleanArgs = args.map(_stripInvisible).toList();
    final cleanCwd = workingDirectory != null
        ? _stripInvisible(workingDirectory!)
        : null;

    // 合并环境变量
    final environment = <String, String>{
      ...Platform.environment,
      'PYTHONUNBUFFERED': '1',
      'PYTHONIOENCODING': 'utf-8',
      ...?env,
    };

    AppLogger.instance.log(
      '[MCP/stdio] 连接: $cleanCommand ${cleanArgs.join(" ")}',
    );

    try {
      _process = await Process.start(
        cleanCommand,
        cleanArgs,
        environment: environment,
        workingDirectory: cleanCwd,
      );
    } catch (e) {
      AppLogger.instance.log('[MCP/stdio] Process.start 失败: $e');
      rethrow;
    }

    AppLogger.instance.log('[MCP/stdio] 进程已启动, pid=${_process!.pid}');

    const stdoutDecoder = Utf8Decoder(allowMalformed: true);
    final stderrEncoding = Platform.isWindows
        ? systemEncoding.decoder
        : const Utf8Decoder(allowMalformed: true);

    _stdoutSub = _process!.stdout
        .transform(stdoutDecoder)
        .transform(const LineSplitter())
        .listen(_onLine);

    _stderrSub = _process!.stderr.transform(stderrEncoding).listen((chunk) {
      if (_stderrBuffer.length < 2000) {
        _stderrBuffer.write(chunk);
      }
    });

    _process!.exitCode.then(_onProcessExit);

    // 等待进程完成启动
    await Future.delayed(const Duration(milliseconds: 1000));
    if (_process == null) {
      final stderr = _stderrBuffer.toString().trim();
      throw Exception(stderr.isNotEmpty ? stderr : '进程启动后立即退出');
    }
  }

  @override
  Future<dynamic> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_process == null) throw Exception('MCP 未连接');

    final id = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final payload = jsonEncode(request);
    AppLogger.instance.log('[MCP/stdio] 发送: $method (id=$id)');
    _process!.stdin.writeln(payload);

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
    if (_process == null) return;
    final notification = {'jsonrpc': '2.0', 'method': method, 'params': params};
    _process!.stdin.writeln(jsonEncode(notification));
  }

  @override
  Future<void> disconnect() async {
    try {
      _process?.kill();
    } catch (_) {}
    _cleanup();
  }

  // ─── 私有方法 ─────────────────────────────────────────────

  void _onProcessExit(int exitCode) {
    final stderr = _stderrBuffer.toString().trim();
    AppLogger.instance.log('[MCP/stdio] 进程退出, code=$exitCode');
    final reason = stderr.isNotEmpty
        ? '进程退出 (code $exitCode): $stderr'
        : '进程退出 (code $exitCode)';

    _cleanup();
    _disconnectedController.add(reason);
  }

  void _cleanup() {
    _stderrSub?.cancel();
    _stderrSub = null;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _process = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('MCP 连接已断开'));
      }
    }
    _pending.clear();
  }

  void _onLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      _handleMessage(json);
    } catch (_) {}
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message.containsKey('id') && message['id'] != null) {
      final id = message['id'] as int;
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

  static String _stripInvisible(String s) {
    return s
        .replaceAll(
          RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]'),
          '',
        )
        .trim();
  }
}

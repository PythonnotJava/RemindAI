import 'dart:async';
import 'dart:io';

import '../logger/app_logger.dart';

/// 为 SSE / Streamable HTTP 传输可选拉起本地进程。
///
/// 背景：部分 MCP server 虽然对外暴露 SSE/HTTP 接口，但本身是一个需要
/// 手动敲命令启动的本地进程 (如 `node server.js` 监听某端口)。此前应用
/// 只会去连 url，从不管这个进程有没有启动，用户必须自己每次手动拉起。
/// 这个类补上"如果配置了 command，就先拉起进程，再等它把端口打开"这一步
/// —— 只负责进程本身的生死，不接管它的 stdout/stdin (那是 stdio 传输的
/// JSON-RPC 通道语义，这里的进程只是"背后跑着的服务"，通信仍然走 SSE/HTTP)。
class LocalProcessLauncher {
  Process? _process;
  final StringBuffer _stderrBuffer = StringBuffer();

  bool get isRunning => _process != null;
  int? get pid => _process?.pid;

  /// 启动进程。不等待端口就绪——就绪判断由调用方通过 [waitForPortOpen] 完成，
  /// 两者分离是因为"进程要不要拉起"和"端口何时就绪"是两个独立关注点。
  Future<void> start({
    required String command,
    required List<String> args,
    Map<String, String>? env,
    String? workingDirectory,
  }) async {
    final environment = <String, String>{...Platform.environment, ...?env};

    AppLogger.instance.log(
      '[MCP/local-process] 启动: $command ${args.join(" ")}'
      '${workingDirectory != null ? " (cwd=$workingDirectory)" : ""}',
    );

    _process = await Process.start(
      command,
      args,
      environment: environment,
      workingDirectory: workingDirectory,
    );

    AppLogger.instance.log('[MCP/local-process] 已启动, pid=${_process!.pid}');

    _process!.stderr.transform(const SystemEncoding().decoder).listen((chunk) {
      if (_stderrBuffer.length < 2000) _stderrBuffer.write(chunk);
    });
    // stdout 不关心内容，只是不能不消费，否则子进程可能因管道满而阻塞。
    _process!.stdout.drain();

    unawaited(
      _process!.exitCode.then((code) {
        AppLogger.instance.log('[MCP/local-process] 进程退出, code=$code');
        _process = null;
      }),
    );
  }

  /// 轮询等待 [uri] 的 host:port 可建立 TCP 连接——用最原始的 socket 探测
  /// 而不是发起真正的 HTTP/SSE 请求，因为 SSE 端点的 GET 是长连接流式
  /// 语义，用它做"就绪探测"会一直挂着、还得处理取消；纯 TCP connect
  /// 探测端口是否有人监听，协议无关，做完立刻断开，足够回答"进程起来了吗"
  /// 这个问题，真正的协议级校验交给后续 transport.connect() 去做。
  Future<bool> waitForPortOpen(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    Duration retryInterval = const Duration(milliseconds: 300),
  }) async {
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      // 进程如果已经退出了，再等下去也不会有结果，提前失败退出轮询。
      if (_process == null) return false;
      if (await _probeOnce(host, port)) return true;
      await Future.delayed(retryInterval);
    }
    return false;
  }

  Future<bool> _probeOnce(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取已捕获的 stderr (用于失败时给出更有信息量的错误提示)
  String get stderrOutput => _stderrBuffer.toString().trim();

  /// 结束进程。Windows 上 kill() 默认发送的信号相当于强制终止，足够用；
  /// 不像 QdrantService 那样需要"先 SIGTERM 优雅退出再 SIGKILL"的两段式——
  /// 这里的本地进程只是给 MCP server 打个底，没有需要优雅落盘的持久化状态。
  Future<void> kill() async {
    final proc = _process;
    if (proc == null) return;
    try {
      proc.kill();
    } catch (_) {}
    _process = null;
  }
}

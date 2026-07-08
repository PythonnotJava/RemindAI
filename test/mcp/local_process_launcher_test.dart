import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/mcp/local_process_launcher.dart';

/// 验证 LocalProcessLauncher 的真实进程生命周期与端口探测行为。
///
/// 背景: 这个类是给 SSE/HTTP 传输的 MCP 服务器补上的"可选自动拉起本地进程"
/// 能力——部分 MCP server 对外是 SSE/HTTP 接口，但本身需要先手动跑一个进程
/// 才能把端口打开。这里不用 mock，而是用真实的 `python -m http.server`
/// 当作"背后跑着的服务"来验证：进程真的能被启动、端口就绪能被正确探测到、
/// kill() 真的能终止进程——这三点都是直接关系到"会不会留下占端口的僵尸
/// 进程"的关键行为，用假的 Process 抽象验证不出这类真实系统调用层面的问题。
void main() {
  /// 获取一个当前空闲的本地端口：先绑定 0 端口拿到系统分配的临时端口，
  /// 立即释放，再把这个端口号交给待启动的子进程使用。存在极小的窗口期
  /// 竞争风险（其他进程抢先占用），但在测试环境下足够稳定。
  Future<int> pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  group('LocalProcessLauncher - 真实进程生命周期', () {
    test('start() 后端口会在探测中变为就绪状态', () async {
      final port = await pickFreePort();
      final launcher = LocalProcessLauncher();

      await launcher.start(
        command: 'python',
        args: ['-m', 'http.server', '$port', '--bind', '127.0.0.1'],
      );

      expect(launcher.isRunning, isTrue);
      expect(launcher.pid, isNotNull);

      final ready = await launcher.waitForPortOpen(
        Uri.parse('http://127.0.0.1:$port'),
        timeout: const Duration(seconds: 10),
        retryInterval: const Duration(milliseconds: 100),
      );

      expect(ready, isTrue);
      print('[测试] 端口 $port 在超时前探测到就绪, pid=${launcher.pid}');

      await launcher.kill();
      expect(launcher.isRunning, isFalse);
    });

    test('kill() 后进程真正终止，端口不再可连接', () async {
      final port = await pickFreePort();
      final launcher = LocalProcessLauncher();

      await launcher.start(
        command: 'python',
        args: ['-m', 'http.server', '$port', '--bind', '127.0.0.1'],
      );
      final ready = await launcher.waitForPortOpen(
        Uri.parse('http://127.0.0.1:$port'),
        timeout: const Duration(seconds: 10),
      );
      expect(ready, isTrue, reason: '前置条件: 进程必须先起来才能验证 kill 后的效果');

      await launcher.kill();

      // 给系统一点时间真正释放端口 (进程终止是异步的)
      bool stillOpen = true;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        try {
          final socket = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 300),
          );
          socket.destroy();
        } catch (_) {
          stillOpen = false;
          break;
        }
      }

      expect(stillOpen, isFalse, reason: 'kill() 后端口应当不再可连接');
      print('[测试] 结论: kill() 后端口 $port 确认已释放，没有留下僵尸进程占用');
    });

    test('waitForPortOpen 对一直不开端口的进程应在超时后返回 false', () async {
      final launcher = LocalProcessLauncher();
      // 启动一个不会监听任何端口、只是空转的进程
      await launcher.start(
        command: 'python',
        args: ['-c', 'import time; time.sleep(30)'],
      );

      final port = await pickFreePort(); // 一个当前必然没人监听的端口
      final ready = await launcher.waitForPortOpen(
        Uri.parse('http://127.0.0.1:$port'),
        timeout: const Duration(seconds: 2),
        retryInterval: const Duration(milliseconds: 200),
      );

      expect(ready, isFalse);
      print('[测试] 结论: 端口一直未就绪时，正确在超时后返回 false 而不是无限等待');

      await launcher.kill();
    });

    test('进程启动失败 (命令不存在) 时 start() 应抛出异常而不是静默失败', () async {
      final launcher = LocalProcessLauncher();
      expect(
        () => launcher.start(
          command: 'this-command-does-not-exist-abcxyz',
          args: const [],
        ),
        throwsA(anything),
      );
      print('[测试] 结论: 不存在的命令会抛出异常，调用方能感知到启动失败');
    });
  });
}

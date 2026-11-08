import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/background_jobs.dart';
import 'package:remind_ai/core/toolshell/executor.dart';
import 'package:remind_ai/core/toolshell/head_tail_output.dart';
import 'package:remind_ai/core/toolshell/system_executor.dart';

/// 自动模式"真的有完整权限且能自动化"的几个关键点：
/// 1. `toolshell_exec` 能跑任意命令（无白名单）并拿到 exit_code/stdout；
/// 2. 输出保留「开头 + 结尾」，不再只留尾巴（构建失败根因在开头）；
/// 3. 超时会强制终止进程树并快速返回，不会把整个对话拖死；
/// 4. `system_probe(category="android")` 能报告 adb/设备信息。
void main() {
  group('HeadTailCollector', () {
    test('未超限时原样拼回', () {
      final collector = HeadTailCollector()
        ..add(utf8.encode('hello '))
        ..add(utf8.encode('world'));

      expect(collector.truncated, isFalse);
      expect(collector.omittedBytes, 0);
      expect(collector.plainText, 'hello world');
      expect(collector.total, 11);
    });

    test('超限时保留开头与结尾，中间标记省略', () {
      // 头 10 字节、尾 20 字节（尾要放得下最后一段 15 字节的收尾信息）
      final collector = HeadTailCollector(headLimit: 10, tailLimit: 20);
      collector
        ..add(utf8.encode('HEAD-0123456789'))
        ..add(utf8.encode('X' * 500))
        ..add(utf8.encode('TAIL-9876543210'));

      final text = collector.plainText;
      expect(collector.truncated, isTrue);
      expect(collector.omittedBytes, greaterThan(0));
      expect(text.startsWith('HEAD-'), isTrue, reason: '开头必须保留');
      expect(text.endsWith('9876543210'), isTrue, reason: '结尾必须保留');
      expect(text.contains('中间省略'), isTrue);
      expect(collector.total, 15 + 500 + 15);
    });

    test('单块比头还大时也能正确切分', () {
      final collector = HeadTailCollector(headLimit: 4, tailLimit: 4);
      collector.add(utf8.encode('0123456789'));

      expect(collector.plainText.startsWith('0123'), isTrue);
      expect(collector.plainText.endsWith('6789'), isTrue);
      expect(collector.omittedBytes, 2);
    });

    test('空块不改变状态', () {
      final collector = HeadTailCollector()..add(const <int>[]);
      expect(collector.total, 0);
      expect(collector.truncated, isFalse);
      expect(collector.plainText, '');
    });
  });

  group('toolshell_exec', () {
    late Directory tempDir;
    late Executor executor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exec_caps_');
      executor = Executor(
        projectRoot: tempDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: true,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('能执行任意命令并返回 exit_code 与 stdout', () async {
      final raw = await executor.run('toolshell_exec', {
        'command': 'echo hello-remind-ai',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(result['exit_code'], 0);
      expect('${result['stdout']}', contains('hello-remind-ai'));
    });

    test('非零退出码如实返回（不吞错）', () async {
      // `exit 3` 在 cmd 与 PowerShell 里都能用
      final raw = await executor.run('toolshell_exec', {
        'command': 'exit 3',
        'timeout': 20,
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(result['exit_code'], 3);
    });

    test('超时会终止进程树并快速返回 TIMEOUT', () async {
      final command = Platform.isWindows
          ? 'ping -n 30 127.0.0.1'
          : 'sleep 30';

      final stopwatch = Stopwatch()..start();
      final raw = await executor.run('toolshell_exec', {
        'command': command,
        'timeout': 1,
      });
      stopwatch.stop();

      final result = jsonDecode(raw) as Map<String, dynamic>;
      expect(result['status'], 'error');
      expect(result['code'], 'TIMEOUT');
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 15)),
        reason: '超时后应该立刻返回，而不是等命令自己结束',
      );
    });
  });

  group('system_probe(android)', () {
    test('返回 android 类别 + 工具清单 + SDK 环境', () async {
      final raw = await SystemExecutor().run('system_probe', {
        'category': 'android',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(result['category'], 'android');
      expect(result['tools'], isA<List<dynamic>>());
      expect(result['env'], isA<Map<String, dynamic>>());

      final names = (result['tools'] as List<dynamic>)
          .map((e) => (e as Map<String, dynamic>)['name'])
          .toList();
      expect(names, contains('adb'));
    });
  });

  group('android 工作目录', () {
    test('相对 cwd 会落到项目根下', () async {
      final tempDir = await Directory.systemTemp.createTemp('exec_cwd_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final executor = Executor(
        projectRoot: tempDir.path,
        permissionMode: PermissionMode.auto,
      );
      await executor.run('toolshell_exec', {
        'command': Platform.isWindows ? 'cd' : 'pwd',
        'cwd': 'sub/dir',
        'timeout': 20,
      });

      expect(
        Directory(p.join(tempDir.path, 'sub', 'dir')).existsSync(),
        isTrue,
        reason: 'exec 前应先创建 cwd',
      );
    });
  });

  group('后台任务', () {
    late Directory tempDir;
    late Executor executor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exec_bg_');
      executor = Executor(
        projectRoot: tempDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: true,
      );
    });

    tearDown(() async {
      await BackgroundJobManager.instance.disposeAll();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {
        // Windows 上日志句柄可能还没释放，测试目录交给系统清理
      }
    });

    test('启动 → 读输出 → 终止', () async {
      final command = Platform.isWindows
          ? 'ping -n 8 127.0.0.1'
          : 'sh -c "for i in 1 2 3 4 5 6 7 8; do echo line\$i; sleep 0.4; done"';

      final started =
          jsonDecode(
                await executor.run('toolshell_exec_background', {
                  'command': command,
                }),
              )
              as Map<String, dynamic>;
      expect(started['status'], 'ok');
      final jobId = started['job_id'] as String;
      expect(jobId, startsWith('job-'));

      // 等进程吐出一点输出
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      final out =
          jsonDecode(
                await executor.run('toolshell_job_output', {'job_id': jobId}),
              )
              as Map<String, dynamic>;
      expect(out['job_status'], anyOf('running', 'exited'));
      expect('${out['output']}'.trim().isNotEmpty, isTrue);

      final killed =
          jsonDecode(
                await executor.run('toolshell_job_kill', {'job_id': jobId}),
              )
              as Map<String, dynamic>;
      expect(killed['status'], 'ok');
      expect(killed['killed'], isTrue);

      final after =
          jsonDecode(
                await executor.run('toolshell_job_output', {'job_id': jobId}),
              )
              as Map<String, dynamic>;
      expect(after['job_status'], anyOf('killed', 'exited'));

      final list =
          jsonDecode(await executor.run('toolshell_job_list', {}))
              as Map<String, dynamic>;
      expect(list['jobs'], isA<List<dynamic>>());
    });

    test('未知 job_id 报错而不是崩', () async {
      final raw =
          jsonDecode(
                await executor.run('toolshell_job_output', {
                  'job_id': 'job-999',
                }),
              )
              as Map<String, dynamic>;
      expect(raw['status'], 'error');
      expect(raw['code'], 'JOB_NOT_FOUND');
    });
  });
}

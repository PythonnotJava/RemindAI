import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/tool_pipeline.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 toolshell_run_parallel 的行为。
///
/// 覆盖场景:
/// 1. 正常并行成功 (多个 toolshell_read 同时读取不同文件)
/// 2. 超过并行数量上限 (maxCalls=8) 被拒绝
/// 3. 混合批次自动分流：目标不同→并发；同目标/需确认→串行（不再整批拒绝）
/// 4. 嵌套 toolshell_run_parallel 被拒绝
/// 5. 非法参数格式被拒绝 (calls 非数组 / 缺少 tool 字段)
///
/// 注意：测试产物放在系统临时目录里，**不要**再硬编码桌面路径
/// （以前写死 `C:\Users\25654\Desktop\test`，每次跑测试都会在桌面
/// 留下一堆空文件夹）。
void main() {
  late Directory workDir;

  setUpAll(() async {
    workDir = await Directory.systemTemp.createTemp('remind_parallel_test_');

    // 准备三个用于并行读取验证的文件
    await File(
      '${workDir.path}${Platform.pathSeparator}a.txt',
    ).writeAsString('内容A');
    await File(
      '${workDir.path}${Platform.pathSeparator}b.txt',
    ).writeAsString('内容B');
    await File(
      '${workDir.path}${Platform.pathSeparator}c.txt',
    ).writeAsString('内容C');
  });

  tearDownAll(() async {
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
  });

  ToolPipeline buildPipeline() {
    final executor = Executor(
      projectRoot: workDir.path,
      permissionMode: PermissionMode.auto,
    );
    return ToolPipeline(executor: executor, middlewares: const []);
  }

  Future<Map<String, dynamic>> call(
    ToolPipeline pipeline,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final raw = await pipeline.run(tool, args);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('toolshell_run_parallel', () {
    test('场景1: 正常并行读取多个文件，全部成功', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'a.txt'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'b.txt'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'c.txt'},
          },
        ],
      });

      // 终端输出用于人工核验
      print('[场景1] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      expect(res['count'], 3);
      final results = res['results'] as List;
      expect(results.length, 3);
      for (final item in results) {
        final r = item as Map<String, dynamic>;
        final inner = r['result'] as Map<String, dynamic>;
        expect(inner['status'], 'ok');
      }
      // 验证内容确实对应各自文件 (顺序应与输入一致)
      expect(
        (results[0]['result'] as Map)['content'].toString(),
        contains('内容A'),
      );
      expect(
        (results[1]['result'] as Map)['content'].toString(),
        contains('内容B'),
      );
      expect(
        (results[2]['result'] as Map)['content'].toString(),
        contains('内容C'),
      );
    });

    test('场景2: 超过并行数量上限(8个)被整体拒绝', () async {
      final pipeline = buildPipeline();
      final calls = List.generate(
        9,
        (i) => {
          'tool': 'toolshell_read',
          'args': {'path': 'a.txt'},
        },
      );
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': calls,
      });

      print('[场景2] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'TOO_MANY_CALLS');
    });

    test('场景3: 读+写混合批次不再整批拒绝（目标不同 → 并发）', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'a.txt'},
          },
          {
            'tool': 'toolshell_write',
            'args': {
              'path': 'mixed_ok.txt',
              'content': 'x',
              'mode': 'create',
            },
          },
        ],
      });

      print('[场景3] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      expect(res['count'], 2);
      expect(res['parallel_count'], 2);
      expect(res['serial_count'], 0);

      // 写操作确实执行了（旧实现会整批拒绝、文件不存在）
      final f = File(
        '${workDir.path}${Platform.pathSeparator}mixed_ok.txt',
      );
      expect(await f.exists(), isTrue);
      expect(await f.readAsString(), 'x');
    });

    test('场景3b: 同一文件写两次 → 自动串行，最终是后一次的内容', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_write',
            'args': {
              'path': 'same_target.txt',
              'content': 'first',
              'mode': 'overwrite',
            },
          },
          {
            'tool': 'toolshell_write',
            'args': {
              'path': 'same_target.txt',
              'content': 'second',
              'mode': 'overwrite',
            },
          },
        ],
      });

      expect(res['status'], 'ok');
      expect(res['serial_count'], 2);
      expect(res['serialized'], ['toolshell_write', 'toolshell_write']);
      expect(
        await File(
          '${workDir.path}${Platform.pathSeparator}same_target.txt',
        ).readAsString(),
        'second',
      );
    });

    test('场景3c: 读文件 + 执行命令 可以同批并发（用户报的 case）', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'a.txt'},
          },
          {
            'tool': 'toolshell_exec',
            'args': {'command': 'echo parallel-ok'},
          },
        ],
      });

      expect(res['status'], 'ok');
      expect(res['parallel_count'], 2);
      expect(res['serial_count'], 0);

      final results = res['results'] as List<dynamic>;
      final execResult = results[1]['result'] as Map<String, dynamic>;
      expect(execResult['exit_code'], 0);
      expect('${execResult['stdout']}', contains('parallel-ok'));
    });

    test('场景3d: normal 模式下需要确认的工具自动串行', () async {
      final executor = Executor(
        projectRoot: workDir.path,
        permissionMode: PermissionMode.normal,
        onPermissionRequest: (tool, args) async => true,
      );
      final pipeline = ToolPipeline(executor: executor, middlewares: const []);

      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'a.txt'},
          },
          {
            'tool': 'toolshell_exec',
            'args': {'command': 'echo serial-ok'},
          },
        ],
      });

      expect(res['status'], 'ok');
      expect(res['serial_count'], 1);
      expect(res['serialized'], ['toolshell_exec']);

      final results = res['results'] as List<dynamic>;
      final execResult = results[1]['result'] as Map<String, dynamic>;
      expect(execResult['exit_code'], 0);
    });

    test('场景4: 嵌套 toolshell_run_parallel 被拒绝', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_run_parallel',
            'args': {
              'calls': [
                {
                  'tool': 'toolshell_read',
                  'args': {'path': 'a.txt'},
                },
              ],
            },
          },
        ],
      });

      print('[场景4] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'PARALLEL_NOT_ALLOWED');
      expect(res['detail'].toString(), contains('toolshell_run_parallel'));
    });

    test('场景5a: calls 非数组被拒绝', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': '不是数组',
      });

      print('[场景5a] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'INVALID_ARGS');
    });

    test('场景5b: calls 为空数组被拒绝', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {'calls': []});

      print('[场景5b] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'INVALID_ARGS');
    });

    test('场景5c: 子调用缺少 tool 字段被拒绝', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'args': {'path': 'a.txt'},
          },
        ],
      });

      print('[场景5c] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'INVALID_ARGS');
    });

    test('场景6: 单个子调用失败不影响其他子调用 (读取不存在的文件)', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'a.txt'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'not_exist_at_all.txt'},
          },
        ],
      });

      print('[场景6] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final results = res['results'] as List;
      final ok = (results[0]['result'] as Map)['status'];
      final fail = (results[1]['result'] as Map)['status'];
      expect(ok, 'ok');
      expect(fail, 'error');
    });
  });
}

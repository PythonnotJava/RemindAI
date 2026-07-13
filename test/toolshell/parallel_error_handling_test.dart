import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/tool_pipeline.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 toolshell_run_parallel 和子工具在参数缺失时的错误处理
void main() {
  const testRoot = r'C:\Users\25654\Desktop\test';
  late Directory workDir;

  setUpAll(() async {
    workDir = Directory(
      '$testRoot${Platform.pathSeparator}parallel_error_test',
    );
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    // 创建测试文件
    await File(
      '${workDir.path}${Platform.pathSeparator}test.txt',
    ).writeAsString('测试内容');
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

  group('并行调用错误处理', () {
    test('场景1: 子调用 args 缺失 - 应返回清晰错误而非类型异常', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            // 故意不提供 args 字段
          },
        ],
      });

      print('[场景1] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok'); // 并行调用本身成功
      final results = res['results'] as List;
      final firstResult = results[0]['result'] as Map<String, dynamic>;

      // 子调用应该返回清晰的错误，而不是 type 'Null' is not a subtype
      expect(firstResult['status'], 'error');
      expect(firstResult['code'], 'INVALID_ARGS');
      expect(firstResult['detail'].toString(), contains('缺少必需参数 path'));
    });

    test('场景2: 子调用 args 为空对象 - 应返回清晰错误', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {}, // 空对象，缺少 path
          },
        ],
      });

      print('[场景2] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final results = res['results'] as List;
      final firstResult = results[0]['result'] as Map<String, dynamic>;

      expect(firstResult['status'], 'error');
      expect(firstResult['code'], 'INVALID_ARGS');
      expect(firstResult['detail'].toString(), contains('缺少必需参数 path'));
    });

    test('场景3: 子调用 args 不是对象类型 - 应返回清晰错误', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': 'not_an_object', // 错误类型
          },
        ],
      });

      print('[场景3] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final results = res['results'] as List;
      final firstResult = results[0]['result'] as Map<String, dynamic>;

      expect(firstResult['status'], 'error');
      expect(firstResult['code'], 'INVALID_ARGS');
    });

    test('场景4: 混合正确和错误的子调用', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'test.txt'}, // 正确
          },
          {
            'tool': 'toolshell_read',
            'args': {}, // 错误：缺少 path
          },
          {
            'tool': 'toolshell_read',
            // 错误：缺少 args
          },
        ],
      });

      print('[场景4] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final results = res['results'] as List;
      expect(results.length, 3);

      // 第一个应该成功
      expect((results[0]['result'] as Map)['status'], 'ok');

      // 第二、三个应该失败但有清晰错误信息
      expect((results[1]['result'] as Map)['status'], 'error');
      expect((results[1]['result'] as Map)['code'], 'INVALID_ARGS');
      expect((results[2]['result'] as Map)['status'], 'error');
      expect((results[2]['result'] as Map)['code'], 'INVALID_ARGS');
    });

    test('场景5: toolshell_write 缺少必需参数', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'test.txt'}, // 用于触发 PARALLEL_NOT_ALLOWED
          },
        ],
      });

      // 注意：toolshell_write 在 PARALLEL_NOT_ALLOWED 列表中，
      // 所以我们改为测试直接调用
      final writeRes = await call(pipeline, 'toolshell_write', {});

      print('[场景5] 结果: ${jsonEncode(writeRes)}');

      expect(writeRes['status'], 'error');
      expect(writeRes['code'], 'INVALID_ARGS');
      expect(writeRes['detail'].toString(), contains('缺少必需参数'));
    });

    test('场景6: toolshell_exec 缺少 command 参数', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_exec', {});

      print('[场景6] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'INVALID_ARGS');
      expect(res['detail'].toString(), contains('缺少必需参数 command'));
    });

    test('场景7: toolshell_search 缺少 pattern 参数', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_search',
            'args': {'scope': '.'}, // 缺少 pattern
          },
        ],
      });

      print('[场景7] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final results = res['results'] as List;
      final firstResult = results[0]['result'] as Map<String, dynamic>;

      expect(firstResult['status'], 'error');
      expect(firstResult['code'], 'INVALID_ARGS');
      expect(firstResult['detail'].toString(), contains('缺少必需参数 pattern'));
    });
  });
}

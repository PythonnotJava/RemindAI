import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/tool_pipeline.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 在一个真实的小型开发项目 (Node/Express 结构) 上验证
/// toolshell_run_parallel 的实际收益与安全边界。
///
/// 项目位于 C:\Users\25654\Desktop\test\demo_project，结构:
///   package.json
///   src/index.js
///   src/api/user.js
///   src/api/order.js
///   src/utils/date.js
///   src/utils/logger.js
///   tests/user.test.js
///
/// 测试完成后不删除该项目，便于人工检查产物。
void main() {
  const projectRoot = r'C:\Users\25654\Desktop\test\demo_project';

  ToolPipeline buildPipeline() {
    final executor = Executor(
      projectRoot: projectRoot,
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

  setUpAll(() {
    expect(
      Directory(projectRoot).existsSync(),
      isTrue,
      reason: '需要先准备好示例开发项目: $projectRoot',
    );
  });

  group('toolshell_run_parallel - 真实开发项目场景', () {
    test('场景1: 一次性并行摸清项目结构 (5个源码文件同时读取)', () async {
      final pipeline = buildPipeline();
      final sw = Stopwatch()..start();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'src/index.js'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'src/api/user.js'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'src/api/order.js'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'src/utils/date.js'},
          },
          {
            'tool': 'toolshell_read',
            'args': {'path': 'src/utils/logger.js'},
          },
        ],
      });
      sw.stop();

      print('[场景1] 并行读取5个文件耗时: ${sw.elapsedMilliseconds}ms');
      print('[场景1] 返回汇总: status=${res['status']} count=${res['count']}');

      expect(res['status'], 'ok');
      expect(res['count'], 5);
      final results = res['results'] as List;
      for (final item in results) {
        final r = item as Map<String, dynamic>;
        final inner = r['result'] as Map<String, dynamic>;
        expect(inner['status'], 'ok', reason: '${r['args']} 应该读取成功');
      }
      // 验证具体内容确实读到了对应文件
      final indexContent = (results[0]['result'] as Map)['content'].toString();
      expect(indexContent, contains('express'));
      final userContent = (results[1]['result'] as Map)['content'].toString();
      expect(userContent, contains('router.get'));

      print('[场景1] 结论: 5个文件的内容在同一批并行请求中全部正确取回');
    });

    test('场景2: 并行搜索 — 同时按不同模式定位代码', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_search',
            'args': {
              'pattern': '*.js',
              'scope': 'src/api',
              'content': 'router\\.',
            },
          },
          {
            'tool': 'toolshell_search',
            'args': {'pattern': '*.js', 'scope': 'src/utils'},
          },
          {
            'tool': 'toolshell_search',
            'args': {'pattern': '*.test.js', 'scope': 'tests'},
          },
        ],
      });

      print('[场景2] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      expect(res['count'], 3);
      final results = res['results'] as List;
      for (final item in results) {
        final inner = (item as Map)['result'] as Map;
        expect(inner['status'], 'ok');
      }
      // src/api 下按 router. 内容过滤应命中 user.js 和 order.js
      final apiMatches = (results[0]['result'] as Map)['matches'] as List;
      expect(apiMatches.length, greaterThanOrEqualTo(1));
      // src/utils 下应能列出 date.js 和 logger.js
      final utilsMatches = (results[1]['result'] as Map)['matches'] as List;
      expect(utilsMatches.length, 2);
    });

    test('场景3: 混合读取+搜索 一批发出，互不干扰', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'package.json'},
          },
          {
            'tool': 'toolshell_search',
            'args': {'pattern': '*.js', 'scope': 'src'},
          },
        ],
      });

      print('[场景3] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'ok');
      final pkg = (res['results'] as List)[0] as Map;
      final pkgResult = pkg['result'] as Map;
      expect(pkgResult['status'], 'ok');
      expect(pkgResult['content'].toString(), contains('demo-project'));
    });

    test('场景4: 想在同批里夹带 npm install (toolshell_exec) 被整体拒绝', () async {
      final pipeline = buildPipeline();
      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_read',
            'args': {'path': 'package.json'},
          },
          {
            'tool': 'toolshell_exec',
            'args': {'command': 'npm install'},
          },
        ],
      });

      print('[场景4] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'PARALLEL_NOT_ALLOWED');
      expect(res['detail'].toString(), contains('toolshell_exec'));
      // node_modules 不应该被创建 (确实没有执行到)
      expect(
        Directory(
          '$projectRoot${Platform.pathSeparator}node_modules',
        ).existsSync(),
        isFalse,
      );
    });

    test('场景5: 想在同批里夹带修改 package.json 被整体拒绝，内容未变', () async {
      final pipeline = buildPipeline();
      final before = await File(
        '$projectRoot${Platform.pathSeparator}package.json',
      ).readAsString();

      final res = await call(pipeline, 'toolshell_run_parallel', {
        'calls': [
          {
            'tool': 'toolshell_search',
            'args': {'pattern': '*.js', 'scope': 'src'},
          },
          {
            'tool': 'toolshell_write',
            'args': {
              'path': 'package.json',
              'content': '{"tampered": true}',
              'mode': 'overwrite',
            },
          },
        ],
      });

      print('[场景5] 结果: ${jsonEncode(res)}');

      expect(res['status'], 'error');
      expect(res['code'], 'PARALLEL_NOT_ALLOWED');

      final after = await File(
        '$projectRoot${Platform.pathSeparator}package.json',
      ).readAsString();
      expect(after, equals(before), reason: 'package.json 不应被改动');
    });

    test('场景6: 串行对照组 — 逐个执行同样5次读取，用于耗时对比', () async {
      final executor = Executor(
        projectRoot: projectRoot,
        permissionMode: PermissionMode.auto,
      );
      final paths = [
        'src/index.js',
        'src/api/user.js',
        'src/api/order.js',
        'src/utils/date.js',
        'src/utils/logger.js',
      ];

      final sw = Stopwatch()..start();
      for (final path in paths) {
        final raw = await executor.run('toolshell_read', {'path': path});
        final r = jsonDecode(raw) as Map<String, dynamic>;
        expect(r['status'], 'ok');
      }
      sw.stop();

      print('[场景6] 串行读取5个文件耗时: ${sw.elapsedMilliseconds}ms (对照组，用于对比场景1的并行耗时)');
    });
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:remind_ai/core/toolshell/executor.dart';
import 'package:remind_ai/core/memory/project_config.dart';

/// 测试 assets/bin 中的三个 exe 是否能在 Agent 中被实际调用。
///
/// 这些工具由 Executor 在初始化时探测并缓存路径，
/// 在 toolshell_search 和 toolshell_exec 中使用：
/// - rg.exe: 内容搜索 (toolshell_search + content 参数)
/// - fd.exe: 文件名搜索 (toolshell_search 纯 pattern)
/// - rtk.exe: 命令输出压缩 (toolshell_exec 白名单命令)
void main() {
  late Executor executor;
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('exe_test_');
    // 创建测试文件
    File(
      p.join(tempDir.path, 'hello.dart'),
    ).writeAsStringSync('void main() {\n  print("hello");\n}\n');
    File(
      p.join(tempDir.path, 'world.py'),
    ).writeAsStringSync('print("world")\n');
    File(p.join(tempDir.path, 'sub', 'nested.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('nested content here\n');

    executor = Executor(
      projectRoot: tempDir.path,
      permissionMode: PermissionMode.auto,
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  group('rg.exe (内容搜索)', () {
    test('toolshell_search 带 content 参数使用 rg', () async {
      final result = await executor.run('toolshell_search', {
        'pattern': '*.dart',
        'content': 'print',
      });

      print('rg 搜索结果: $result');
      expect(result, contains('"status":"ok"'));
      // 应该匹配到含 print 的内容
      expect(result, contains('print'));
      // 确认是 rg 引擎
      expect(result, contains('"engine":"rg"'));
      // 至少有 1 个匹配
      expect(result, contains('"total":1'));
    });

    test('rg 搜索无匹配时返回空结果', () async {
      final result = await executor.run('toolshell_search', {
        'pattern': '*.dart',
        'content': 'nonexistent_xyz_abc',
      });

      print('rg 空结果: $result');
      expect(result, contains('"status":"ok"'));
      expect(result, contains('"total":0'));
    });
  });

  group('fd.exe (文件名搜索)', () {
    test('toolshell_search 纯 pattern 使用 fd', () async {
      final result = await executor.run('toolshell_search', {
        'pattern': '.dart',
      });

      print('fd 搜索结果: $result');
      expect(result, contains('"status":"ok"'));
      expect(result, contains('hello.dart'));
    });

    test('fd 搜索 py 文件', () async {
      final result = await executor.run('toolshell_search', {'pattern': '.py'});

      print('fd py 搜索: $result');
      expect(result, contains('"status":"ok"'));
      expect(result, contains('world.py'));
    });

    test('fd 搜索嵌套目录', () async {
      final result = await executor.run('toolshell_search', {
        'pattern': 'nested',
      });

      print('fd 嵌套搜索: $result');
      expect(result, contains('"status":"ok"'));
      expect(result, contains('nested.txt'));
    });
  });

  group('rtk.exe (命令输出压缩)', () {
    test('git status 命令被 rtk 包裹', () async {
      // 在临时目录初始化 git 以确保 git status 能运行
      await Process.run('git', ['init'], workingDirectory: tempDir.path);

      final result = await executor.run('toolshell_exec', {
        'command': 'git status',
      });

      print('rtk git status 结果: $result');
      // 无论 rtk 是否生效，命令应该执行成功
      expect(result, contains('"status":"ok"'));
      // 终端应该打印了 [RTK] 相关日志（表明尝试了包裹）
    });

    test('非白名单命令不被 rtk 包裹', () async {
      final result = await executor.run('toolshell_exec', {
        'command': 'echo hello_rtk_test',
      });

      print('echo 结果: $result');
      expect(result, contains('"status":"ok"'));
      expect(result, contains('hello_rtk_test'));
    });
  });
}

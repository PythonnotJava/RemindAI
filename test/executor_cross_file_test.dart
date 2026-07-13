import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 测试 auto 模式 + allowOutsideRoot 的跨文件访问
void main() {
  group('Executor 跨文件访问测试', () {
    late Directory tempDir;
    late Directory projectDir;
    late Directory outsideDir;
    late String testFilePath;

    setUp(() async {
      // 创建临时目录结构
      tempDir = await Directory.systemTemp.createTemp('executor_test_');
      projectDir = Directory(p.join(tempDir.path, 'project'));
      outsideDir = Directory(p.join(tempDir.path, 'outside'));
      await projectDir.create();
      await outsideDir.create();

      // 在项目外创建测试文件
      testFilePath = p.join(outsideDir.path, 'test.txt');
      await File(testFilePath).writeAsString('外部文件内容');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('allowOutsideRoot=false (默认) 应该拒绝跨文件访问', () async {
      final executor = Executor(
        projectRoot: projectDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: false, // 默认值
      );

      final result = await executor.run('toolshell_read', {
        'path': testFilePath,
      });

      // 应该返回错误
      expect(result, contains('路径越界'));
    });

    test('allowOutsideRoot=true 应该允许跨文件访问（绝对路径）', () async {
      final executor = Executor(
        projectRoot: projectDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: true, // 关键设置
      );

      final result = await executor.run('toolshell_read', {
        'path': testFilePath,
      });

      print('读取结果: $result');

      // 应该成功读取
      expect(result, contains('外部文件内容'));
      expect(result, contains('status'));
      expect(result, contains('success'));
    });

    test('allowOutsideRoot=true 相对路径仍然相对 projectRoot', () async {
      final executor = Executor(
        projectRoot: projectDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: true,
      );

      // 在项目内创建文件
      final insideFile = File(p.join(projectDir.path, 'inside.txt'));
      await insideFile.writeAsString('项目内文件');

      // 使用相对路径
      final result = await executor.run('toolshell_read', {
        'path': 'inside.txt', // 相对路径
      });

      print('相对路径读取结果: $result');

      // 应该成功读取
      expect(result, contains('项目内文件'));
    });

    test('auto 模式 + allowOutsideRoot=true 应该允许写入外部文件', () async {
      final executor = Executor(
        projectRoot: projectDir.path,
        permissionMode: PermissionMode.auto,
        allowOutsideRoot: true,
      );

      final outsideWritePath = p.join(outsideDir.path, 'write_test.txt');

      final result = await executor.run('toolshell_write', {
        'path': outsideWritePath,
        'content': '写入外部内容',
        'mode': 'create',
      });

      print('写入结果: $result');

      // 应该成功写入
      expect(result, contains('success'));

      // 验证文件确实被创建
      expect(await File(outsideWritePath).exists(), isTrue);
      expect(await File(outsideWritePath).readAsString(), equals('写入外部内容'));
    });

    test('normal 模式即使 allowOutsideRoot=true 也需要权限确认', () async {
      var permissionRequested = false;

      final executor = Executor(
        projectRoot: projectDir.path,
        permissionMode: PermissionMode.normal, // 注意这里是 normal
        allowOutsideRoot: true,
        onPermissionRequest: (tool, args) async {
          permissionRequested = true;
          return false; // 拒绝
        },
      );

      final result = await executor.run('toolshell_write', {
        'path': p.join(outsideDir.path, 'blocked.txt'),
        'content': '应该被拒绝',
        'mode': 'create',
      });

      // 应该请求了权限
      expect(permissionRequested, isTrue);

      // 应该被拒绝
      expect(result, contains('PERMISSION_DENIED'));
    });
  });
}

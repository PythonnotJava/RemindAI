import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 allowOutsideRoot 对路径边界的控制：
/// - false(默认): 越界路径被拒绝 (路径越界)
/// - true: 越界路径可读/写，但受保护文件名 (.env/.git/...) 仍被拦截
void main() {
  late Directory root; // projectRoot
  late Directory outside; // root 之外的目录

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remindai_root_');
    outside = await Directory.systemTemp.createTemp('remindai_outside_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await outside.exists()) await outside.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    Executor exec,
    String tool,
    Map<String, dynamic> args,
  ) async {
    return jsonDecode(await exec.run(tool, args)) as Map<String, dynamic>;
  }

  group('沙箱模式 (allowOutsideRoot=false, 默认)', () {
    test('越界绝对路径写入被拒绝', () async {
      final exec = Executor(
        projectRoot: root.path,
        permissionMode: PermissionMode.auto,
      );
      final target = File('${outside.path}${Platform.pathSeparator}note.txt');
      final res = await call(exec, 'toolshell_write', {
        'path': target.path,
        'mode': 'create',
        'content': 'hi',
      });
      expect(res['status'], 'error');
      expect(res['detail'].toString(), contains('路径越界'));
      expect(await target.exists(), isFalse);
    });

    test('越界绝对路径读取被拒绝', () async {
      final exec = Executor(
        projectRoot: root.path,
        permissionMode: PermissionMode.auto,
      );
      final f = File('${outside.path}${Platform.pathSeparator}data.txt');
      await f.writeAsString('secret');
      final res = await call(exec, 'toolshell_read', {'path': f.path});
      expect(res['status'], 'error');
      expect(res['detail'].toString(), contains('路径越界'));
    });
  });

  group('解除边界模式 (allowOutsideRoot=true)', () {
    Executor build() => Executor(
      projectRoot: root.path,
      permissionMode: PermissionMode.auto,
      allowOutsideRoot: true,
    );

    test('可写入并读回 root 之外的绝对路径', () async {
      final exec = build();
      final target = '${outside.path}${Platform.pathSeparator}note.txt';
      final write = await call(exec, 'toolshell_write', {
        'path': target,
        'mode': 'create',
        'content': 'crossed',
      });
      expect(write['status'], 'ok');

      final read = await call(exec, 'toolshell_read', {'path': target});
      expect(read['status'], 'ok');
      expect(read['content'].toString(), contains('crossed'));
    });

    test('相对路径仍以 projectRoot 为基准解析', () async {
      final exec = build();
      final write = await call(exec, 'toolshell_write', {
        'path': 'inside.txt',
        'mode': 'create',
        'content': 'rel',
      });
      expect(write['status'], 'ok');
      expect(
        await File('${root.path}${Platform.pathSeparator}inside.txt').exists(),
        isTrue,
      );
    });

    test('受保护文件名 (.env) 在越界路径下仍被拦截', () async {
      final exec = build();
      final target = '${outside.path}${Platform.pathSeparator}.env';
      final res = await call(exec, 'toolshell_write', {
        'path': target,
        'mode': 'create',
        'content': 'SECRET=1',
      });
      expect(res['status'], 'error');
      expect(res['code'], 'PROTECTED_PATH');
      expect(await File(target).exists(), isFalse);
    });

    test('受保护目录 (.git) 段在越界路径下仍被拦截', () async {
      final exec = build();
      final target =
          '${outside.path}${Platform.pathSeparator}.git'
          '${Platform.pathSeparator}config';
      final res = await call(exec, 'toolshell_delete', {'path': target});
      expect(res['status'], 'error');
      expect(res['code'], 'PROTECTED_PATH');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/toolshell/read_only_executor.dart';

/// 验证 /sub-readers 依赖的核心安全前提：ReadOnlyExecutor 只放行
/// toolshell_read / toolshell_search，其余一切工具都被直接拒绝，
/// 不会转发到底层 Executor 执行任何写操作。
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remindai_readonly_');
    await File(
      '${root.path}${Platform.pathSeparator}hello.txt',
    ).writeAsString('hello world');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    ReadOnlyExecutor exec,
    String tool,
    Map<String, dynamic> args,
  ) async {
    return jsonDecode(await exec.run(tool, args)) as Map<String, dynamic>;
  }

  group('ReadOnlyExecutor 白名单放行', () {
    test('toolshell_read 正常放行', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_read', {'path': 'hello.txt'});
      expect(res['status'], 'ok');
    });

    test('toolshell_search 正常放行', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_search', {'pattern': '*.txt'});
      expect(res['status'], 'ok');
    });
  });

  group('ReadOnlyExecutor 拒绝一切写/执行类工具', () {
    test('toolshell_write 被拒绝，且文件确实未被写入', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_write', {
        'path': 'new.txt',
        'content': 'should not exist',
        'mode': 'create',
      });
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
      expect(
        await File('${root.path}${Platform.pathSeparator}new.txt').exists(),
        false,
      );
    });

    test('toolshell_delete 被拒绝，且文件确实未被删除', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_delete', {'path': 'hello.txt'});
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
      expect(
        await File('${root.path}${Platform.pathSeparator}hello.txt').exists(),
        true,
      );
    });

    test('toolshell_exec 被拒绝', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_exec', {'command': 'echo hi'});
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });

    test('toolshell_run_python 被拒绝', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_run_python', {
        'code': 'print(1)',
      });
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });

    test('toolshell_run_js 被拒绝', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_run_js', {
        'code': 'console.log(1)',
      });
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });

    test('toolshell_memory_store 被拒绝', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_memory_store', {'text': 'x'});
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });

    test('toolshell_install_skill 被拒绝', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'toolshell_install_skill', {
        'source_dir': root.path,
      });
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });

    test('未知工具名也被拒绝 (不会误放行)', () async {
      final exec = ReadOnlyExecutor(projectRoot: root.path);
      final res = await call(exec, 'some_unknown_tool', {});
      expect(res['status'], 'error');
      expect(res['code'], 'READONLY_MODE');
    });
  });

  group('并发安全性: 多个只读实例可同时指向同一目录而不冲突', () {
    test('两个独立 ReadOnlyExecutor 并行读同一文件不报错', () async {
      final execA = ReadOnlyExecutor(projectRoot: root.path);
      final execB = ReadOnlyExecutor(projectRoot: root.path);

      final results = await Future.wait([
        call(execA, 'toolshell_read', {'path': 'hello.txt'}),
        call(execB, 'toolshell_read', {'path': 'hello.txt'}),
      ]);

      for (final res in results) {
        expect(res['status'], 'ok');
      }
    });
  });

  group('工具定义与白名单保持一致', () {
    test('toolDefinitions 中声明的工具名都在 allowedTools 白名单内', () {
      for (final def in ReadOnlyExecutor.toolDefinitions) {
        final name = (def['function'] as Map)['name'] as String;
        expect(ReadOnlyExecutor.allowedTools.contains(name), true);
      }
    });
  });
}

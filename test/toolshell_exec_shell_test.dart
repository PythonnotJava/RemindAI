import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 端到端验证 toolshell_exec 的跨平台 shell 选择逻辑。
/// 直接跑真实 shell：Windows 用 PowerShell(无则 cmd)，Unix 用 bash(无则 sh)。
/// auto 权限模式绕过确认回调。
void main() {
  late Directory tmp;
  late Executor exec;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('remindai_exec_test_');
    exec = Executor(projectRoot: tmp.path, permissionMode: PermissionMode.auto);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run(String command) async {
    final raw = await exec.run('toolshell_exec', {'command': command});
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('toolshell_exec 跨平台执行', () {
    test('简单命令成功执行并捕获 stdout', () async {
      // echo 在 cmd / PowerShell / bash / sh 下都可用
      final result = await run('echo remindai_marker');
      expect(result['status'], 'ok');
      expect(result['exit_code'], 0);
      expect(result['stdout'].toString(), contains('remindai_marker'));
    });

    test('非零退出码被正确捕获', () async {
      // exit 3 在所有目标 shell 下语义一致
      final result = await run('exit 3');
      expect(result['status'], 'ok');
      expect(result['exit_code'], 3);
    });

    test('&& 链式命令两段都执行 (Windows 会降级到 cmd)', () async {
      final result = await run('echo first && echo second');
      expect(result['status'], 'ok');
      expect(result['exit_code'], 0);
      final out = result['stdout'].toString();
      expect(out, contains('first'));
      expect(out, contains('second'));
    });

    test('PowerShell 专属语法在 Windows 上可执行', () async {
      // Get-Date 是 PowerShell cmdlet；若降级到 cmd 会失败。
      // 仅在 Windows 且存在 PowerShell 时有意义。
      final result = await run(r'Write-Output $PSVersionTable.PSVersion.Major');
      expect(result['status'], 'ok');
      // PowerShell 存在则 exit 0 且输出主版本号(数字)
      if (result['exit_code'] == 0) {
        expect(result['stdout'].toString().trim(), isNotEmpty);
      }
    }, skip: !Platform.isWindows);
  });
}

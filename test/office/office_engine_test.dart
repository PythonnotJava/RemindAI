import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/office/office_engine.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

void main() {
  test('office engine assets and skill tools are present', () {
    expect(OfficeEnginePaths.wordScript, isNotNull);
    expect(OfficeEnginePaths.excelScript, isNotNull);
    final tools =
        jsonDecode(
              File(
                'assets/default_skills/office/tools.json',
              ).readAsStringSync(),
            )
            as List;
    final names = tools
        .map((t) => (t['function'] as Map)['name'] as String)
        .toSet();
    expect(names, contains('office_word_read'));
    expect(names, contains('office_word_edit'));
    expect(names, contains('office_excel_read'));
  });

  test('word engine create/read through the Dart runner', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final tmp = await Directory.systemTemp.createTemp('office_dart_');
    addTearDown(() => tmp.delete(recursive: true));

    final docx = '${tmp.path}${Platform.pathSeparator}test.docx';
    final create = await OfficeEngine.run(
      python: python,
      script: OfficeEnginePaths.wordScript!,
      action: 'create',
      request: {'output': docx, 'markdown': '# Hello\n\nWorld'},
      workingDirectory: tmp.path,
      timeout: const Duration(seconds: 60),
    );
    final created = jsonDecode(create) as Map<String, dynamic>;
    expect(created['status'], 'ok', reason: create);
    expect(File(docx).existsSync(), isTrue);

    final read = await OfficeEngine.run(
      python: python,
      script: OfficeEnginePaths.wordScript!,
      action: 'read',
      request: {
        'path': docx,
        'output_dir': '${tmp.path}${Platform.pathSeparator}out',
      },
      workingDirectory: tmp.path,
      timeout: const Duration(seconds: 60),
    );
    final result = jsonDecode(read) as Map<String, dynamic>;
    expect(result['status'], 'ok', reason: read);
    expect(File('${tmp.path}/out/document.md').existsSync(), isTrue);
  });

  test('Executor routes office_word_* tools', () async {
    final tmp = await Directory.systemTemp.createTemp('office_exec_');
    addTearDown(() => tmp.delete(recursive: true));
    final executor = Executor(
      projectRoot: tmp.path,
      permissionMode: PermissionMode.auto,
    );

    final docx = '${tmp.path}${Platform.pathSeparator}tool.docx';
    final create = await executor.run('office_word_create', {
      'output': docx,
      'markdown': '# Tool\n\nRouted through Executor',
    });
    final created = jsonDecode(create) as Map<String, dynamic>;
    expect(created['status'], 'ok', reason: create);

    final read = await executor.run('office_word_read', {
      'path': docx,
      'output_dir': '${tmp.path}${Platform.pathSeparator}read',
    });
    final result = jsonDecode(read) as Map<String, dynamic>;
    expect(result['status'], 'ok', reason: read);
    expect(result['document_md'], contains('document.md'));
  });

  test('Executor routes office_excel_read', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final tmp = await Directory.systemTemp.createTemp('office_xlsx_');
    addTearDown(() => tmp.delete(recursive: true));
    final xlsx = '${tmp.path}${Platform.pathSeparator}book.xlsx';
    final code = '''
import sys
from openpyxl import Workbook
wb = Workbook()
ws = wb.active
ws.title = "Data"
ws.append(["Name", "Qty"])
ws.append(["A", 1])
ws.append(["B", 2])
wb.save(sys.argv[1])
''';
    final made = await Process.run(python, ['-c', code, xlsx]);
    expect(made.exitCode, 0, reason: made.stderr.toString());

    final executor = Executor(
      projectRoot: tmp.path,
      permissionMode: PermissionMode.auto,
    );
    final read = await executor.run('office_excel_read', {
      'path': xlsx,
      'output_dir': '${tmp.path}${Platform.pathSeparator}read',
    });
    final result = jsonDecode(read) as Map<String, dynamic>;
    expect(result['status'], 'ok', reason: read);
    expect(result['sheets'], isNotEmpty);
    expect((result['sheets'] as List).first['name'], 'Data');
  });

  test('excel engine capabilities', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final result = await OfficeEngine.run(
      python: python,
      script: OfficeEnginePaths.excelScript!,
      action: 'capabilities',
      request: {},
      workingDirectory: Directory.current.path,
      timeout: const Duration(seconds: 60),
    );
    final payload = jsonDecode(result) as Map<String, dynamic>;
    expect(payload['status'], 'ok', reason: result);
    expect((payload['formats'] as Map)['input'], contains('xlsx'));
  });
}

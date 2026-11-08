import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../logger/app_logger.dart';

/// Locates the bundled Python office engines in dev and release layouts.
class OfficeEnginePaths {
  static List<String> get roots {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return [
      p.normalize(p.join(Directory.current.path, 'assets', 'office_engine')),
      p.normalize(
        p.join(exeDir, 'data', 'flutter_assets', 'assets', 'office_engine'),
      ),
      // macOS: Contents/MacOS/<exe> → Contents/Frameworks/App.framework/...
      p.normalize(
        p.join(
          exeDir,
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          'assets',
          'office_engine',
        ),
      ),
      p.normalize(p.join(exeDir, 'assets', 'office_engine')),
    ];
  }

  static String? _find(String relative) {
    for (final root in roots) {
      final candidate = p.normalize(p.join(root, relative));
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static String? get wordScript => _find(p.join('word', 'office_word.py'));
  static String? get excelScript => _find(p.join('excel', 'office_excel.py'));
  static String? get wordRequirements =>
      _find(p.join('word', 'requirements.txt'));
  static String? get excelRequirements =>
      _find(p.join('excel', 'requirements.txt'));

  static List<String> get requirementFiles => [
    ?wordRequirements,
    ?excelRequirements,
  ];
}

/// Runs the standalone office engines as child Python processes.
class OfficeEngine {
  static Future<String> run({
    required String python,
    required String script,
    required String action,
    required Map<String, dynamic> request,
    required String workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final payload = Map<String, dynamic>.from(request);
    payload['base_dir'] ??= workingDirectory;
    final cwd = workingDirectory.isNotEmpty
        ? workingDirectory
        : Directory.current.path;

    Process process;
    try {
      process = await Process.start(
        python,
        [script, action],
        workingDirectory: cwd,
        runInShell: false,
        environment: {'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'},
      );
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'code': 'PYTHON_START_FAILED',
        'message': '无法启动 Python: $e',
      });
    }

    try {
      process.stdin.write(jsonEncode(payload));
      await process.stdin.close();
    } catch (_) {}

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    String stdout;
    String stderr;
    try {
      final results = await Future.wait([
        stdoutFuture,
        stderrFuture,
      ]).timeout(timeout);
      stdout = results[0];
      stderr = results[1];
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return jsonEncode({
        'status': 'error',
        'code': 'TIMEOUT',
        'message': '办公文档处理超时（${timeout.inSeconds}s）',
      });
    }

    final exitCode = await process.exitCode;
    if (stdout.trim().isEmpty) {
      AppLogger.instance.log(
        '[OfficeEngine] empty stdout action=$action exit=$exitCode '
        'stderr=${stderr.length > 500 ? stderr.substring(stderr.length - 500) : stderr}',
      );
      return jsonEncode({
        'status': 'error',
        'code': 'EMPTY_OUTPUT',
        'message': '办公引擎没有返回结果',
        'detail': stderr.length > 1000
            ? stderr.substring(stderr.length - 1000)
            : stderr,
      });
    }

    try {
      jsonDecode(stdout);
    } catch (_) {
      AppLogger.instance.log(
        '[OfficeEngine] invalid JSON action=$action exit=$exitCode',
      );
      return jsonEncode({
        'status': 'error',
        'code': 'INVALID_ENGINE_OUTPUT',
        'message': '办公引擎返回的不是 JSON',
        'detail': stdout.length > 1000 ? stdout.substring(0, 1000) : stdout,
      });
    }

    AppLogger.instance.log(
      '[OfficeEngine] action=$action exit=$exitCode '
      'stdout=${stdout.length}B stderr=${stderr.length}B',
    );
    return stdout;
  }
}

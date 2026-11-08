import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger/app_logger.dart';
import '../office/office_engine.dart';

class PythonBootstrapException implements Exception {
  final String message;
  PythonBootstrapException(this.message);
  @override
  String toString() => message;
}

/// Per-user Python bootstrap used by the office engines.
///
/// Strategy:
/// 1. Reuse a previously installed Python (marker file).
/// 2. Find/install `uv` (single binary, no admin).
/// 3. `uv python install 3.12` into the app support directory.
/// 4. `uv pip install` the office engine requirements.
///
/// Nothing is installed unless the caller explicitly allows it (the
/// workspace is in `auto` mode).  A failed download/install is surfaced as a
/// tool error, never silently swallowed.
class PythonBootstrap {
  PythonBootstrap._();
  static final PythonBootstrap instance = PythonBootstrap._();

  Future<String?>? _installing;

  Future<Directory> _baseDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'python-bootstrap'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _marker(Directory base) async =>
      File(p.join(base.path, 'python-path.txt'));

  Future<String?> installedPython() async {
    final base = await _baseDir();
    final marker = await _marker(base);
    if (await marker.exists()) {
      final value = (await marker.readAsString()).trim();
      if (value.isNotEmpty && await File(value).exists()) return value;
    }
    final pythonDir = Directory(p.join(base.path, 'python'));
    if (!await pythonDir.exists()) return null;
    await for (final entity in pythonDir.list(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (name == 'python.exe' ||
          (name == 'python3' && p.basename(p.dirname(entity.path)) == 'bin')) {
        await marker.writeAsString(entity.path);
        return entity.path;
      }
    }
    return null;
  }

  /// Ensure Python exists. Returns null when auto-install is not possible.
  Future<String?> ensureInstalled() async {
    final existing = await installedPython();
    if (existing != null) return existing;
    final inFlight = _installing;
    if (inFlight != null) return inFlight;
    final future = _install();
    _installing = future;
    try {
      return await future;
    } finally {
      _installing = null;
    }
  }

  Future<String?> _install() async {
    final base = await _baseDir();
    final uv = await _ensureUv(base);
    if (uv == null) return null;

    final pythonDir = p.join(base.path, 'python');
    await Directory(pythonDir).create(recursive: true);
    AppLogger.instance.log(
      '[PythonBootstrap] uv python install 3.12 → $pythonDir',
    );

    final install = await _run(
      uv,
      ['python', 'install', '3.12'],
      environment: {'UV_PYTHON_INSTALL_DIR': pythonDir},
      timeout: const Duration(minutes: 15),
    );
    if (install.exitCode != 0) {
      throw PythonBootstrapException(
        '自动安装 Python 失败: ${_tail(install.stderr)}',
      );
    }

    final found = await _run(
      uv,
      ['python', 'find', '3.12'],
      environment: {'UV_PYTHON_INSTALL_DIR': pythonDir},
      timeout: const Duration(minutes: 2),
    );
    if (found.exitCode != 0) {
      throw PythonBootstrapException(
        'Python 安装完成但无法定位解释器: ${_tail(found.stderr)}',
      );
    }
    final python = found.stdout
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (python.isEmpty || !await File(python).exists()) {
      throw PythonBootstrapException('Python 安装完成但解释器路径无效: $python');
    }

    final marker = await _marker(base);
    await marker.writeAsString(python);
    AppLogger.instance.log('[PythonBootstrap] Python ready: $python');
    await ensureOfficeDeps(python);
    return python;
  }

  /// Install openpyxl/xlrd/python-docx/Pillow for the given interpreter.
  Future<void> ensureOfficeDeps(String python) async {
    final requirements = OfficeEnginePaths.requirementFiles;
    if (requirements.isEmpty) return;
    final base = await _baseDir();
    final key = python.hashCode.toUnsigned(32).toRadixString(16);
    final marker = File(p.join(base.path, 'office-deps-$key.ok'));
    if (await marker.exists()) return;

    final args = <String>[
      'pip',
      'install',
      '--python',
      python,
      for (final req in requirements) ...['-r', req],
    ];
    final uv = await _findUv(base);
    ProcessResult result;
    if (uv != null) {
      result = await _run(
        uv,
        args,
        environment: {'UV_PYTHON_INSTALL_DIR': p.join(base.path, 'python')},
        timeout: const Duration(minutes: 15),
      );
    } else {
      result = await _run(python, [
        '-m',
        'pip',
        'install',
        for (final req in requirements) ...['-r', req],
      ], timeout: const Duration(minutes: 15));
    }
    if (result.exitCode != 0) {
      throw PythonBootstrapException('安装办公引擎依赖失败: ${_tail(result.stderr)}');
    }
    await marker.writeAsString(DateTime.now().toIso8601String());
    AppLogger.instance.log('[PythonBootstrap] office dependencies installed');
  }

  Future<String?> _ensureUv(Directory base) async {
    final existing = await _findUv(base);
    if (existing != null) return existing;

    final asset = _uvAssetName();
    if (asset == null) return null;
    final url =
        'https://github.com/astral-sh/uv/releases/latest/download/$asset';
    final temp = File(p.join(Directory.systemTemp.path, asset));
    AppLogger.instance.log('[PythonBootstrap] downloading uv: $url');
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 15),
        ),
      );
      await dio.download(url, temp.path);
      final uvDir = Directory(p.join(base.path, 'uv'));
      if (await uvDir.exists()) await uvDir.delete(recursive: true);
      await uvDir.create(recursive: true);
      final extracted = await _extractArchive(temp.path, uvDir);
      if (extracted != null) {
        await _makeExecutable(extracted);
        return extracted;
      }
      throw PythonBootstrapException('uv 压缩包中没有找到 uv 可执行文件');
    } catch (e) {
      AppLogger.instance.log('[PythonBootstrap] uv download failed: $e');
      throw PythonBootstrapException(
        '无法下载 uv（自动安装 Python 需要联网）: $e\n'
        '也可以手动安装 Python 后在「运行环境」里指定解释器。',
      );
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  Future<String?> _findUv(Directory base) async {
    final local = Platform.isWindows
        ? p.join(base.path, 'uv', 'uv.exe')
        : p.join(base.path, 'uv', 'uv');
    if (await File(local).exists()) return local;
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(which, ['uv']);
      if (result.exitCode == 0) {
        final value = result.stdout
            .toString()
            .trim()
            .split(RegExp(r'\r?\n'))
            .first
            .trim();
        if (value.isNotEmpty && await File(value).exists()) return value;
      }
    } catch (_) {}
    return null;
  }

  String? _uvAssetName() {
    final arm =
        Platform.version.toLowerCase().contains('arm64') ||
        Platform.version.toLowerCase().contains('aarch64');
    final arch = arm ? 'aarch64' : 'x86_64';
    if (Platform.isWindows) {
      return 'uv-$arch-pc-windows-msvc.zip';
    }
    if (Platform.isMacOS) {
      return 'uv-$arch-apple-darwin.tar.gz';
    }
    if (Platform.isLinux) {
      return 'uv-$arch-unknown-linux-gnu.tar.gz';
    }
    return null;
  }

  Future<String?> _extractArchive(String path, Directory dest) async {
    final bytes = await File(path).readAsBytes();
    Archive archive;
    if (path.toLowerCase().endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else {
      archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    }

    String? uvPath;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalized = p.normalize(file.name.replaceAll('\\', '/'));
      if (normalized.startsWith('..') || p.isAbsolute(normalized)) continue;
      final target = File(p.join(dest.path, normalized));
      if (!p.isWithin(dest.path, target.path)) continue;
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content, flush: true);
      final base = p.basename(normalized).toLowerCase();
      if (base == 'uv' || base == 'uv.exe') uvPath = target.path;
    }
    return uvPath;
  }

  Future<void> _makeExecutable(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (_) {}
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      args,
      runInShell: false,
      environment: environment,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    String stdout;
    String stderr;
    try {
      final values = await Future.wait([
        stdoutFuture,
        stderrFuture,
      ]).timeout(timeout);
      stdout = values[0];
      stderr = values[1];
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return ProcessResult(process.pid, -1, '', '超时（${timeout.inSeconds}s）');
    }
    final code = await process.exitCode;
    return ProcessResult(process.pid, code, stdout, stderr);
  }

  String _tail(String value) {
    final text = value.trim();
    if (text.length <= 1500) return text;
    return text.substring(text.length - 1500);
  }
}

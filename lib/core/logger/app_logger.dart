import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../settings/app_settings.dart';

/// 应用日志服务 — 拦截所有 print 输出并写入日志文件
///
/// 日志存储在可配置目录下（默认 < rootDir >/logs/），按日期分文件。
/// 支持查看、清空操作，由日志页面调用。
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  late String _logDir;
  IOSink? _sink;
  String _currentDate = '';
  bool _initialized = false;

  /// 使用自定义路径初始化日志目录
  Future<void> init([String? customLogDir]) async {
    if (_initialized) return;
    if (customLogDir != null && customLogDir.isNotEmpty) {
      _logDir = customLogDir;
    } else {
      final root = await AppSettings.getRootDir();
      _logDir = p.join(root, 'logs');
    }
    await Directory(_logDir).create(recursive: true);
    _initialized = true;
    _rotateSink();
  }

  /// 运行时更新日志目录（设置页面修改后调用）
  Future<void> updateLogDir(String newDir) async {
    if (newDir.isEmpty || newDir == _logDir) return;
    _closeSinkSafely();
    _currentDate = '';
    _logDir = newDir;
    await Directory(_logDir).create(recursive: true);
    _rotateSink();
  }

  /// 日志目录路径
  String get logDir => _logDir;

  /// 写入一行日志
  void log(String line) {
    if (!_initialized) return;
    _rotateSink();
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final logLine = '[$time] $line';

    // 只写入文件，不调用 print（避免与 Zone.print 递归）
    // 控制台输出由 main.dart 的 Zone.print hook 中的 parent.print 处理

    try {
      _sink?.writeln(logLine);  // 写入文件
    } catch (e) {
      // 忽略写入错误，避免崩溃
    }
  }

  /// 确保当前写入的是今天的日志文件
  void _rotateSink() {
    final today = _todayStr();
    if (today == _currentDate && _sink != null) return;

    _closeSinkSafely();
    _currentDate = today;
    final file = File(p.join(_logDir, '$today.log'));
    _sink = file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  /// 安全关闭当前 sink。
  /// close() 已隐含 flush，无需单独调用 flush()。
  /// 未 await 的 flush() 会让 sink 进入 "bound" 状态导致 close 抛异常。
  void _closeSinkSafely() {
    final s = _sink;
    _sink = null;
    try {
      s?.close();
    } catch (_) {
      // sink 可能已关闭或处于 bound 状态，忽略
    }
  }

  /// 读取今天的日志内容
  Future<String> readToday() async {
    if (!_initialized) return '';
    final file = File(p.join(_logDir, '${_todayStr()}.log'));
    if (!await file.exists()) return '';
    try {
      return await file.readAsString(encoding: utf8);
    } catch (e) {
      // 如果 UTF-8 解码失败，尝试以字节方式读取
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 列出所有日志文件 (按时间倒序)
  Future<List<FileSystemEntity>> listLogFiles() async {
    if (!_initialized) return [];
    final dir = Directory(_logDir);
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 读取指定日志文件
  Future<String> readFile(String fileName) async {
    final file = File(p.join(_logDir, fileName));
    if (!await file.exists()) return '';
    try {
      return await file.readAsString(encoding: utf8);
    } catch (e) {
      // 如果 UTF-8 解码失败，尝试以字节方式读取
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  /// 清空所有日志
  Future<int> clearAll() async {
    if (!_initialized) return 0;
    _closeSinkSafely();
    _currentDate = '';

    final dir = Directory(_logDir);
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) {
        await entity.delete();
        count++;
      }
    }
    return count;
  }

  /// 获取日志总占用大小 (字节)
  Future<int> totalSize() async {
    if (!_initialized) return 0;
    final dir = Directory(_logDir);
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// 关闭日志 (应用退出时调用)
  void dispose() {
    _closeSinkSafely();
  }

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

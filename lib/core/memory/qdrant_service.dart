import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../logger/app_logger.dart';
import '../settings/app_settings.dart';

/// Qdrant 进程管理器 (Singleton)
///
/// 职责:
/// - 从 assets 复制 qdrant.exe 到可写目录 (~/.RemindAI/bin/)
/// - spawn 进程, 监听端口 6333
/// - 健康检查循环
/// - 崩溃自动重启 (最多 3 次)
/// - 应用退出时 graceful shutdown
class QdrantService {
  static QdrantService? _instance;
  static QdrantService get instance => _instance ??= QdrantService._();
  QdrantService._();

  static const int defaultPort = 6333;
  static const int _maxRestarts = 3;
  static const Duration _healthInterval = Duration(seconds: 10);
  static const Duration _startupTimeout = Duration(seconds: 30);

  Process? _process;
  Timer? _healthTimer;
  int _restartCount = 0;
  bool _shuttingDown = false;
  bool _isRunning = false;

  /// 用户在设置中手动指定的可执行文件路径 (优先级最高，空=自动检测)
  String _manualPath = '';

  /// 设置手动指定的 Qdrant 路径 (下次启动生效)
  void setManualPath(String path) {
    _manualPath = path.trim();
  }

  /// 当前状态
  bool get isRunning => _isRunning;
  int get port => defaultPort;
  String get baseUrl => 'http://localhost:$defaultPort';
  String get resolvedExecutablePath => _executablePath;

  /// 真实探活 — 直接 HTTP 探测端口，不依赖内部 _isRunning 标志。
  /// 用于检测外部/遗留进程是否已占用端口并响应。
  /// 探测成功会同步更新 _isRunning。
  Future<bool> probeHealth() async {
    final healthy = await _checkHealth();
    if (healthy) _isRunning = true;
    return healthy;
  }

  /// 计算存储目录占用 (字节)。目录不存在返回 0。
  Future<int> storageSize() async {
    try {
      // _storagePath 可能尚未初始化
      final dirPath = _storageInitialized
          ? _storagePath
          : await _defaultStoragePath();
      final dir = Directory(dirPath);
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  bool _storageInitialized = false;

  Future<String> _defaultStoragePath() async {
    final root = await _rootDir();
    return p.join(root, 'memory', 'qdrant_storage');
  }

  /// Qdrant 可执行文件路径
  late String _executablePath;

  /// 存储目录
  late String _storagePath;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  /// 初始化: 解析可执行文件路径和存储目录
  ///
  /// 可执行文件解析优先级 (避免不必要的复制):
  ///   1. 系统 PATH 中已安装的 qdrant (尊重用户自带)
  ///   2. assets/bin 中随包分发的 qdrant.exe (直接执行，不复制)
  ///   3. 复制到 .RemindAI/bin/ 作为兜底 (仅当上述都不可用)
  /// 若全部失败，_executablePath 为空，start() 会抛出可读错误提示。
  Future<void> _init() async {
    final remindAiDir = await _rootDir();
    _storagePath = p.join(remindAiDir, 'memory', 'qdrant_storage');
    _storageInitialized = true;
    await Directory(_storagePath).create(recursive: true);

    // 清理残留的 WAL 锁文件 (上次非正常退出可能留下)
    // Qdrant 在 WAL 锁存在时会 PANIC，导致启动失败。
    await _cleanWalLocks();

    _executablePath = await _resolveExecutable(remindAiDir);
  }

  /// 清理所有 collection shard 下的 .wal 锁文件。
  /// Qdrant 上次未正常关闭时会残留此文件，导致下次启动 PANIC。
  Future<void> _cleanWalLocks() async {
    try {
      final collectionsDir = Directory(p.join(_storagePath, 'collections'));
      if (!await collectionsDir.exists()) return;
      await for (final collection in collectionsDir.list()) {
        if (collection is! Directory) continue;
        await for (final shard in collection.list()) {
          if (shard is! Directory) continue;
          final walLock = File(p.join(shard.path, 'wal', '.wal'));
          if (await walLock.exists()) {
            await walLock.delete();
            AppLogger.instance.log('[Qdrant] 清理残留 WAL 锁: ${walLock.path}');
          }
        }
      }
    } catch (e) {
      AppLogger.instance.log('[Qdrant] 清理 WAL 锁时出错 (继续): $e');
    }
  }

  /// 解析 qdrant 可执行文件路径，按优先级尝试。
  /// 返回可用路径；找不到时返回空字符串。
  Future<String> _resolveExecutable(String remindAiDir) async {
    final exeName = Platform.isWindows ? 'qdrant.exe' : 'qdrant';

    // 0. 用户手动指定的路径 (优先级最高)
    if (_manualPath.isNotEmpty && await File(_manualPath).exists()) {
      return _manualPath;
    }

    // 1. 系统 PATH 中的 qdrant (用户自行安装)
    final systemPath = await _findInSystemPath(exeName);
    if (systemPath != null) return systemPath;

    // 2. assets/bin 中随包分发的 qdrant — 直接执行，无需复制
    for (final candidate in _bundledCandidates(exeName)) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    // 3. 兜底: 已复制到 .RemindAI/bin 的副本
    final localCopy = p.join(remindAiDir, 'bin', exeName);
    if (await File(localCopy).exists()) {
      return localCopy;
    }

    // 都没有 → 尝试复制一份到 .RemindAI/bin (仅当 bundled 源存在)
    for (final candidate in _bundledCandidates(exeName)) {
      final source = File(candidate);
      if (await source.exists()) {
        await Directory(p.dirname(localCopy)).create(recursive: true);
        await source.copy(localCopy);
        return localCopy;
      }
    }

    return ''; // 完全找不到
  }

  /// 检测当前会使用的 qdrant 路径及来源 (供设置 UI 展示，不启动进程)。
  /// [manualPath] 为用户手动指定路径 (可空)。
  /// 返回 (路径, 来源描述)；路径为空表示未找到。
  Future<({String path, String source})> detectExecutable(
    String manualPath,
  ) async {
    final exeName = Platform.isWindows ? 'qdrant.exe' : 'qdrant';
    final manual = manualPath.trim();

    if (manual.isNotEmpty) {
      if (await File(manual).exists()) {
        return (path: manual, source: '手动指定');
      }
      return (path: '', source: '手动指定路径无效 (文件不存在)');
    }

    final systemPath = await _findInSystemPath(exeName);
    if (systemPath != null) {
      return (path: systemPath, source: '系统 PATH');
    }

    for (final candidate in _bundledCandidates(exeName)) {
      if (await File(candidate).exists()) {
        return (path: candidate, source: '应用内置 (assets)');
      }
    }

    final root = await _rootDir();
    final localCopy = p.join(root, 'bin', exeName);
    if (await File(localCopy).exists()) {
      return (path: localCopy, source: '本地副本');
    }

    return (path: '', source: '未找到');
  }

  /// 随包分发的 qdrant 候选路径 (开发模式 + release 解压后)
  List<String> _bundledCandidates(String exeName) => [
    // 开发模式: 项目目录下的 assets/bin
    p.normalize(p.join(Directory.current.path, 'assets', 'bin', exeName)),
    // release: 安装目录下解压的 flutter_assets
    p.normalize(
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'flutter_assets',
        'assets',
        'bin',
        exeName,
      ),
    ),
  ];

  /// 在系统 PATH 中查找可执行文件，返回绝对路径或 null。
  Future<String?> _findInSystemPath(String exeName) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        Platform.isWindows ? exeName : 'qdrant',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) {
          // where 可能返回多行，取第一行
          final first = out.split(RegExp(r'\r?\n')).first.trim();
          if (first.isNotEmpty && await File(first).exists()) {
            return first;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 存储根目录: 从 AppSettings 全局根目录获取
  Future<String> _rootDir() async {
    return await AppSettings.getRootDir();
  }

  /// 启动 Qdrant (幂等: 已运行则跳过)
  Future<void> start() async {
    if (_isRunning) return;
    _shuttingDown = false;
    _restartCount = 0;

    await _init();

    // 端口已被占用且能响应 (外部/遗留进程) → 直接复用，不再 spawn
    if (await _checkHealth()) {
      _isRunning = true;
      _startHealthCheck();
      return;
    }

    // 未找到可执行文件 → 给出可读的提示
    if (_executablePath.isEmpty) {
      throw Exception(
        '未找到 Qdrant 可执行文件。请将 qdrant 加入系统 PATH，'
        '或确认应用 assets/bin 目录下存在 qdrant 可执行文件。',
      );
    }

    await _spawn();
  }

  /// spawn 进程
  Future<void> _spawn() async {
    AppLogger.instance.log('[Qdrant] 启动: $_executablePath');
    AppLogger.instance.log('[Qdrant] 存储路径: $_storagePath');
    AppLogger.instance.log('[Qdrant] 端口: $defaultPort');

    _process = await Process.start(
      _executablePath,
      [],
      environment: {
        'QDRANT__SERVICE__HTTP_PORT': '$defaultPort',
        'QDRANT__STORAGE__STORAGE_PATH': _storagePath,
      },
    );

    // 捕获 stderr 便于诊断启动失败
    _process!.stderr.transform(systemEncoding.decoder).listen((data) {
      AppLogger.instance.log('[Qdrant stderr] $data');
    });
    _process!.stdout.transform(systemEncoding.decoder).listen((data) {
      // 仅在启动阶段输出前几行方便诊断
      if (!_isRunning) {
        AppLogger.instance.log('[Qdrant stdout] $data');
      }
    });

    // 监听进程退出
    _process!.exitCode.then((code) {
      AppLogger.instance.log('[Qdrant] 进程退出, code=$code');
      _isRunning = false;
      if (!_shuttingDown && _restartCount < _maxRestarts) {
        _restartCount++;
        Future.delayed(const Duration(seconds: 2), _spawn);
      }
    });

    // 等待 Qdrant 就绪
    final ready = await _waitForHealthy();
    if (ready) {
      _isRunning = true;
      _startHealthCheck();
    } else {
      AppLogger.instance.log('[Qdrant] 启动超时! 进程是否仍在运行: ${_process != null}');
      throw Exception('Qdrant 启动超时 (${_startupTimeout.inSeconds}s)');
    }
  }

  /// 等待健康检查通过
  Future<bool> _waitForHealthy() async {
    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _checkHealth()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// 健康检查
  Future<bool> _checkHealth() async {
    try {
      final resp = await _dio.get('$baseUrl/healthz');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 启动定期健康检查
  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_healthInterval, (_) async {
      if (_shuttingDown) return;
      final healthy = await _checkHealth();
      if (!healthy && !_shuttingDown) {
        _isRunning = false;
        // 进程可能已崩溃，exitCode future 会触发自动重启
      }
    });
  }

  /// 优雅关闭
  Future<void> shutdown() async {
    _shuttingDown = true;
    _healthTimer?.cancel();
    _healthTimer = null;

    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      // Windows 上 SIGTERM 可能不生效，等待后强制杀
      await _process!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _process = null;
      _isRunning = false;
    }
  }

  /// 释放资源
  void dispose() {
    shutdown();
    _instance = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 一个后台任务：长驻进程 + 落盘日志。
///
/// 为什么要有它：`adb logcat`、`flutter run`、`npm run dev`、本地服务这类命令
/// 永远不会自己退出，`toolshell_exec` 只能等超时然后被杀掉，等于拿不到任何
/// 中途输出。后台任务把 stdout/stderr 直接写进文件，模型用
/// `toolshell_job_output` 按需读尾部，就能"一边跑一边看"。
class BackgroundJob {
  BackgroundJob({
    required this.id,
    required this.command,
    required this.pid,
    required this.logPath,
    required this.startedAt,
  });

  final String id;
  final String command;
  final int pid;
  final String logPath;
  final DateTime startedAt;

  Process? process;

  /// 进程退出码；null 表示还在跑。
  int? exitCode;

  /// 是否被主动终止。
  bool killed = false;

  /// 日志是否因为超过上限而被截断。
  bool logTruncated = false;

  bool get running => exitCode == null && !killed;

  Map<String, dynamic> toJson() => {
    'job_id': id,
    'command': command,
    'pid': pid,
    'job_status': running ? 'running' : (killed ? 'killed' : 'exited'),
    if (exitCode != null) 'exit_code': exitCode,
    'log_file': logPath,
    'started_at': startedAt.toIso8601String(),
    'log_truncated': logTruncated,
  };
}

/// 后台任务注册表（进程级单例）。
///
/// 单例是刻意的：`Executor` 每个会话/每轮都可能重建，而任务的生命周期要比
/// 一次 LLM 调用长得多。任务随应用退出一起消失。
class BackgroundJobManager {
  BackgroundJobManager._();

  static final BackgroundJobManager instance = BackgroundJobManager._();

  /// 同时最多保留的任务数（防止模型无限起进程）。
  static const int maxJobs = 8;

  /// 单个任务日志文件上限（8MB）。超了只停止写入，进程继续跑。
  static const int maxLogBytes = 8 * 1024 * 1024;

  final Map<String, BackgroundJob> _jobs = <String, BackgroundJob>{};
  int _seq = 0;

  int get count => _jobs.length;

  /// 启动一个后台进程，stdout/stderr 全部落盘到 [logDir]。
  ///
  /// [logDir] 一般传 `<项目根>/.toolshell/jobs`，方便用户自己去翻日志。
  Future<BackgroundJob> start({
    required String executable,
    required List<String> arguments,
    required String command,
    required String cwd,
    required String logDir,
    Map<String, String>? environment,
  }) async {
    if (_jobs.length >= maxJobs) {
      throw StateError(
        '后台任务已达上限 $maxJobs 个，请先 toolshell_job_kill 掉不用的任务',
      );
    }

    await Directory(logDir).create(recursive: true);

    final id = 'job-${++_seq}';
    final logPath = p.join(logDir, '$id.log');

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: cwd,
      environment: environment,
    );

    final job = BackgroundJob(
      id: id,
      command: command,
      pid: process.pid,
      logPath: logPath,
      startedAt: DateTime.now(),
    )..process = process;

    // 日志落盘：超过上限就停止写入（但继续 drain，避免管道堵死子进程）。
    final sink = File(logPath).openWrite();
    final writer = _CappedLogWriter(sink, maxLogBytes, onTruncated: () {
      job.logTruncated = true;
    });
    process.stdout.listen(writer.add);
    process.stderr.listen(writer.add);

    unawaited(
      process.exitCode.then((code) async {
        job.exitCode = code;
        await writer.close();
      }),
    );

    _jobs[id] = job;
    return job;
  }

  /// 读取任务状态 + 日志尾部。
  ///
  /// [tailBytes] 控制返回多少字节的尾部输出（默认 16KB，和 exec 的头部保留
  /// 量级相当，足够看清 logcat 最后几百行）。
  Map<String, dynamic> output(String jobId, {int tailBytes = 16000}) {
    final job = _jobs[jobId];
    if (job == null) {
      throw StateError('未知的后台任务: $jobId');
    }

    final file = File(job.logPath);
    var text = '';
    var total = 0;
    var truncated = false;
    if (file.existsSync()) {
      total = file.lengthSync();
      final start = total > tailBytes ? total - tailBytes : 0;
      truncated = start > 0;
      final raf = file.openSync();
      try {
        raf.setPositionSync(start);
        text = _decode(raf.readSync(total - start));
      } finally {
        raf.closeSync();
      }
    }

    return {
      ...job.toJson(),
      'output': text,
      'output_bytes': total,
      'output_truncated': truncated,
    };
  }

  /// 终止任务（整棵进程树）。
  Future<bool> kill(String jobId) async {
    final job = _jobs[jobId];
    if (job == null) throw StateError('未知的后台任务: $jobId');
    if (!job.running) return false;

    job.killed = true;
    await _killProcessTree(job.pid);
    try {
      job.exitCode ??= await job.process?.exitCode.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      job.exitCode ??= -1;
    }
    return true;
  }

  List<Map<String, dynamic>> list() {
    final jobs = _jobs.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return jobs.map((job) => job.toJson()).toList();
  }

  /// 退出前清理：杀掉所有还在跑的任务。
  Future<void> disposeAll() async {
    for (final job in _jobs.values) {
      if (job.running) {
        await _killProcessTree(job.pid);
      }
    }
    _jobs.clear();
    // 给日志 sink 一点时间落盘/关闭（Windows 上文件句柄没释放会挡住删除）。
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _killProcessTree(int pid) async {
    try {
      if (Platform.isWindows) {
        await Process.run(
          'taskkill',
          ['/PID', '$pid', '/T', '/F'],
        ).timeout(const Duration(seconds: 8));
      } else {
        Process.killPid(pid, ProcessSignal.sigkill);
        try {
          await Process.run(
            'pkill',
            ['-9', '-P', '$pid'],
          ).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    } catch (_) {
      // 进程可能已经自己退了
    }
  }

  static String _decode(List<int> bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 有上限的日志写入器：超过上限后停止写，但继续接收数据（避免管道反压）。
class _CappedLogWriter {
  _CappedLogWriter(this._sink, this._maxBytes, {required this.onTruncated});

  final IOSink _sink;
  final int _maxBytes;
  final void Function() onTruncated;

  int _written = 0;
  bool _closed = false;

  void add(List<int> data) {
    if (_closed || data.isEmpty) return;
    if (_written >= _maxBytes) {
      if (!_notified) {
        _notified = true;
        onTruncated();
        _sink.writeln('\n…[日志超过 ${(_maxBytes / 1024 / 1024).toStringAsFixed(0)}MB，后续输出已丢弃]…');
      }
      return;
    }
    final room = _maxBytes - _written;
    if (data.length <= room) {
      _sink.add(data);
      _written += data.length;
    } else {
      _sink.add(data.sublist(0, room));
      _written = _maxBytes;
      _notified = true;
      onTruncated();
      _sink.writeln('\n…[日志超过 ${(_maxBytes / 1024 / 1024).toStringAsFixed(0)}MB，后续输出已丢弃]…');
    }
  }

  bool _notified = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {}
  }
}

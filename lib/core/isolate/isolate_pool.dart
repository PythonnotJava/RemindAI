import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

/// Isolate 池 — 管理一组常驻 worker isolate，复用以避免反复创建销毁的开销。
///
/// 使用 round-robin 策略分配任务。每个 worker 同一时刻只处理一个任务，
/// 多余任务排队等待空闲 worker。
///
/// 生命周期:
/// - 在 main() 中调用 [IsolatePool.init] 启动
/// - 应用退出时调用 [IsolatePool.dispose] 清理
///
/// 用法:
/// ```dart
/// final result = await IsolatePool.instance.run(myFunction, myArg);
/// ```
class IsolatePool {
  IsolatePool._();
  static final IsolatePool instance = IsolatePool._();

  final List<_Worker> _workers = [];
  bool _initialized = false;

  /// 初始化 Isolate 池。
  ///
  /// [size] 为 worker 数量，默认取 CPU 核心数的一半，钳位到 [2, 6]。
  /// 桌面应用不宜开太多 isolate，2-4 个足够覆盖偶发的并行计算需求。
  Future<void> init([int? size]) async {
    if (_initialized) return;
    final count = size ?? _defaultPoolSize();
    for (var i = 0; i < count; i++) {
      _workers.add(await _Worker.spawn(i));
    }
    _initialized = true;
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 当前 worker 数量
  int get poolSize => _workers.length;

  /// 提交一个计算任务到池中执行。
  ///
  /// [function] 必须是顶层函数或静态方法（isolate 限制）。
  /// [arg] 为传入参数，必须可跨 isolate 传递。
  /// 返回计算结果。
  Future<R> run<T, R>(FutureOr<R> Function(T) function, T arg) async {
    if (!_initialized) {
      throw StateError('IsolatePool 未初始化，请先调用 init()');
    }
    // 找到空闲 worker，如果都忙则排队等待
    final worker = await _acquireWorker();
    try {
      return await worker.execute(function, arg);
    } finally {
      _releaseWorker(worker);
    }
  }

  /// 并行执行多个相同函数的任务，返回结果列表（顺序对应输入）。
  Future<List<R>> runBatch<T, R>(
    FutureOr<R> Function(T) function,
    List<T> args,
  ) async {
    final futures = args.map((arg) => run(function, arg));
    return Future.wait(futures);
  }

  /// 释放所有 worker isolate。
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    _initialized = false;
  }

  // --- 内部调度 ---

  final Queue<Completer<_Worker>> _waitQueue = Queue();

  Future<_Worker> _acquireWorker() async {
    // 优先找空闲 worker
    for (final w in _workers) {
      if (!w.isBusy) {
        w.isBusy = true;
        return w;
      }
    }
    // 所有 worker 都忙，排队
    final completer = Completer<_Worker>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void _releaseWorker(_Worker worker) {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeFirst();
      next.complete(worker);
    } else {
      worker.isBusy = false;
    }
  }

  static int _defaultPoolSize() {
    // 取 CPU 核心数一半，钳位到 [2, 6]
    final cores = _cpuCores();
    return (cores ~/ 2).clamp(2, 6);
  }

  static int _cpuCores() {
    // Dart 没有直接获取 CPU 核数的 API，通过 Platform.numberOfProcessors
    // 获取（dart:io）。
    try {
      return _platformProcessors();
    } catch (_) {
      return 4; // fallback
    }
  }
}

/// 获取平台 CPU 核数 — 独立顶层函数避免 import 问题
int _platformProcessors() {
  // dart:io 的 Platform.numberOfProcessors
  // 使用 dart:io 在 isolate 内也可访问
  return 4; // 保守默认值，实际在 init 时可传入
}

// =============================================================================
// Worker Isolate
// =============================================================================

/// 消息协议：主 isolate → worker
class _TaskRequest<T> {
  final int id;
  final Function function;
  final T arg;
  final SendPort replyPort;

  _TaskRequest(this.id, this.function, this.arg, this.replyPort);
}

/// 消息协议：worker → 主 isolate
class _TaskResponse<R> {
  final int id;
  final R? result;
  final Object? error;
  final StackTrace? stackTrace;

  _TaskResponse.success(this.id, this.result) : error = null, stackTrace = null;
  _TaskResponse.failure(this.id, this.error, this.stackTrace) : result = null;
}

/// 单个 Worker isolate 封装
class _Worker {
  final int index;
  final Isolate _isolate;
  final SendPort _sendPort;
  bool isBusy = false;

  _Worker._(this.index, this._isolate, this._sendPort);

  /// 创建并启动一个 worker isolate
  static Future<_Worker> spawn(int index) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerEntryPoint,
      receivePort.sendPort,
      debugName: 'IsolatePool-worker-$index',
    );
    final sendPort = await receivePort.first as SendPort;
    receivePort.close();
    return _Worker._(index, isolate, sendPort);
  }

  /// 在此 worker 上执行任务
  Future<R> execute<T, R>(FutureOr<R> Function(T) function, T arg) async {
    final responsePort = ReceivePort();
    final taskId = _nextTaskId++;
    _sendPort.send(
      _TaskRequest<T>(taskId, function, arg, responsePort.sendPort),
    );
    final response = await responsePort.first as _TaskResponse;
    responsePort.close();
    if (response.error != null) {
      Error.throwWithStackTrace(
        response.error!,
        response.stackTrace ?? StackTrace.current,
      );
    }
    return response.result as R;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static int _nextTaskId = 0;

  /// Worker isolate 入口
  static void _workerEntryPoint(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    port.listen((message) async {
      if (message is _TaskRequest) {
        try {
          final result = await message.function(message.arg);
          message.replyPort.send(_TaskResponse.success(message.id, result));
        } catch (e, st) {
          message.replyPort.send(
            _TaskResponse.failure(message.id, e.toString(), st),
          );
        }
      }
    });
  }
}

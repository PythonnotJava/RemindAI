import 'dart:async';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart';

/// 数据库操作消息
class _DbMessage {
  final String sql;
  final List<Object?>? params;
  final SendPort replyPort;
  const _DbMessage(this.sql, this.params, this.replyPort);
}

/// 异步数据库执行器 - 在独立 Isolate 中执行 SQL，不阻塞主线程
class AsyncDbExecutor {
  Isolate? _isolate;
  SendPort? _sendPort;
  final _readyCompleter = Completer<void>();

  final String dbPath;

  AsyncDbExecutor(this.dbPath);

  /// 启动后台 Isolate
  Future<void> start() async {
    if (_isolate != null) return;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntry, [
      receivePort.sendPort,
      dbPath,
    ]);

    // 等待 Isolate 初始化完成
    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
    });

    _sendPort = await completer.future;
    _readyCompleter.complete();
  }

  /// 在后台 Isolate 执行 SQL（不阻塞主线程）
  Future<void> execute(String sql, [List<Object?>? params]) async {
    await _readyCompleter.future;

    final receivePort = ReceivePort();
    _sendPort!.send(_DbMessage(sql, params, receivePort.sendPort));

    // 等待执行完成
    await receivePort.first;
  }

  /// 批量执行（事务）
  Future<void> executeBatch(List<String> sqlList) async {
    await _readyCompleter.future;

    final receivePort = ReceivePort();
    _sendPort!.send(
      _DbMessage(
        'BEGIN;${sqlList.join(';')};COMMIT;',
        null,
        receivePort.sendPort,
      ),
    );

    await receivePort.first;
  }

  /// 停止后台 Isolate
  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  /// Isolate 入口函数
  static void _isolateEntry(List<dynamic> args) {
    final SendPort mainSendPort = args[0];
    final String dbPath = args[1];

    // 打开数据库
    final db = sqlite3.open(dbPath);

    // 创建接收端口
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    // 监听并执行 SQL
    receivePort.listen((message) {
      if (message is _DbMessage) {
        try {
          if (message.params != null && message.params!.isNotEmpty) {
            db.execute(message.sql, message.params!);
          } else {
            db.execute(message.sql);
          }
          message.replyPort.send('ok');
        } catch (e) {
          message.replyPort.send('error: $e');
        }
      }
    });
  }
}

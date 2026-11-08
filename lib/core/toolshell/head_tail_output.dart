import 'dart:convert';

/// 只保留子进程输出"头 + 尾"的收集器。
///
/// 为什么不是"只留最后 N 字符"：`flutter build`、`gradle`、`aapt2`、
/// `adb install` 这类命令的失败根因几乎都在输出**开头**（第一处 error），
/// 从尾部截断恰好把它丢掉，模型只能看到一串无用的收尾日志，于是反复重试。
///
/// 策略：头 [headLimit]、尾 [tailLimit] 各自封顶，中间用一行标记省略；
/// 内存占用与命令输出总量无关。
class HeadTailCollector {
  HeadTailCollector({this.headLimit = 16000, this.tailLimit = 24000});

  /// 头部保留字节数（约 16KB，足够装下构建失败的头几条 error）。
  final int headLimit;

  /// 尾部保留字节数（约 24KB，装最后几条进度/退出信息）。
  final int tailLimit;

  final List<int> _head = <int>[];
  final List<int> _tail = <int>[];

  /// 收到的总字节数（含被省略部分）。
  int total = 0;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    total += chunk.length;

    var rest = chunk;
    final headRoom = headLimit - _head.length;
    if (headRoom > 0) {
      final take = rest.length <= headRoom ? rest.length : headRoom;
      _head.addAll(rest.take(take));
      if (take == rest.length) return;
      rest = rest.sublist(take);
    }

    _tail.addAll(rest);
    final overflow = _tail.length - tailLimit;
    if (overflow > 0) _tail.removeRange(0, overflow);
  }

  /// 是否有内容被省略。
  bool get truncated => total > _head.length + _tail.length;

  /// 被省略的字节数。
  int get omittedBytes => total - _head.length - _tail.length;

  /// 拼接后的文本。[decode] 由调用方提供（复用 Executor 的 UTF-8 → GBK 回退解码）。
  String text(String Function(dynamic raw) decode) {
    final head = decode(_head);
    final tail = decode(_tail);
    if (omittedBytes <= 0) return '$head$tail';
    return '$head\n…[中间省略 $omittedBytes 字节]…\n$tail';
  }

  /// 供测试/诊断使用：按 UTF-8（容错）解码。
  String get plainText =>
      text((raw) => utf8.decode(raw as List<int>, allowMalformed: true));
}

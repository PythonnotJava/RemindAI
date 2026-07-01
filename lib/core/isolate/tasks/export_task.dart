// 导出渲染任务 — 在 Isolate 中构建 Markdown 内容。
//
// 适用场景:
// - 长对话 (>50条消息) 的 Markdown 构建
// - PDF/Word/HTML 导出前的内容准备
//
// 注意: Pandoc 调用本身是子进程，不需要 Isolate。
// 但 Markdown 的字符串构建（遍历所有消息、拼接附件）在主线程上也会卡 UI。

/// 导出消息的简化表示（可跨 Isolate 传递）
class ExportMessage {
  final String role; // 'user' | 'assistant' | 'system' | 'tool'
  final String? content;
  final List<ExportAttachment> attachments;
  final List<Map<String, dynamic>>? toolCalls;
  final DateTime timestamp;

  ExportMessage({
    required this.role,
    this.content,
    this.attachments = const [],
    this.toolCalls,
    required this.timestamp,
  });
}

/// 附件的简化表示
class ExportAttachment {
  final String name;
  final String path;
  final bool isImage;

  ExportAttachment({
    required this.name,
    required this.path,
    required this.isImage,
  });
}

/// 导出任务参数
class ExportBuildParam {
  final List<ExportMessage> messages;
  final String title;
  final String locale; // 'zh' | 'en'

  ExportBuildParam({
    required this.messages,
    required this.title,
    this.locale = 'zh',
  });
}

/// 顶层函数: 构建对话 Markdown（可传入 Isolate）
String exportBuildMarkdownTask(ExportBuildParam param) {
  final buffer = StringBuffer();
  final now = _formatDateTime(DateTime.now());

  final exportTimeLabel = param.locale == 'zh' ? '导出时间' : 'Exported at';
  final conversationLabel = param.locale == 'zh' ? '对话' : 'Conversation';
  final userLabel = param.locale == 'zh' ? '\u{1F9D1} 用户' : '\u{1F9D1} User';
  final assistantLabel = param.locale == 'zh'
      ? '\u{1F916} 助手'
      : '\u{1F916} Assistant';

  buffer.writeln('# $conversationLabel: ${param.title}');
  buffer.writeln('> $exportTimeLabel: $now');
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();

  for (final msg in param.messages) {
    if (msg.role == 'system' || msg.role == 'tool') continue;
    // Skip tool-call-only assistant messages
    if (msg.role == 'assistant' &&
        msg.toolCalls != null &&
        msg.toolCalls!.isNotEmpty &&
        (msg.content == null || msg.content!.startsWith('[工具调用]'))) {
      continue;
    }

    final roleLabel = msg.role == 'user'
        ? '## $userLabel'
        : '## $assistantLabel';
    buffer.writeln(roleLabel);
    buffer.writeln(msg.content ?? '');

    if (msg.attachments.isNotEmpty) {
      buffer.writeln();
      for (final att in msg.attachments) {
        if (att.isImage) {
          buffer.writeln('![${att.name}](${att.path})');
        } else {
          buffer.writeln('\u{1F4CE} `${att.name}` _(${att.path})_');
        }
      }
    }

    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
  }

  return buffer.toString();
}

/// 顶层函数: 构建单条消息 Markdown
String exportBuildSingleMessageTask(ExportMessage msg) {
  final buffer = StringBuffer();
  final now = _formatDateTime(DateTime.now());

  buffer.writeln('> 导出时间: $now');
  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();

  final roleLabel = msg.role == 'user' ? '## \u{1F9D1} 用户' : '## \u{1F916} 助手';
  buffer.writeln(roleLabel);
  buffer.writeln(msg.content ?? '');

  if (msg.attachments.isNotEmpty) {
    buffer.writeln();
    for (final att in msg.attachments) {
      if (att.isImage) {
        buffer.writeln('![${att.name}](${att.path})');
      } else {
        buffer.writeln('\u{1F4CE} `${att.name}` _(${att.path})_');
      }
    }
  }

  buffer.writeln();
  buffer.writeln('---');
  buffer.writeln();

  return buffer.toString();
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

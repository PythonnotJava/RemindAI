import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n_ext.dart';
import '../llm/models.dart';
import '../logger/app_logger.dart';
import '../models/file_attachment.dart';

/// 导出格式
enum ExportFormat { markdown, pdf, word, html }

extension ExportFormatExtension on ExportFormat {
  String get extension {
    switch (this) {
      case ExportFormat.markdown:
        return 'md';
      case ExportFormat.pdf:
        return 'pdf';
      case ExportFormat.word:
        return 'docx';
      case ExportFormat.html:
        return 'html';
    }
  }

  String get label {
    switch (this) {
      case ExportFormat.markdown:
        return 'Markdown (.md)';
      case ExportFormat.pdf:
        return 'PDF (.pdf)';
      case ExportFormat.word:
        return 'Word (.docx)';
      case ExportFormat.html:
        return 'HTML (.html)';
    }
  }
}

/// 对话导出工具类
class ConversationExporter {
  /// 格式化日期时间为 yyyy-MM-dd HH:mm
  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  /// 格式化日期时间为 yyyyMMdd_HHmmss（用于文件名）
  static String _formatDateTimeCompact(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  /// 导出整个对话
  static Future<String?> exportConversation({
    required List<ChatMessage> messages,
    required String title,
    required ExportFormat format,
    required String pandocPath,
  }) async {
    final markdown = _buildConversationMarkdown(messages, title);
    return _exportWithFormat(
      markdown: markdown,
      fileName: title,
      format: format,
      pandocPath: pandocPath,
    );
  }

  /// 导出单条消息
  static Future<String?> exportMessage({
    required ChatMessage message,
    required ExportFormat format,
    required String pandocPath,
  }) async {
    final markdown = _buildSingleMessageMarkdown(message);
    final fileName = '消息_${_formatDateTimeCompact(message.timestamp)}';
    return _exportWithFormat(
      markdown: markdown,
      fileName: fileName,
      format: format,
      pandocPath: pandocPath,
    );
  }

  /// 构建整个对话的 Markdown 内容
  static String _buildConversationMarkdown(
    List<ChatMessage> messages,
    String title,
  ) {
    final buffer = StringBuffer();
    final now = _formatDateTime(DateTime.now());

    buffer.writeln('# 对话: $title');
    buffer.writeln('> 导出时间: $now');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in messages) {
      if (msg.role == ChatRole.system || msg.role == ChatRole.tool) continue;
      // Skip tool-call-only messages
      if (msg.role == ChatRole.assistant &&
          msg.toolCalls != null &&
          msg.toolCalls!.isNotEmpty &&
          (msg.content == null || msg.content!.startsWith('[工具调用]'))) {
        continue;
      }
      _appendMessage(buffer, msg);
    }

    return buffer.toString();
  }

  /// 构建单条消息的 Markdown 内容
  static String _buildSingleMessageMarkdown(ChatMessage message) {
    final buffer = StringBuffer();
    final now = _formatDateTime(DateTime.now());

    buffer.writeln('> 导出时间: $now');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    _appendMessage(buffer, message);

    return buffer.toString();
  }

  /// 向 buffer 中追加一条消息
  static void _appendMessage(StringBuffer buffer, ChatMessage message) {
    final roleLabel = message.role == ChatRole.user
        ? '## \u{1F9D1} 用户'
        : '## \u{1F916} 助手';
    buffer.writeln(roleLabel);
    buffer.writeln(message.content ?? '');

    // 处理附件
    if (message.attachments.isNotEmpty) {
      buffer.writeln();
      for (final att in message.attachments) {
        if (att.type == FileAttachmentType.image) {
          // 图片嵌入 (Pandoc 会渲染到 PDF/Word)
          buffer.writeln('![${att.name}](${att.path})');
        } else {
          // 其他文件显示为路径
          buffer.writeln('📎 `${att.name}` _(${att.path})_');
        }
      }
    }

    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
  }

  /// 执行导出：根据格式选择直接写 md 或通过 pandoc 转换
  ///
  /// 返回: 成功时为保存路径, 用户取消返回 null。
  /// 当 Pandoc 转换失败时抛出 [ExportFallbackException]，
  /// 由调用者决定是否降级为 Markdown 导出。
  static Future<String?> _exportWithFormat({
    required String markdown,
    required String fileName,
    required ExportFormat format,
    required String pandocPath,
  }) async {
    // 清理文件名中的非法字符
    final safeFileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    if (format == ExportFormat.markdown) {
      return _saveMarkdownFile(markdown, safeFileName);
    }

    // 需要 pandoc 转换
    final tempDir = await getTemporaryDirectory();
    final inputFile = File(p.join(tempDir.path, '$safeFileName.md'));
    final outputFile = File(
      p.join(tempDir.path, '$safeFileName.${format.extension}'),
    );

    try {
      // 写入临时 md 文件
      await inputFile.writeAsString(markdown, flush: true);

      // 调用 pandoc 转换
      // PDF 导出需要 XeLaTeX 引擎以支持中文 Unicode
      final args = <String>[inputFile.path, '-o', outputFile.path];
      if (format == ExportFormat.pdf) {
        args.addAll([
          '--pdf-engine=xelatex',
          '-V',
          'CJKmainfont=Microsoft YaHei',
          '-V',
          'geometry:margin=1in',
        ]);
      }
      final result = await Process.run(pandocPath, args);

      if (result.exitCode != 0 || !await outputFile.exists()) {
        final stderr = (result.stderr as String?)?.trim() ?? '';
        final reason = stderr.isNotEmpty
            ? stderr
            : 'Pandoc 退出码 ${result.exitCode}';
        AppLogger.instance.log('[Export] ${format.label} 导出失败: $reason');
        throw ExportFallbackException(
          reason: reason,
          markdown: markdown,
          fileName: safeFileName,
        );
      }

      // 转换成功，让用户选择保存位置
      final savedPath = await _pickSaveLocation(safeFileName, format.extension);
      if (savedPath == null) return null;

      await outputFile.copy(savedPath);
      return savedPath;
    } on ExportFallbackException {
      rethrow;
    } catch (e) {
      // Pandoc 不可用
      String reason;
      if (pandocPath.isEmpty) {
        reason = '未配置 Pandoc 路径，请在「设置 → 工具路径」中配置';
      } else {
        reason = '无法运行 Pandoc: $e';
      }
      AppLogger.instance.log('[Export] ${format.extension} 导出失败: $reason');
      throw ExportFallbackException(
        reason: reason,
        markdown: markdown,
        fileName: safeFileName,
      );
    } finally {
      // 清理临时文件
      try {
        if (await inputFile.exists()) await inputFile.delete();
        if (await outputFile.exists()) await outputFile.delete();
      } catch (_) {}
    }
  }

  /// 降级导出为 Markdown（用户确认后调用）
  static Future<String?> exportAsMarkdownFallback({
    required String markdown,
    required String fileName,
  }) async {
    return _saveMarkdownFile(markdown, fileName);
  }

  /// 保存为 Markdown 文件
  static Future<String?> _saveMarkdownFile(
    String markdown,
    String fileName,
  ) async {
    final savedPath = await _pickSaveLocation(fileName, 'md');
    if (savedPath == null) return null;

    await File(savedPath).writeAsString(markdown, flush: true);
    return savedPath;
  }

  /// 弹出文件保存对话框
  static Future<String?> _pickSaveLocation(String fileName, String ext) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存导出文件',
      fileName: '$fileName.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    return result;
  }

  /// 显示格式选择菜单并执行导出
  static Future<void> showExportMenu({
    required BuildContext context,
    required List<ChatMessage> messages,
    required String title,
    required String pandocPath,
  }) async {
    final format = await _showFormatDialog(context);
    if (format == null) return;

    // 显示加载指示器
    // ignore: use_build_context_synchronously
    _showLoadingDialog(context, format);

    final markdown = _buildConversationMarkdown(messages, title);

    try {
      final result = await _exportWithFormat(
        markdown: markdown,
        fileName: title,
        format: format,
        pandocPath: pandocPath,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载
      _showSuccessSnackBar(context, result);
    } on ExportFallbackException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载
      final confirmed = await _showFallbackDialog(context, format, e.reason);
      if (confirmed && context.mounted) {
        final result = await exportAsMarkdownFallback(
          markdown: e.markdown,
          fileName: e.fileName,
        );
        if (context.mounted) _showSuccessSnackBar(context, result);
      }
    }
  }

  /// 显示单条消息导出菜单
  static Future<void> showMessageExportMenu({
    required BuildContext context,
    required ChatMessage message,
    required String pandocPath,
  }) async {
    final format = await _showFormatDialog(context);
    if (format == null) return;

    // ignore: use_build_context_synchronously
    _showLoadingDialog(context, format);

    try {
      final result = await exportMessage(
        message: message,
        format: format,
        pandocPath: pandocPath,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载
      _showSuccessSnackBar(context, result);
    } on ExportFallbackException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载
      final confirmed = await _showFallbackDialog(context, format, e.reason);
      if (confirmed && context.mounted) {
        final result = await exportAsMarkdownFallback(
          markdown: e.markdown,
          fileName: e.fileName,
        );
        if (context.mounted) _showSuccessSnackBar(context, result);
      }
    }
  }

  /// 显示导出加载对话框 (不可取消，导出完毕后由代码 pop)
  static void _showLoadingDialog(BuildContext context, ExportFormat format) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Text(context.s.exportExporting(format.label)),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示格式选择对话框
  static Future<ExportFormat?> _showFormatDialog(BuildContext context) async {
    return showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  context.s.exportFormatTitle,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              ...ExportFormat.values.map(
                (format) => ListTile(
                  leading: Icon(_formatIcon(format)),
                  title: Text(format.label),
                  onTap: () => Navigator.pop(context, format),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 获取格式对应图标
  static IconData _formatIcon(ExportFormat format) {
    switch (format) {
      case ExportFormat.markdown:
        return Icons.description_outlined;
      case ExportFormat.pdf:
        return Icons.picture_as_pdf_outlined;
      case ExportFormat.word:
        return Icons.article_outlined;
      case ExportFormat.html:
        return Icons.code;
    }
  }

  /// 显示导出成功 SnackBar
  static void _showSuccessSnackBar(BuildContext context, String? result) {
    if (result == null) return; // 用户取消
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(context.s.exportSuccess(result))),
            ],
          ),
        ),
      );
  }

  /// 导出失败时弹出确认对话框，询问是否降级为 Markdown
  static Future<bool> _showFallbackDialog(
    BuildContext context,
    ExportFormat format,
    String reason,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 36),
        title: Text(context.s.exportFailed(format.label)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '失败原因:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                reason,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(context.s.exportFallbackMd),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.exportFallbackBtn),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 导出降级异常 — Pandoc 转换失败时抛出，携带必要信息供调用者降级处理
class ExportFallbackException implements Exception {
  final String reason;
  final String markdown;
  final String fileName;

  ExportFallbackException({
    required this.reason,
    required this.markdown,
    required this.fileName,
  });
}

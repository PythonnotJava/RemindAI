import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/models/file_attachment.dart';

/// 消息气泡内的附件展示区。
///
/// - 图片：渲染缩略图，点击可全屏预览。
/// - 其他文件：显示小图标卡片，点击预览（纯文本用内置查看器，
///   非纯文本调用系统默认程序打开）。
class MessageAttachments extends StatelessWidget {
  final List<FileAttachment> attachments;
  final bool isUser;

  const MessageAttachments({
    super.key,
    required this.attachments,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => !a.isImage).toList();

    return Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
            children: [for (final img in images) _ImageThumb(attachment: img)],
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 8),
        if (files.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
            children: [for (final f in files) _FileCard(attachment: f)],
          ),
      ],
    );
  }
}

/// 图片缩略图，点击全屏预览。
class _ImageThumb extends StatelessWidget {
  final FileAttachment attachment;
  const _ImageThumb({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final file = File(attachment.path);
    final exists = file.existsSync();

    return GestureDetector(
      onTap: exists ? () => _preview(context, file) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
          color: colorScheme.surfaceContainerLow,
          child: exists
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => _missing(colorScheme),
                )
              : _missing(colorScheme),
        ),
      ),
    );
  }

  Widget _missing(ColorScheme colorScheme) => Container(
    width: 120,
    height: 120,
    alignment: Alignment.center,
    child: Icon(Icons.broken_image_outlined, color: colorScheme.outline),
  );

  void _preview(BuildContext context, File file) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ImagePreviewDialog(file: file, name: attachment.name),
    );
  }
}

/// 全屏图片预览（可缩放、可在系统中打开）。
class _ImagePreviewDialog extends StatelessWidget {
  final File file;
  final String name;
  const _ImagePreviewDialog({required this.file, required this.name});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 图片层：可缩放拖动
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(file)),
            ),
          ),
          // 按钮层：始终浮在最上方，不被图片遮挡
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.s.attachOpenWith,
                    icon: const Icon(
                      Icons.open_in_new,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => OpenFilex.open(file.path),
                  ),
                  IconButton(
                    tooltip: context.s.commonClose,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 非图片文件卡片：小图标 + 文件名 + 大小，点击预览/打开。
class _FileCard extends StatelessWidget {
  final FileAttachment attachment;
  const _FileCard({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: attachment.iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  attachment.icon,
                  size: 18,
                  color: attachment.iconColor,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      attachment.formattedSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final file = File(attachment.path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.attachFileNotExist(attachment.path))),
      );
      return;
    }
    // 纯文本/代码 → 内置查看器；其它 → 系统默认程序打开
    if (attachment.isReadableAsText) {
      showDialog(
        context: context,
        builder: (ctx) => _TextPreviewDialog(attachment: attachment),
      );
    } else {
      OpenFilex.open(file.path);
    }
  }
}

/// 内置纯文本/代码预览对话框。
class _TextPreviewDialog extends StatelessWidget {
  final FileAttachment attachment;
  const _TextPreviewDialog({required this.attachment});

  Future<String> _read() async {
    try {
      final raw = await File(attachment.path).readAsString();
      const maxChars = 200000;
      if (raw.length > maxChars) {
        return '${raw.substring(0, maxChars)}\n\n…（文件过大，已截断）';
      }
      return raw;
    } catch (e) {
      try {
        // 回退到 latin1，避免非 UTF-8 文本崩溃
        final bytes = await File(attachment.path).readAsBytes();
        return String.fromCharCodes(bytes);
      } catch (_) {
        return '无法读取文件内容：$e';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(attachment.icon, size: 18, color: attachment.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      attachment.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: context.s.attachOpenWith,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => OpenFilex.open(attachment.path),
                  ),
                  IconButton(
                    tooltip: context.s.commonClose,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<String>(
                future: _read(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      snap.data!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

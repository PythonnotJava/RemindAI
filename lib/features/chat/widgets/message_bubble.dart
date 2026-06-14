import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/conversation_exporter.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/llm/models.dart';
import '../../../providers/settings_provider.dart';
import 'markdown_view.dart';
import 'message_attachments.dart';

/// 消息气泡组件
class MessageBubble extends ConsumerWidget {
  final ChatMessage message;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;
  final int? messageIndex;

  const MessageBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
    this.messageIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == ChatRole.user;
    final colorScheme = Theme.of(context).colorScheme;
    final hasText = (message.content ?? '').trim().isNotEmpty;
    final hasAttachments = message.attachments.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // 附件区（图片缩略图 / 文件卡片）
            if (hasAttachments) ...[
              MessageAttachments(
                attachments: message.attachments,
                isUser: isUser,
              ),
              if (hasText) const SizedBox(height: 6),
            ],
            // 消息气泡（无文本且只有附件时不渲染空气泡）
            if (hasText)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: isUser
                    ? _buildUserContent(context)
                    : _buildAssistantContent(context),
              ),
            // 操作按钮行
            if (hasText)
              _MessageActions(
                message: message,
                onDelete: onDelete,
                onRegenerate: onRegenerate,
                onEdit: onEdit,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MarkdownView(
      data: message.content ?? '',
      textColor: colorScheme.onPrimaryContainer,
    );
  }

  Widget _buildAssistantContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = message.content ?? '';
    if (content.isEmpty) return const SizedBox.shrink();

    return MarkdownView(data: content, textColor: colorScheme.onSurface);
  }
}

/// 消息操作按钮行
class _MessageActions extends ConsumerWidget {
  final ChatMessage message;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;

  const _MessageActions({
    required this.message,
    this.onDelete,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = message.content ?? '';
    final isUser = message.role == ChatRole.user;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 编辑按钮 (仅用户消息)
          if (isUser && onEdit != null) ...[
            Tooltip(
              message: context.s.msgEdit,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          // 重新生成按钮 (仅助手消息)
          if (!isUser && onRegenerate != null) ...[
            Tooltip(
              message: context.s.msgRegenerate,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onRegenerate,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Tooltip(
            message: context.s.msgCopy,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.s.msgCopied),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy_outlined,
                  size: 16,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: context.s.msgExport,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                final settings = ref.read(settingsProvider).valueOrNull;
                final pandocPath = (settings?.pandocPath.isNotEmpty ?? false)
                    ? settings!.pandocPath
                    : 'pandoc';
                ConversationExporter.showMessageExportMenu(
                  context: context,
                  message: message,
                  pandocPath: pandocPath,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.ios_share_outlined,
                  size: 16,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (onDelete != null)
            Tooltip(
              message: context.s.msgDelete,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 流式输出气泡 (正在生成中的助手消息)
class StreamingBubble extends StatelessWidget {
  final String text;

  const StreamingBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: text.isEmpty
            ? _buildTypingIndicator(context, colorScheme)
            : MarkdownView(data: text, textColor: colorScheme.onSurface),
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.s.msgThinking,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}

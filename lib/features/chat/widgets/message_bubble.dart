import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/export/conversation_exporter.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/llm/models.dart';
import '../../../providers/settings_provider.dart';
import '../chat_provider.dart';
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
    final hasThinking = (message.thinkingContent ?? '').trim().isNotEmpty;
    final hasToolCalls = message.toolCalls != null && message.toolCalls!.isNotEmpty;
    final chatFont = ref.watch(chatFontProvider);
    final chatFontSize = ref.watch(chatFontSizeProvider);

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
              if (hasText || hasThinking || hasToolCalls) const SizedBox(height: 6),
            ],
            // Thinking 区域（助手消息且有思考内容）
            if (!isUser && hasThinking) ...[
              _ThinkingSection(
                content: message.thinkingContent!,
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 6),
            ],
            // 工具调用区域（助手消息且有工具调用）
            if (!isUser && hasToolCalls) ...[
              _ToolCallsSection(
                toolCalls: message.toolCalls!,
                colorScheme: colorScheme,
                interrupted: message.interrupted,
              ),
              const SizedBox(height: 6),
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
                    ? _buildUserContent(context, chatFont, chatFontSize)
                    : _buildAssistantContent(context, chatFont, chatFontSize),
              ),
            // 操作按钮行
            if (hasText)
              _MessageActions(
                message: message,
                onDelete: onDelete,
                onRegenerate: onRegenerate,
                onEdit: onEdit,
              ),
            // 中断标记
            if (message.interrupted)
              _InterruptedTag(
                colorScheme: colorScheme,
                hasThinking: hasThinking,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserContent(
    BuildContext context,
    String chatFont,
    double chatFontSize,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return MarkdownView(
      data: message.content ?? '',
      textColor: colorScheme.onPrimaryContainer,
      fontFamily: chatFont,
      fontSize: chatFontSize,
    );
  }

  Widget _buildAssistantContent(
    BuildContext context,
    String chatFont,
    double chatFontSize,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = message.content ?? '';
    if (content.isEmpty) return const SizedBox.shrink();

    return MarkdownView(
      data: content,
      textColor: colorScheme.onSurface,
      fontFamily: chatFont,
      fontSize: chatFontSize,
    );
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

/// 用户手动中断标记 — 气泡底部的小标签
class _InterruptedTag extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool hasThinking;

  const _InterruptedTag({
    required this.colorScheme,
    this.hasThinking = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = hasThinking ? '思考过程已中断' : '回复已中断';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 14,
              color: colorScheme.error,
            ),
            const SizedBox(width: 4),
            Text(
              message,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thinking 思考过程展示组件（可折叠）
class _ThinkingSection extends StatefulWidget {
  final String content;
  final ColorScheme colorScheme;

  const _ThinkingSection({
    required this.content,
    required this.colorScheme,
  });

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerLow.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '思考过程',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: widget.colorScheme.outline,
                ),
              ],
            ),
          ),
          // 思考内容（可展开）
          if (_expanded) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: widget.colorScheme.outline.withOpacity(0.2)),
            const SizedBox(height: 8),
            Text(
              widget.content,
              style: TextStyle(
                fontSize: 12,
                color: widget.colorScheme.onSurface.withOpacity(0.7),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 工具调用区域（折叠显示历史工具调用）
class _ToolCallsSection extends StatefulWidget {
  final List<ChatToolCall> toolCalls;
  final ColorScheme colorScheme;
  final bool interrupted;

  const _ToolCallsSection({
    required this.toolCalls,
    required this.colorScheme,
    required this.interrupted,
  });

  @override
  State<_ToolCallsSection> createState() => _ToolCallsSectionState();
}

class _ToolCallsSectionState extends State<_ToolCallsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏（点击展开/折叠）
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  size: 16,
                  color: widget.interrupted
                      ? widget.colorScheme.error
                      : widget.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '工具调用 (${widget.toolCalls.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: widget.interrupted
                        ? widget.colorScheme.error
                        : widget.colorScheme.primary,
                  ),
                ),
                if (widget.interrupted) ...[
                  const SizedBox(width: 6),
                  Text(
                    '已中断',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colorScheme.error.withOpacity(0.7),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: widget.colorScheme.outline,
                ),
              ],
            ),
          ),
          // 工具调用列表（可展开）
          if (_expanded) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: widget.colorScheme.outline.withOpacity(0.2)),
            const SizedBox(height: 8),
            ...widget.toolCalls.map((tc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_right,
                    size: 16,
                    color: widget.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tc.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.colorScheme.onSurface,
                          ),
                        ),
                        if (tc.arguments.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatArguments(tc.arguments),
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.colorScheme.onSurface.withOpacity(0.6),
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  String _formatArguments(Map<String, dynamic> args) {
    if (args.isEmpty) return '()';
    final entries = args.entries.take(3).map((e) => '${e.key}: ${e.value}');
    return entries.join(', ');
  }
}

/// 流式输出气泡 (正在生成中的助手消息)
class StreamingBubble extends ConsumerStatefulWidget {
  final String text;

  const StreamingBubble({super.key, required this.text});

  @override
  ConsumerState<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends ConsumerState<StreamingBubble>
    with SingleTickerProviderStateMixin {
  /// 思考计时器 — 每秒 +1
  Timer? _thinkingTimer;
  int _elapsedSeconds = 0;

  /// 呼吸灯动画 — 让等待时的视觉更有节奏感
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // 如果初始就没 text，立即开始计时
    if (widget.text.isEmpty) _startTimer();
  }

  @override
  void didUpdateWidget(covariant StreamingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从空 → 有文本：停止计时
    if (oldWidget.text.isEmpty && widget.text.isNotEmpty) {
      _stopTimer();
    }
    // 从有文本 → 空（理论上不会，但保险）：重启计时
    if (oldWidget.text.isNotEmpty && widget.text.isEmpty) {
      _startTimer();
    }
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _thinkingTimer?.cancel();
    _thinkingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
  }

  @override
  void dispose() {
    _thinkingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // ✅ 直接监听 streamingThinking，不触发整个页面重建
    final thinkingContent = ref.watch(
      chatProvider.select((s) => s.streamingThinking),
    );

    // 如果有思考内容，显示思考区域
    final hasThinking = thinkingContent.isNotEmpty;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 思考区域（如果有）
            if (hasThinking) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '思考中...',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            // 主要内容
            if (widget.text.isEmpty && !hasThinking)
              _buildThinkingIndicator(context, colorScheme)
            else if (widget.text.isNotEmpty)
              MarkdownView(data: widget.text, textColor: colorScheme.onSurface)
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingIndicator(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final timeLabel = _formatElapsed(_elapsedSeconds);
    return FadeTransition(
      opacity: _pulseAnimation,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
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
          const SizedBox(width: 6),
          Text(
            timeLabel,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化秒数 → "3s" / "1:05"
  static String _formatElapsed(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

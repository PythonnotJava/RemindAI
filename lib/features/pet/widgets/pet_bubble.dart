import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/pet/pet_chat_service.dart';
import 'floating_pet.dart';

/// 跟随宠物的文本气泡 — 显示小猫的回复
///
/// - 跟随宠物位置移动
/// - 支持 Markdown 渲染 (SelectableText + GptMarkdown)
/// - 用户可手动关闭
/// - 内容可被再次投喂给宠物
class PetBubble extends StatelessWidget {
  const PetBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = FloatingPetController.instance;
    final chatService = PetChatService.instance;

    return ValueListenableBuilder<Offset>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        return ListenableBuilder(
          listenable: chatService,
          builder: (context, _) {
            if (!controller.visible) return const SizedBox.shrink();

            final reply = chatService.currentReply;
            final isThinking = chatService.isThinking;

            if (reply == null && !isThinking) return const SizedBox.shrink();
            // TTS 短回复不显示气泡
            if (reply != null && reply.useTts && !isThinking) {
              return const SizedBox.shrink();
            }

            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final screenSize = MediaQuery.of(context).size;
            const petSize = 96.0;

            final bubbleWidth = (screenSize.width * 0.3).clamp(200.0, 400.0);
            var bubbleLeft = position.dx + petSize / 2 - bubbleWidth / 2;
            bubbleLeft = bubbleLeft.clamp(8.0, screenSize.width - bubbleWidth - 8);
            final bubbleBottom = screenSize.height - position.dy + 8;

            return Positioned(
              left: bubbleLeft,
              bottom: bubbleBottom,
              child: _BubbleContent(
                reply: reply,
                isThinking: isThinking,
                width: bubbleWidth,
                theme: theme,
                colorScheme: colorScheme,
              ),
            );
          },
        );
      },
    );
  }
}

class _BubbleContent extends StatelessWidget {
  final PetReply? reply;
  final bool isThinking;
  final double width;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _BubbleContent({
    required this.reply,
    required this.isThinking,
    required this.width,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏 + 倒计时 + 关闭 + 投喂按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Icon(Icons.pets, size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  isThinking ? context.s.petBubbleThinking : context.s.petBubbleTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // 倒计时显示
                if (!isThinking && PetChatService.instance.countdown > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${PetChatService.instance.countdown}s',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (reply != null) ...[
                  _buildFeedButton(context),
                  const SizedBox(width: 2),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: PetChatService.instance.dismissReply,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: context.s.petBubbleClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容区
          Flexible(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                PetChatService.instance.resetDismissCountdown();
                return false;
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: isThinking
                    ? _buildThinking(context)
                    : _buildReplyContent(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinking(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(context.s.petBubbleGenerating, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildReplyContent(BuildContext context) {
    if (reply == null) return const SizedBox.shrink();
    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        final defaultButtons = selectableRegionState.contextMenuButtonItems;
        // 找到 Copy 按钮，用于获取选中文本
        final copyButton = defaultButtons.where(
          (b) => b.type == ContextMenuButtonType.copy,
        );

        // 投喂选中文本给小猫
        final feedButtons = PetChatService.instance.allAskModes.map((mode) {
          return ContextMenuButtonItem(
            label: context.s.petBubbleFeedSelected(mode.label),
            onPressed: () {
              if (copyButton.isNotEmpty) {
                copyButton.first.onPressed?.call();
              }
              ContextMenuController.removeAny();
              Clipboard.getData('text/plain').then((data) {
                final text = data?.text ?? '';
                if (text.isNotEmpty) {
                  PetChatService.instance.ask(text, mode);
                }
              });
            },
          );
        }).toList();

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: [...defaultButtons, ...feedButtons],
        );
      },
      child: GptMarkdown(
        reply!.text,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
      ),
    );
  }

  Widget _buildFeedButton(BuildContext context) {
    final modes = PetChatService.instance.allAskModes;
    return PopupMenuButton<PetAskModeBase>(
      icon: Icon(Icons.restaurant, size: 14, color: colorScheme.tertiary),
      tooltip: context.s.petBubbleFeedAll,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      iconSize: 14,
      itemBuilder: (_) => modes.map((mode) {
        return PopupMenuItem(value: mode, child: Text(context.s.petBubbleFeedFollow(mode.label)));
      }).toList(),
      onSelected: (mode) {
        if (reply != null) {
          PetChatService.instance.ask(reply!.text, mode);
        }
      },
    );
  }
}

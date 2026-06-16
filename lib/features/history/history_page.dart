import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../../core/db/tables/conversations.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../providers/database_provider.dart';
import '../chat/chat_provider.dart';

/// 用于从外部触发导航到对话页的回调
typedef NavigateToChatCallback = void Function();

class HistoryPage extends ConsumerWidget {
  final NavigateToChatCallback? onNavigateToChat;

  const HistoryPage({super.key, this.onNavigateToChat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context, ref),
          const Divider(height: 1),
          Expanded(
            child: conversationsAsync.when(
              data: (conversations) => conversations.isEmpty
                  ? _buildEmptyState(context)
                  : _buildList(context, ref, conversations),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  context.s.chatLoadFailedWithError(e.toString()),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.history, color: colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          Text(
            context.s.historyTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: context.s.historyClearAll,
            child: IconButton(
              icon: Icon(
                Icons.delete_sweep_outlined,
                size: 20,
                color: colorScheme.outline,
              ),
              onPressed: () => _deleteAll(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            context.s.historyEmpty,
            style: TextStyle(fontSize: 16, color: colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.historyEmptyHint,
            style: TextStyle(fontSize: 13, color: colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Conversation> conversations,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conv = conversations[index];
        return _ConversationTile(
          conversation: conv,
          onTap: () => _openConversation(context, ref, conv),
          onDelete: () => _deleteConversation(context, ref, conv),
        );
      },
    );
  }

  void _openConversation(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) {
    // 显示 loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: SpinKitFadingCircle(color: Colors.white, size: 40),
        ),
      ),
    );

    // 异步加载对话
    ref.read(chatProvider.notifier).loadConversation(conv.id).then((_) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 关闭 loading
        onNavigateToChat?.call();
      }
    });
  }

  void _deleteConversation(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.historyDeleteTitle),
        content: Text(context.s.historyDeleteConfirm(conv.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(conversationsProvider.notifier)
                  .deleteConversation(conv.id);
            },
            child: Text(
              context.s.commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.historyClearAllTitle),
        content: Text(context.s.historyClearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(conversationsProvider.notifier).deleteAll();
            },
            child: Text(
              context.s.historyClearBtn,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeStr = _formatTime(context, conversation.updatedAt);

    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: colorScheme.errorContainer,
        child: Icon(Icons.delete, color: colorScheme.error),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // 让对话框控制删除
      },
      child: ListTile(
        leading: Icon(
          Icons.chat_outlined,
          color: colorScheme.primary,
          size: 22,
        ),
        title: Text(
          conversation.title.isNotEmpty
              ? conversation.title
              : context.s.historyUntitled,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          timeStr,
          style: TextStyle(fontSize: 12, color: colorScheme.outline),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: colorScheme.outline,
          ),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return context.s.historyJustNow;
    if (diff.inHours < 1) return context.s.historyMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.s.historyHoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.s.historyDaysAgo(diff.inDays);

    return context.s.historyDateFormat(dateTime.month, dateTime.day);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../providers/memory_provider.dart';

class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(memoryViewProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.memoryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.s.memoryRefresh,
            onPressed: () => ref.invalidate(memoryViewProvider),
          ),
        ],
      ),
      body: memoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(context.s.chatLoadFailedWithError(e.toString())),
        ),
        data: (view) => _buildContent(context, ref, view),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, MemoryView view) {
    return Column(
      children: [
        // 存储统计区 — 始终展示 (SQLite / Qdrant 占用 / 条数)
        _StorageStats(view: view, ref: ref),
        const Divider(height: 1),
        Expanded(child: _buildList(context, ref, view)),
      ],
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, MemoryView view) {
    if (!view.enabled) {
      return _EmptyHint(
        icon: Icons.settings_suggest_outlined,
        text: context.s.memoryEmbNotConfigured,
      );
    }
    if (!view.qdrantRunning) {
      return _EmptyHint(
        icon: Icons.cloud_off,
        text: context.s.memoryQdrantNotRunning,
      );
    }
    if (view.items.isEmpty) {
      return _EmptyHint(
        icon: Icons.memory_outlined,
        text: context.s.memoryEmptyHint,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: view.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _MemoryCard(
          item: view.items[index],
          collection: view.collection,
          ref: ref,
        );
      },
    );
  }
}

class _StorageStats extends StatelessWidget {
  final MemoryView view;
  final WidgetRef ref;
  const _StorageStats({required this.view, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _StatCard(
            title: 'SQLite',
            value: formatBytes(view.sqliteBytes),
            icon: Icons.storage,
          ),
          const SizedBox(width: 12),
          _StatCard(
            title: 'Qdrant',
            value: view.qdrantRunning
                ? formatBytes(view.qdrantBytes)
                : context.s.memoryQdrantStopped,
            icon: Icons.hub,
          ),
          const SizedBox(width: 12),
          _StatCard(
            title: context.s.memoryCount,
            value: '${view.pointCount}',
            icon: Icons.memory,
          ),
          const Spacer(),
          if (view.items.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: () => _confirmClear(context),
              icon: const Icon(Icons.delete_sweep),
              label: Text(context.s.commonClear),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.memoryClearTitle),
        content: Text(context.s.memoryClearConfirm(view.pointCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final manager = ref.read(memoryManagerProvider);
    if (manager != null) {
      await manager.deleteCollection(view.collection);
      ref.invalidate(memoryViewProvider);
    }
  }
}

class _MemoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String collection;
  final WidgetRef ref;
  const _MemoryCard({
    required this.item,
    required this.collection,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = item['text'] as String? ?? context.s.memoryContentEmpty;
    final timestamp = item['timestamp'] as String? ?? '';
    final source = item['source'] as String? ?? '';
    final query = item['user_query'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bookmark_outline,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatTime(timestamp),
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
                if (source.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      source == 'auto_store'
                          ? context.s.memorySourceAuto
                          : source,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: context.s.commonDelete,
                  onPressed: () => _delete(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (query != null && query.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                context.s.memoryFromQuery(query),
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final manager = ref.read(memoryManagerProvider);
    final id = item['id'];
    if (manager == null || id is! int) return;
    await manager.deletePoint(collection, id);
    ref.invalidate(memoryViewProvider);
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.outline, height: 1.5),
          ),
        ],
      ),
    );
  }
}

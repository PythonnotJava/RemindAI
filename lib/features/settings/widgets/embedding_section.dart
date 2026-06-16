import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/settings/app_settings.dart';
import '../../../providers/settings_provider.dart';
import 'embedding_editor_dialog.dart';

/// 嵌入式模型区块 — 多卡片选择 + 新增
class EmbeddingSection extends ConsumerWidget {
  final List<EmbeddingConfig> embeddings;
  final String selectedId;

  const EmbeddingSection({
    super.key,
    required this.embeddings,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.s.embSectionHint,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (embeddings.isEmpty)
          _EmptyCard(onAdd: () => _openEditor(context, ref, null))
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final cfg in embeddings)
                _EmbeddingCard(
                  config: cfg,
                  selected: cfg.id == selectedId,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .selectEmbedding(cfg.id),
                  onEdit: () => _openEditor(context, ref, cfg),
                  onDelete: () => _confirmDelete(context, ref, cfg),
                ),
              _AddCard(onTap: () => _openEditor(context, ref, null)),
            ],
          ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    EmbeddingConfig? existing,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => EmbeddingEditorDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    EmbeddingConfig cfg,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.embSectionDeleteTitle),
        content: Text(context.s.embSectionDeleteConfirm(cfg.displayName)),
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
    if (ok == true) {
      await ref.read(settingsProvider.notifier).deleteEmbedding(cfg.id);
    }
  }
}

/// 单个嵌入模型卡片
class _EmbeddingCard extends StatelessWidget {
  final EmbeddingConfig config;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmbeddingCard({
    required this.config,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 280,
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.displayName,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.s.embSectionDefault,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _kv(context, 'Model', config.model),
                const SizedBox(height: 2),
                _kv(context, 'URL', config.baseUrl),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _flag(context, 'Qdrant', config.useQdrant),
                    const SizedBox(width: 6),
                    _flag(context, 'SQLite', config.persistToSqlite),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: context.s.commonEdit,
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: context.s.commonDelete,
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Consolas',
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _flag(BuildContext context, String label, bool on) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!on) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// 新增卡片 (虚线占位)
class _AddCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      height: 150,
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: DottedBorderBox(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 28, color: colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    context.s.embSectionAdd,
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 空状态卡片
class _EmptyCard extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return _AddCard(onTap: onAdd);
  }
}

/// 简易虚线边框容器
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
      ),
      child: child,
    );
  }
}

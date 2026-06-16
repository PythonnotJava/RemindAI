import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/expert/expert.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../providers/experts_provider.dart';
import 'expert_editor_dialog.dart';

String _localizedCategory(BuildContext context, String category) {
  return switch (category) {
    '技术' => context.s.expertCategoryTech,
    '分析' => context.s.expertCategoryAnalysis,
    '办公' => context.s.expertCategoryOffice,
    '创意' => context.s.expertCategoryCreative,
    '自定义' => context.s.expertCategoryCustom,
    _ => category,
  };
}

/// 专家标签页 — 展示所有领域专家卡片，点击跳转到对话
class ExpertsPage extends ConsumerWidget {
  final void Function(Expert expert) onStartChat;

  const ExpertsPage({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expertsAsync = ref.watch(expertsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.expertsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.s.expertsCreate,
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: expertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(context.s.chatLoadFailedWithError(err.toString())),
        ),
        data: (experts) => _buildGrid(context, ref, experts),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, List<Expert> experts) {
    if (experts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.s.expertsEmpty,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.s.expertsCreateFirst),
            ),
          ],
        ),
      );
    }

    // 按分类分组
    final grouped = <String, List<Expert>>{};
    for (final e in experts) {
      grouped.putIfAbsent(e.category, () => []).add(e);
    }
    final categories = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Text(
              _localizedCategory(context, category),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: grouped[category]!
                .map(
                  (e) => _ExpertCard(
                    expert: e,
                    onTap: () => onStartChat(e),
                    onEdit: () => _showEditDialog(context, ref, e),
                    onDelete: e.isBuiltin
                        ? null
                        : () => _confirmDelete(context, ref, e),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => ExpertEditorDialog(
        onSave: (expert) async {
          await ref.read(expertsProvider.notifier).addExpert(expert);
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Expert expert) {
    showDialog(
      context: context,
      builder: (_) => ExpertEditorDialog(
        expert: expert,
        onSave: (updated) async {
          await ref.read(expertsProvider.notifier).updateExpert(updated);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expert expert,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.expertsDeleteTitle),
        content: Text(context.s.expertsDeleteConfirm(expert.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(expertsProvider.notifier).deleteExpert(expert.id);
    }
  }
}

// ─── 专家卡片 ─────────────────────────────────────────────

class _ExpertCard extends StatelessWidget {
  final Expert expert;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _ExpertCard({
    required this.expert,
    required this.onTap,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 260,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        _resolveIcon(expert.icon),
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    if (!expert.isBuiltin && onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: onDelete,
                        tooltip: context.s.commonDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                      tooltip: context.s.commonEdit,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  expert.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  expert.description.isEmpty ? '点击开始对话' : expert.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (expert.boundSkills.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: expert.boundSkills
                        .take(3)
                        .map(
                          (s) => Chip(
                            label: Text(
                              s,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 根据字符串名称解析 Material Icon
  static IconData _resolveIcon(String name) {
    const iconMap = <String, IconData>{
      'slideshow': Icons.slideshow,
      'analytics': Icons.analytics,
      'code': Icons.code,
      'edit_note': Icons.edit_note,
      'person': Icons.person,
      'psychology': Icons.psychology,
      'school': Icons.school,
      'translate': Icons.translate,
      'brush': Icons.brush,
      'terminal': Icons.terminal,
      'science': Icons.science,
      'business': Icons.business,
      'support_agent': Icons.support_agent,
      'architecture': Icons.architecture,
      'auto_fix_high': Icons.auto_fix_high,
      'calculate': Icons.calculate,
      'campaign': Icons.campaign,
      'draw': Icons.draw,
      'fitness_center': Icons.fitness_center,
      'local_hospital': Icons.local_hospital,
      'menu_book': Icons.menu_book,
      'music_note': Icons.music_note,
      'palette': Icons.palette,
      'photo_camera': Icons.photo_camera,
      'restaurant': Icons.restaurant,
      'travel_explore': Icons.travel_explore,
      'desktop_windows': Icons.desktop_windows,
      'web': Icons.web,
    };
    return iconMap[name] ?? Icons.person;
  }
}

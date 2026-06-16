import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../core/skill/skill_model.dart';
import '../../providers/skills_provider.dart';
import '../../widgets/reorderable_card_grid.dart';

class SkillsPage extends ConsumerWidget {
  const SkillsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.skillsTitle)),
      body: const SkillsPageBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _importZip(context, ref),
        tooltip: context.s.skillsImport,
        child: const Icon(Icons.upload_file),
      ),
    );
  }

  Future<void> _importZip(BuildContext context, WidgetRef ref) async {
    await SkillsPageBody.importZip(context, ref);
  }
}

/// 技能管理的内容体（可独立嵌入到其他容器中）
class SkillsPageBody extends ConsumerWidget {
  const SkillsPageBody({super.key});

  static Future<void> importZip(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: '选择技能 ZIP 包',
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    try {
      final skill = await ref.read(skillsProvider.notifier).importFromZip(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.s.skillsImportSuccess(skill.name, skill.toolCount),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final detail = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.s.skillsImportFailed(detail)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);

    return skillsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(context.s.chatLoadFailedWithError(e.toString()))),
      data: (skills) {
        if (skills.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.extension_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  context.s.skillsEmpty,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  context.s.skillsEmptyHint,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => importZip(context, ref),
                  icon: const Icon(Icons.upload_file),
                  label: Text(context.s.skillsImport),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  context.s.skillsReorderHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ReorderableCardGrid<Skill>(
                items: skills,
                keyOf: (s) => s.id,
                onReorder: (reordered) =>
                    ref.read(skillsProvider.notifier).reorder(reordered),
                itemBuilder: (context, skill) => _SkillCardTile(skill: skill),
                trailing: _AddSkillCard(onTap: () => importZip(context, ref)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 技能卡片
class _SkillCardTile extends ConsumerWidget {
  final Skill skill;
  const _SkillCardTile({required this.skill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: skill.isActive
                ? colorScheme.primary.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  skill.isBuiltIn ? Icons.lock : Icons.extension,
                  size: 18,
                  color: skill.isActive ? colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (skill.isBuiltIn)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      context.s.skillsBuiltin,
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              skill.description.isEmpty ? '—' : skill.description,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              context.s.skillsToolCount(skill.toolCount),
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Switch(
                  value: skill.isActive,
                  onChanged: skill.isBuiltIn
                      ? null
                      : (_) => ref
                            .read(skillsProvider.notifier)
                            .toggleActive(skill.id),
                ),
                const Spacer(),
                if (!skill.isBuiltIn)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: context.s.commonDelete,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _confirmDelete(context, ref, skill.id, skill.name),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String skillId,
    String skillName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.skillsDeleteTitle),
        content: Text(context.s.skillsDeleteConfirm(skillName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(skillsProvider.notifier).remove(skillId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// 新增技能卡片 (虚线占位)
class _AddSkillCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSkillCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      height: 150,
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file, size: 28, color: colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    context.s.skillsImport,
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

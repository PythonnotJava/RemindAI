import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../providers/database_provider.dart';
import '../models/agent_config.dart';

const _uuid = Uuid();

/// 创建新Agent的对话框
class CreateAgentDialog extends ConsumerStatefulWidget {
  const CreateAgentDialog({super.key});

  @override
  ConsumerState<CreateAgentDialog> createState() => _CreateAgentDialogState();
}

class _CreateAgentDialogState extends ConsumerState<CreateAgentDialog> {
  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  AgentRole _selectedRole = AgentRole.worker;
  String? _selectedModelCardId;

  // 技能
  final Set<String> _selectedSkills = {};
  static const _availableSkillIds = [
    ('system', Icons.computer),
    ('toolshell', Icons.terminal),
  ];

  // 权限
  final Set<AgentPermission> _selectedPermissions = {};

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _create() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedModelCardId == null) return;

    final config = AgentConfig(
      id: _uuid.v4(),
      name: name,
      role: _selectedRole,
      systemPrompt: _promptController.text.trim(),
      modelCardId: _selectedModelCardId!,
      enabledSkills: _selectedSkills.toList(),
      permissions: _selectedPermissions.map((p) => p.name).toList(),
    );

    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardsAsync = ref.watch(modelCardsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Icon(Icons.add_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    context.s.createAgentTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 名称
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.s.createAgentName,
                  hintText: context.s.createAgentNameHint,
                  prefixIcon: const Icon(Icons.badge, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              // 角色选择
              Text(
                context.s.createAgentRole,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: AgentRole.values
                    .where((r) => r != AgentRole.commander)
                    .map(
                      (role) => ChoiceChip(
                        selected: _selectedRole == role,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(role.icon, size: 14, color: role.color),
                            const SizedBox(width: 4),
                            Text(role.localizedLabel(context)),
                          ],
                        ),
                        onSelected: (s) {
                          if (s) setState(() => _selectedRole = role);
                        },
                        labelStyle: theme.textTheme.labelSmall,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              // 模型选择
              cardsAsync.when(
                data: (cards) => DropdownButtonFormField<String>(
                  initialValue: _selectedModelCardId,
                  decoration: InputDecoration(
                    labelText: context.s.createAgentModel,
                    prefixIcon: const Icon(Icons.smart_toy, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  items: cards
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, style: theme.textTheme.bodySmall),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedModelCardId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(context.s.createAgentModelFailed),
              ),
              const SizedBox(height: 14),
              // 技能挂载
              Text(
                context.s.createAgentSkills,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _availableSkillIds.map((s) {
                  final (id, icon) = s;
                  final label = id == 'system'
                      ? context.s.createAgentSysDetect
                      : context.s.createAgentFileCmd;
                  final selected = _selectedSkills.contains(id);
                  return FilterChip(
                    selected: selected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14),
                        const SizedBox(width: 4),
                        Text(label),
                      ],
                    ),
                    onSelected: (v) => setState(() {
                      v ? _selectedSkills.add(id) : _selectedSkills.remove(id);
                    }),
                    labelStyle: theme.textTheme.labelSmall,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // 权限
              Text(
                context.s.createAgentPermissions,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: AgentPermission.values.map((perm) {
                  final selected = _selectedPermissions.contains(perm);
                  return FilterChip(
                    selected: selected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(perm.icon, size: 14),
                        const SizedBox(width: 4),
                        Text(perm.localizedLabel(context)),
                      ],
                    ),
                    onSelected: (v) => setState(() {
                      v
                          ? _selectedPermissions.add(perm)
                          : _selectedPermissions.remove(perm);
                    }),
                    labelStyle: theme.textTheme.labelSmall,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // 系统提示
              Expanded(
                child: TextField(
                  controller: _promptController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    labelText: context.s.createAgentPromptLabel,
                    hintText: context.s.createAgentPromptHint,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              // 按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.s.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.s.expertsCreate2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

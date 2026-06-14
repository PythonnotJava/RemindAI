import 'package:flutter/material.dart';
import '../../core/expert/expert.dart';
import '../../core/l10n/l10n_ext.dart';

/// 专家创建/编辑对话框
class ExpertEditorDialog extends StatefulWidget {
  final Expert? expert; // null = 创建模式
  final Future<void> Function(Expert expert) onSave;

  const ExpertEditorDialog({super.key, this.expert, required this.onSave});

  @override
  State<ExpertEditorDialog> createState() => _ExpertEditorDialogState();
}

class _ExpertEditorDialogState extends State<ExpertEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _promptCtrl;
  late String _category;
  late String _icon;
  late List<String> _boundSkills;
  bool _saving = false;

  static const _categories = ['技术', '分析', '办公', '创意', '自定义'];

  /// Returns localized display name for a stored category value.
  String _localizedCategory(BuildContext context, String category) {
    switch (category) {
      case '技术':
        return context.s.expertCategoryTech;
      case '分析':
        return context.s.expertCategoryAnalysis;
      case '办公':
        return context.s.expertCategoryOffice;
      case '创意':
        return context.s.expertCategoryCreative;
      case '自定义':
        return context.s.expertCategoryCustom;
      default:
        return category;
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.expert;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _promptCtrl = TextEditingController(text: e?.systemPrompt ?? '');
    _category = e?.category ?? '自定义';
    _icon = e?.icon ?? 'person';
    _boundSkills = e?.boundSkills.toList() ?? ['toolshell'];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.expert != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditing
                    ? context.s.expertEditorEdit
                    : context.s.expertEditorCreate,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称 + 图标
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameCtrl,
                              decoration: InputDecoration(
                                labelText: context.s.expertEditorName,
                                hintText: context.s.expertsNameHint,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _IconSelector(
                            selected: _icon,
                            onChanged: (v) => setState(() => _icon = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 分类
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: InputDecoration(
                          labelText: context.s.expertEditorCategory,
                          border: const OutlineInputBorder(),
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(_localizedCategory(context, c)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _category = v!),
                      ),
                      const SizedBox(height: 16),
                      // 描述
                      TextField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          labelText: context.s.expertEditorDesc,
                          hintText: context.s.expertsDescHint,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      // System Prompt
                      TextField(
                        controller: _promptCtrl,
                        decoration: InputDecoration(
                          labelText: context.s.expertEditorPrompt,
                          hintText: context.s.expertsPromptHint,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        minLines: 4,
                      ),
                      const SizedBox(height: 16),
                      // 绑定技能
                      Text(
                        context.s.expertsBindSkills,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _SkillChip(
                            label: 'toolshell',
                            selected: _boundSkills.contains('toolshell'),
                            onToggle: () => _toggleSkill('toolshell'),
                          ),
                          _SkillChip(
                            label: 'schedule',
                            selected: _boundSkills.contains('schedule'),
                            onToggle: () => _toggleSkill('schedule'),
                          ),
                          _SkillChip(
                            label: 'system',
                            selected: _boundSkills.contains('system'),
                            onToggle: () => _toggleSkill('system'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(context.s.commonCancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isEditing
                                ? context.s.commonSave
                                : context.s.expertsCreate2,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_boundSkills.contains(skill)) {
        _boundSkills.remove(skill);
      } else {
        _boundSkills.add(skill);
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s.expertsNameRequired)));
      return;
    }
    if (_promptCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s.expertsPromptRequired)));
      return;
    }

    setState(() => _saving = true);

    final expert = Expert(
      id: widget.expert?.id,
      name: name,
      icon: _icon,
      description: _descCtrl.text.trim(),
      systemPrompt: _promptCtrl.text.trim(),
      boundSkills: _boundSkills,
      category: _category,
      isBuiltin: widget.expert?.isBuiltin ?? false,
      createdAt: widget.expert?.createdAt,
    );

    await widget.onSave(expert);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

// ─── 辅助组件 ─────────────────────────────────────────────

class _IconSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _IconSelector({required this.selected, required this.onChanged});

  static const _icons = <String, IconData>{
    'person': Icons.person,
    'slideshow': Icons.slideshow,
    'analytics': Icons.analytics,
    'code': Icons.code,
    'edit_note': Icons.edit_note,
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
    'menu_book': Icons.menu_book,
    'palette': Icons.palette,
    'travel_explore': Icons.travel_explore,
    'desktop_windows': Icons.desktop_windows,
    'web': Icons.web,
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      tooltip: context.s.expertsSelectIcon,
      itemBuilder: (_) => _icons.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Icon(
                e.value,
                color: e.key == selected
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          )
          .toList(),
      child: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          _icons[selected] ?? Icons.person,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onToggle;

  const _SkillChip({
    required this.label,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onToggle(),
    );
  }
}

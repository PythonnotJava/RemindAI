import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/shortcuts/shortcut_config.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/tools/tool_plugin.dart';

/// 快捷键管理工具
class ShortcutsTool extends ToolPlugin {
  @override
  String get id => 'shortcuts';

  @override
  String get name => '截图';

  @override
  IconData get icon => Icons.keyboard;

  @override
  String get description => '查看和自定义应用快捷键';

  @override
  String get category => '快捷键';

  @override
  String localizedName(BuildContext context) => context.s.toolShortcutsName;

  @override
  String localizedDescription(BuildContext context) =>
      context.s.toolShortcutsDesc;

  @override
  String localizedCategory(BuildContext context) =>
      context.s.toolShortcutsCategory;

  @override
  Widget buildUI(BuildContext context, ToolConfig config) {
    return const _ShortcutsPanel();
  }
}

class _ShortcutsPanel extends StatefulWidget {
  const _ShortcutsPanel();

  @override
  State<_ShortcutsPanel> createState() => _ShortcutsPanelState();
}

class _ShortcutsPanelState extends State<_ShortcutsPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bindings = ShortcutConfig.instance.bindings.values.toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.keyboard, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                context.s.toolShortcutsCategory,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(context.s.shortcutReset),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.s.shortcutHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: bindings.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final binding = bindings[index];
                return _ShortcutTile(
                  binding: binding,
                  onEdit: () => _editShortcut(binding),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetAll() async {
    await ShortcutConfig.instance.resetToDefaults();
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.shortcutResetDone),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _editShortcut(ShortcutBinding binding) async {
    final result = await showDialog<ShortcutBinding>(
      context: context,
      builder: (ctx) => _ShortcutRecordDialog(binding: binding),
    );
    if (result != null) {
      await ShortcutConfig.instance.update(result.id, result);
      setState(() {});
    }
  }
}

/// 单个快捷键行
class _ShortcutTile extends StatelessWidget {
  final ShortcutBinding binding;
  final VoidCallback onEdit;

  const _ShortcutTile({required this.binding, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      title: Text(binding.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              binding.displayString,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
            tooltip: context.s.shortcutEdit,
          ),
        ],
      ),
    );
  }
}

/// 快捷键录入对话框 — 按下组合键即录入
class _ShortcutRecordDialog extends StatefulWidget {
  final ShortcutBinding binding;
  const _ShortcutRecordDialog({required this.binding});

  @override
  State<_ShortcutRecordDialog> createState() => _ShortcutRecordDialogState();
}

class _ShortcutRecordDialogState extends State<_ShortcutRecordDialog> {
  ShortcutBinding? _recorded;
  bool _waiting = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(context.s.shortcutEditTitle(widget.binding.label)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.s.shortcutEditHint),
            const SizedBox(height: 20),
            KeyboardListener(
              focusNode: FocusNode()..requestFocus(),
              autofocus: true,
              onKeyEvent: _onKey,
              child: Container(
                width: double.infinity,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _waiting
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: _waiting ? 2 : 1,
                  ),
                ),
                child: Text(
                  _recorded?.displayString ?? context.s.shortcutEditWaiting,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(context.s.shortcutCancel),
        ),
        FilledButton(
          onPressed: _recorded != null
              ? () => Navigator.of(context).pop(_recorded)
              : null,
          child: Text(context.s.shortcutConfirm),
        ),
      ],
    );
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    // 忽略单独的修饰键
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return;
    }

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // 至少需要一个修饰键
    if (!ctrl && !shift && !alt) return;

    setState(() {
      _recorded = ShortcutBinding(
        id: widget.binding.id,
        label: widget.binding.label,
        key: key,
        control: ctrl,
        shift: shift,
        alt: alt,
      );
      _waiting = false;
    });
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dock_panel/dock_panel.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/utils/directory_picker.dart';
import '../models/agent_config.dart';
import '../providers/multi_agent_provider.dart';
import '../theme/agent_dock_theme.dart';
import 'agent_chat_panel.dart';
import 'agent_explorer.dart';
import 'command_center.dart';
import 'create_agent_dialog.dart';

const _uuid = Uuid();

/// 多Agent协作工作区
class AgentWorkspace extends ConsumerStatefulWidget {
  const AgentWorkspace({super.key});

  @override
  ConsumerState<AgentWorkspace> createState() => _AgentWorkspaceState();
}

class _AgentWorkspaceState extends ConsumerState<AgentWorkspace> {
  final Set<String> _activePanelIds = {};
  bool _dockInitialized = false;

  void _initDockLayout() {
    if (_dockInitialized) return;
    _dockInitialized = true;

    final notifier = ref.read(multiAgentProvider.notifier);
    final agentState = ref.read(multiAgentProvider);

    if (agentState.commanderId == null) {
      notifier.createAgent(
        AgentConfig(
          id: _uuid.v4(),
          name: context.s.multiAgentHQ,
          role: AgentRole.commander,
          systemPrompt:
              '你是多Agent协作系统的总指挥。\n'
              '1. 接收用户的复杂任务并分解\n'
              '2. 分配给合适的工作Agent\n'
              '3. 协调各Agent之间的协作\n'
              '4. 汇总结果向用户报告',
          modelCardId: '',
          closable: false,
        ),
      );
    }
    _setupDockLayout();
    ref.listenManual(dockManagerProvider, _detectClosedPanels);
  }

  void _setupDockLayout() {
    final dock = ref.read(dockManagerProvider.notifier);
    final explorer = DockPanel(
      id: '__explorer__',
      title: context.s.multiAgentManager,
      icon: Icons.account_tree,
      closable: false,
      builder: (_) => AgentExplorer(onShowAgent: _addAgentPanel),
    );
    final command = DockPanel(
      id: '__command_center__',
      title: context.s.multiAgentHQ,
      icon: Icons.military_tech,
      closable: false,
      builder: (_) => const CommandCenter(),
    );
    dock.registerPanel(explorer);
    dock.registerPanel(command);

    dock.setLayout(
      DockLayout(
        root: DockSplit(
          id: generateNodeId(),
          axis: DockAxis.horizontal,
          children: [
            DockGroup(id: generateNodeId(), panels: [explorer]),
            DockGroup(id: generateNodeId(), panels: [command]),
          ],
          flexes: [0.18, 0.82],
        ),
      ),
    );
    _activePanelIds.addAll(['__explorer__', '__command_center__']);
  }

  Future<void> _createNewAgent() async {
    final config = await showDialog<AgentConfig>(
      context: context,
      builder: (_) => const CreateAgentDialog(),
    );
    if (config == null) return;
    ref.read(multiAgentProvider.notifier).createAgent(config);
    _addAgentPanel(config.id);
  }

  void _addAgentPanel(String agentId) {
    if (_activePanelIds.contains(agentId)) return;
    final rt = ref.read(multiAgentProvider).agents[agentId];
    if (rt == null) return;
    ref
        .read(dockManagerProvider.notifier)
        .addPanel(
          DockPanel(
            id: agentId,
            title: rt.config.name,
            icon: rt.config.role.icon,
            closable: true,
            builder: (_) => AgentChatPanel(agentId: agentId),
          ),
        );
    _activePanelIds.add(agentId);
  }

  void _detectClosedPanels(DockLayout? prev, DockLayout next) {
    if (prev == null) return;
    final gone = _ids(prev.root).difference(_ids(next.root));
    for (final id in gone) {
      if (id.startsWith('__')) continue;
      _activePanelIds.remove(id);
      ref.read(multiAgentProvider.notifier).hideAgent(id);
    }
  }

  Set<String> _ids(DockNode? n) => switch (n) {
    null => <String>{},
    DockGroup(:final panels) => panels.map((p) => p.id).toSet(),
    DockSplit(:final children) => children.expand((c) => _ids(c)).toSet(),
  };

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(multiAgentProvider);
    final theme = Theme.of(context);

    if (!agentState.hasWorkspace) {
      return _WorkspaceSetup(
        onSelected: (p) =>
            ref.read(multiAgentProvider.notifier).setWorkingDirectory(p),
        onRestore: _showSnapshotPicker,
      );
    }

    if (!_dockInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initDockLayout();
        if (mounted) setState(() {});
      });
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _Toolbar(
          dir: agentState.workingDirectory!,
          onAdd: _createNewAgent,
          onChangeDir: () => _confirmChangeDir(context),
        ),
        Expanded(child: DockArea(theme: buildDockTheme(theme))),
      ],
    );
  }

  /// 确认切换目录（防止误操作丢失工作）
  Future<void> _confirmChangeDir(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.multiAgentSwitchDir),
        content: Text(context.s.multiAgentSwitchDirConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.commonSwitch),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(multiAgentProvider.notifier).clearWorkingDirectory();
      setState(() => _dockInitialized = false);
    }
  }

  /// 显示历史快照选择器
  Future<void> _showSnapshotPicker() async {
    final snapshots = await ref
        .read(multiAgentProvider.notifier)
        .listSnapshots();
    if (!mounted) return;
    if (snapshots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s.multiAgentNoHistory)));
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _SnapshotPickerDialog(snapshots: snapshots),
    );
    if (selected != null && mounted) {
      final ok = await ref
          .read(multiAgentProvider.notifier)
          .restoreSnapshot(selected);
      if (ok) {
        setState(() => _dockInitialized = false);
      }
    }
  }
}

// ─── 工作目录选择 ────────────────────────────────────────────

class _WorkspaceSetup extends StatelessWidget {
  const _WorkspaceSetup({required this.onSelected, required this.onRestore});
  final ValueChanged<String> onSelected;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 20),
            Text(
              context.s.multiAgentSelectDir,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '多Agent协作需要一个共享工作目录，\n所有Agent将在此目录下读写文件、执行任务。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () async {
                final dir = await pickDirectory(
                  dialogTitle: context.s.multiAgentSelectDirTitle,
                );
                if (dir != null) onSelected(dir);
              },
              icon: const Icon(Icons.folder, size: 20),
              label: Text(context.s.multiAgentOpenDir),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.history, size: 18),
              label: Text(context.s.multiAgentRestoreHistory),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.s.multiAgentDirHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 工具栏 ──────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.dir,
    required this.onAdd,
    required this.onChangeDir,
  });
  final String dir;
  final VoidCallback onAdd;
  final VoidCallback onChangeDir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirName = dir.split(RegExp(r'[/\\]')).last;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.groups, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            context.s.multiAgentTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onChangeDir,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      dirName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_horiz,
                    size: 12,
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              context.s.multiAgentNewAgent,
              style: theme.textTheme.labelSmall,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 历史快照选择对话框 ───────────────────────────────────────────

class _SnapshotPickerDialog extends StatefulWidget {
  const _SnapshotPickerDialog({required this.snapshots});
  final List<WorkspaceSnapshot> snapshots;

  @override
  State<_SnapshotPickerDialog> createState() => _SnapshotPickerDialogState();
}

class _SnapshotPickerDialogState extends State<_SnapshotPickerDialog> {
  late List<WorkspaceSnapshot> _snapshots;

  @override
  void initState() {
    super.initState();
    _snapshots = List.from(widget.snapshots);
  }

  Future<void> _deleteSnapshot(int index) async {
    final snap = _snapshots[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.multiAgentDeleteHistory),
        content: Text(context.s.multiAgentDeleteHistoryConfirm(snap.dirName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await File(snap.filePath).delete();
      } catch (_) {}
      setState(() => _snapshots.removeAt(index));
      if (_snapshots.isEmpty && mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.s.multiAgentHistorySection)),
          Text(
            context.s.multiAgentHistoryCount(_snapshots.length),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 320,
        child: _snapshots.isEmpty
            ? Center(
                child: Text(
                  context.s.multiAgentNoHistoryShort,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              )
            : ListView.separated(
                itemCount: _snapshots.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final snap = _snapshots[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.restore, size: 20),
                    title: Text(
                      snap.dirName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDateTime(snap.savedAt)} · '
                      '${snap.agentCount} 个Agent · '
                      '${snap.messageCount} 条消息',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: theme.colorScheme.error.withValues(alpha: 0.6),
                      ),
                      onPressed: () => _deleteSnapshot(index),
                      tooltip: context.s.multiAgentDeleteRecord,
                      splashRadius: 16,
                    ),
                    onTap: () => Navigator.pop(ctx, snap.filePath),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.commonCancel),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

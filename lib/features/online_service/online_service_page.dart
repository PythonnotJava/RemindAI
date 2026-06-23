import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../core/online_service/online_service_config.dart';
import '../../core/online_service/online_session.dart';
import '../../providers/database_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/skills_provider.dart';
import 'online_service_provider.dart';

/// 在线服务运维面板 (嵌入到"服务"Tab)
class OnlineServicePageBody extends ConsumerStatefulWidget {
  const OnlineServicePageBody({super.key});

  @override
  ConsumerState<OnlineServicePageBody> createState() =>
      _OnlineServicePageBodyState();
}

class _OnlineServicePageBodyState extends ConsumerState<OnlineServicePageBody> {
  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: '2002');
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(onlineServiceConfigProvider);
    final server = ref.watch(onlineServerProvider);
    final users = ref.watch(onlineUsersProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('${context.s.olsTitle}: $e')),
      data: (config) {
        _portController.text = config.port.toString();
        return _buildContent(context, config, server, users);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    OnlineServiceConfig config,
    dynamic server,
    List<OnlineSession> users,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRunning = server.isRunning as bool;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ─── 标题栏 ───────────────────────────────
        Row(
          children: [
            Icon(Icons.cloud_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              context.s.olsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _StatusChip(isRunning: isRunning, port: server.boundPort as int?),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.s.olsIntro,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // ─── 控制区 ───────────────────────────────
        _ControlSection(config: config, isRunning: isRunning),
        const SizedBox(height: 20),

        // ─── 在线用户 ─────────────────────────────
        _UsersSection(users: users),
        const SizedBox(height: 20),

        // ─── 白名单管理 ───────────────────────────
        _WhitelistSection(config: config),
      ],
    );
  }

  // ignore: unused_element
  void _saveConfig(OnlineServiceConfig config) {
    ref.read(onlineServiceConfigProvider.notifier).save(config);
  }
}

// ─── 状态指示器 ──────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool isRunning;
  final int? port;
  const _StatusChip({required this.isRunning, this.port});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withValues(alpha: 0.1)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? Colors.green : cs.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning ? Colors.green : cs.outline,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isRunning
                ? context.s.olsRunningPort(port ?? 0)
                : context.s.olsStopped,
            style: TextStyle(
              fontSize: 12,
              color: isRunning ? Colors.green.shade700 : cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 控制面板 ──────────────────────────────────────────

class _ControlSection extends ConsumerWidget {
  final OnlineServiceConfig config;
  final bool isRunning;
  const _ControlSection({required this.config, required this.isRunning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.s.olsControl, style: theme.textTheme.titleSmall),
                const Spacer(),
                // 启用开关
                Switch(
                  value: config.enabled,
                  onChanged: (v) => _save(ref, config.copyWith(enabled: v)),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                // 端口
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: TextEditingController(text: '${config.port}'),
                    decoration: InputDecoration(
                      labelText: context.s.olsPort,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (v) {
                      final port = int.tryParse(v);
                      if (port != null && port > 0 && port < 65536) {
                        _save(ref, config.copyWith(port: port));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // 最大连接
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: TextEditingController(
                      text: '${config.maxConnections}',
                    ),
                    decoration: InputDecoration(
                      labelText: context.s.olsMaxConn,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (v) {
                      final max = int.tryParse(v);
                      if (max != null && max > 0) {
                        _save(ref, config.copyWith(maxConnections: max));
                      }
                    },
                  ),
                ),
                const Spacer(),
                // 拉闸按钮
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _save(ref, config.copyWith(accepting: !config.accepting)),
                  icon: Icon(
                    config.accepting
                        ? Icons.power_settings_new
                        : Icons.power_off,
                  ),
                  label: Text(
                    config.accepting ? context.s.olsPause : context.s.olsResume,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: config.accepting
                        ? cs.errorContainer
                        : cs.primaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save(WidgetRef ref, OnlineServiceConfig config) {
    ref.read(onlineServiceConfigProvider.notifier).save(config);
  }
}

// ─── 在线用户列表 ────────────────────────────────────────

class _UsersSection extends ConsumerWidget {
  final List<OnlineSession> users;
  const _UsersSection({required this.users});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.s.olsOnlineUsers,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${users.length}',
                    style: TextStyle(fontSize: 11, color: cs.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (users.isEmpty)
              Text(
                context.s.olsNoUsers,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              )
            else
              ...users.map((u) => _UserTile(session: u)),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final OnlineSession session;
  const _UserTile({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final duration = DateTime.now().difference(session.connectedAt);
    final minutes = duration.inMinutes;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.person, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.nickname, style: const TextStyle(fontSize: 13)),
                Text(
                  context.s.olsUserSessionInfo(
                    session.clientIp,
                    minutes,
                    session.messages.length,
                  ),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (session.busy)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                context.s.olsBusy,
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: cs.error),
            tooltip: context.s.olsKick,
            onPressed: () {
              ref.read(onlineServerProvider).kickSession(session.id);
            },
          ),
        ],
      ),
    );
  }
}

// ─── 白名单管理 ─────────────────────────────────────────

class _WhitelistSection extends ConsumerWidget {
  final OnlineServiceConfig config;
  const _WhitelistSection({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final modelCards = ref.watch(modelCardsProvider).valueOrNull ?? [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.s.olsWhitelist, style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  context.s.olsWhitelistHint,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: context.s.olsWhitelistAdd,
                  onPressed: () => _showAddDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (config.whitelist.isEmpty)
              Text(
                context.s.olsWhitelistEmpty,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              )
            else
              ...config.whitelist.asMap().entries.map(
                (e) => _WhitelistTile(
                  entry: e.value,
                  index: e.key,
                  config: config,
                  modelCards: modelCards,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _WhitelistEditDialog(
        config: config,
        onSave: (entry) {
          final newList = [...config.whitelist, entry];
          ref
              .read(onlineServiceConfigProvider.notifier)
              .save(config.copyWith(whitelist: newList));
        },
      ),
    );
  }
}

/// 白名单编辑对话框 — 配置 IP/昵称/模型/MCP/Skill
class _WhitelistEditDialog extends ConsumerStatefulWidget {
  final OnlineServiceConfig config;
  final WhitelistEntry? existing; // null = 新增
  final void Function(WhitelistEntry) onSave;

  const _WhitelistEditDialog({
    required this.config,
    this.existing,
    required this.onSave,
  });

  @override
  ConsumerState<_WhitelistEditDialog> createState() =>
      _WhitelistEditDialogState();
}

class _WhitelistEditDialogState extends ConsumerState<_WhitelistEditDialog> {
  late TextEditingController _ipCtrl;
  late TextEditingController _nickCtrl;
  Set<String> _selectedModels = {};
  bool _mcpEnabled = false;
  Set<String> _selectedMcps = {};
  bool _skillEnabled = false;
  Set<String> _selectedSkills = {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _ipCtrl = TextEditingController(text: e?.ip ?? '');
    _nickCtrl = TextEditingController(text: e?.nickname ?? '');
    _selectedModels = (e?.allowedModelCardIds ?? []).toSet();
    _mcpEnabled = e?.mcpEnabled ?? false;
    _selectedMcps = (e?.mcpServerIds ?? []).toSet();
    _skillEnabled = e?.skillEnabled ?? false;
    _selectedSkills = (e?.skillIds ?? []).toSet();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelCards = ref.watch(modelCardsProvider).valueOrNull ?? [];
    final mcpServers = ref.watch(mcpServersProvider).valueOrNull ?? [];
    final skills = ref.watch(skillsProvider).valueOrNull ?? [];

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? context.s.olsWhitelistAddTitle
            : context.s.olsWhitelistEditTitle,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IP + 昵称
              TextField(
                controller: _ipCtrl,
                decoration: InputDecoration(
                  labelText: context.s.olsWhitelistIp,
                  hintText: context.s.olsWhitelistIpHint,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nickCtrl,
                decoration: InputDecoration(
                  labelText: context.s.olsWhitelistNickname,
                  hintText: context.s.olsNicknameHint,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // 模型分配
              _buildSectionHeader(context.s.olsWhitelistModels),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: modelCards
                    .map(
                      (c) => FilterChip(
                        label: Text(
                          c.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: _selectedModels.contains(c.id),
                        onSelected: (v) => setState(() {
                          v
                              ? _selectedModels.add(c.id)
                              : _selectedModels.remove(c.id);
                        }),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),

              // MCP 分配
              Row(
                children: [
                  _buildSectionHeader(context.s.olsWhitelistMcp),
                  const Spacer(),
                  Switch(
                    value: _mcpEnabled,
                    onChanged: (v) => setState(() => _mcpEnabled = v),
                  ),
                ],
              ),
              if (_mcpEnabled)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: mcpServers
                      .map(
                        (s) => FilterChip(
                          label: Text(
                            s.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _selectedMcps.contains(s.id),
                          onSelected: (v) => setState(() {
                            v
                                ? _selectedMcps.add(s.id)
                                : _selectedMcps.remove(s.id);
                          }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 12),

              // Skill 分配
              Row(
                children: [
                  _buildSectionHeader(context.s.olsWhitelistSkill),
                  const Spacer(),
                  Switch(
                    value: _skillEnabled,
                    onChanged: (v) => setState(() => _skillEnabled = v),
                  ),
                ],
              ),
              if (_skillEnabled)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: skills
                      .map(
                        (s) => FilterChip(
                          label: Text(
                            s.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _selectedSkills.contains(s.id),
                          onSelected: (v) => setState(() {
                            v
                                ? _selectedSkills.add(s.id)
                                : _selectedSkills.remove(s.id);
                          }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.olsCancel),
        ),
        FilledButton(
          onPressed: () {
            if (_ipCtrl.text.trim().isEmpty) return;
            final entry = WhitelistEntry(
              ip: _ipCtrl.text.trim(),
              nickname: _nickCtrl.text.trim(),
              allowedModelCardIds: _selectedModels.toList(),
              mcpEnabled: _mcpEnabled,
              mcpServerIds: _selectedMcps.toList(),
              skillEnabled: _skillEnabled,
              skillIds: _selectedSkills.toList(),
            );
            widget.onSave(entry);
            Navigator.pop(context);
          },
          child: Text(context.s.olsSave),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _WhitelistTile extends ConsumerWidget {
  final WhitelistEntry entry;
  final int index;
  final OnlineServiceConfig config;
  final List<dynamic> modelCards;

  const _WhitelistTile({
    required this.entry,
    required this.index,
    required this.config,
    required this.modelCards,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              entry.ip,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text(
              entry.nickname.isEmpty ? '-' : entry.nickname,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          // MCP 开关
          _MiniToggle(
            label: 'MCP',
            value: entry.mcpEnabled,
            onChanged: (v) => _updateEntry(ref, entry.copyWith(mcpEnabled: v)),
          ),
          const SizedBox(width: 8),
          // Skill 开关
          _MiniToggle(
            label: 'Skill',
            value: entry.skillEnabled,
            onChanged: (v) =>
                _updateEntry(ref, entry.copyWith(skillEnabled: v)),
          ),
          const SizedBox(width: 8),
          // 模型数量标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.allowedModelCardIds.isEmpty
                  ? context.s.olsAllModels
                  : context.s.olsNModels(entry.allowedModelCardIds.length),
              style: TextStyle(fontSize: 10, color: cs.tertiary),
            ),
          ),
          const SizedBox(width: 8),
          // 编辑
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 16, color: cs.primary),
            tooltip: context.s.olsWhitelistEdit,
            onPressed: () => _showEditDialog(context, ref),
          ),
          // 删除
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
            tooltip: context.s.olsRemove,
            onPressed: () => _removeEntry(ref),
          ),
        ],
      ),
    );
  }

  void _updateEntry(WidgetRef ref, WhitelistEntry newEntry) {
    final list = [...config.whitelist];
    list[index] = newEntry;
    ref
        .read(onlineServiceConfigProvider.notifier)
        .save(config.copyWith(whitelist: list));
  }

  void _removeEntry(WidgetRef ref) {
    final list = [...config.whitelist];
    list.removeAt(index);
    ref
        .read(onlineServiceConfigProvider.notifier)
        .save(config.copyWith(whitelist: list));
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _WhitelistEditDialog(
        config: config,
        existing: entry,
        onSave: (updated) => _updateEntry(ref, updated),
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _MiniToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: value ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: value ? cs.primary : cs.onSurfaceVariant,
            fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../core/mcp/mcp_registry.dart';
import '../../core/mcp/transports/mcp_transport.dart';
import '../../providers/mcp_provider.dart';
import '../../widgets/reorderable_card_grid.dart';

class McpPage extends ConsumerWidget {
  const McpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.mcpTitle)),
      body: const McpPageBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => McpPageBody.showAddDialog(context, ref),
        tooltip: context.s.mcpAdd,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// MCP 服务管理的内容体（可独立嵌入到其他容器中）
class McpPageBody extends ConsumerWidget {
  const McpPageBody({super.key});

  static void showAddDialog(BuildContext context, WidgetRef ref) {
    showServerDialog(context, ref, null);
  }

  static void showServerDialog(
    BuildContext context,
    WidgetRef ref,
    McpServerConfig? existing,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _McpServerFormDialog(
        existing: existing,
        onSave: (config) {
          if (existing == null) {
            ref
                .read(mcpServersProvider.notifier)
                .add(
                  name: config.name,
                  transportType: config.transportType,
                  command: config.command,
                  args: config.args,
                  env: config.env,
                  cwd: config.cwd,
                  url: config.url,
                  httpHeaders: config.httpHeaders,
                );
          } else {
            ref.read(mcpServersProvider.notifier).updateServer(config);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(mcpServersProvider);

    return serversAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(context.s.chatLoadFailedWithError(e.toString()))),
      data: (servers) {
        if (servers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(context.s.mcpEmpty, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  context.s.mcpEmptyHint,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => showAddDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(context.s.mcpAdd),
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
                  context.s.mcpReorderHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ReorderableCardGrid<McpServerConfig>(
                items: servers,
                keyOf: (s) => s.id,
                onReorder: (reordered) =>
                    ref.read(mcpServersProvider.notifier).reorder(reordered),
                itemBuilder: (context, server) => _McpCardTile(server: server),
                trailing: _AddMcpCard(onTap: () => showAddDialog(context, ref)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// MCP 服务卡片
class _McpCardTile extends ConsumerWidget {
  final McpServerConfig server;
  const _McpCardTile({required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status =
        ref.watch(mcpConnectionsProvider).statuses[server.id] ??
        McpConnectionStatus.disconnected;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showServerDialog(context, ref),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: server.enabled
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
                  _statusDot(status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      server.name,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _transportBadge(server.transportType, colorScheme),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                server.isHttpTransport
                    ? server.url
                    : '${server.command} ${server.args.join(" ")}'.trim(),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 启用开关
                  Switch(
                    value: server.enabled,
                    onChanged: (_) => ref
                        .read(mcpServersProvider.notifier)
                        .toggleEnabled(server.id),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      status == McpConnectionStatus.connected
                          ? Icons.link_off
                          : Icons.link,
                      size: 18,
                    ),
                    tooltip: status == McpConnectionStatus.connected
                        ? context.s.mcpDisconnect
                        : context.s.mcpTestConnection,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _toggleConnection(context, ref, server, status),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: context.s.commonDelete,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _confirmDelete(context, ref, server.id, server.name),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot(McpConnectionStatus status) {
    switch (status) {
      case McpConnectionStatus.connected:
        return const Icon(Icons.circle, color: Colors.green, size: 12);
      case McpConnectionStatus.connecting:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case McpConnectionStatus.error:
        return const Icon(Icons.circle, color: Colors.red, size: 12);
      case McpConnectionStatus.disconnected:
        return const Icon(Icons.circle, color: Colors.grey, size: 12);
    }
  }

  Widget _transportBadge(McpTransportType type, ColorScheme colorScheme) {
    final (label, color) = switch (type) {
      McpTransportType.stdio => ('stdio', colorScheme.tertiary),
      McpTransportType.sse => ('SSE', colorScheme.primary),
      McpTransportType.streamableHttp => ('HTTP', colorScheme.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  void _toggleConnection(
    BuildContext context,
    WidgetRef ref,
    McpServerConfig server,
    McpConnectionStatus status,
  ) async {
    if (status == McpConnectionStatus.connected) {
      ref.read(mcpConnectionsProvider.notifier).disconnect(server.id);
      return;
    }
    try {
      final tools = await ref
          .read(mcpConnectionsProvider.notifier)
          .connect(server);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.mcpConnectSuccess(tools.length))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final detail = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.s.mcpConnectFailedWithDetail(detail),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  void _showServerDialog(BuildContext context, WidgetRef ref) {
    McpPageBody.showServerDialog(context, ref, server);
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String serverId,
    String serverName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.mcpDeleteTitle),
        content: Text(context.s.mcpDeleteConfirm(serverName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mcpServersProvider.notifier).remove(serverId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// 新增 MCP 卡片 (虚线占位)
class _AddMcpCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddMcpCard({required this.onTap});

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
                  Icon(Icons.add, size: 28, color: colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    context.s.mcpAdd,
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

/// MCP 服务器配置表单对话框（支持多传输类型）
class _McpServerFormDialog extends StatefulWidget {
  final McpServerConfig? existing;
  final void Function(McpServerConfig config) onSave;

  const _McpServerFormDialog({this.existing, required this.onSave});

  @override
  State<_McpServerFormDialog> createState() => _McpServerFormDialogState();
}

class _McpServerFormDialogState extends State<_McpServerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late McpTransportType _transportType;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _commandCtrl;
  late final TextEditingController _argsCtrl;
  late final TextEditingController _cwdCtrl;
  late final TextEditingController _envCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _transportType = e?.transportType ?? McpTransportType.stdio;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _commandCtrl = TextEditingController(text: e?.command ?? '');
    _argsCtrl = TextEditingController(text: e?.args.join(' ') ?? '');
    _cwdCtrl = TextEditingController(text: e?.cwd ?? '');
    _envCtrl = TextEditingController(
      text: e?.env.entries.map((e) => '${e.key}=${e.value}').join('\n') ?? '',
    );
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _headersCtrl = TextEditingController(
      text:
          e?.httpHeaders.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n') ??
          '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _commandCtrl.dispose();
    _argsCtrl.dispose();
    _cwdCtrl.dispose();
    _envCtrl.dispose();
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? context.s.mcpEditTitle : context.s.mcpAddTitle),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 传输类型选择
                _buildTransportSelector(),
                const SizedBox(height: 16),
                // 名称
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: context.s.mcpFormName,
                    hintText: context.s.mcpNameHint,
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? context.s.mcpFormNameRequired
                      : null,
                ),
                const SizedBox(height: 12),
                // 根据传输类型显示不同字段
                if (_transportType == McpTransportType.stdio) ...[
                  _buildStdioFields(),
                ] else ...[
                  _buildHttpFields(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.commonCancel),
        ),
        FilledButton(
          onPressed: _onSubmit,
          child: Text(isEdit ? context.s.commonSave : context.s.mcpAdd2),
        ),
      ],
    );
  }

  Widget _buildTransportSelector() {
    return SegmentedButton<McpTransportType>(
      segments: const [
        ButtonSegment(
          value: McpTransportType.stdio,
          label: Text('Stdio'),
          icon: Icon(Icons.terminal, size: 16),
        ),
        ButtonSegment(
          value: McpTransportType.sse,
          label: Text('SSE'),
          icon: Icon(Icons.sync_alt, size: 16),
        ),
        ButtonSegment(
          value: McpTransportType.streamableHttp,
          label: Text('HTTP'),
          icon: Icon(Icons.http, size: 16),
        ),
      ],
      selected: {_transportType},
      onSelectionChanged: (set) => setState(() => _transportType = set.first),
    );
  }

  Widget _buildStdioFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _commandCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormCommand,
            hintText: context.s.mcpCommandHint,
          ),
          validator: (v) =>
              _transportType == McpTransportType.stdio &&
                  (v == null || v.isEmpty)
              ? context.s.mcpFormCommandRequired
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _argsCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormArgs,
            hintText: context.s.mcpArgsHint,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cwdCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormCwd,
            hintText: context.s.mcpCwdHint,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _envCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormEnv,
            hintText: context.s.mcpEnvHint,
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildHttpFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormUrl,
            hintText: _transportType == McpTransportType.sse
                ? context.s.mcpSseHint
                : context.s.mcpStreamableHint,
          ),
          validator: (v) =>
              _transportType != McpTransportType.stdio &&
                  (v == null || v.isEmpty)
              ? context.s.mcpFormUrlRequired
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _headersCtrl,
          decoration: InputDecoration(
            labelText: context.s.mcpFormHeaders,
            hintText: context.s.mcpHeaderHint,
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;

    final args = _argsCtrl.text.trim().isEmpty
        ? <String>[]
        : _argsCtrl.text.trim().split(RegExp(r'\s+'));

    final env = <String, String>{};
    for (final line in _envCtrl.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex > 0) {
        env[trimmed.substring(0, eqIndex)] = trimmed.substring(eqIndex + 1);
      }
    }

    final httpHeaders = <String, String>{};
    for (final line in _headersCtrl.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        httpHeaders[trimmed.substring(0, colonIndex).trim()] = trimmed
            .substring(colonIndex + 1)
            .trim();
      }
    }

    Navigator.pop(context);

    if (widget.existing == null) {
      // 创建新的 — 用 copyWith 会缺少 id/createdAt，这里直接传参数给 onSave
      // onSave 内部会调用 notifier.add(...)
      widget.onSave(
        McpServerConfig(
          id: '', // 占位，add 时由 registry 生成
          name: _nameCtrl.text.trim(),
          transportType: _transportType,
          command: _commandCtrl.text.trim(),
          args: args,
          env: env,
          cwd: _cwdCtrl.text.trim(),
          url: _urlCtrl.text.trim(),
          httpHeaders: httpHeaders,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      widget.onSave(
        widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          transportType: _transportType,
          command: _commandCtrl.text.trim(),
          args: args,
          env: env,
          cwd: _cwdCtrl.text.trim(),
          url: _urlCtrl.text.trim(),
          httpHeaders: httpHeaders,
        ),
      );
    }
  }
}

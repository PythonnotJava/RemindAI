import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// 添加向导第一步：让用户选一个"要连什么"的意图，而不是一上来
/// 就丢给他一堆技术字段
enum _AddIntent {
  /// 尚未选择（仅在新增流程首屏使用）
  none,

  /// 一个 npx / uvx 包（最常见 —— 官方 server 都走这条路）
  npmPackage,

  /// 一段本地脚本 (Python / Node / 任意可执行文件)
  localScript,

  /// 远程 SSE / HTTP endpoint
  remoteUrl,

  /// 手动填全部字段（等价于原来的编辑模式）
  advanced,
}

class _McpServerFormDialogState extends State<_McpServerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late McpTransportType _transportType;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cmdLineCtrl; // 完整命令行 (command + args)
  late final TextEditingController _cwdCtrl;
  late final TextEditingController _envCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headersCtrl;

  /// 当前对话框处于哪个流程页
  ///
  /// - 新增: 初始为 none，用户点某个卡片后切到对应 intent
  /// - 编辑: 直接进 advanced（保持完整字段可编辑）
  _AddIntent _intent = _AddIntent.none;

  /// 高级模式（第二屏底部的可折叠 env / cwd / headers）是否展开
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _transportType = e?.transportType ?? McpTransportType.stdio;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    // 把 command + args 合为一行显示，方便用户编辑
    _cmdLineCtrl = TextEditingController(text: _buildCmdLine(e));
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

    // 编辑现有配置时跳过选类型页，直接进高级表单
    if (widget.existing != null) {
      _intent = _AddIntent.advanced;
      _advancedExpanded = true;
    }
  }

  /// 从现有配置构建完整命令行展示文本
  String _buildCmdLine(McpServerConfig? config) {
    if (config == null) return '';
    final parts = <String>[];
    if (config.command.isNotEmpty) {
      parts.add(_quoteIfNeeded(config.command));
    }
    for (final arg in config.args) {
      parts.add(_quoteIfNeeded(arg));
    }
    return parts.join(' ');
  }

  /// 含空格的路径加引号
  String _quoteIfNeeded(String s) {
    if (s.contains(' ') && !s.startsWith('"')) return '"$s"';
    return s;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cmdLineCtrl.dispose();
    _cwdCtrl.dispose();
    _envCtrl.dispose();
    _urlCtrl.dispose();
    _headersCtrl.dispose();
    _packageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    // ========== 第一屏: 选择"你要添加什么"意图 ==========
    if (!isEdit && _intent == _AddIntent.none) {
      return AlertDialog(
        title: Text(context.s.mcpAddTitle),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择你要添加的 MCP 服务类型',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _IntentCard(
                  icon: Icons.rocket_launch_outlined,
                  title: '常用模板',
                  subtitle: '一键填充官方 MCP server（filesystem / github 等）',
                  accent: true,
                  onTap: () => _pickTemplate(),
                ),
                _IntentCard(
                  icon: Icons.content_paste_go,
                  title: '从 JSON 粘贴',
                  subtitle: '兼容 Claude Desktop / Cursor 配置格式',
                  onTap: () => _importFromJson(),
                ),
                _IntentCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'npm / uvx 包',
                  subtitle: '通过 npx 或 uvx 运行的官方/第三方 server',
                  onTap: () => _enterIntent(_AddIntent.npmPackage),
                ),
                _IntentCard(
                  icon: Icons.description_outlined,
                  title: '本地脚本',
                  subtitle: '你自己写的 Python / Node / 可执行文件',
                  onTap: () => _enterIntent(_AddIntent.localScript),
                ),
                _IntentCard(
                  icon: Icons.cloud_outlined,
                  title: '远程 URL',
                  subtitle: 'SSE 或 Streamable HTTP endpoint',
                  onTap: () => _enterIntent(_AddIntent.remoteUrl),
                ),
                const Divider(height: 24),
                _IntentCard(
                  icon: Icons.tune,
                  title: '手动配置（高级）',
                  subtitle: '完整字段可编辑，适合已经知道要填什么的用户',
                  compact: true,
                  onTap: () => _enterIntent(_AddIntent.advanced),
                ),
              ],
            ),
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

    // ========== 第二屏: 根据意图显示对应表单 ==========
    return AlertDialog(
      title: Row(
        children: [
          if (!isEdit)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: '返回',
              visualDensity: VisualDensity.compact,
              onPressed: _backToIntentPicker,
            ),
          Expanded(
            child: Text(
              isEdit ? context.s.mcpEditTitle : _intentTitle(_intent),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // advanced 模式才显示传输类型切换，其它意图已被固定
                if (_intent == _AddIntent.advanced) ...[
                  _buildTransportSelector(),
                  const SizedBox(height: 16),
                ],
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
                // 按意图渲染核心字段（advanced 走完整表单）
                ..._buildIntentBody(),
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

  // ==================== 向导辅助 ====================

  /// 进入某个意图对应的第二屏，同时预设传输类型
  void _enterIntent(_AddIntent intent) {
    setState(() {
      _intent = intent;
      switch (intent) {
        case _AddIntent.npmPackage:
        case _AddIntent.localScript:
          _transportType = McpTransportType.stdio;
          break;
        case _AddIntent.remoteUrl:
          if (_transportType == McpTransportType.stdio) {
            _transportType = McpTransportType.streamableHttp;
          }
          break;
        case _AddIntent.advanced:
          _advancedExpanded = true;
          break;
        default:
          break;
      }
    });
  }

  /// 返回意图选择首屏
  void _backToIntentPicker() {
    setState(() {
      _intent = _AddIntent.none;
      _advancedExpanded = false;
    });
  }

  String _intentTitle(_AddIntent intent) {
    switch (intent) {
      case _AddIntent.npmPackage:
        return '添加 npm / uvx 包';
      case _AddIntent.localScript:
        return '添加本地脚本';
      case _AddIntent.remoteUrl:
        return '添加远程 URL';
      case _AddIntent.advanced:
        return '手动配置';
      default:
        return context.s.mcpAddTitle;
    }
  }

  /// 按当前意图渲染核心表单区（不含名称字段）
  List<Widget> _buildIntentBody() {
    switch (_intent) {
      case _AddIntent.npmPackage:
        return _buildNpmPackageBody();
      case _AddIntent.localScript:
        return _buildLocalScriptBody();
      case _AddIntent.remoteUrl:
        return _buildRemoteUrlBody();
      case _AddIntent.advanced:
      default:
        // 编辑模式和"手动配置"意图都走完整表单
        return [
          if (_transportType == McpTransportType.stdio)
            _buildStdioFields()
          else
            _buildHttpFields(),
        ];
    }
  }

  // ---------- npm / uvx 包意图 ----------
  List<Widget> _buildNpmPackageBody() {
    return [
      _RunnerSelector(
        selected: _detectRunner(),
        onChanged: (runner) {
          setState(() {
            final rest = _extractPackageAndArgs();
            _cmdLineCtrl.text = _joinRunnerCmd(runner, rest);
          });
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _packageCtrl,
        decoration: const InputDecoration(
          labelText: '包名 + 参数',
          hintText: '@modelcontextprotocol/server-filesystem /path',
          helperText: '直接写包名即可，无需前缀 npx / uvx',
        ),
        onChanged: (v) {
          final runner = _detectRunner();
          _cmdLineCtrl.text = _joinRunnerCmd(runner, v.trim());
        },
        validator: (v) => (v == null || v.trim().isEmpty)
            ? context.s.mcpFormCommandRequired
            : null,
      ),
      const SizedBox(height: 8),
      _buildParsePreview(),
      const SizedBox(height: 12),
      _buildAdvancedFold(showCwd: true, showEnv: true, showHeaders: false),
    ];
  }

  // ---------- 本地脚本意图 ----------
  List<Widget> _buildLocalScriptBody() {
    return [
      _buildCommandLineField(
        required: true,
        labelOverride: '完整启动命令',
        hintOverride: r'python "C:\path\main.py" --port 8080',
      ),
      const SizedBox(height: 4),
      Text(
        '含空格的路径请用双引号包裹。例: uv run "C:\\My Projects\\main.py"',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      _buildAdvancedFold(showCwd: true, showEnv: true, showHeaders: false),
    ];
  }

  // ---------- 远程 URL 意图 ----------
  List<Widget> _buildRemoteUrlBody() {
    return [
      SegmentedButton<McpTransportType>(
        segments: const [
          ButtonSegment(
            value: McpTransportType.streamableHttp,
            label: Text('HTTP'),
            icon: Icon(Icons.http, size: 14),
          ),
          ButtonSegment(
            value: McpTransportType.sse,
            label: Text('SSE'),
            icon: Icon(Icons.sync_alt, size: 14),
          ),
        ],
        selected: {_transportType},
        onSelectionChanged: (set) => setState(() => _transportType = set.first),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _urlCtrl,
        decoration: InputDecoration(
          labelText: context.s.mcpFormUrl,
          hintText: _transportType == McpTransportType.sse
              ? context.s.mcpSseHint
              : context.s.mcpStreamableHint,
        ),
        validator: (v) => (v == null || v.trim().isEmpty)
            ? context.s.mcpFormUrlRequired
            : null,
      ),
      const SizedBox(height: 12),
      _buildAdvancedFold(showCwd: false, showEnv: false, showHeaders: true),
    ];
  }

  /// 折叠的"高级选项"区块 —— 把 cwd / env / headers 收起来避免视觉噪声
  Widget _buildAdvancedFold({
    required bool showCwd,
    required bool showEnv,
    required bool showHeaders,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _advancedExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '高级选项',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_advancedExpanded) ...[
          const SizedBox(height: 4),
          if (showCwd) ...[
            TextFormField(
              controller: _cwdCtrl,
              decoration: InputDecoration(
                labelText: context.s.mcpFormCwd,
                hintText: context.s.mcpCwdHint,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showEnv) ...[
            TextFormField(
              controller: _envCtrl,
              decoration: InputDecoration(
                labelText: context.s.mcpFormEnv,
                hintText: context.s.mcpEnvHint,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
          ],
          if (showHeaders) ...[
            TextFormField(
              controller: _headersCtrl,
              decoration: InputDecoration(
                labelText: context.s.mcpFormHeaders,
                hintText: context.s.mcpHeaderHint,
              ),
              maxLines: 3,
            ),
          ],
        ],
      ],
    );
  }

  // ---------- npm 意图辅助: 拆解 / 重组 runner + 包 ----------

  /// 用于 npm 意图页面的"包名+参数"输入框
  ///
  /// 注意: 这是一个衍生视图，实际数据仍存在 _cmdLineCtrl 中；
  /// 该 controller 只在 npm 意图页面内使用，同步策略见 _packageCtrl getter。
  late final TextEditingController _packageCtrl = TextEditingController(
    text: _extractPackageAndArgs(),
  );

  /// 检测当前命令行使用的 runner
  String _detectRunner() {
    final tokens = _parseCmdLine(_cmdLineCtrl.text.trim());
    if (tokens.isEmpty) return 'npx';
    final first = tokens.first.toLowerCase();
    if (first == 'uvx' || first == 'uv') return 'uvx';
    if (first == 'pnpm') return 'pnpm';
    if (first == 'bunx' || first == 'bun') return 'bunx';
    return 'npx';
  }

  /// 从命令行中去掉 runner 部分，只保留包名+参数
  String _extractPackageAndArgs() {
    final tokens = _parseCmdLine(_cmdLineCtrl.text.trim());
    if (tokens.isEmpty) return '';
    final first = tokens.first.toLowerCase();
    List<String> rest;
    if (first == 'npx') {
      // 去掉可能存在的 -y / --yes 标志
      rest = tokens.sublist(1);
      if (rest.isNotEmpty && (rest.first == '-y' || rest.first == '--yes')) {
        rest = rest.sublist(1);
      }
    } else if (first == 'uvx' || first == 'uv') {
      rest = tokens.sublist(1);
      if (first == 'uv' && rest.isNotEmpty && rest.first == 'run') {
        rest = rest.sublist(1);
      }
    } else if (first == 'pnpm' || first == 'bunx' || first == 'bun') {
      rest = tokens.sublist(1);
      if (first == 'bun' && rest.isNotEmpty && rest.first == 'x') {
        rest = rest.sublist(1);
      }
    } else {
      // 未识别 runner，整体作为包+参数
      rest = tokens;
    }
    return rest.map(_quoteIfNeeded).join(' ');
  }

  /// 根据 runner + 包名 参数 拼回完整命令行
  String _joinRunnerCmd(String runner, String pkgAndArgs) {
    final trimmed = pkgAndArgs.trim();
    if (trimmed.isEmpty) return '';
    switch (runner) {
      case 'uvx':
        return 'uvx $trimmed';
      case 'pnpm':
        return 'pnpm dlx $trimmed';
      case 'bunx':
        return 'bunx $trimmed';
      case 'npx':
      default:
        return 'npx -y $trimmed';
    }
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
        _buildCommandLineField(required: true),
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
        const SizedBox(height: 20),
        _buildLocalProcessSection(),
      ],
    );
  }

  /// SSE/HTTP 模式下"可选的本地进程启动"分区——部分 MCP server 对外是
  /// SSE/HTTP 接口，但本身是需要先手动跑起来的本地进程。这里允许用户
  /// 一并填写启动命令，留空则保持原来的纯远程连接行为不变。
  Widget _buildLocalProcessSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.terminal,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              context.s.mcpLocalProcessSectionTitle,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.s.mcpLocalProcessSectionHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _buildCommandLineField(
          required: false,
          labelOverride: '启动命令 (可选)',
          hintOverride: 'python main.py --port 8080',
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

  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // Shell-aware 命令行解析: 支持引号包裹含空格路径
    final parsed = _parseCmdLine(_cmdLineCtrl.text.trim());
    final command = parsed.isNotEmpty ? parsed.first : '';
    final args = parsed.length > 1 ? parsed.sublist(1) : <String>[];

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
      widget.onSave(
        McpServerConfig(
          id: '',
          name: _nameCtrl.text.trim(),
          transportType: _transportType,
          command: command,
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
          command: command,
          args: args,
          env: env,
          cwd: _cwdCtrl.text.trim(),
          url: _urlCtrl.text.trim(),
          httpHeaders: httpHeaders,
        ),
      );
    }
  }

  /// 带实时解析预览的命令行输入组件
  Widget _buildCommandLineField({
    required bool required,
    String? labelOverride,
    String? hintOverride,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _cmdLineCtrl,
          decoration: InputDecoration(
            labelText: labelOverride ?? '命令行',
            hintText: hintOverride ?? 'npx -y @anthropic/mcp-server',
            suffixIcon: Tooltip(
              message:
                  '直接粘贴完整命令行\n'
                  '含空格的路径请用双引号包裹\n'
                  '例: uv run "C:\\My Projects\\main.py"',
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? context.s.mcpFormCommandRequired
              : null,
          maxLines: 1,
          onChanged: (_) => setState(() {}),
        ),
        // 解析预览：当用户输入内容时显示实际解析结果
        if (_cmdLineCtrl.text.trim().isNotEmpty) _buildParsePreview(),
      ],
    );
  }

  /// 命令解析预览标签
  Widget _buildParsePreview() {
    final parsed = _parseCmdLine(_cmdLineCtrl.text.trim());
    if (parsed.isEmpty) return const SizedBox.shrink();

    final command = parsed.first;
    final args = parsed.length > 1 ? parsed.sublist(1) : <String>[];

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.arrow_right, size: 14, color: colorScheme.primary),
          _parseChip(command, colorScheme.primary, '可执行程序'),
          for (final arg in args) _parseChip(arg, colorScheme.tertiary, '参数'),
        ],
      ),
    );
  }

  Widget _parseChip(String text, Color color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, fontFamily: 'Consolas', color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Shell-aware 命令行解析。
  ///
  /// 支持:
  /// - 空格分隔参数: `npx -y @anthropic/mcp`
  /// - 双引号包裹含空格路径: `python "C:\path with spaces\main.py"`
  /// - 无引号的普通路径: `uv run C:\Users\test\main.py`
  List<String> _parseCmdLine(String input) {
    if (input.isEmpty) return [];

    final tokens = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ' ' && !inQuotes) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }

  // ==================== JSON 导入 ====================

  /// 弹出 JSON 粘贴对话框，兼容 Claude Desktop / Cursor 官方格式：
  /// ```json
  /// {
  ///   "mcpServers": {
  ///     "filesystem": {
  ///       "command": "npx",
  ///       "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
  ///       "env": {"KEY": "VAL"}
  ///     }
  ///   }
  /// }
  /// ```
  /// 也支持单条条目直接粘贴（去掉外层 mcpServers 包裹）。
  Future<void> _importFromJson() async {
    final jsonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从 JSON 导入'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '兼容 Claude Desktop / Cursor 的 mcpServers 配置格式。可直接从官方文档复制粘贴。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: jsonCtrl,
                maxLines: 12,
                minLines: 8,
                autofocus: true,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                decoration: const InputDecoration(
                  hintText:
                      '{\n  "mcpServers": {\n    "filesystem": {\n      "command": "npx",\n      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"]\n    }\n  }\n}',
                  hintStyle: TextStyle(fontSize: 11),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('从剪贴板粘贴'),
                  onPressed: () async {
                    final clip = await Clipboard.getData(Clipboard.kTextPlain);
                    if (clip?.text != null) {
                      jsonCtrl.text = clip!.text!;
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      _applyJsonPayload(jsonCtrl.text);
      if (!mounted) return;
      // 导入成功后切到高级视图，让用户核对全部字段
      setState(() {
        _intent = _AddIntent.advanced;
        _advancedExpanded = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已导入 JSON 配置，请检查后保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('JSON 解析失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 把 JSON 内容解析并填充到表单
  void _applyJsonPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('JSON 内容为空');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException('顶层必须是对象');
    }

    // 支持两种结构：{ "mcpServers": { "name": {...} } } 或直接 { "command": "...", ... }
    Map<String, dynamic>? entry;
    String? entryName;

    if (decoded['mcpServers'] is Map) {
      final servers = decoded['mcpServers'] as Map;
      if (servers.isEmpty) throw const FormatException('mcpServers 为空');
      final firstKey = servers.keys.first.toString();
      entryName = firstKey;
      entry = Map<String, dynamic>.from(servers[firstKey] as Map);
    } else if (decoded['command'] != null ||
        decoded['url'] != null ||
        decoded['args'] != null) {
      entry = Map<String, dynamic>.from(decoded);
      entryName = decoded['name']?.toString();
    } else {
      // 也许用户直接把 { "filesystem": {...} } 粘进来
      final firstKey = decoded.keys.first.toString();
      final firstVal = decoded[firstKey];
      if (firstVal is Map) {
        entryName = firstKey;
        entry = Map<String, dynamic>.from(firstVal);
      }
    }

    if (entry == null) {
      throw const FormatException('无法识别配置结构');
    }

    // 名称
    if (entryName != null && entryName.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = entryName;
    }

    // 传输类型 & URL
    final url = entry['url']?.toString() ?? '';
    if (url.isNotEmpty) {
      final type = entry['type']?.toString().toLowerCase();
      if (type == 'sse') {
        _transportType = McpTransportType.sse;
      } else if (type == 'http' ||
          type == 'streamable-http' ||
          type == 'streamablehttp') {
        _transportType = McpTransportType.streamableHttp;
      } else {
        // 根据 URL 后缀猜一下
        _transportType = url.contains('/sse')
            ? McpTransportType.sse
            : McpTransportType.streamableHttp;
      }
      _urlCtrl.text = url;
    } else {
      _transportType = McpTransportType.stdio;
    }

    // 命令行
    final command = entry['command']?.toString() ?? '';
    final argsRaw = entry['args'];
    final args = <String>[];
    if (argsRaw is List) {
      for (final a in argsRaw) {
        args.add(a.toString());
      }
    }
    if (command.isNotEmpty || args.isNotEmpty) {
      final parts = <String>[];
      if (command.isNotEmpty) parts.add(_quoteIfNeeded(command));
      for (final a in args) {
        parts.add(_quoteIfNeeded(a));
      }
      _cmdLineCtrl.text = parts.join(' ');
    }

    // 环境变量
    final envRaw = entry['env'];
    if (envRaw is Map) {
      _envCtrl.text = envRaw.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n');
    }

    // 工作目录
    final cwd = entry['cwd']?.toString() ?? '';
    if (cwd.isNotEmpty) _cwdCtrl.text = cwd;

    // 请求头
    final headersRaw = entry['headers'] ?? entry['httpHeaders'];
    if (headersRaw is Map) {
      _headersCtrl.text = headersRaw.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
    }

    setState(() {});
  }

  // ==================== 常用模板 ====================

  /// 常用 MCP server 预设，一键填充
  static final List<_McpTemplate> _templates = [
    _McpTemplate(
      icon: Icons.folder_outlined,
      name: 'filesystem',
      description: '文件系统访问（读写指定目录）',
      cmdLine: 'npx -y @modelcontextprotocol/server-filesystem <目录路径>',
    ),
    _McpTemplate(
      icon: Icons.psychology_outlined,
      name: 'memory',
      description: '持久化知识图谱记忆',
      cmdLine: 'npx -y @modelcontextprotocol/server-memory',
    ),
    _McpTemplate(
      icon: Icons.travel_explore,
      name: 'fetch',
      description: '抓取网页内容为 Markdown',
      cmdLine: 'uvx mcp-server-fetch',
    ),
    _McpTemplate(
      icon: Icons.terminal,
      name: 'sequential-thinking',
      description: '分步思考推理',
      cmdLine: 'npx -y @modelcontextprotocol/server-sequential-thinking',
    ),
    _McpTemplate(
      icon: Icons.code,
      name: 'github',
      description: 'GitHub 仓库/PR/Issue 操作',
      cmdLine: 'npx -y @modelcontextprotocol/server-github',
      env: 'GITHUB_PERSONAL_ACCESS_TOKEN=<你的 token>',
    ),
    _McpTemplate(
      icon: Icons.storage,
      name: 'sqlite',
      description: '查询本地 SQLite 数据库',
      cmdLine: 'uvx mcp-server-sqlite --db-path <db 路径>',
    ),
  ];

  Future<void> _pickTemplate() async {
    final picked = await showDialog<_McpTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择常用模板'),
        children: [
          for (final t in _templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    t.icon,
                    size: 20,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          t.description,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.cmdLine,
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _transportType = McpTransportType.stdio;
      if (_nameCtrl.text.isEmpty) _nameCtrl.text = picked.name;
      _cmdLineCtrl.text = picked.cmdLine;
      _packageCtrl.text = _extractPackageAndArgs();
      if (picked.env != null) {
        _envCtrl.text = picked.env!;
      }
      // 选完模板后进 npm 意图页，露出包名字段方便替换占位符
      _intent = _AddIntent.npmPackage;
      _advancedExpanded = picked.env != null;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已填充 ${picked.name} 模板，请替换 <> 占位符')));
  }
}

/// 意图选择卡片（第一屏用的大按钮）
class _IntentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  final bool compact;

  const _IntentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = accent
        ? cs.primaryContainer.withValues(alpha: 0.5)
        : cs.surfaceContainerHighest.withValues(alpha: 0.5);
    final borderColor = accent
        ? cs.primary.withValues(alpha: 0.5)
        : cs.outlineVariant;
    final iconColor = accent ? cs.primary : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 10 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: compact ? 20 : 24, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// npm 意图的 runner 选择器（npx / uvx / pnpm dlx / bunx）
class _RunnerSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RunnerSelector({required this.selected, required this.onChanged});

  static const _runners = <(String, String)>[
    ('npx', 'npx'),
    ('uvx', 'uvx'),
    ('pnpm', 'pnpm dlx'),
    ('bunx', 'bunx'),
  ];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: [
        for (final (value, label) in _runners)
          ButtonSegment(value: value, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (set) => onChanged(set.first),
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

/// 模板项定义
class _McpTemplate {
  final IconData icon;
  final String name;
  final String description;
  final String cmdLine;
  final String? env;

  const _McpTemplate({
    required this.icon,
    required this.name,
    required this.description,
    required this.cmdLine,
    this.env,
  });
}

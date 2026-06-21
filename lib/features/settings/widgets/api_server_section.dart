import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/server/api_server_config.dart';
import '../../../providers/api_server_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/mcp_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/skills_provider.dart';
import '../../../core/search/search_config.dart';

/// 对外 API 服务设置区块。
///
/// 让用户开关服务、配置端口/令牌, 并选择性绑定模型/技能/MCP/记忆/搜索。
/// 完全独立于主程序会话状态。
class ApiServerSection extends ConsumerWidget {
  const ApiServerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(apiServerConfigProvider);
    return configAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.s.apiServerLoadFailed(e)),
        ),
      ),
      data: (config) => _ApiServerCard(config: config),
    );
  }
}

class _ApiServerCard extends ConsumerStatefulWidget {
  final ApiServerConfig config;
  const _ApiServerCard({required this.config});

  @override
  ConsumerState<_ApiServerCard> createState() => _ApiServerCardState();
}

class _ApiServerCardState extends ConsumerState<_ApiServerCard> {
  late TextEditingController _portCtrl;
  late TextEditingController _tokenCtrl;
  late TextEditingController _ipCtrl;
  late ApiServerConfig _draft;

  /// 令牌输入框是否隐藏明文
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _draft = widget.config;
    _portCtrl = TextEditingController(text: _draft.port.toString());
    _tokenCtrl = TextEditingController(text: _draft.token);
    _ipCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _persist(ApiServerConfig next) async {
    setState(() => _draft = next);
    await ref.read(apiServerConfigProvider.notifier).save(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = context.s;
    final server = ref.watch(apiServerProvider);
    final running = server.isRunning;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 开关 + 运行状态
            Row(
              children: [
                Icon(Icons.lan_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.apiServerTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        running
                            ? s.apiServerRunningPort(server.boundPort ?? 0)
                            : s.apiServerStopped,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: running ? Colors.green : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _draft.enabled,
                  onChanged: (v) => _persist(_draft.copyWith(enabled: v)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.apiServerIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),

            if (_draft.enabled) ...[
              const Divider(height: 28),

              // 端口 + 令牌
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: s.apiServerPort,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        final p = int.tryParse(v) ?? 1228;
                        _persist(_draft.copyWith(port: p));
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _tokenCtrl,
                      obscureText: _obscureToken,
                      decoration: InputDecoration(
                        labelText: s.apiServerToken,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _obscureToken
                                  ? s.apiServerTokenShow
                                  : s.apiServerTokenHide,
                              icon: Icon(
                                _obscureToken
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureToken = !_obscureToken),
                            ),
                            IconButton(
                              tooltip: s.apiServerTokenRandom,
                              icon: const Icon(Icons.casino_outlined, size: 18),
                              onPressed: () {
                                final t = _genToken();
                                _tokenCtrl.text = t;
                                _persist(_draft.copyWith(token: t));
                              },
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (v) =>
                          _persist(_draft.copyWith(token: v.trim())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final p = int.tryParse(_portCtrl.text) ?? 1228;
                      _persist(
                        _draft.copyWith(port: p, token: _tokenCtrl.text.trim()),
                      );
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(s.apiServerSaveRestart),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: running ? _openInBrowser : null,
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: Text(s.apiServerTestInBrowser),
                  ),
                ],
              ),

              const Divider(height: 28),
              _buildProtocolToggle(theme, cs),
              const Divider(height: 28),
              _buildModelSelector(theme),
              const SizedBox(height: 16),
              _buildMemorySelector(theme),
              const SizedBox(height: 16),
              _buildSearchSelector(theme),
              const SizedBox(height: 16),
              _buildSkillSelector(theme),
              const SizedBox(height: 16),
              _buildMcpSelector(theme),
              const SizedBox(height: 16),
              _buildBindAllToggle(theme, cs),
              if (_draft.bindAll) ...[
                const SizedBox(height: 16),
                _buildIpWhitelist(theme, cs),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _genToken() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'rk_${now.toRadixString(36)}${now.hashCode.toRadixString(36)}';
  }

  /// 在浏览器打开正在运行的服务地址 (用于快速测试连通性)。
  /// 用无需鉴权的 /health 探活端点, 浏览器直接可见 {"status":"ok"}。
  Future<void> _openInBrowser() async {
    final server = ref.read(apiServerProvider);
    final port = server.boundPort ?? _draft.port;
    final uri = Uri.parse('http://127.0.0.1:$port/health');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.apiServerTestInBrowserFailed(uri.toString()))),
      );
    }
  }

  Widget _fieldLabel(ThemeData theme, String text, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // 协议模式: 三个独立端点开关 (OpenAI 聚合 / Claude 聚合 / Claude 纯代理)
  Widget _buildProtocolToggle(ThemeData theme, ColorScheme cs) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(
          theme,
          s.apiServerProtocolTitle,
          hint: s.apiServerProtocolHint,
        ),
        _buildEndpointTile(
          theme,
          cs,
          icon: Icons.api_outlined,
          title: s.apiServerOpenAiAggTitle,
          path: 'POST /v1/chat/completions',
          desc: s.apiServerOpenAiAggDesc,
          value: _draft.enableOpenAi,
          onChanged: (v) => _persist(_draft.copyWith(enableOpenAi: v)),
        ),
        const SizedBox(height: 10),
        _buildEndpointTile(
          theme,
          cs,
          icon: Icons.hub_outlined,
          title: s.apiServerClaudeAggTitle,
          path: 'POST /v1/agent/messages',
          desc: s.apiServerClaudeAggDesc,
          value: _draft.enableClaudeAgent,
          onChanged: (v) => _persist(_draft.copyWith(enableClaudeAgent: v)),
        ),
        const SizedBox(height: 10),
        _buildEndpointTile(
          theme,
          cs,
          icon: Icons.bolt_outlined,
          title: s.apiServerClaudeProxyTitle,
          path: 'POST /v1/messages',
          desc: s.apiServerClaudeProxyDesc,
          value: _draft.enableClaudeProxy,
          onChanged: (v) => _persist(_draft.copyWith(enableClaudeProxy: v)),
        ),
      ],
    );
  }

  /// 单个端点开关卡片。
  Widget _buildEndpointTile(
    ThemeData theme,
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String path,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: value ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        path,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // 模型卡白名单 (多选): 勾选哪些模型卡对外开放; 全不选 = 开放全部
  Widget _buildModelSelector(ThemeData theme) {
    final s = context.s;
    final cards = ref.watch(modelCardsProvider).valueOrNull ?? const [];
    final selected = _draft.allowedModelCardIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(theme, s.apiServerModelsTitle, hint: s.apiServerModelsHint),
        if (cards.isEmpty)
          Text(
            s.apiServerModelsEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else ...[
          if (selected.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.apiServerModelsAllOpen,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cards.map((c) {
              final on = selected.contains(c.id);
              return FilterChip(
                label: Text('${c.name} · ${c.modelId}'),
                selected: on,
                onSelected: (v) {
                  final next = {...selected};
                  if (v) {
                    next.add(c.id);
                  } else {
                    next.remove(c.id);
                  }
                  _persist(_draft.copyWith(allowedModelCardIds: next.toList()));
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // 记忆档位选择
  Widget _buildMemorySelector(ThemeData theme) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(theme, s.apiServerMemoryTitle, hint: s.apiServerMemoryHint),
        SegmentedButton<ServerMemoryMode>(
          segments: [
            ButtonSegment(
              value: ServerMemoryMode.none,
              label: Text(s.apiServerMemoryNone),
            ),
            ButtonSegment(
              value: ServerMemoryMode.isolated,
              label: Text(s.apiServerMemoryIsolated),
            ),
            ButtonSegment(
              value: ServerMemoryMode.shared,
              label: Text(s.apiServerMemoryShared),
            ),
          ],
          selected: {_draft.memoryMode},
          showSelectedIcon: false,
          onSelectionChanged: (set) =>
              _persist(_draft.copyWith(memoryMode: set.first)),
        ),
      ],
    );
  }

  // 搜索引擎选择
  Widget _buildSearchSelector(ThemeData theme) {
    final s = context.s;
    final current = SearchProvider.fromId(_draft.searchProviderId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(theme, s.apiServerSearchTitle, hint: s.apiServerSearchHint),
        SegmentedButton<SearchProvider>(
          segments: [
            ButtonSegment(
              value: SearchProvider.none,
              label: Text(s.apiServerSearchOff),
            ),
            const ButtonSegment(
              value: SearchProvider.tavily,
              label: Text('Tavily'),
            ),
            const ButtonSegment(
              value: SearchProvider.brave,
              label: Text('Brave'),
            ),
            const ButtonSegment(
              value: SearchProvider.baidu,
              label: Text('Baidu'),
            ),
          ],
          selected: {current},
          showSelectedIcon: false,
          onSelectionChanged: (set) =>
              _persist(_draft.copyWith(searchProviderId: set.first.id)),
        ),
      ],
    );
  }

  // 技能多选
  Widget _buildSkillSelector(ThemeData theme) {
    final s = context.s;
    final skills = ref.watch(skillsProvider).valueOrNull ?? const [];
    final selected = _draft.skillIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(theme, s.apiServerSkillsTitle, hint: s.apiServerSkillsHint),
        if (skills.isEmpty)
          Text(
            s.apiServerSkillsEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills.map((sk) {
              final on = selected.contains(sk.id);
              return FilterChip(
                label: Text(sk.name),
                selected: on,
                onSelected: (v) {
                  final next = {...selected};
                  if (v) {
                    next.add(sk.id);
                  } else {
                    next.remove(sk.id);
                  }
                  _persist(_draft.copyWith(skillIds: next.toList()));
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  // MCP 多选
  Widget _buildMcpSelector(ThemeData theme) {
    final s = context.s;
    final servers = ref.watch(mcpServersProvider).valueOrNull ?? const [];
    final connState = ref.watch(mcpConnectionsProvider);
    final selected = _draft.mcpServerIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(theme, s.apiServerMcpTitle, hint: s.apiServerMcpHint),
        if (servers.isEmpty)
          Text(
            s.apiServerMcpEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: servers.map((srv) {
              final connected = connState.clients.containsKey(srv.id);
              final on = selected.contains(srv.id);
              return FilterChip(
                avatar: Icon(
                  connected ? Icons.check_circle : Icons.circle_outlined,
                  size: 16,
                  color: connected
                      ? Colors.green
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: Text(srv.name),
                selected: on,
                onSelected: (v) {
                  final next = {...selected};
                  if (v) {
                    next.add(srv.id);
                  } else {
                    next.remove(srv.id);
                  }
                  _persist(_draft.copyWith(mcpServerIds: next.toList()));
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  // 绑定全部网卡 (危险)
  Widget _buildBindAllToggle(ThemeData theme, ColorScheme cs) {
    final s = context.s;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _draft.bindAll ? cs.errorContainer.withValues(alpha: 0.4) : null,
        border: Border.all(
          color: _draft.bindAll ? cs.error : cs.outlineVariant,
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: _draft.bindAll ? cs.error : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.apiServerBindAllTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  s.apiServerBindAllDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _draft.bindAll,
            onChanged: (v) async {
              if (v) {
                final ok = await _confirmBindAll();
                if (!ok) return;
              }
              _persist(_draft.copyWith(bindAll: v));
            },
          ),
        ],
      ),
    );
  }

  // IP 白名单 (仅 bindAll 时显示)
  Widget _buildIpWhitelist(ThemeData theme, ColorScheme cs) {
    final s = context.s;
    final list = _draft.ipWhitelist;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(
            theme,
            s.apiServerIpWhitelistTitle,
            hint: s.apiServerIpWhitelistHint,
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.apiServerIpWhitelistEmpty,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: list.map((ip) {
                  return InputChip(
                    label: Text(ip),
                    onDeleted: () {
                      final next = [...list]..remove(ip);
                      _persist(_draft.copyWith(ipWhitelist: next));
                    },
                  );
                }).toList(),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _ipCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: s.apiServerIpWhitelistInputHint,
                  ),
                  onSubmitted: (_) => _addIp(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _addIp,
                icon: const Icon(Icons.add, size: 16),
                label: Text(s.apiServerIpWhitelistAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addIp() {
    final rule = _ipCtrl.text.trim();
    if (rule.isEmpty) return;
    if (!_isValidIpRule(rule)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.apiServerIpWhitelistInvalid)),
      );
      return;
    }
    if (_draft.ipWhitelist.contains(rule)) {
      _ipCtrl.clear();
      return;
    }
    final next = [..._draft.ipWhitelist, rule];
    _ipCtrl.clear();
    _persist(_draft.copyWith(ipWhitelist: next));
  }

  /// 校验是否为合法 IPv4 或 IPv4 CIDR 网段。
  bool _isValidIpRule(String rule) {
    String ipPart = rule;
    if (rule.contains('/')) {
      final parts = rule.split('/');
      if (parts.length != 2) return false;
      final prefix = int.tryParse(parts[1]);
      if (prefix == null || prefix < 0 || prefix > 32) return false;
      ipPart = parts[0];
    }
    final octets = ipPart.split('.');
    if (octets.length != 4) return false;
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  Future<bool> _confirmBindAll() async {
    final s = context.s;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.apiServerBindAllConfirmTitle),
        content: Text(s.apiServerBindAllConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.apiServerBindAllConfirmCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.apiServerBindAllConfirmOk),
          ),
        ],
      ),
    );
    return r ?? false;
  }
}

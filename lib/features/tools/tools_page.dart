import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../core/tools/tool_plugin.dart';
import '../../core/tools/tool_registry.dart';

/// 工具标签页 — 显示所有已注册工具的网格
class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  String? _activeToolId;

  /// 已打开过的工具分配稳定 key（防止 rebuild 丢状态）
  final Map<String, GlobalKey> _toolKeys = {};

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(toolRegistryProvider);
    final theme = Theme.of(context);
    final isToolActive = _activeToolId != null;

    // 用 IndexedStack 同时保持网格和工具 UI 存活
    return IndexedStack(
      index: isToolActive ? 1 : 0,
      children: [
        // index 0: 工具网格
        _buildGrid(registry, theme),
        // index 1: 当前工具 UI
        _buildToolView(registry, theme),
      ],
    );
  }

  Widget _buildToolView(ToolRegistry registry, ThemeData theme) {
    if (_activeToolId == null) return const SizedBox.shrink();

    final tool = registry.getById(_activeToolId!);
    if (tool == null) return const SizedBox.shrink();

    final config = registry.getConfig(tool.id);
    _toolKeys.putIfAbsent(_activeToolId!, () => GlobalKey());

    return Column(
      key: _toolKeys[_activeToolId!],
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _activeToolId = null),
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: context.s.toolsBack,
              ),
              const SizedBox(width: 8),
              Icon(tool.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                tool.localizedName(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (tool.buildSettings(context, config, (_) {}) != null)
                IconButton(
                  onPressed: () => _showSettings(tool, config),
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: context.s.toolsSettings,
                ),
            ],
          ),
        ),
        Expanded(child: tool.buildUI(context, config)),
      ],
    );
  }

  // PLACEHOLDER_GRID_METHOD

  Widget _buildGrid(ToolRegistry registry, ThemeData theme) {
    final grouped = registry.groupedLocalized(context);

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.build_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(
              context.s.toolsEmpty,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              context.s.toolsTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        ...grouped.entries.expand(
          (entry) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  entry.key,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ToolCard(
                    tool: entry.value[index],
                    onTap: () => _openTool(entry.value[index]),
                    onSettings: () => _showSettings(
                      entry.value[index],
                      registry.getConfig(entry.value[index].id),
                    ),
                  ),
                  childCount: entry.value.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
              ),
            ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _openTool(ToolPlugin tool) {
    setState(() => _activeToolId = tool.id);
  }

  // PLACEHOLDER_SETTINGS_METHOD

  void _showSettings(ToolPlugin tool, config) {
    final registry = ref.read(toolRegistryProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(tool.icon, size: 20),
            const SizedBox(width: 8),
            Text(context.s.toolsSettingsOf(tool.localizedName(context))),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: tool.buildSettings(ctx, registry.getConfig(tool.id), (
            newConfig,
          ) {
            registry.saveConfig(newConfig);
            Navigator.of(ctx).pop();
            setState(() {});
          }),
        ),
      ),
    );
  }
}

/// 工具卡片
class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.onTap,
    required this.onSettings,
  });

  final ToolPlugin tool;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(tool.icon, size: 22, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tool.localizedName(context),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.localizedDescription(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSettings,
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

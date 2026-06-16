import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../models/agent_config.dart';
import '../providers/multi_agent_provider.dart';
import 'agent_badge_dialog.dart';

/// 类似文件管理器的 Agent 列表面板
/// 显示所有 Agent（包括被隐藏的），可调出/隐藏/删除
class AgentExplorer extends ConsumerWidget {
  const AgentExplorer({super.key, required this.onShowAgent});

  /// 当用户点击"显示"某个Agent时回调（用于在Dock中添加面板）
  final ValueChanged<String> onShowAgent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiAgentProvider);
    final theme = Theme.of(context);

    final visible = state.visibleAgents;
    final hidden = state.hiddenAgentList;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 极端压缩：只显示图标
        if (constraints.maxHeight < 60) {
          return Center(
            child: Icon(
              Icons.account_tree,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          );
        }

        final showFooter = constraints.maxHeight >= 160;

        return Container(
          color: theme.colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 列表区域（可滚动，彻底防溢出）
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (visible.isNotEmpty) ...[
                      _SectionHeader(
                        title: context.s.multiAgentActive,
                        count: visible.length,
                      ),
                      ...visible.map(
                        (rt) => _AgentTile(
                          runtime: rt,
                          isHidden: false,
                          onToggle: () {
                            ref
                                .read(multiAgentProvider.notifier)
                                .hideAgent(rt.config.id);
                          },
                          onDelete: rt.config.closable
                              ? () => ref
                                    .read(multiAgentProvider.notifier)
                                    .removeAgent(rt.config.id)
                              : null,
                        ),
                      ),
                    ],
                    if (hidden.isNotEmpty) ...[
                      _SectionHeader(
                        title: context.s.multiAgentHidden,
                        count: hidden.length,
                      ),
                      ...hidden.map(
                        (rt) => _AgentTile(
                          runtime: rt,
                          isHidden: true,
                          onToggle: () {
                            onShowAgent(rt.config.id);
                            ref
                                .read(multiAgentProvider.notifier)
                                .showAgent(rt.config.id);
                          },
                          onDelete: () => ref
                              .read(multiAgentProvider.notifier)
                              .removeAgent(rt.config.id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showFooter)
                // 底部信息
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${context.s.multiAgentTotalAgents}: ${state.agents.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  const _AgentTile({
    required this.runtime,
    required this.isHidden,
    required this.onToggle,
    this.onDelete,
  });

  final AgentRuntime runtime;
  final bool isHidden;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = runtime.config;
    final statusColor = switch (runtime.status) {
      AgentStatus.idle => Colors.green,
      AgentStatus.thinking => Colors.amber,
      AgentStatus.tooling => Colors.blue,
      AgentStatus.error => Colors.red,
    };

    return InkWell(
      onTap: onToggle,
      onLongPress: () => showDialog(
        context: context,
        builder: (_) => AgentBadgeDialog(agentId: runtime.config.id),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 80;
            return Row(
              children: [
                // 状态指示灯
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isHidden ? Colors.grey : statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                // 角色图标
                Icon(config.role.icon, size: 14, color: config.role.color),
                const SizedBox(width: 6),
                // 名称
                Expanded(
                  child: Text(
                    config.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isHidden
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface,
                      decoration: isHidden ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 操作按钮 — 宽度不够时隐藏
                if (!narrow) ...[
                  if (isHidden)
                    Icon(
                      Icons.visibility,
                      size: 14,
                      color: theme.colorScheme.primary,
                    )
                  else
                    Icon(
                      Icons.visibility_off,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: theme.colorScheme.error.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

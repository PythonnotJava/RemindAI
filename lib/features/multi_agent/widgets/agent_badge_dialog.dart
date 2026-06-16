import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../providers/database_provider.dart';
import '../models/agent_config.dart';
import '../providers/multi_agent_provider.dart';

/// Agent 工牌 — 展示 Agent 的完整信息
class AgentBadgeDialog extends ConsumerWidget {
  const AgentBadgeDialog({super.key, required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(multiAgentProvider);
    final runtime = state.agents[agentId];
    if (runtime == null) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.s.agentBadgeNotExist),
        ),
      );
    }

    final config = runtime.config;
    final theme = Theme.of(context);
    final cardsAsync = ref.watch(modelCardsProvider);

    // 找到模型名称
    final modelName =
        cardsAsync.whenOrNull(
          data: (cards) {
            final card = cards
                .where((c) => c.id == config.modelCardId)
                .firstOrNull;
            return card?.name;
          },
        ) ??
        context.s.agentBadgeNotConfigured;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头像区
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: config.role.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: config.role.color, width: 2),
                ),
                child: Icon(
                  config.role.icon,
                  size: 28,
                  color: config.role.color,
                ),
              ),
              const SizedBox(height: 12),
              // 名称
              Text(
                config.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              // 角色标签
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: config.role.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: config.role.color.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  config.role.localizedLabel(context),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: config.role.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // 信息列表
              Expanded(
                child: ListView(
                  children: [
                    _InfoRow(
                      icon: Icons.smart_toy,
                      label: context.s.agentBadgeModel,
                      value: modelName,
                    ),
                    _InfoRow(
                      icon: Icons.fingerprint,
                      label: 'ID',
                      value: config.id.substring(0, 8),
                    ),
                    _InfoRow(
                      icon: Icons.shield,
                      label: context.s.agentBadgePermissions,
                      value: config.permissions.isEmpty
                          ? context.s.agentBadgeNoPermissions
                          : config.permissions.join(', '),
                    ),
                    _InfoRow(
                      icon: Icons.extension,
                      label: context.s.agentBadgeSkills,
                      value: config.enabledSkills.isEmpty
                          ? context.s.agentBadgeNone
                          : config.enabledSkills.join(', '),
                    ),
                    _InfoRow(
                      icon: Icons.build,
                      label: context.s.agentBadgeTools,
                      value: config.enabledTools.isEmpty
                          ? context.s.agentBadgeNone
                          : '${config.enabledTools.length}',
                    ),
                    _InfoRow(
                      icon: Icons.message,
                      label: context.s.agentBadgeMsgCount,
                      value: '${runtime.messages.length}',
                    ),
                    _InfoRow(
                      icon: Icons.circle,
                      label: context.s.agentBadgeStatus,
                      value: switch (runtime.status) {
                        AgentStatus.idle => context.s.agentBadgeIdle,
                        AgentStatus.thinking => context.s.agentBadgeThinking,
                        AgentStatus.tooling => context.s.agentBadgeExecuting,
                        AgentStatus.error => context.s.agentBadgeError,
                      },
                    ),
                    if (config.systemPrompt.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(
                              Icons.description,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.s.agentBadgeSystemPrompt,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          config.systemPrompt,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            height: 1.5,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.s.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../chat_provider.dart';

/// `/sub-readers` 进度卡片 — 展示规划阶段拆出的子任务及各自的并行执行状态。
///
/// 三个阶段对应的展示：
/// - 规划中 (subtasks 为空): 显示"正在规划子任务..."
/// - 并行执行中: 每个子任务一行，带状态图标 (等待/执行中/完成/失败)
/// - 完成: 所有子任务状态定型，[SubReadersRun.inProgress] 变为 false，
///   卡片会在外层 (chat_provider) 延迟数秒后自动收起
class SubReadersCard extends StatelessWidget {
  final SubReadersRun run;

  const SubReadersCard({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '/sub-readers',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (run.inProgress)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: colorScheme.primary,
                        ),
                      )
                    else
                      Icon(Icons.check_circle, size: 16, color: Colors.green),
                  ],
                ),
                if (run.subtasks.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '正在规划子任务...',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    '已派生 ${run.subtasks.length} 个只读子 Agent 并行处理',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final task in run.subtasks)
                    _buildTaskRow(task, colorScheme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(SubReaderDisplay task, ColorScheme colorScheme) {
    final (icon, color) = switch (task.status) {
      SubReaderStatus.planned => (
        Icons.hourglass_empty,
        colorScheme.onSurfaceVariant,
      ),
      SubReaderStatus.running => (Icons.autorenew, colorScheme.tertiary),
      SubReaderStatus.done => (Icons.check_circle_outline, Colors.green),
      SubReaderStatus.error => (Icons.error_outline, colorScheme.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.scope,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                ),
                if (task.preview != null && task.preview!.isNotEmpty)
                  Text(
                    task.preview!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

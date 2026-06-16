import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/font/custom_font_loader.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../models/agent_config.dart';
import '../models/agent_message.dart';
import '../providers/multi_agent_provider.dart';

/// 总AI指挥部面板 — 可向所有Agent广播指令，查看全局时间线
class CommandCenter extends ConsumerStatefulWidget {
  const CommandCenter({super.key});

  @override
  ConsumerState<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends ConsumerState<CommandCenter>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _broadcast() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(multiAgentProvider.notifier).broadcastFromCommander(text);
  }

  Future<void> _broadcastFiles(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: context.s.multiAgentSelectGlobalFile,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (paths.isEmpty) return;
    ref.read(multiAgentProvider.notifier).broadcastFiles(paths);
  }

  Future<void> _exportTimeline(MultiAgentState state) async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: context.s.multiAgentExportRecord,
      fileName: '协作记录_${DateTime.now().toIso8601String().split('T').first}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (savePath == null) return;
    if (!mounted) return;

    final buf = StringBuffer();
    buf.writeln('# 多Agent协作记录');
    buf.writeln();
    if (state.workingDirectory != null) {
      buf.writeln('**工作目录**: `${state.workingDirectory}`');
    }
    buf.writeln('**导出时间**: ${DateTime.now().toString().substring(0, 19)}');
    final participants = state.agents.values
        .map((rt) => '${rt.config.name}(${rt.config.role.label})')
        .join('、');
    buf.writeln('**参与者**: $participants');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    for (final msg in state.timeline) {
      final time =
          '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
          '${msg.timestamp.minute.toString().padLeft(2, '0')}:'
          '${msg.timestamp.second.toString().padLeft(2, '0')}';

      final fromName = msg.fromAgentId == 'user'
          ? context.s.multiAgentUser
          : msg.fromAgentId == 'system'
          ? context.s.multiAgentSystem
          : state.agents[msg.fromAgentId]?.config.name ?? msg.fromAgentId;

      final toName = msg.toAgentId != null
          ? ' → ${state.agents[msg.toAgentId]?.config.name ?? msg.toAgentId}'
          : '';

      final typeTag = switch (msg.type) {
        AgentMessageType.broadcast => ' [广播]',
        AgentMessageType.direct => ' [私信]',
        AgentMessageType.system => ' [系统]',
        AgentMessageType.toolResult => ' [工具]',
        _ => '',
      };

      buf.writeln('## $time $fromName$toName$typeTag');
      buf.writeln();
      buf.writeln(msg.content);
      buf.writeln();
    }

    try {
      await File(savePath).writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.multiAgentExported(savePath))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.s.multiAgentExportFailed(e.toString())),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiAgentProvider);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 极端压缩：只显示图标
        if (constraints.maxHeight < 80) {
          return Center(
            child: Icon(
              Icons.military_tech,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          );
        }

        final showInput = constraints.maxHeight >= 150;
        final showTabs = constraints.maxHeight >= 120;

        return Column(
          children: [
            if (showTabs)
              // Tab 切换：时间线 / 任务看板
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabController,
                        labelStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: theme.textTheme.labelSmall,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: [
                          Tab(text: context.s.multiAgentTimeline, height: 30),
                          Tab(text: context.s.multiAgentOverview, height: 30),
                        ],
                      ),
                    ),
                    // 导出按钮
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        onPressed: state.timeline.isEmpty
                            ? null
                            : () => _exportTimeline(state),
                        icon: Icon(
                          Icons.file_download_outlined,
                          size: 16,
                          color: state.timeline.isEmpty
                              ? Colors.grey
                              : theme.colorScheme.primary,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                        splashRadius: 14,
                        tooltip: context.s.multiAgentExportRecord,
                      ),
                    ),
                  ],
                ),
              ),
            // 内容区
            Expanded(
              child: showTabs
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _TimelineView(
                          timeline: state.timeline,
                          agents: state.agents,
                        ),
                        _OverviewView(state: state),
                      ],
                    )
                  : _TimelineView(
                      timeline: state.timeline,
                      agents: state.agents,
                    ),
            ),
            if (showInput)
              // 广播输入
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.campaign,
                      size: 16,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if ((event is KeyDownEvent ||
                                  event is KeyRepeatEvent) &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              HardwareKeyboard.instance.isControlPressed) {
                            _broadcast();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _inputController,
                          style: theme.textTheme.bodySmall,
                          maxLines: 3,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: context.s.multiAgentBroadcastHint,
                            hintStyle: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: theme.dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _broadcast,
                      icon: Icon(
                        Icons.send,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 14,
                      tooltip: context.s.multiAgentBroadcast,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => _broadcastFiles(ref),
                      icon: Icon(
                        Icons.attach_file,
                        size: 16,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 14,
                      tooltip: context.s.multiAgentGlobalFile,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 全局时间线视图
class _TimelineView extends StatelessWidget {
  const _TimelineView({required this.timeline, required this.agents});
  final List<AgentMessage> timeline;
  final Map<String, AgentRuntime> agents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (timeline.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            Text(
              context.s.multiAgentNoMessages,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: timeline.length,
      itemBuilder: (context, index) {
        final msg = timeline[index];
        return _TimelineItem(message: msg, agents: agents);
      },
    );
  }
}

/// 时间线中的单条消息
class _TimelineItem extends ConsumerWidget {
  const _TimelineItem({required this.message, required this.agents});
  final AgentMessage message;
  final Map<String, AgentRuntime> agents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chatFont = ref.watch(chatFontProvider);
    final chatFontSize = ref.watch(chatFontSizeProvider);

    final fromAgent = agents[message.fromAgentId];
    final fromName = message.fromAgentId == 'user'
        ? context.s.multiAgentYou
        : message.fromAgentId == 'system'
        ? context.s.multiAgentSystem
        : fromAgent?.config.name ?? message.fromAgentId;
    final fromColor = message.fromAgentId == 'user'
        ? theme.colorScheme.primary
        : message.fromAgentId == 'system'
        ? Colors.grey
        : fromAgent?.config.role.color ?? Colors.grey;

    final typeIcon = switch (message.type) {
      AgentMessageType.user => Icons.person,
      AgentMessageType.assistant => Icons.smart_toy,
      AgentMessageType.broadcast => Icons.campaign,
      AgentMessageType.direct => Icons.arrow_forward,
      AgentMessageType.system => Icons.info_outline,
      AgentMessageType.toolResult => Icons.build,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(typeIcon, size: 14, color: fromColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      fromName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fromColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (message.toAgentId != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_right_alt,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      Text(
                        agents[message.toAgentId]?.config.name ??
                            message.toAgentId!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              agents[message.toAgentId]?.config.role.color ??
                              Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _formatTime(message.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message.content,
                  style: _safeChatStyle(
                    chatFont,
                    chatFontSize,
                    theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

/// 总览视图 — 显示所有Agent状态和消息统计
class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.state});
  final MultiAgentState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agents = state.agents.values.toList();

    if (agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            Text(
              context.s.multiAgentNoAgents,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 统计卡片
        Row(
          children: [
            _StatCard(
              label: context.s.multiAgentTotalAgents,
              value: '${agents.length}',
              icon: Icons.groups,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: context.s.multiAgentActive,
              value:
                  '${agents.where((a) => a.status != AgentStatus.idle).length}',
              icon: Icons.bolt,
              color: Colors.amber,
            ),
            const SizedBox(width: 8),
            _StatCard(
              label: context.s.multiAgentTotalMessages,
              value: '${state.timeline.length}',
              icon: Icons.message,
              color: Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Agent 状态列表
        Text(
          context.s.multiAgentStatus,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...agents.map((rt) => _AgentStatusCard(runtime: rt)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentStatusCard extends StatelessWidget {
  const _AgentStatusCard({required this.runtime});
  final AgentRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = runtime.config;
    final statusText = switch (runtime.status) {
      AgentStatus.idle => context.s.multiAgentIdle,
      AgentStatus.thinking => context.s.multiAgentThinking,
      AgentStatus.tooling => context.s.agentBadgeExecuting,
      AgentStatus.error => context.s.multiAgentError,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(config.role.icon, size: 16, color: config.role.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              config.name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: config.role.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: config.role.color,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.s.multiAgentMsgCount(runtime.messages.length),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 安全获取聊天字体样式，自定义字体直接用 fontFamily，Google Font 走 getFont
TextStyle _safeChatStyle(String fontFamily, double fontSize, Color color) {
  if (CustomFontLoader.instance.loadedFonts.contains(fontFamily)) {
    return TextStyle(fontFamily: fontFamily, color: color, fontSize: fontSize, height: 1.4);
  }
  try {
    return GoogleFonts.getFont(
      fontFamily,
      color: color,
      fontSize: fontSize,
      height: 1.4,
    );
  } catch (_) {
    return TextStyle(color: color, fontSize: fontSize, height: 1.4);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/font/custom_font_loader.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../providers/settings_provider.dart';
import '../../chat/widgets/markdown_view.dart';
import '../models/agent_config.dart';
import '../models/agent_message.dart';
import '../providers/multi_agent_provider.dart';
import 'agent_badge_dialog.dart';

/// 单个 Agent 的对话面板（嵌入到 DockPanel 中）
class AgentChatPanel extends ConsumerStatefulWidget {
  const AgentChatPanel({super.key, required this.agentId});

  final String agentId;

  @override
  ConsumerState<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends ConsumerState<AgentChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  AgentRuntime? _lastRuntime; // 缓存引用，dispose时不依赖ref

  @override
  void initState() {
    super.initState();
    // 恢复草稿
    final rt = ref.read(multiAgentProvider).agents[widget.agentId];
    if (rt != null && rt.draftText.isNotEmpty) {
      _controller.text = rt.draftText;
    }
    _lastRuntime = rt;
    // 监听文本变化 → 保存草稿
    _controller.addListener(_saveDraft);
  }

  void _saveDraft() {
    final rt = ref.read(multiAgentProvider).agents[widget.agentId];
    if (rt != null) {
      _lastRuntime = rt;
      rt.draftText = _controller.text;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_saveDraft);
    // dispose 时 ref 已失效，直接通过缓存引用保存草稿
    _lastRuntime?.draftText = _controller.text;
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    // 清空草稿
    final rt = ref.read(multiAgentProvider).agents[widget.agentId];
    if (rt != null) rt.draftText = '';

    ref
        .read(multiAgentProvider.notifier)
        .sendMessageToAgent(widget.agentId, text);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: context.s.multiAgentSelectFile,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    if (paths.isEmpty) return;
    ref
        .read(multiAgentProvider.notifier)
        .sendFileToAgent(widget.agentId, paths);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiAgentProvider);
    final runtime = state.agents[widget.agentId];
    if (runtime == null) {
      return Center(child: Text(context.s.multiAgentRemoved));
    }

    final config = runtime.config;
    final messages = runtime.messages;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 极端压缩：高度不足80px，只显示最小化标识
        if (constraints.maxHeight < 80) {
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AgentBadgeDialog(agentId: widget.agentId),
            ),
            child: Center(
              child: Icon(config.role.icon, size: 16, color: config.role.color),
            ),
          );
        }

        // 紧凑模式：高度不足150px，隐藏输入栏
        final showInput = constraints.maxHeight >= 150;
        // 中等模式：高度不足200px，隐藏状态栏
        final showStatusBar = constraints.maxHeight >= 120;

        return Column(
          children: [
            if (showStatusBar)
              GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AgentBadgeDialog(agentId: widget.agentId),
                ),
                child: _StatusBar(runtime: runtime),
              ),
            // 消息列表
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                scrollCacheExtent: ScrollCacheExtent.pixels(500),
                itemCount:
                    messages.length +
                    (runtime.streamingText.isNotEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < messages.length) {
                    return RepaintBoundary(
                      child: _MessageBubble(
                        message: messages[index],
                        agentName: config.name,
                        agentColor: config.role.color,
                      ),
                    );
                  }
                  return _StreamingBubble(
                    text: runtime.streamingText,
                    agentName: config.name,
                    agentColor: config.role.color,
                  );
                },
              ),
            ),
            if (showInput)
              _InputBar(
                controller: _controller,
                focusNode: _focusNode,
                onSend: _send,
                onPickFile: _pickFiles,
                enabled:
                    runtime.status == AgentStatus.idle ||
                    runtime.status == AgentStatus.error,
              ),
          ],
        );
      },
    );
  }
}

/// Agent 状态栏
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.runtime});
  final AgentRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = runtime.config;

    final statusText = switch (runtime.status) {
      AgentStatus.idle => context.s.multiAgentReady,
      AgentStatus.thinking => context.s.multiAgentThinking,
      AgentStatus.tooling => context.s.multiAgentExecutingTool,
      AgentStatus.error => context.s.multiAgentError,
    };
    final statusColor = switch (runtime.status) {
      AgentStatus.idle => Colors.green,
      AgentStatus.thinking => Colors.amber,
      AgentStatus.tooling => Colors.blue,
      AgentStatus.error => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(config.role.icon, size: 14, color: config.role.color),
          const SizedBox(width: 6),
          Text(
            config.role.localizedLabel(context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: config.role.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡
class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.agentName,
    required this.agentColor,
  });

  final AgentMessage message;
  final String agentName;
  final Color agentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isUser = message.type == AgentMessageType.user;
    final chatFont = ref.watch(chatFontProvider);
    final chatFontSize = ref.watch(chatFontSizeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: isUser
                ? null
                : Border.all(
                    color: agentColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
          ),
          child: isUser
              ? SelectableText(
                  message.content,
                  style: _safeChatStyle(chatFont, chatFontSize,
                      theme.colorScheme.onSurface),
                )
              : MarkdownView(
                  data: message.content,
                  textColor: theme.colorScheme.onSurface,
                  fontFamily: chatFont,
                  fontSize: chatFontSize,
                ),
        ),
      ),
    );
  }
}

/// 流式输出气泡
class _StreamingBubble extends ConsumerWidget {
  const _StreamingBubble({
    required this.text,
    required this.agentName,
    required this.agentColor,
  });

  final String text;
  final String agentName;
  final Color agentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chatFont = ref.watch(chatFontProvider);
    final chatFontSize = ref.watch(chatFontSizeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: agentColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownView(
                data: text,
                textColor: theme.colorScheme.onSurface,
                fontFamily: chatFont,
                fontSize: chatFontSize,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: agentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入栏 — Enter换行，Ctrl+Enter发送
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onPickFile,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onPickFile;
  final bool enabled;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      onSend();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 文件传输按钮
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton(
              onPressed: enabled ? onPickFile : null,
              icon: Icon(
                Icons.attach_file,
                size: 18,
                color: enabled
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                    : Colors.grey,
              ),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              splashRadius: 16,
              tooltip: context.s.multiAgentSendFile,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                style: theme.textTheme.bodySmall,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: enabled
                      ? context.s.multiAgentInputHint
                      : context.s.multiAgentWaiting,
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton(
              onPressed: enabled ? onSend : null,
              icon: Icon(
                Icons.send,
                size: 18,
                color: enabled ? theme.colorScheme.primary : Colors.grey,
              ),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              splashRadius: 16,
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
    return TextStyle(fontFamily: fontFamily, color: color, fontSize: fontSize, height: 1.5);
  }
  try {
    return GoogleFonts.getFont(
      fontFamily,
      color: color,
      fontSize: fontSize,
      height: 1.5,
    );
  } catch (_) {
    return TextStyle(color: color, fontSize: fontSize, height: 1.5);
  }
}

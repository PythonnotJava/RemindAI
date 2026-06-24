import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path/path.dart' as p;

import '../../core/export/conversation_exporter.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/llm/models.dart';
import '../../core/models/file_attachment.dart';
import '../../core/settings/app_settings.dart';
import '../../core/skill/skill_model.dart';
import '../../providers/database_provider.dart';
import '../../core/mcp/mcp_registry.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
import '../../core/db/tables/model_cards.dart' as db;
import '../../widgets/model_logo.dart';
import 'chat_provider.dart';
import 'widgets/chat_scroll_nav.dart';
import 'widgets/markdown_view.dart';
import 'widgets/message_bubble.dart';
import 'widgets/new_workspace_dialog.dart';
import 'widgets/tool_call_card.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// 用户是否在列表底部附近 (控制自动滚动行为)
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();
    // 监听滚动位置，判断用户是否在底部附近
    _scrollController.addListener(_onScroll);
    // 启动时把设置中的工作目录同步到 provider（仅当 provider 尚未设置时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider).valueOrNull;
      final saved = settings?.workingDirectory ?? '';
      final current = ref.read(workingDirectoryProvider);
      if (saved.isNotEmpty && current.isEmpty) {
        ref.read(workingDirectoryProvider.notifier).state = saved;
      }

      // 自动加载默认模型卡片（仅当尚未选择模型时）
      _autoLoadDefaultModel();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // 距离底部 150px 以内视为"在底部"
    _isNearBottom = pos.pixels >= pos.maxScrollExtent - 150;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatProvider.notifier).sendMessage(text);
    _focusNode.requestFocus();
  }

  /// 自动加载默认模型卡片到 activeModelCardProvider
  Future<void> _autoLoadDefaultModel() async {
    final current = ref.read(activeModelCardProvider);
    if (current != null) return; // 已有活跃模型，不覆盖

    final dao = ref.read(modelCardsDaoProvider);
    final db.ModelCard? defaultCard = await dao.getDefault();
    if (defaultCard == null) return; // 数据库中无卡片

    final llmCard = ModelCard(
      id: defaultCard.id,
      name: defaultCard.name,
      baseUrl: defaultCard.baseUrl,
      apiKey: defaultCard.apiKey,
      model: defaultCard.modelId,
      logoPath: defaultCard.logoPath,
      provider: defaultCard.provider,
      contextWindow: defaultCard.contextWindow,
    );
    ref.read(activeModelCardProvider.notifier).state = llmCard;
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Auto-scroll: 仅当用户在底部附近时才跟随新内容滚动
    // 用户发送消息 (messages 增加 + isLoading 变 true) 时强制滚动到底
    ref.listen(chatProvider, (prev, next) {
      final userSent =
          (prev?.messages.length ?? 0) < next.messages.length && next.isLoading;
      if (userSent) {
        _isNearBottom = true;
        _scrollToBottom(force: true);
      } else {
        _scrollToBottom();
      }
    });

    return Scaffold(
      body: Column(
        children: [
          // App bar area
          _buildTopBar(context, chatState),
          const Divider(height: 1),
          // Message list
          Expanded(
            child: chatState.isLoadingHistory
                ? Center(
                    child: SpinKitFadingCircle(
                      color: Theme.of(context).colorScheme.primary,
                      size: 36,
                    ),
                  )
                : chatState.messages.isEmpty && !chatState.isLoading
                ? _buildEmptyState(context)
                : Stack(
                    children: [
                      _buildMessageList(context, chatState),
                      ChatScrollNav(scrollController: _scrollController),
                    ],
                  ),
          ),
          // Error banner
          if (chatState.error != null) _buildErrorBanner(context, chatState),
          // Permission confirmation bar
          if (chatState.pendingPermission != null)
            _PermissionBar(
              permission: chatState.pendingPermission!,
              onApprove: () =>
                  ref.read(chatProvider.notifier).approvePermission(),
              onReject: () =>
                  ref.read(chatProvider.notifier).rejectPermission(),
              onAlways: () => ref.read(chatProvider.notifier).approveAlways(),
            ),
          // Thinking timer bar
          _ThinkingBar(isLoading: chatState.isLoading),
          // Input bar
          _ChatInput(
            controller: _controller,
            focusNode: _focusNode,
            isLoading: chatState.isLoading,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ChatState chatState) {
    final colorScheme = Theme.of(context).colorScheme;
    final modelCard = ref.watch(activeModelCardProvider);
    final modelCardsAsync = ref.watch(modelCardsProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.psychology, color: colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          // 模型选择器
          modelCardsAsync.when(
            data: (cards) => PopupMenuButton<db.ModelCard>(
              onSelected: (selected) {
                // 将 db.ModelCard 转换为 llm ModelCard
                final llmCard = ModelCard(
                  id: selected.id,
                  name: selected.name,
                  baseUrl: selected.baseUrl,
                  apiKey: selected.apiKey,
                  model: selected.modelId,
                  logoPath: selected.logoPath,
                  provider: selected.provider,
                  contextWindow: selected.contextWindow,
                );
                ref.read(chatProvider.notifier).switchModel(llmCard);
              },
              itemBuilder: (context) => cards.map((card) {
                final isActive = modelCard?.id == card.id;
                return PopupMenuItem<db.ModelCard>(
                  value: card,
                  child: Row(
                    children: [
                      if (isActive)
                        Icon(Icons.check, size: 16, color: colorScheme.primary)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      ModelLogo(
                        logoPath: card.logoPath,
                        name: card.name,
                        modelId: card.modelId,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              card.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              card.modelId,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (modelCard != null) ...[
                    ModelLogo(
                      logoPath: modelCard.logoPath,
                      name: modelCard.name,
                      modelId: modelCard.model,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    modelCard != null ? modelCard.model : context.s.chatNoModel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: modelCard != null
                          ? colorScheme.onSurface
                          : colorScheme.error,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            loading: () => Text(
              context.s.chatLoading,
              style: TextStyle(fontSize: 14, color: colorScheme.outline),
            ),
            error: (_, _) => Text(
              context.s.chatLoadFailed,
              style: TextStyle(fontSize: 14, color: colorScheme.error),
            ),
          ),
          const Spacer(),
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: context.s.chatExport,
              onPressed: () {
                final settings = ref.read(settingsProvider).valueOrNull;
                final pandocPath = (settings?.pandocPath.isNotEmpty ?? false)
                    ? settings!.pandocPath
                    : 'pandoc';
                ConversationExporter.showExportMenu(
                  context: context,
                  messages: chatState.messages,
                  title: '对话_${DateTime.now().millisecondsSinceEpoch}',
                  pandocPath: pandocPath,
                );
              },
            ),
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              tooltip: context.s.chatClear,
              onPressed: () {
                ref.read(chatProvider.notifier).clearChat();
              },
            ),
          // 新建对话按钮
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: context.s.chatNew,
            onPressed: () {
              ref.read(chatProvider.notifier).newConversation();
            },
          ),
          // 新建工作目录按钮
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            tooltip: context.s.chatNewWorkspace,
            onPressed: () => NewWorkspaceDialog.show(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final modelCard = ref.watch(activeModelCardProvider);

    if (modelCard == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off, size: 48, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              '请先在「模型」页面添加模型卡片',
              style: TextStyle(fontSize: 16, color: colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              context.s.chatNeedConfig,
              style: TextStyle(fontSize: 13, color: colorScheme.outlineVariant),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            context.s.chatStartConversation,
            style: TextStyle(fontSize: 16, color: colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.chatSupportsTools,
            style: TextStyle(fontSize: 13, color: colorScheme.outlineVariant),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => NewWorkspaceDialog.show(context),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: Text(context.s.chatCreateWorkspace),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, ChatState chatState) {
    // 虚拟化列表：只渲染可见区域的消息
    final messages = chatState.messages;
    final activeToolCalls = chatState.activeToolCalls;
    final isLoading = chatState.isLoading;

    // 总 item 数 = 消息 + 活跃 tool calls + 流式输出 (可选)
    final itemCount =
        messages.length + activeToolCalls.length + (isLoading ? 1 : 0);

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: itemCount,
        // 预渲染 500px 区域外的项，减少快速滚动白屏
        scrollCacheExtent: ScrollCacheExtent.pixels(500),
        itemBuilder: (context, index) {
          // 消息区
          if (index < messages.length) {
            return _buildMessageItem(messages[index], index);
          }
          // 活跃 tool calls 区
          final toolCallIndex = index - messages.length;
          if (toolCallIndex < activeToolCalls.length) {
            return ToolCallCard(toolCall: activeToolCalls[toolCallIndex]);
          }
          // 流式输出 bubble
          return StreamingBubble(text: chatState.streamingText);
        },
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage msg, int index) {
    // 跳过纯工具调用的 assistant 消息
    if (msg.role == ChatRole.assistant &&
        msg.toolCalls != null &&
        msg.toolCalls!.isNotEmpty &&
        (msg.content == null || msg.content!.startsWith('[工具调用]'))) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: MessageBubble(
        message: msg,
        messageIndex: index,
        onDelete: () {
          ref.read(chatProvider.notifier).deleteMessage(index);
        },
        onRegenerate: msg.role == ChatRole.assistant
            ? () {
                ref.read(chatProvider.notifier).regenerateMessage(index);
              }
            : null,
        onEdit: msg.role == ChatRole.user
            ? () {
                final content = ref
                    .read(chatProvider.notifier)
                    .editMessage(index);
                if (content != null) {
                  _controller.text = content;
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: content.length),
                  );
                  _focusNode.requestFocus();
                }
              }
            : null,
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, ChatState chatState) {
    final colorScheme = Theme.of(context).colorScheme;
    return _AutoDismissBanner(
      message: chatState.error!,
      colorScheme: colorScheme,
      onDismiss: () => ref.read(chatProvider.notifier).clearError(),
    );
  }
}

/// 自动消失的错误/提示横幅 — 带倒计时进度条。
class _AutoDismissBanner extends StatefulWidget {
  final String message;
  final ColorScheme colorScheme;
  final VoidCallback onDismiss;

  /// 倒计时时长（与 provider 端的 Timer 对齐）。
  static const duration = Duration(seconds: 6);

  const _AutoDismissBanner({
    required this.message,
    required this.colorScheme,
    required this.onDismiss,
  });

  @override
  State<_AutoDismissBanner> createState() => _AutoDismissBannerState();
}

class _AutoDismissBannerState extends State<_AutoDismissBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _AutoDismissBanner.duration,
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _AutoDismissBanner old) {
    super.didUpdateWidget(old);
    // 消息变了 → 重新开始倒计时
    if (old.message != widget.message) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: widget.colorScheme.errorContainer,
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: widget.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: widget.colorScheme.error,
                ),
                onPressed: widget.onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        // 倒计时进度条：从满到空
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LinearProgressIndicator(
              value: 1.0 - _controller.value,
              minHeight: 2,
              backgroundColor: widget.colorScheme.errorContainer,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.colorScheme.error.withValues(alpha: 0.6),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─── Input Bar ─────────────────────────────────────────────

class _ChatInput extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSend;

  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onSend,
  });

  @override
  ConsumerState<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<_ChatInput> {
  /// 发送逻辑: 如果正在 loading，先中断当前响应再发送新消息

  /// 发送逻辑: 如果正在 loading，先中断当前响应再发送新消息
  void _handleSend() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    if (widget.isLoading) {
      ref.read(chatProvider.notifier).cancelResponse();
    }
    widget.onSend();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: FileAttachment.supportedExtensions,
    );

    if (result != null && result.files.isNotEmpty) {
      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      if (files.isNotEmpty) {
        ref.read(chatProvider.notifier).addAttachments(files);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final attachments = ref.watch(chatProvider.select((s) => s.attachments));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toolbar: Skills / MCP / WorkDir / Memory / Search / Attach chips
          Row(
            children: [
              const _SkillsChip(),
              const SizedBox(width: 8),
              const _McpChip(),
              const SizedBox(width: 8),
              const _WorkDirChip(),
              const SizedBox(width: 8),
              const _RuntimeChip(),
              const SizedBox(width: 8),
              const _MemoryChip(),
              const SizedBox(width: 8),
              const _SearchChip(),
              const SizedBox(width: 8),
              ActionChip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: Text(
                  context.s.chatAttachments,
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: widget.isLoading ? null : _pickFiles,
              ),
            ],
          ),
          // Attachment chips
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AttachmentChipsRow(attachments: attachments),
          ],
          const SizedBox(height: 8),
          // Text field + send button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      final enterAction = ref.read(
                        settingsProvider.select(
                          (s) => s.valueOrNull?.enterAction ?? 'send',
                        ),
                      );
                      final hasModifier =
                          HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isAltPressed;
                      final shouldSend =
                          (enterAction == 'send' && !hasModifier) ||
                          (enterAction == 'newline' && hasModifier);
                      if (shouldSend) {
                        _handleSend();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    maxLines: null,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: widget.isLoading
                          ? context.s.chatInterruptHint
                          : context.s.chatInputHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              widget.isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            ref.read(chatProvider.notifier).cancelResponse();
                          },
                          icon: const Icon(Icons.stop_circle),
                          color: Theme.of(context).colorScheme.error,
                          iconSize: 28,
                          tooltip: context.s.chatStopGenerate,
                        ),
                        IconButton.filled(
                          onPressed: _handleSend,
                          icon: const Icon(Icons.send, size: 20),
                          tooltip: context.s.chatInterruptAndSend,
                        ),
                      ],
                    )
                  : IconButton.filled(
                      onPressed: _handleSend,
                      icon: const Icon(Icons.send),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 附件卡片行
class _AttachmentChipsRow extends ConsumerWidget {
  final List<FileAttachment> attachments;
  const _AttachmentChipsRow({required this.attachments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          final leading =
              attachment.isImage && File(attachment.path).existsSync()
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(attachment.path),
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Icon(
                      attachment.icon,
                      size: 16,
                      color: attachment.iconColor,
                    ),
                  ),
                )
              : Icon(attachment.icon, size: 16, color: attachment.iconColor);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                leading,
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    attachment.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  attachment.formattedSize,
                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    ref.read(chatProvider.notifier).removeAttachment(index);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkillsChip extends ConsumerWidget {
  const _SkillsChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);
    final activeCount =
        skillsAsync.valueOrNull?.where((s) => s.isActive).length ?? 0;

    return ActionChip(
      avatar: const Icon(Icons.extension, size: 16),
      label: Text(
        activeCount > 0 ? 'Skills ($activeCount)' : 'Skills',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _showSkillsSheet(context, ref),
    );
  }

  void _showSkillsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.6,
        expand: false,
        builder: (_, scrollController) => Consumer(
          builder: (context, ref, _) {
            final skillsAsync = ref.watch(skillsProvider);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.extension, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        context.s.chatSkillManage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: skillsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        context.s.chatLoadFailedWithError(e.toString()),
                      ),
                    ),
                    data: (skills) {
                      if (skills.isEmpty) {
                        return Center(
                          child: Text(
                            context.s.chatNoSkills,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: skills.length,
                        itemBuilder: (context, index) {
                          final skill = skills[index];
                          return ListTile(
                            leading: Icon(
                              skill.isBuiltIn
                                  ? Icons.verified
                                  : Icons.extension,
                              size: 20,
                            ),
                            title: Text(skill.name),
                            subtitle: Text(
                              skill.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 浏览 SKILL.md
                                IconButton(
                                  icon: const Icon(
                                    Icons.description_outlined,
                                    size: 18,
                                  ),
                                  tooltip: context.s.chatViewSkillMd,
                                  onPressed: () =>
                                      _showSkillMd(context, ref, skill),
                                ),
                                // 卸载
                                if (!skill.isBuiltIn)
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    tooltip: context.s.chatUninstall,
                                    onPressed: () => _confirmRemoveSkill(
                                      context,
                                      ref,
                                      skill,
                                    ),
                                  ),
                                // 启用/禁用开关
                                Switch(
                                  value: skill.isActive,
                                  onChanged: (_) => ref
                                      .read(skillsProvider.notifier)
                                      .toggleActive(skill.id),
                                ),
                              ],
                            ),
                            dense: true,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 浏览技能的 SKILL.md 内容
  void _showSkillMd(BuildContext context, WidgetRef ref, Skill skill) async {
    final file = File(p.join(skill.path, 'SKILL.md'));
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      content = '无法读取 SKILL.md:\n$e';
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(skill.name),
        content: SizedBox(
          width: 500,
          height: 400,
          child: SingleChildScrollView(
            child: MarkdownView(
              data: content,
              textColor: Theme.of(ctx).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonClose),
          ),
        ],
      ),
    );
  }

  /// 确认卸载技能
  void _confirmRemoveSkill(BuildContext context, WidgetRef ref, Skill skill) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.chatUninstallSkill),
        content: Text(context.s.chatUninstallSkillConfirm(skill.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(skillsProvider.notifier).remove(skill.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.s.chatUninstalled(skill.name))),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.chatUninstall),
          ),
        ],
      ),
    );
  }
}

class _McpChip extends ConsumerWidget {
  const _McpChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(mcpConnectionsProvider);
    final connectedCount = connections.statuses.values
        .where((s) => s == McpConnectionStatus.connected)
        .length;

    return ActionChip(
      avatar: const Icon(Icons.hub, size: 16),
      label: Text(
        connectedCount > 0 ? 'MCP ($connectedCount)' : 'MCP',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => _showMcpSheet(context, ref),
    );
  }

  void _showMcpSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.2,
        maxChildSize: 0.6,
        expand: false,
        builder: (_, scrollController) => Consumer(
          builder: (context, ref, _) {
            final serversAsync = ref.watch(mcpServersProvider);
            final connections = ref.watch(mcpConnectionsProvider);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.hub, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'MCP 服务',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: serversAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        context.s.chatLoadFailedWithError(e.toString()),
                      ),
                    ),
                    data: (servers) {
                      if (servers.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              '暂无 MCP 服务配置\n请前往 MCP 页面添加服务器',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollController,
                        itemCount: servers.length,
                        itemBuilder: (context, index) {
                          final server = servers[index];
                          final status =
                              connections.statuses[server.id] ??
                              McpConnectionStatus.disconnected;
                          final toolCount =
                              connections.toolsCache[server.id]?.length ?? 0;
                          return ListTile(
                            leading: _statusDot(status),
                            title: Text(server.name),
                            subtitle: Text(
                              status == McpConnectionStatus.connected
                                  ? '$toolCount 个工具'
                                  : _statusLabel(context, status),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (status == McpConnectionStatus.connecting)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  IconButton(
                                    icon: Icon(
                                      status == McpConnectionStatus.connected
                                          ? Icons.link_off
                                          : Icons.link,
                                      size: 18,
                                    ),
                                    tooltip:
                                        status == McpConnectionStatus.connected
                                        ? context.s.chatDisconnect
                                        : context.s.chatConnect,
                                    onPressed: () => _toggleConnection(
                                      context,
                                      ref,
                                      server,
                                      status,
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  tooltip: context.s.chatUninstall,
                                  onPressed: () =>
                                      _confirmRemoveMcp(context, ref, server),
                                ),
                              ],
                            ),
                            dense: true,
                            onTap: () =>
                                _toggleConnection(context, ref, server, status),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusDot(McpConnectionStatus status) {
    Color color;
    switch (status) {
      case McpConnectionStatus.connected:
        color = Colors.green;
      case McpConnectionStatus.connecting:
        color = Colors.orange;
      case McpConnectionStatus.error:
        color = Colors.red;
      case McpConnectionStatus.disconnected:
        color = Colors.grey;
    }
    return Icon(Icons.circle, color: color, size: 10);
  }

  String _statusLabel(BuildContext context, McpConnectionStatus status) {
    switch (status) {
      case McpConnectionStatus.connected:
        return context.s.chatConnected;
      case McpConnectionStatus.connecting:
        return context.s.chatConnecting;
      case McpConnectionStatus.error:
        return context.s.chatConnectFailed;
      case McpConnectionStatus.disconnected:
        return context.s.chatNotConnected;
    }
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
      await ref.read(mcpConnectionsProvider.notifier).connect(server);
    } catch (e) {
      if (context.mounted) {
        final detail = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.s.chatConnectFailed}: $detail',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  /// 确认卸载 MCP 服务
  void _confirmRemoveMcp(
    BuildContext context,
    WidgetRef ref,
    McpServerConfig server,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.chatUninstallMcp),
        content: Text(context.s.chatUninstallMcpConfirm(server.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mcpServersProvider.notifier).remove(server.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.s.chatUninstalled(server.name))),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.chatUninstall),
          ),
        ],
      ),
    );
  }
}

/// 工作目录选择 Chip：显示当前目录名，点击选择目录
class _WorkDirChip extends ConsumerWidget {
  const _WorkDirChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final workDir = ref.watch(workingDirectoryProvider);
    final hasDir = workDir.isNotEmpty;
    final label = hasDir ? _basename(workDir) : context.s.chatWorkingDir;

    return InputChip(
      avatar: Icon(
        hasDir ? Icons.folder : Icons.folder_open,
        size: 16,
        color: hasDir ? colorScheme.primary : null,
      ),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: hasDir ? workDir : context.s.chatSelectWorkingDir,
      onPressed: () => _pickDir(context, ref),
      onDeleted: hasDir ? () => _clearDir(ref) : null,
      deleteIcon: hasDir ? const Icon(Icons.close, size: 14) : null,
    );
  }

  Future<void> _pickDir(BuildContext context, WidgetRef ref) async {
    final title = context.s.chatSelectWorkingDir;

    // 如果当前工作目录已被删除，先清空，避免系统文件对话框卡死
    final current = ref.read(workingDirectoryProvider);
    if (current.isNotEmpty && !Directory(current).existsSync()) {
      ref.read(workingDirectoryProvider.notifier).state = '';
      await ref.read(settingsProvider.notifier).updateWorkingDirectory('');
    }

    try {
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: title)
          .timeout(const Duration(seconds: 60));
      if (dir != null && context.mounted) {
        ref.read(workingDirectoryProvider.notifier).state = dir;
        await ref.read(settingsProvider.notifier).updateWorkingDirectory(dir);
      }
    } on TimeoutException {
      // 文件对话框超时（系统级卡死），静默忽略
    } catch (_) {
      // 其他平台异常，静默忽略
    }
  }

  Future<void> _clearDir(WidgetRef ref) async {
    ref.read(workingDirectoryProvider.notifier).state = '';
    await ref.read(settingsProvider.notifier).updateWorkingDirectory('');
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.where((s) => s.isNotEmpty).lastOrNull ?? path;
  }
}

/// 记忆设置 Chip：显示嵌入式模型记忆状态，点击弹出快捷开关
class _MemoryChip extends ConsumerWidget {
  const _MemoryChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(settingsProvider);
    final embedding = settingsAsync.valueOrNull?.embedding;
    final configured = embedding?.isConfigured ?? false;

    return ActionChip(
      avatar: Icon(
        configured ? Icons.psychology : Icons.psychology_outlined,
        size: 16,
        color: configured ? colorScheme.primary : null,
      ),
      label: Text(context.s.chatMemory, style: const TextStyle(fontSize: 12)),
      tooltip: configured
          ? context.s.chatMemoryEnabled
          : context.s.chatEmbeddingNotConfigured,
      onPressed: () => _showMemorySheet(context, ref, embedding),
    );
  }

  void _showMemorySheet(
    BuildContext context,
    WidgetRef ref,
    EmbeddingConfig? embedding,
  ) {
    if (embedding == null || !embedding.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.chatEmbeddingNotConfiguredHint)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => _MemorySheet(embedding: embedding),
    );
  }
}

/// 记忆快捷设置面板
class _MemorySheet extends ConsumerStatefulWidget {
  final EmbeddingConfig embedding;
  const _MemorySheet({required this.embedding});

  @override
  ConsumerState<_MemorySheet> createState() => _MemorySheetState();
}

class _MemorySheetState extends ConsumerState<_MemorySheet> {
  late bool _useQdrant;
  late bool _persistToSqlite;

  @override
  void initState() {
    super.initState();
    _useQdrant = widget.embedding.useQdrant;
    _persistToSqlite = widget.embedding.persistToSqlite;
  }

  @override
  Widget build(BuildContext context) {
    // Session 级记忆开关 (null = 跟随 memory.json)
    final sessionRecall = ref.watch(sessionMemoryRecallProvider);
    final sessionStore = ref.watch(sessionMemoryStoreProvider);
    // 未设置 session 覆盖时默认开启
    final recallEnabled = sessionRecall ?? true;
    final storeEnabled = sessionStore ?? true;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.psychology, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.s.chatMemorySettings,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    widget.embedding.model,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.manage_search),
              title: Text(context.s.chatEnableRecall),
              subtitle: Text(context.s.chatEnableRecallDesc),
              value: recallEnabled,
              onChanged: (v) {
                ref.read(sessionMemoryRecallProvider.notifier).state = v;
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.save_alt),
              title: Text(context.s.chatEnableStore),
              subtitle: Text(context.s.chatEnableStoreDesc),
              value: storeEnabled,
              onChanged: (v) {
                ref.read(sessionMemoryStoreProvider.notifier).state = v;
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.hub_outlined),
              title: Text(context.s.chatEnableQdrant),
              subtitle: Text(context.s.chatEnableQdrantDesc),
              value: _useQdrant,
              onChanged: (v) {
                setState(() => _useQdrant = v);
                _save();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.storage_outlined),
              title: Text(context.s.chatEnableSqlite),
              subtitle: Text(context.s.chatEnableSqliteDesc),
              value: _persistToSqlite,
              onChanged: (v) {
                setState(() => _persistToSqlite = v);
                _save();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final updated = widget.embedding.copyWith(
      useQdrant: _useQdrant,
      persistToSqlite: _persistToSqlite,
    );
    // 更新当前选中的嵌入模型配置 (id 已存在则原地更新)
    ref.read(settingsProvider.notifier).upsertEmbedding(updated);
  }
}

/// 搜索服务 Chip：选择当前会话使用的搜索引擎
class _SearchChip extends ConsumerWidget {
  const _SearchChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentProvider = ref.watch(sessionSearchProvider);
    final active = currentProvider != SearchProvider.none;

    return ActionChip(
      avatar: Icon(
        active ? Icons.travel_explore : Icons.travel_explore_outlined,
        size: 16,
        color: active ? colorScheme.primary : null,
      ),
      label: Text(
        active ? _providerLabel(currentProvider) : context.s.chatSearch,
        style: const TextStyle(fontSize: 12),
      ),
      tooltip: active
          ? '${context.s.chatSearchActive}: ${_providerLabel(currentProvider)}'
          : context.s.chatSearchHint,
      onPressed: () => _showSearchMenu(context, ref),
    );
  }

  String _providerLabel(SearchProvider provider) => switch (provider) {
    SearchProvider.tavily => 'Tavily',
    SearchProvider.brave => 'Brave',
    SearchProvider.baidu => 'Baidu',
    SearchProvider.none => 'Off',
  };

  void _showSearchMenu(BuildContext context, WidgetRef ref) {
    final currentProvider = ref.read(sessionSearchProvider);
    final searchSettings = ref.read(searchSettingsProvider).valueOrNull;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.travel_explore, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      context.s.chatSearchTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const Divider(),
              RadioGroup<SearchProvider>(
                groupValue: currentProvider,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(sessionSearchProvider.notifier).state = v;
                    Navigator.pop(ctx);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // None - 关闭
                    RadioListTile<SearchProvider>(
                      value: SearchProvider.none,
                      title: Text(context.s.chatSearchOff),
                      subtitle: Text(context.s.chatSearchOffDesc),
                      secondary: const Icon(Icons.block, size: 20),
                    ),
                    // Tavily
                    RadioListTile<SearchProvider>(
                      value: SearchProvider.tavily,
                      title: const Text('Tavily'),
                      subtitle: Text(
                        searchSettings
                                    ?.getConfig(SearchProvider.tavily)
                                    .isConfigured ==
                                true
                            ? context.s.chatSearchReady
                            : context.s.chatSearchNotConfigured,
                      ),
                      secondary: const Icon(Icons.travel_explore, size: 20),
                      enabled:
                          searchSettings
                              ?.getConfig(SearchProvider.tavily)
                              .isConfigured ==
                          true,
                    ),
                    // Brave
                    RadioListTile<SearchProvider>(
                      value: SearchProvider.brave,
                      title: const Text('Brave Search'),
                      subtitle: Text(
                        searchSettings
                                    ?.getConfig(SearchProvider.brave)
                                    .isConfigured ==
                                true
                            ? context.s.chatSearchReady
                            : context.s.chatSearchNotConfigured,
                      ),
                      secondary: const Icon(Icons.shield_outlined, size: 20),
                      enabled:
                          searchSettings
                              ?.getConfig(SearchProvider.brave)
                              .isConfigured ==
                          true,
                    ),
                    // Baidu
                    RadioListTile<SearchProvider>(
                      value: SearchProvider.baidu,
                      title: Text(context.s.searchBaidu),
                      subtitle: Text(
                        searchSettings
                                    ?.getConfig(SearchProvider.baidu)
                                    .isConfigured ==
                                true
                            ? context.s.chatSearchReady
                            : context.s.chatSearchNotConfigured,
                      ),
                      secondary: const Icon(Icons.search, size: 20),
                      enabled:
                          searchSettings
                              ?.getConfig(SearchProvider.baidu)
                              .isConfigured ==
                          true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 运行环境 Chip：选择本次对话使用的 Python / npm 解释器
class _RuntimeChip extends ConsumerWidget {
  const _RuntimeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final python = ref.watch(sessionPythonProvider);
    final npm = ref.watch(sessionNpmProvider);
    final active = python.isNotEmpty || npm.isNotEmpty;

    return ActionChip(
      avatar: Icon(
        Icons.terminal,
        size: 16,
        color: active ? colorScheme.primary : null,
      ),
      label: Text(
        context.s.chatEnvironment,
        style: const TextStyle(fontSize: 12),
      ),
      tooltip: active ? context.s.chatEnvConfigured : context.s.chatEnvHint,
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (ctx) => const _RuntimeSheet(),
      ),
    );
  }
}

/// 运行环境设置面板
class _RuntimeSheet extends ConsumerWidget {
  const _RuntimeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final python = ref.watch(sessionPythonProvider);
    final npm = ref.watch(sessionNpmProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.terminal, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.s.chatEnvTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    context.s.chatEnvSessionScope,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.s.chatEnvDesc,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
            const Divider(),
            _RuntimeTile(
              icon: Icons.code,
              title: 'Python 解释器',
              hint: context.s.chatEnvPythonHint,
              value: python,
              onPick: () => _pick(context, ref, sessionPythonProvider, ['exe']),
              onClear: () =>
                  ref.read(sessionPythonProvider.notifier).state = '',
            ),
            _RuntimeTile(
              icon: Icons.javascript,
              title: 'Node / npm',
              hint: context.s.chatEnvSelectNpm,
              value: npm,
              onPick: () =>
                  _pick(context, ref, sessionNpmProvider, ['exe', 'cmd']),
              onClear: () => ref.read(sessionNpmProvider.notifier).state = '',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    StateProvider<String> provider,
    List<String> extensions,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? extensions : null,
      dialogTitle: context.s.chatEnvSelectFile,
    );
    final path = result?.files.singleOrNull?.path;
    if (path != null) {
      ref.read(provider.notifier).state = path;
    }
  }
}

/// 运行环境单项
class _RuntimeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _RuntimeTile({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasValue = value.isNotEmpty;

    return ListTile(
      leading: Icon(icon, color: hasValue ? colorScheme.primary : null),
      title: Text(title),
      subtitle: Text(
        hasValue ? value : hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: hasValue ? colorScheme.onSurfaceVariant : colorScheme.outline,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasValue)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: context.s.chatEnvClear,
              onPressed: onClear,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 20),
            tooltip: context.s.chatEnvSelect,
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}

// ─── 权限确认卡片 ─────────────────────────────────────────────

class _PermissionBar extends StatelessWidget {
  final PendingPermission permission;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onAlways;

  const _PermissionBar({
    required this.permission,
    required this.onApprove,
    required this.onReject,
    required this.onAlways,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 20, color: colorScheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '请求: ${permission.displayName}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  permission.summary,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAlways,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              context.s.chatPermAlways,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: onApprove,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              context.s.chatPermAllow,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: onReject,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              context.s.chatPermDeny,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Thinking Timer Bar ──────────────────────────────────────

/// 输入框上方的思考计时条，当模型正在生成时始终可见。
class _ThinkingBar extends StatefulWidget {
  final bool isLoading;

  const _ThinkingBar({required this.isLoading});

  @override
  State<_ThinkingBar> createState() => _ThinkingBarState();
}

class _ThinkingBarState extends State<_ThinkingBar>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _elapsedSeconds = 0;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isLoading) _startTimer();
  }

  @override
  void didUpdateWidget(covariant _ThinkingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLoading && widget.isLoading) {
      _startTimer();
    } else if (oldWidget.isLoading && !widget.isLoading) {
      _stopTimer();
    }
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final timeLabel = _formatElapsed(_elapsedSeconds);

    return FadeTransition(
      opacity: _pulseAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          border: Border(
            top: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.s.msgThinking,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              timeLabel,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatElapsed(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

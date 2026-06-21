import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_context.dart';
import '../../core/agent/agent_hook.dart';
import '../../core/db/daos/conversations_dao.dart';
import '../../core/llm/models.dart';
import '../../core/models/file_attachment.dart';
import '../../core/logger/app_logger.dart';
import '../../core/notification/notification_service.dart';
import '../../core/pet/pet_economy.dart';
import '../../core/pet/pet_chat_service.dart';
import '../../core/toolshell/agent_loop.dart';
import '../../core/utils/file_processor.dart';
import '../../core/pet/pet_observer.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
export '../../providers/session_provider.dart';

/// UI 中用于展示的工具调用信息
class ToolCallDisplay {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final ToolCallStatus status;
  final String? result;

  ToolCallDisplay({
    required this.id,
    required this.name,
    required this.arguments,
    this.status = ToolCallStatus.executing,
    this.result,
  });

  ToolCallDisplay copyWith({ToolCallStatus? status, String? result}) =>
      ToolCallDisplay(
        id: id,
        name: name,
        arguments: arguments,
        status: status ?? this.status,
        result: result ?? this.result,
      );
}

enum ToolCallStatus { executing, done, error }

/// Chat 状态
/// 待确认的权限请求
class PendingPermission {
  final String toolName;
  final Map<String, dynamic> args;
  final Completer<bool> completer;

  PendingPermission({
    required this.toolName,
    required this.args,
    required this.completer,
  });

  /// 工具的中文展示名
  String get displayName => switch (toolName) {
    'toolshell_write' => '写入文件',
    'toolshell_delete' => '删除文件',
    'toolshell_exec' => '执行命令',
    _ => toolName,
  };

  /// 操作摘要
  String get summary => switch (toolName) {
    'toolshell_write' =>
      '${args['mode'] ?? 'overwrite'} → ${args['path'] ?? '?'}',
    'toolshell_delete' => '删除 ${args['path'] ?? '?'}',
    'toolshell_exec' => args['command'] as String? ?? '?',
    _ => args.toString(),
  };
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isLoadingHistory;
  final String streamingText;
  final List<ToolCallDisplay> activeToolCalls;
  final String? error;
  final int? currentConversationId;
  final List<FileAttachment> attachments;
  final PendingPermission? pendingPermission;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.streamingText = '',
    this.activeToolCalls = const [],
    this.error,
    this.currentConversationId,
    this.attachments = const [],
    this.pendingPermission,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingHistory,
    String? streamingText,
    List<ToolCallDisplay>? activeToolCalls,
    String? error,
    int? currentConversationId,
    bool clearConversationId = false,
    List<FileAttachment>? attachments,
    PendingPermission? pendingPermission,
    bool clearPermission = false,
  }) => ChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
    streamingText: streamingText ?? this.streamingText,
    activeToolCalls: activeToolCalls ?? this.activeToolCalls,
    error: error,
    currentConversationId: clearConversationId
        ? null
        : (currentConversationId ?? this.currentConversationId),
    attachments: attachments ?? this.attachments,
    pendingPermission: clearPermission
        ? null
        : (pendingPermission ?? this.pendingPermission),
  );
}

/// 活跃模型卡片 Provider (临时，后续接入 Models 页面的持久化)
final activeModelCardProvider = StateProvider<ModelCard?>((ref) => null);

/// 工作目录 Provider
/// 空字符串表示"未选定工作目录"。由设置同步或输入框工具栏手动选择。
final workingDirectoryProvider = StateProvider<String>((ref) => '');

/// Chat StateNotifier
class ChatNotifier extends StateNotifier<ChatState> {
  final Ref _ref;
  StreamSubscription<AgentEvent>? _subscription;

  /// 错误提示自动消失计时器
  Timer? _errorTimer;

  /// AgentLoop 使用的消息历史 (Map 格式)
  final List<Map<String, dynamic>> _agentMessages = [];

  /// 上一次构建上下文时激活的用户技能签名。
  /// 用于检测会话中途技能集合变化，决定是否刷新 system prompt 的技能区。
  /// null 表示尚未捕获（首条消息时初始化）。
  String? _activeSkillSig;

  /// 当前对话轮次的 hooks 引用 (用于 AgentDone 后触发 onAgentDone)
  List<AgentHook> _activeHooks = [];

  /// 当前轮次的 token 计数（用于宠物经济系统奖励）
  int _currentTokenCount = 0;

  ChatNotifier(this._ref) : super(const ChatState());

  ConversationsDao get _conversationsDao => _ref.read(conversationsDaoProvider);

  /// 创建新会话
  Future<void> newConversation() async {
    _subscription?.cancel();
    // hooks: onSessionEnd
    await _fireSessionEnd();
    _agentMessages.clear();
    _activeSkillSig = null;
    state = const ChatState();
    // 刷新历史列表
    _ref.read(conversationsProvider.notifier).refresh();
  }

  /// 加载已有会话
  Future<void> loadConversation(int conversationId) async {
    _subscription?.cancel();
    _agentMessages.clear();
    _activeSkillSig = null;

    // 进入加载状态，让 UI 显示过渡动画
    state = state.copyWith(isLoadingHistory: true);

    final messages = await _conversationsDao.getMessages(conversationId);

    // 重建 agentMessages 用于继续对话
    final contextBuilder = AgentContextBuilder(_ref);
    final systemPrompt = await contextBuilder.buildSystemPrompt();
    _agentMessages.add({'role': 'system', 'content': systemPrompt});
    for (final msg in messages) {
      if (msg.role != ChatRole.system) {
        _agentMessages.add(msg.toMap());
      }
    }

    // 修复不完整的消息链: 如果尾部有带 tool_calls 的 assistant 消息
    // 但后面没有对应的 tool 消息，就截断它（防止 LLM 返回 400）
    _sanitizeAgentMessages();

    // 过滤掉系统消息，只显示用户和助手消息
    final displayMessages = messages
        .where((m) => m.role != ChatRole.system)
        .toList();

    state = ChatState(
      messages: displayMessages,
      currentConversationId: conversationId,
      isLoadingHistory: true, // 保持 loading，让 UI 有一帧缓冲
    );

    // 延迟一帧后关闭 loading，让布局在遮罩下完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    state = state.copyWith(isLoadingHistory: false);
  }

  /// 清理 _agentMessages 中不完整的 tool_calls 链
  /// OpenAI 协议要求: assistant(tool_calls) 后必须紧跟对应数量的 tool messages
  void _sanitizeAgentMessages() {
    while (_agentMessages.isNotEmpty) {
      final last = _agentMessages.last;
      final role = last['role'] as String?;
      final toolCalls = last['tool_calls'] as List?;

      // 如果最后一条是带 tool_calls 的 assistant → 后面缺 tool messages，删掉
      if (role == 'assistant' && toolCalls != null && toolCalls.isNotEmpty) {
        _agentMessages.removeLast();
        continue;
      }
      break;
    }
  }

  /// 切换模型
  void switchModel(ModelCard modelCard) {
    _ref.read(activeModelCardProvider.notifier).state = modelCard;
  }

  /// 添加附件
  void addAttachments(List<File> files) {
    final newAttachments = files
        .map((f) => FileAttachment.fromFile(f))
        .toList();
    state = state.copyWith(
      attachments: [...state.attachments, ...newAttachments],
    );
  }

  /// 移除附件
  void removeAttachment(int index) {
    final updated = List<FileAttachment>.from(state.attachments);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      state = state.copyWith(attachments: updated);
    }
  }

  /// 清空附件
  void clearAttachments() {
    state = state.copyWith(attachments: []);
  }

  // ─── 权限确认 ─────────────────────────────────────────────

  /// 权限请求回调 — 被 Executor 在 normal 模式下调用
  /// 设置 state.pendingPermission 通知 UI 弹出确认卡片，等待用户响应
  Future<bool> _onPermissionRequest(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingPermission: PendingPermission(
        toolName: toolName,
        args: args,
        completer: completer,
      ),
    );
    return completer.future;
  }

  /// 用户批准操作
  void approvePermission() {
    final pending = state.pendingPermission;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(true);
    }
    state = state.copyWith(clearPermission: true);
  }

  /// 用户拒绝操作
  void rejectPermission() {
    final pending = state.pendingPermission;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(false);
    }
    state = state.copyWith(clearPermission: true);
  }

  /// 用户选择"本会话始终允许" — 切换为 auto 模式
  void approveAlways() {
    approvePermission();
    // 后续操作不再弹确认 (通过重建 executor 时设置 auto 模式实现)
    // 这里设置一个标记让下次 sendMessage 时使用 auto mode
    _sessionAutoApprove = true;
  }

  bool _sessionAutoApprove = false;

  /// 清除错误提示
  void clearError() {
    _errorTimer?.cancel();
    _errorTimer = null;
    state = state.copyWith(error: null);
  }

  /// 设置错误提示，并在若干秒后自动消失（默认 6 秒）。
  void _setError(String message, {bool stopLoading = true}) {
    _errorTimer?.cancel();
    state = state.copyWith(
      error: message,
      isLoading: stopLoading ? false : state.isLoading,
    );
    _errorTimer = Timer(const Duration(seconds: 6), () {
      _errorTimer = null;
      // 仅当当前显示的还是这条错误时才清除，避免覆盖新错误
      if (state.error == message) {
        state = state.copyWith(error: null);
      }
    });
  }

  /// 发送消息
  Future<void> sendMessage(String input) async {
    final hasAttachments = state.attachments.isNotEmpty;
    if (input.trim().isEmpty && !hasAttachments) return;

    final modelCard = _ref.read(activeModelCardProvider);
    if (modelCard == null) {
      _setError('请先在「模型」页面添加并选择一个模型卡片', stopLoading: false);
      return;
    }

    // 快照附件并立即清空 UI 中的附件列表
    final pendingAttachments = List<FileAttachment>.from(state.attachments);

    // 如果当前没有会话，创建一个
    int? conversationId = state.currentConversationId;
    if (conversationId == null) {
      final title = input.length > 20 ? '${input.substring(0, 20)}...' : input;
      final conversation = await _conversationsDao.create(
        title: title,
        modelCardId: modelCard.id,
      );
      conversationId = conversation.id;
      state = state.copyWith(currentConversationId: conversationId);
      _ref.read(conversationsProvider.notifier).refresh();
    }

    final userMsg = ChatMessage.user(input, attachments: pendingAttachments);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      streamingText: '',
      activeToolCalls: [],
      error: null,
      attachments: [],
    );
    PetObserver.instance.notifyUserMessage(
      preview: input.length > 30 ? '${input.substring(0, 30)}...' : input,
    );

    await _conversationsDao.saveMessage(conversationId, userMsg);

    // 处理附件为 content parts
    List<Map<String, dynamic>>? contentParts;
    if (hasAttachments) {
      final fileParts = await FileProcessor.processAttachments(
        pendingAttachments,
      );
      contentParts = [
        if (input.trim().isNotEmpty) {'type': 'text', 'text': input},
        ...fileParts,
      ];
    }

    // ─── 使用 AgentContext 构建执行环境 ───
    final contextBuilder = AgentContextBuilder(_ref);
    final agentContext = await contextBuilder.build(
      modelCard: modelCard,
      existingMessages: _agentMessages,
      sessionAutoApprove: _sessionAutoApprove,
      onPermissionRequest: _onPermissionRequest,
    );

    // 保存 hooks 引用 (AgentDone 后触发)
    _activeHooks = agentContext.hooks;

    // ─── 中途技能变化时刷新 system prompt 的技能区 ───
    // 工具列表每条消息都实时重建（新技能/MCP 工具会自动生效），
    // 但 system prompt 仅在首条消息注入一次。若用户在会话中途启用/停用了技能，
    // 其 SKILL.md 引导文字不会进入上下文，导致"有工具却不知如何用"。
    // 这里仅在"激活技能集合发生变化"时替换 system 消息的技能区，
    // 保留专家角色与元技能前缀；技能未变则保持原样以维护 LLM 的 prompt cache。
    final currentSig = contextBuilder.computeSkillSignature();
    if (_activeSkillSig == null) {
      // 首条消息：记录基线签名，不触发刷新
      _activeSkillSig = currentSig;
      print('[SKILL] 会话基线技能签名: ${currentSig.isEmpty ? "(无激活技能)" : currentSig}');
    } else if (currentSig != _activeSkillSig &&
        _agentMessages.isNotEmpty &&
        _agentMessages.first['role'] == 'system') {
      print('[SKILL] ⟳ 检测到技能变化，刷新 system prompt');
      print(
        '[SKILL]   旧签名: ${_activeSkillSig!.isEmpty ? "(无)" : _activeSkillSig}',
      );
      print('[SKILL]   新签名: ${currentSig.isEmpty ? "(无)" : currentSig}');
      _agentMessages.first['content'] =
          '${agentContext.systemPromptPrefix}${agentContext.skillsSection}';
      _activeSkillSig = currentSig;
      print(
        '[SKILL]   ✓ 已注入技能引导，system prompt 长度=${(_agentMessages.first['content'] as String).length}',
      );
    } else {
      print(
        '[SKILL] 技能签名未变，保持 prompt cache: ${currentSig.isEmpty ? "(无激活技能)" : currentSig}',
      );
    }

    // hooks: onSessionStart (仅首次发送时触发)
    if (_agentMessages.length <= 1) {
      for (final hook in agentContext.hooks) {
        await hook.onSessionStart(conversationId, _agentMessages);
      }
    }

    // 启动 AgentLoop
    // hooks: onBeforeUserMessage
    for (final hook in agentContext.hooks) {
      await hook.onBeforeUserMessage(input, _agentMessages);
    }

    final agentLoop = agentContext.createLoop();

    // 监听事件流
    _subscription?.cancel();
    _currentTokenCount = 0;
    PetObserver.instance.notifyAiGenerating();
    _subscription = agentLoop
        .chat(input, contentParts: contentParts)
        .listen(
          (event) => _handleEvent(event, conversationId!),
          onError: (e, stackTrace) {
            AppLogger.instance.log('[ChatProvider] Stream error: $e');
            AppLogger.instance.log('[ChatProvider] StackTrace: $stackTrace');
            PetObserver.instance.notifyAiError(error: e.toString());
            _setError(e.toString());
          },
        );
  }

  void _handleEvent(AgentEvent event, int conversationId) {
    switch (event) {
      case AgentToken(text: final text):
        _currentTokenCount += text.length ~/ 4; // 粗略估算: 4字符≈1 token
        state = state.copyWith(streamingText: state.streamingText + text);
      case AgentToolStart(name: final name, args: final args):
        final toolCall = ToolCallDisplay(
          id: '${name}_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          arguments: args,
        );
        // 如果 streamingText 含有 DSML 标记（模型以文本形式输出的工具调用），
        // 说明这些内容已被解析为 tool_call，清除残留的标记文本
        final cleanedStream = state.streamingText.contains('DSML')
            ? ''
            : state.streamingText;
        state = state.copyWith(
          streamingText: cleanedStream,
          activeToolCalls: [...state.activeToolCalls, toolCall],
        );
      case AgentToolResult(toolCallId: _, result: final result):
        final updated = state.activeToolCalls.map((tc) {
          if (tc == state.activeToolCalls.last &&
              tc.status == ToolCallStatus.executing) {
            final isError = result.contains('"status":"error"');
            return tc.copyWith(
              status: isError ? ToolCallStatus.error : ToolCallStatus.done,
              result: result,
            );
          }
          return tc;
        }).toList();
        state = state.copyWith(activeToolCalls: updated);
      case AgentDone(content: final content):
        // 如果最终 content 为空，使用之前流式累积的文本
        // (某些模型在 tool_call 后的回复轮次不返回 content)
        final finalContent = content.isNotEmpty ? content : state.streamingText;
        final assistantMsg = ChatMessage.assistant(finalContent);
        // 把工具调用历史也追加为消息（展示用）
        final toolMessages = state.activeToolCalls.map((tc) {
          return ChatMessage(
            role: ChatRole.assistant,
            content: '[工具调用] ${tc.name}',
            toolCalls: [
              ChatToolCall(id: tc.id, name: tc.name, arguments: tc.arguments),
            ],
          );
        }).toList();
        state = state.copyWith(
          messages: [...state.messages, ...toolMessages, assistantMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
        );
        // 保存助手消息到数据库
        _conversationsDao.saveMessage(conversationId, assistantMsg);
        // 触发 hooks: onAgentDone (记忆存储等后处理)
        for (final hook in _activeHooks) {
          hook.onAgentDone(finalContent, []);
        }
        // 窗口失焦时发送系统通知 (受设置开关控制)
        final notifyEnabled =
            _ref.read(settingsProvider).valueOrNull?.notifyOnBlur ?? true;
        if (notifyEnabled) {
          NotificationService.instance.notify(
            title: 'RemindAI 对话完成',
            body: finalContent.isEmpty ? '助手已完成回复' : finalContent,
          );
        }
        PetObserver.instance.notifyAiCompleted(
          summary: finalContent.length > 50
              ? '${finalContent.substring(0, 50)}...'
              : finalContent,
        );
        // 宠物经济：根据 token 消耗奖励宠物币
        if (_currentTokenCount > 0) {
          PetEconomy.instance.rewardForTokens(_currentTokenCount).then((
            reward,
          ) {
            if (reward > 0) {
              // 通过宠物气泡通知用户
              PetChatService.instance.showCoinReward(reward);
            }
          });
          _currentTokenCount = 0;
        }
      case AgentError(message: final message):
        AppLogger.instance.log('[ChatProvider] AgentError: $message');
        PetObserver.instance.notifyAiError(error: message);
        _setError(message);
    }
  }

  /// 中断当前流式响应 — 保留已生成的部分输出并标记为「用户中断」
  void cancelResponse() {
    _subscription?.cancel();
    _subscription = null;

    final partial = state.streamingText;
    final convId = state.currentConversationId;

    // 只要有部分文本或正在执行的工具调用，都应保留到消息列表
    if (partial.isNotEmpty || state.activeToolCalls.isNotEmpty) {
      // 构建已中断的助手消息
      final content = partial.isNotEmpty
          ? partial
          : state.activeToolCalls.map((tc) => '[工具调用中] ${tc.name}').join('\n');
      final assistantMsg = ChatMessage.assistant(content, interrupted: true);

      // 把工具调用历史也追加为消息（展示用）
      final toolMessages = state.activeToolCalls
          .where((tc) => tc.status == ToolCallStatus.done)
          .map((tc) => ChatMessage(
                role: ChatRole.assistant,
                content: '[工具调用] ${tc.name}',
                toolCalls: [
                  ChatToolCall(
                    id: tc.id,
                    name: tc.name,
                    arguments: tc.arguments,
                  ),
                ],
              ))
          .toList();

      state = state.copyWith(
        messages: [...state.messages, ...toolMessages, assistantMsg],
        isLoading: false,
        streamingText: '',
        activeToolCalls: [],
      );

      // 持久化
      if (convId != null) {
        _conversationsDao.saveMessage(convId, assistantMsg);
      }
      // 同步 agentMessages 上下文 (让后续对话知道之前的部分回复)
      _agentMessages.add({'role': 'assistant', 'content': content});
    } else {
      // 连思考阶段都没开始输出，直接恢复空闲
      state = state.copyWith(
        isLoading: false,
        streamingText: '',
        activeToolCalls: [],
      );
    }
  }

  /// 删除指定索引的消息
  Future<void> deleteMessage(int index) async {
    if (index < 0 || index >= state.messages.length) return;

    final updated = List<ChatMessage>.from(state.messages);
    updated.removeAt(index);
    state = state.copyWith(messages: updated);

    // 同步删除数据库中的消息
    if (state.currentConversationId != null) {
      await _conversationsDao.deleteMessageAt(
        state.currentConversationId!,
        index,
      );
    }
  }

  /// 重新生成指定索引的助手消息
  ///
  /// 删除该助手消息，找到它之前的用户消息，截断 _agentMessages，
  /// 然后重新发送该用户消息。
  Future<void> regenerateMessage(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    final msg = state.messages[messageIndex];
    if (msg.role != ChatRole.assistant) return;

    // 找到该助手消息之前最近的用户消息
    String? userContent;
    int userIdx = -1;
    for (int i = messageIndex - 1; i >= 0; i--) {
      if (state.messages[i].role == ChatRole.user) {
        userContent = state.messages[i].content ?? '';
        userIdx = i;
        break;
      }
    }
    if (userContent == null || userContent.isEmpty) return;

    // 截断 state.messages: 保留到用户消息（含），删除之后的所有消息
    final updatedMessages = state.messages.sublist(0, userIdx + 1);
    state = state.copyWith(messages: updatedMessages);

    // 截断 _agentMessages: 找到对应的用户消息并保留到该处
    // _agentMessages 包含 system/tool/assistant 等消息，需要找到最后一条匹配的 user 消息
    int agentUserIdx = -1;
    int userCount = 0;
    // 计算 UI 中该用户消息是第几条 user 消息
    int targetUserOrder = 0;
    for (int i = 0; i <= userIdx; i++) {
      if (state.messages[i].role == ChatRole.user) {
        targetUserOrder++;
      }
    }
    // 在 _agentMessages 中找到第 targetUserOrder 条 user 消息
    for (int i = 0; i < _agentMessages.length; i++) {
      if (_agentMessages[i]['role'] == 'user') {
        userCount++;
        if (userCount == targetUserOrder) {
          agentUserIdx = i;
          break;
        }
      }
    }

    if (agentUserIdx >= 0) {
      // 保留到该 user 消息（含）
      _agentMessages.removeRange(agentUserIdx + 1, _agentMessages.length);
      // 移除该 user 消息本身，因为 sendMessage 会重新添加
      _agentMessages.removeAt(agentUserIdx);
    }

    // 重新发送
    await sendMessage(userContent);
  }

  /// 编辑指定索引的用户消息
  ///
  /// 截断该消息及之后的所有消息，返回该消息的文本内容供 UI 填入输入框。
  String? editMessage(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return null;
    final msg = state.messages[messageIndex];
    if (msg.role != ChatRole.user) return null;

    final content = msg.content ?? '';

    // 计算 messageIndex 是 state.messages 中第几条 user 消息
    int userOrdinal = 0;
    for (int i = 0; i <= messageIndex; i++) {
      if (state.messages[i].role == ChatRole.user) {
        userOrdinal++;
      }
    }

    // 截断 state.messages: 移除该消息及之后的所有消息
    final updatedMessages = state.messages.sublist(0, messageIndex);
    state = state.copyWith(messages: updatedMessages);

    // 在 _agentMessages 中找到第 userOrdinal 条 user 消息并截断
    int userCount = 0;
    for (int i = 0; i < _agentMessages.length; i++) {
      if (_agentMessages[i]['role'] == 'user') {
        userCount++;
        if (userCount == userOrdinal) {
          // 移除该 user 消息及之后的所有消息
          _agentMessages.removeRange(i, _agentMessages.length);
          break;
        }
      }
    }

    return content;
  }

  /// 清空对话
  void clearChat() {
    _subscription?.cancel();
    _fireSessionEnd();
    _agentMessages.clear();
    _activeSkillSig = null;
    state = const ChatState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _errorTimer?.cancel();
    _fireSessionEnd();
    super.dispose();
  }

  /// 触发 onSessionEnd 钩子
  Future<void> _fireSessionEnd() async {
    final convId = state.currentConversationId;
    if (convId == null || _activeHooks.isEmpty) return;
    // 计算对话轮数 (user 消息数)
    final turns = state.messages.where((m) => m.role == ChatRole.user).length;
    for (final hook in _activeHooks) {
      await hook.onSessionEnd(convId, turns);
    }
  }
}

/// Chat Provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});

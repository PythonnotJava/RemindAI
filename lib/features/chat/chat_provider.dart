import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_context.dart';
import '../../core/agent/agent_hook.dart';
import '../../core/db/daos/conversations_dao.dart';
import '../../core/isolate/compute_service.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/llm_provider.dart';
import '../../core/llm/models.dart';
import '../../core/models/file_attachment.dart';
import '../../core/logger/app_logger.dart';
import '../../core/notification/notification_service.dart';
import '../../core/pet/pet_economy.dart';
import '../../core/pet/pet_chat_service.dart';
import '../../core/toolshell/agent_loop.dart';
import '../../core/toolshell/autonomous_loop.dart';
import '../../core/toolshell/read_only_executor.dart';
import '../../core/toolshell/sub_readers_orchestrator.dart';
import '../../core/utils/file_processor.dart';
import '../../core/pet/pet_observer.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
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

/// `/sub-readers` 单个子任务的 UI 展示状态
enum SubReaderStatus { planned, running, done, error }

/// `/sub-readers` 单个子任务的 UI 展示信息
class SubReaderDisplay {
  final String id;
  final String scope;
  final SubReaderStatus status;
  final String? preview;

  const SubReaderDisplay({
    required this.id,
    required this.scope,
    this.status = SubReaderStatus.planned,
    this.preview,
  });

  SubReaderDisplay copyWith({SubReaderStatus? status, String? preview}) =>
      SubReaderDisplay(
        id: id,
        scope: scope,
        status: status ?? this.status,
        preview: preview ?? this.preview,
      );
}

/// `/sub-readers` 整体运行状态 — 展示在聊天流里的一张进度卡片
class SubReadersRun {
  final String description;
  final List<SubReaderDisplay> subtasks;

  /// 整体是否仍在跑（规划中 / 子任务并行执行中 / 合并中）
  final bool inProgress;

  const SubReadersRun({
    required this.description,
    required this.subtasks,
    this.inProgress = true,
  });

  SubReadersRun copyWith({
    List<SubReaderDisplay>? subtasks,
    bool? inProgress,
  }) => SubReadersRun(
    description: description,
    subtasks: subtasks ?? this.subtasks,
    inProgress: inProgress ?? this.inProgress,
  );
}

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

  /// Loop 模式状态
  final bool loopEnabled;
  final int loopIteration;
  final int loopMaxIterations;
  final bool loopRunning;

  /// `/sub-readers` 当前运行状态；null 表示当前没有正在展示的 sub-readers 卡片
  final SubReadersRun? subReadersRun;

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
    this.loopEnabled = false,
    this.loopIteration = 0,
    this.loopMaxIterations = 10,
    this.loopRunning = false,
    this.subReadersRun,
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
    bool? loopEnabled,
    int? loopIteration,
    int? loopMaxIterations,
    bool? loopRunning,
    SubReadersRun? subReadersRun,
    bool clearSubReadersRun = false,
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
    loopEnabled: loopEnabled ?? this.loopEnabled,
    loopIteration: loopIteration ?? this.loopIteration,
    loopMaxIterations: loopMaxIterations ?? this.loopMaxIterations,
    loopRunning: loopRunning ?? this.loopRunning,
    subReadersRun: clearSubReadersRun
        ? null
        : (subReadersRun ?? this.subReadersRun),
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
  StreamSubscription? _subscription;

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

  /// 流式 token 合并缓冲：每个 token 先入此缓冲，由 [_flushTimer] 周期性合并到
  /// state.streamingText，避免"每 token 一次 setState + 全量 rebuild + markdown 重解析"
  /// 导致的长思考卡顿。仅改变状态刷新时机，不改变最终文本内容。
  final StringBuffer _streamBuffer = StringBuffer();
  Timer? _flushTimer;

  /// 流式刷新间隔。约 50ms（≈20fps）足够顺滑，又把每秒 setState 次数从
  /// 数百次降到 ~20 次。
  static const _flushInterval = Duration(milliseconds: 50);

  /// 把累积的流式缓冲合并进 state.streamingText 并清空缓冲、停掉计时器。
  /// 在任何需要读取完整 streamingText 的时机（工具开始、完成、出错、中断、新会话、销毁）
  /// 必须先调用本方法，保证消费方拿到的是完整文本。
  void _flushStreamBuffer() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_streamBuffer.isEmpty) return;
    final pending = _streamBuffer.toString();
    _streamBuffer.clear();
    state = state.copyWith(streamingText: state.streamingText + pending);
  }

  ChatNotifier(this._ref) : super(const ChatState());

  ConversationsDao get _conversationsDao => _ref.read(conversationsDaoProvider);

  /// 创建新会话
  Future<void> newConversation() async {
    _subscription?.cancel();
    // 清理流式缓冲与计时器，避免残留 token 写入新会话
    _flushTimer?.cancel();
    _flushTimer = null;
    _streamBuffer.clear();
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
  /// 清理 _agentMessages 尾部不完整的 tool_calls 序列。
  ///
  /// 中断对话时 AgentLoop 可能已写入 assistant(tool_calls) + 部分 tool 回复。
  /// API 要求每个 tool_call 都有对应的 tool response，否则 400。
  /// 此方法从尾部向前清理，直到消息序列合法。
  void _sanitizeAgentMessages() {
    while (_agentMessages.isNotEmpty) {
      final last = _agentMessages.last;
      final role = last['role'] as String?;

      // 尾部是 tool message → 可能是不完整序列的一部分，先摘掉
      if (role == 'tool') {
        _agentMessages.removeLast();
        continue;
      }

      // 尾部是带 tool_calls 的 assistant → 后面缺 tool messages，删掉
      final toolCalls = last['tool_calls'] as List?;
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

  // ─── Loop 模式 ─────────────────────────────────────────────

  /// 切换 Loop 模式开关
  void toggleLoop() {
    state = state.copyWith(loopEnabled: !state.loopEnabled);
  }

  /// 设置 Loop 最大迭代次数（10-100，步进 5）
  void setLoopMaxIterations(int max) {
    // 对齐到步进 5
    final aligned = ((max / 5).round() * 5).clamp(10, 100);
    state = state.copyWith(loopMaxIterations: aligned);
  }

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

  // ─── /sub-readers: 并行只读子 Agent 编排 ──────────────────────

  /// 执行 `/sub-readers` 命令：把理解任务拆解为若干只读子任务，
  /// 用同模型类型的多个独立子 Agent 并行处理，最后综合汇总为一份理解。
  ///
  /// 与 [sendMessage] 走完全不同的路径——不进入 [AgentLoop] 的单轮对话，
  /// 而是驱动 [SubReadersOrchestrator] 的三阶段流程（规划→并行执行→合并），
  /// 期间通过 [ChatState.subReadersRun] 把进度实时展示为一张聊天卡片，
  /// 完成后把综合理解作为一条普通 assistant 消息追加到对话历史。
  Future<void> runSubReaders(String description) async {
    if (description.trim().isEmpty) return;

    final modelCard = _ref.read(activeModelCardProvider);
    if (modelCard == null) {
      _setError('请先在「模型」页面添加并选择一个模型卡片', stopLoading: false);
      return;
    }

    final workDir = _ref.read(workingDirectoryProvider);
    if (workDir.isEmpty) {
      _setError('/sub-readers 需要先选择工作目录', stopLoading: false);
      return;
    }

    // 如果当前没有会话，创建一个（与 sendMessage 行为一致，保证历史可追溯）
    int? conversationId = state.currentConversationId;
    if (conversationId == null) {
      final title =
          '/sub-readers ${description.length > 16 ? '${description.substring(0, 16)}...' : description}';
      final conversation = await _conversationsDao.create(
        title: title,
        modelCardId: modelCard.id,
      );
      conversationId = conversation.id;
      state = state.copyWith(currentConversationId: conversationId);
      _ref.read(conversationsProvider.notifier).refresh();
    }

    // 用户这条消息按普通消息展示 + 持久化，保证对话历史完整可读
    final userMsg = ChatMessage.user('/sub-readers $description');
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      error: null,
      subReadersRun: SubReadersRun(
        description: description,
        subtasks: const [],
      ),
    );
    await _conversationsDao.saveMessage(conversationId, userMsg);

    final provider = LlmProviderX.fromId(modelCard.provider);
    final orchestrator = SubReadersOrchestrator(
      createLlm: () => LlmClient(
        baseUrl: modelCard.baseUrl,
        apiKey: modelCard.apiKey,
        model: modelCard.model,
        provider: provider,
      ),
      // 每个子任务独立一份只读 Executor 实例，互不共享可变状态；
      // 因为只读，即使多个子 Agent 同时指向同一 workDir 也不会产生写冲突。
      createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: workDir),
      readOnlyTools: ReadOnlyExecutor.toolDefinitions,
    );

    try {
      await for (final event in orchestrator.run(description)) {
        _handleSubReadersEvent(event, conversationId);
      }
    } catch (e) {
      AppLogger.instance.log('[SubReaders] 未捕获异常: $e');
      state = state.copyWith(isLoading: false, clearSubReadersRun: true);
      _setError('/sub-readers 执行失败: $e');
    }
  }

  void _handleSubReadersEvent(SubReadersEvent event, int conversationId) {
    final run = state.subReadersRun;
    switch (event) {
      case SubReadersPlanned(tasks: final tasks):
        state = state.copyWith(
          subReadersRun: SubReadersRun(
            description: run?.description ?? '',
            subtasks: tasks
                .map((t) => SubReaderDisplay(id: t.id, scope: t.scope))
                .toList(),
          ),
        );
      case SubReaderStarted(taskId: final id):
        if (run == null) return;
        state = state.copyWith(
          subReadersRun: run.copyWith(
            subtasks: run.subtasks
                .map(
                  (s) => s.id == id
                      ? s.copyWith(status: SubReaderStatus.running)
                      : s,
                )
                .toList(),
          ),
        );
      case SubReaderFinished(
        taskId: final id,
        preview: final preview,
        success: final ok,
      ):
        if (run == null) return;
        state = state.copyWith(
          subReadersRun: run.copyWith(
            subtasks: run.subtasks
                .map(
                  (s) => s.id == id
                      ? s.copyWith(
                          status: ok
                              ? SubReaderStatus.done
                              : SubReaderStatus.error,
                          preview: preview,
                        )
                      : s,
                )
                .toList(),
          ),
        );
      case SubReadersMerged(finalContent: final content):
        final assistantMsg = ChatMessage.assistant(content);
        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          isLoading: false,
          subReadersRun: run?.copyWith(inProgress: false),
        );
        _conversationsDao.saveMessage(conversationId, assistantMsg);
        // 卡片保留展示已完成状态一小段时间，再自动收起，避免长期占据聊天流。
        // 用描述文本粗略确认这仍是同一次 run（用户没有立刻发起新的 /sub-readers）。
        final finishedDescription = run?.description;
        Timer(const Duration(seconds: 4), () {
          if (finishedDescription != null &&
              state.subReadersRun?.description == finishedDescription &&
              state.subReadersRun?.inProgress == false) {
            state = state.copyWith(clearSubReadersRun: true);
          }
        });
      case SubReadersError(message: final message):
        state = state.copyWith(isLoading: false, clearSubReadersRun: true);
        _setError('/sub-readers: $message');
    }
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
    // 新一轮开始前清理可能残留的流式缓冲/计时器
    _flushTimer?.cancel();
    _flushTimer = null;
    _streamBuffer.clear();
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

    // ─── 重扫项目级临时技能目录,感知中途变化 ───
    // 模型可能在上一轮用 toolshell_write 往工作目录的 .toolshell/skills/
    // 写入了新的项目级技能。这里强制重建 projectSkillsProvider 让其重扫磁盘,
    // 使新技能的工具与 SKILL.md 在本轮就能生效。
    // 项目技能与全局技能数据源隔离,重扫不影响全局技能管理 UI。
    // 技能集合未变时,下方的签名比对会保持 prompt cache,无额外开销。
    try {
      _ref.invalidate(projectSkillsProvider);
      await _ref.read(projectSkillsProvider.future);
    } catch (e) {
      print('[SKILL] 重扫项目技能失败(忽略): $e');
    }

    // ─── 使用 AgentContext 构建执行环境 ───
    final contextBuilder = AgentContextBuilder(_ref);
    final agentContext = await contextBuilder.build(
      modelCard: modelCard,
      existingMessages: _agentMessages,
      sessionAutoApprove: _sessionAutoApprove,
      onPermissionRequest: _onPermissionRequest,
      userInput: input,
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

    // 启动 AgentLoop 或 AutonomousLoop
    // hooks: onBeforeUserMessage
    for (final hook in agentContext.hooks) {
      await hook.onBeforeUserMessage(input, _agentMessages);
    }

    // 监听事件流
    _subscription?.cancel();
    _currentTokenCount = 0;
    PetObserver.instance.notifyAiGenerating();

    if (state.loopEnabled) {
      // ─── Loop 模式 ───
      state = state.copyWith(loopRunning: true, loopIteration: 0);
      final loopConfig = LoopConfig(
        maxIterations: state.loopMaxIterations,
        autoApprove: true,
      );
      final autonomousLoop = AutonomousLoop(
        llm: agentContext.llm,
        executor: agentContext.executor,
        tools: agentContext.tools,
        messages: _agentMessages,
        config: loopConfig,
        messagePipeline: agentContext.messagePipeline,
        hooks: agentContext.hooks,
      );
      _subscription = autonomousLoop
          .run(input)
          .listen(
            (event) => _handleLoopEvent(event, conversationId!),
            onError: (e, stackTrace) {
              AppLogger.instance.log('[ChatProvider] Loop stream error: $e');
              PetObserver.instance.notifyAiError(error: e.toString());
              state = state.copyWith(loopRunning: false);
              _setError(e.toString());
            },
          );
    } else {
      // ─── 普通模式 ───
      final agentLoop = agentContext.createLoop();
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
  }

  /// 处理 Loop 模式事件
  void _handleLoopEvent(LoopEvent event, int conversationId) {
    switch (event) {
      case LoopIterStart(iteration: final iter, maxIterations: final max):
        state = state.copyWith(loopIteration: iter);
        // 添加一条分隔消息到 UI
        final iterMsg = ChatMessage.assistant('─── Loop 第 $iter/$max 轮 ───');
        state = state.copyWith(messages: [...state.messages, iterMsg]);
      case LoopAgentEvent(event: final agentEvent):
        // 透传给普通事件处理
        _handleEvent(agentEvent, conversationId);
      case LoopDone(totalIterations: final iters, summary: final summary):
        _flushStreamBuffer();
        final doneMsg = ChatMessage.assistant(
          '─── ✅ Loop 完成 ($iters 轮) ───\n\n$summary',
        );
        state = state.copyWith(
          messages: [...state.messages, doneMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
        );
        _conversationsDao.saveMessage(conversationId, doneMsg);
        PetObserver.instance.notifyAiCompleted(summary: 'Loop 完成: $iters 轮');
        // 宠物奖励
        if (_currentTokenCount > 0) {
          PetEconomy.instance.rewardForTokens(_currentTokenCount).then((
            reward,
          ) {
            if (reward > 0) PetChatService.instance.showCoinReward(reward);
          });
          _currentTokenCount = 0;
        }
      case LoopExhausted(maxIterations: final max, lastOutput: final output):
        _flushStreamBuffer();
        final exhaustedMsg = ChatMessage.assistant(
          '─── ⚠️ Loop 达到最大轮次 ($max 轮)，自动停止 ───\n\n'
          '最后输出：${output.length > 300 ? '${output.substring(0, 300)}...' : output}',
        );
        state = state.copyWith(
          messages: [...state.messages, exhaustedMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
        );
        _conversationsDao.saveMessage(conversationId, exhaustedMsg);
      case LoopAbort(iteration: final iter, reason: final reason):
        _flushStreamBuffer();
        final abortMsg = ChatMessage.assistant(
          '─── ❌ Loop 放弃 (第 $iter 轮) ───\n\n原因：$reason',
        );
        state = state.copyWith(
          messages: [...state.messages, abortMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
        );
        _conversationsDao.saveMessage(conversationId, abortMsg);
      case LoopError(iteration: final iter, message: final msg):
        state = state.copyWith(loopRunning: false, loopIteration: 0);
        _setError('Loop 第 $iter 轮出错: $msg');
      case LoopStalled(iteration: final iter):
        _flushStreamBuffer();
        final stalledMsg = ChatMessage.assistant(
          '─── ⚠️ Loop 检测到无进展 (第 $iter 轮)，自动停止 ───\n\n'
          '连续两轮操作高度相似，可能陷入循环。请调整任务描述后重试。',
        );
        state = state.copyWith(
          messages: [...state.messages, stalledMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
        );
        _conversationsDao.saveMessage(conversationId, stalledMsg);
    }
  }

  void _handleEvent(AgentEvent event, int conversationId) {
    switch (event) {
      case AgentToken(text: final text):
        _currentTokenCount += ComputeService.estimateTokens(text);
        // 合并写入缓冲，由计时器周期性刷新到 state，避免每 token 一次全量 rebuild
        _streamBuffer.write(text);
        _flushTimer ??= Timer(_flushInterval, _flushStreamBuffer);
      case AgentToolStart(name: final name, args: final args):
        // 工具开始前先把缓冲刷净，保证下面读取的 streamingText 完整
        _flushStreamBuffer();
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
        // 刷净缓冲，确保 state.streamingText 含全部已流式文本
        _flushStreamBuffer();
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
        // 刷净缓冲，保留出错前已生成的部分文本
        _flushStreamBuffer();
        AppLogger.instance.log('[ChatProvider] AgentError: $message');
        PetObserver.instance.notifyAiError(error: message);
        _setError(message);
      case AgentLoopLimitReached(rounds: final rounds):
        // 单轮对话内部工具调用轮次熔断：保留已生成的部分文本，明确提示原因，
        // 与真正的 LLM/网络错误(AgentError)区分开，不走 _friendlyError 的
        // 异常文案启发式匹配。
        _flushStreamBuffer();
        final message = '本次回复内部工具调用次数过多(已达上限 $rounds 次)，已自动中止';
        AppLogger.instance.log('[ChatProvider] AgentLoopLimitReached: $rounds');
        PetObserver.instance.notifyAiError(error: message);
        _setError(message);
    }
  }

  /// 中断当前流式响应 — 保留已生成的部分输出并标记为「用户中断」
  void cancelResponse() {
    _subscription?.cancel();
    _subscription = null;
    // 中断前刷净缓冲，保留已生成的部分输出
    _flushStreamBuffer();
    // 清理 AgentLoop 可能已写入的不完整 tool_calls 序列
    _sanitizeAgentMessages();

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
          .map(
            (tc) => ChatMessage(
              role: ChatRole.assistant,
              content: '[工具调用] ${tc.name}',
              toolCalls: [
                ChatToolCall(id: tc.id, name: tc.name, arguments: tc.arguments),
              ],
            ),
          )
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
    _flushTimer?.cancel();
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

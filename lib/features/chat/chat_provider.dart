import 'dart:async';
import 'dart:convert';
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
  final String streamingThinking; // 新增：流式思考内容缓冲
  final List<ToolCallDisplay> activeToolCalls;

  /// 流式可视化文件列表（实时更新）
  final List<String> streamingHtmlFiles;
  final List<String> streamingSvgFiles;
  final List<String> streamingVideoFiles;

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

  /// 消息分页：是否还有更早的历史消息
  final bool hasMoreHistory;

  /// 消息分页：当前显示的第一条消息的数据库 ID（用于加载更早消息）
  final int? firstMessageId;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.streamingText = '',
    this.streamingThinking = '', // 新增
    this.activeToolCalls = const [],
    this.streamingHtmlFiles = const [],
    this.streamingSvgFiles = const [],
    this.streamingVideoFiles = const [],
    this.error,
    this.currentConversationId,
    this.attachments = const [],
    this.pendingPermission,
    this.loopEnabled = false,
    this.loopIteration = 0,
    this.loopMaxIterations = 20,
    this.loopRunning = false,
    this.subReadersRun,
    this.hasMoreHistory = false,
    this.firstMessageId,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingHistory,
    String? streamingText,
    String? streamingThinking, // 新增
    List<ToolCallDisplay>? activeToolCalls,
    List<String>? streamingHtmlFiles,
    List<String>? streamingSvgFiles,
    List<String>? streamingVideoFiles,
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
    bool? hasMoreHistory,
    int? firstMessageId,
  }) => ChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
    streamingText: streamingText ?? this.streamingText,
    streamingThinking: streamingThinking ?? this.streamingThinking, // 新增
    activeToolCalls: activeToolCalls ?? this.activeToolCalls,
    streamingHtmlFiles: streamingHtmlFiles ?? this.streamingHtmlFiles,
    streamingSvgFiles: streamingSvgFiles ?? this.streamingSvgFiles,
    streamingVideoFiles: streamingVideoFiles ?? this.streamingVideoFiles,
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
    hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
    firstMessageId: firstMessageId ?? this.firstMessageId,
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

  /// 上次扫描项目技能目录时记录的 mtime，用于轻量变化检测。
  /// 已有 AgentContext 缓存时，只在此时间戳变化时才执行完整重扫，
  /// 避免每条消息都遍历磁盘，同时确保用户手动放入新技能也能被及时发现。
  DateTime? _projectSkillsDirMtime;

  /// 当前对话轮次的 hooks 引用 (用于 AgentDone 后触发 onAgentDone)
  List<AgentHook> _activeHooks = [];

  /// 当前轮次的 token 计数（用于宠物经济系统奖励）
  int _currentTokenCount = 0;

  /// ─── AgentContext 缓存 ───
  /// 同一个对话会话内复用，避免每条消息发送时都全量重建(加载技能、
  /// 扫描目录、解析 JSON、MCP 工具收集等)。仅在以下时机 invalidate:
  /// - 新建会话 (newConversation)
  /// - 加载历史会话 (loadConversation)
  /// - 显式切换模型 (switchModel)
  /// 其他情况(如技能变化)由 _activeSkillSig 机制处理，不需要重建整个 context。
  AgentContext? _cachedAgentContext;
  AgentContextBuilder? _cachedContextBuilder;

  /// 流式 token 合并缓冲：每个 token 先入此缓冲，由 [_flushTimer] 周期性合并到
  /// state.streamingText，避免"每 token 一次 setState + 全量 rebuild + markdown 重解析"
  /// 导致的长思考卡顿。仅改变状态刷新时机，不改变最终文本内容。
  final StringBuffer _streamBuffer = StringBuffer();
  Timer? _flushTimer;

  /// 思考内容的流式缓冲（与 _streamBuffer 类似）
  final StringBuffer _thinkingBuffer = StringBuffer();
  Timer? _thinkingFlushTimer;

  /// 流式刷新间隔。100ms（≈10fps）已经足够顺滑，把每秒 setState 次数
  /// 从数百次降到 ~10 次，大幅减少 UI 重建开销。
  static const _flushInterval = Duration(milliseconds: 100);

  /// 思考内容的刷新间隔。300ms = 每秒最多 3-4 次更新，大幅减少 UI 重建。
  /// 思考内容用户不太关注实时性，可以设置得更长。
  static const _thinkingFlushInterval = Duration(milliseconds: 300);

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

  /// 把累积的思考缓冲合并进 state.streamingThinking 并清空缓冲、停掉计时器。
  void _flushThinkingBuffer() {
    _thinkingFlushTimer?.cancel();
    _thinkingFlushTimer = null;
    if (_thinkingBuffer.isEmpty) return;
    final pending = _thinkingBuffer.toString();
    _thinkingBuffer.clear();
    state = state.copyWith(
      streamingThinking: state.streamingThinking + pending,
    );
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
    _thinkingFlushTimer?.cancel(); // ✅ 清理思考缓冲定时器
    _thinkingFlushTimer = null;
    _thinkingBuffer.clear();
    // hooks: onSessionEnd
    await _fireSessionEnd();
    _agentMessages.clear();
    _activeSkillSig = null;
    _projectSkillsDirMtime = null;
    _cachedAgentContext = null;
    _cachedContextBuilder = null;
    state = const ChatState();
    // 刷新历史列表
    _ref.read(conversationsProvider.notifier).refresh();
  }

  /// 加载已有会话
  Future<void> loadConversation(int conversationId) async {
    _subscription?.cancel();
    _agentMessages.clear();
    _activeSkillSig = null;
    _projectSkillsDirMtime = null;
    _cachedAgentContext = null;
    _cachedContextBuilder = null;

    // 进入加载状态，让 UI 显示过渡动画
    state = state.copyWith(isLoadingHistory: true);

    // 分页加载：初始加载最近 30 条消息
    const initialPageSize = 30;
    final dbMessages = await _conversationsDao.getMessagesPage(
      conversationId,
      limit: initialPageSize,
    );
    final totalCount = await _conversationsDao.getMessageCount(conversationId);
    final hasMore = dbMessages.length < totalCount;

    // 提取消息和第一条消息的 ID
    final messages = dbMessages.map((dm) => dm.message).toList();
    final firstMsgId = dbMessages.isNotEmpty ? dbMessages.first.id : null;

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
      hasMoreHistory: hasMore,
      firstMessageId: firstMsgId,
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
    // 模型变了需要重建 LLM 客户端和可能的 system prompt(token 限制不同)
    _cachedAgentContext = null;
    _cachedContextBuilder = null;
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

  /// 加载更早的历史消息（向上翻页）
  Future<void> loadOlderMessages() async {
    final conversationId = state.currentConversationId;
    final firstMsgId = state.firstMessageId;

    if (conversationId == null ||
        firstMsgId == null ||
        !state.hasMoreHistory ||
        state.isLoadingHistory) {
      return;
    }

    state = state.copyWith(isLoadingHistory: true);

    try {
      // 加载更早的一批消息（20条）
      const pageSize = 20;
      final dbMessages = await _conversationsDao.getMessagesPage(
        conversationId,
        limit: pageSize,
        beforeMessageId: firstMsgId,
      );

      if (dbMessages.isEmpty) {
        state = state.copyWith(isLoadingHistory: false, hasMoreHistory: false);
        return;
      }

      final olderMessages = dbMessages.map((dm) => dm.message).toList();
      final newFirstMsgId = dbMessages.first.id;

      // 更新 _agentMessages（在 system prompt 后插入）
      final systemMsgCount = _agentMessages
          .where((m) => m['role'] == 'system')
          .length;
      for (var i = olderMessages.length - 1; i >= 0; i--) {
        final msg = olderMessages[i];
        if (msg.role != ChatRole.system) {
          _agentMessages.insert(systemMsgCount, msg.toMap());
        }
      }

      // 过滤掉系统消息
      final olderDisplayMessages = olderMessages
          .where((m) => m.role != ChatRole.system)
          .toList();

      // 将新消息追加到现有消息前面
      final currentMessages = state.messages;
      final updatedMessages = [...olderDisplayMessages, ...currentMessages];

      // 检查是否还有更多
      final totalCount = await _conversationsDao.getMessageCount(
        conversationId,
      );
      final hasMore = updatedMessages.length < totalCount;

      state = state.copyWith(
        messages: updatedMessages,
        isLoadingHistory: false,
        hasMoreHistory: hasMore,
        firstMessageId: newFirstMsgId,
      );
    } catch (e) {
      AppLogger.instance.log('[加载历史消息失败] $e');
      state = state.copyWith(isLoadingHistory: false);
    }
  }

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
        maxOutputTokens: modelCard.maxOutputTokens,
      ),
      // 每个子任务独立一份只读 Executor 实例，互不共享可变状态；
      // 因为只读，即使多个子 Agent 同时指向同一 workDir 也不会产生写冲突。
      // allowOutsideRoot: true 使子 Agent 可以访问用户指定的任意绝对路径
      // (桌面交互模式下与主 Executor 行为一致，否则跨目录读取会被"路径越界"拒绝)。
      createReadOnlyExecutor: () =>
          ReadOnlyExecutor(projectRoot: workDir, allowOutsideRoot: true),
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

    // ─── 防御性清理：上一轮被中断后 AgentLoop generator 可能在后续微任务
    // 中继续往 _agentMessages 追加了 tool/assistant(tool_calls) 消息，
    // 导致消息链不合法。在新一轮起步前再做一次 sanitize 确保干净。
    _sanitizeAgentMessages();

    // 快照附件并立即清空 UI 中的附件列表
    final pendingAttachments = List<FileAttachment>.from(state.attachments);

    // ─── 立即更新 UI 状态 → 让按钮点击有即时视觉反馈，消除卡顿感 ───
    final userMsg = ChatMessage.user(input, attachments: pendingAttachments);
    _flushTimer?.cancel();
    _flushTimer = null;
    _streamBuffer.clear();
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      streamingText: '',
      streamingThinking: '',
      streamingHtmlFiles: [],
      streamingSvgFiles: [],
      streamingVideoFiles: [],
      activeToolCalls: [],
      error: null,
      attachments: [],
    );
    PetObserver.instance.notifyUserMessage(
      preview: input.length > 30 ? '${input.substring(0, 30)}...' : input,
    );

    // ─── 让出一帧给 UI 渲染 loading 状态，然后再执行重活 ───
    // 这保证了上面 setState 的新状态能先被 Flutter 引擎处理并绘制，
    // 用户看到的是"发送后立即进入 loading 动画"，而不是"按钮卡住不动"。
    await Future<void>.delayed(Duration.zero);

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
    // 写入了新的项目级技能，或者用户手动往该目录放入了新技能文件夹。
    // 策略：
    // - 无缓存（首条消息 / 会话切换）时：无条件全量重扫
    // - 有缓存时：仅检查 .toolshell/skills/ 目录的 mtime，变了才重扫+重建 context
    //   mtime 检查是纯内存 stat 调用（<1ms），避免每条消息都遍历磁盘
    bool needRescanSkills = false;
    if (_cachedAgentContext == null) {
      needRescanSkills = true;
    } else {
      // 轻量 mtime 检查
      final skillsDir = Directory(
        '${_ref.read(workingDirectoryProvider)}/.toolshell/skills',
      );
      try {
        if (await skillsDir.exists()) {
          final stat = await skillsDir.stat();
          if (_projectSkillsDirMtime == null ||
              stat.modified != _projectSkillsDirMtime) {
            needRescanSkills = true;
          }
        } else if (_projectSkillsDirMtime != null) {
          // 目录被删除了，也需要刷新
          needRescanSkills = true;
        }
      } catch (_) {
        // stat 失败忽略，不影响正常流程
      }
    }

    if (needRescanSkills) {
      try {
        _ref.invalidate(projectSkillsProvider);
        await _ref.read(projectSkillsProvider.future);
        // 记录当前 mtime
        final skillsDir = Directory(
          '${_ref.read(workingDirectoryProvider)}/.toolshell/skills',
        );
        if (await skillsDir.exists()) {
          final stat = await skillsDir.stat();
          _projectSkillsDirMtime = stat.modified;
        } else {
          _projectSkillsDirMtime = null;
        }
        // 有缓存时检测到变化，需要重建 context 以加载新技能的工具和 prompt
        if (_cachedAgentContext != null) {
          _cachedAgentContext = null;
          _cachedContextBuilder = null;
        }
      } catch (e) {
        print('[SKILL] 重扫项目技能失败(忽略): $e');
      }
    }

    // ─── 使用 AgentContext 构建执行环境 ───
    // 同一个对话会话内复用缓存，避免每条消息都全量重建(节省 100-500ms)。
    // 需要重建的时机已在 newConversation/loadConversation/switchModel 中 invalidate。
    final contextBuilder = _cachedContextBuilder ?? AgentContextBuilder(_ref);
    final agentContext =
        _cachedAgentContext ??
        await contextBuilder.build(
          modelCard: modelCard,
          existingMessages: _agentMessages,
          sessionAutoApprove: _sessionAutoApprove,
          onPermissionRequest: _onPermissionRequest,
          userInput: input,
        );
    _cachedAgentContext = agentContext;
    _cachedContextBuilder = contextBuilder;

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

    // 估算输入 token（包括所有历史消息 + 当前输入 + 系统提示词 + 工具定义）
    int inputTokens = 0;
    for (final msg in _agentMessages) {
      final content = msg['content'];
      if (content is String) {
        inputTokens += ComputeService.estimateTokens(content);
      }
      // 工具调用也算 token
      if (msg['tool_calls'] != null) {
        inputTokens += ComputeService.estimateTokens(
          jsonEncode(msg['tool_calls']),
        );
      }
    }
    // 当前用户输入
    inputTokens += ComputeService.estimateTokens(input);
    // 工具定义（粗略估算：每个工具约 100 tokens）
    inputTokens += agentContext.tools.length * 100;

    // 累积输入 token
    _currentTokenCount += inputTokens;

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
        contextWindow: agentContext.contextWindow,
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
        // Loop 中间轮次的 AgentDone 不是整个会话完成，不能走普通完成逻辑
        // （否则会关闭 loading、发完成通知、结算奖励，让 UI 看起来第一轮已结束）。
        if (agentEvent case AgentDone(content: final content)) {
          _flushStreamBuffer();
          final finalContent = content.isNotEmpty
              ? content
              : state.streamingText;
          if (finalContent.isNotEmpty) {
            final assistantMsg = ChatMessage.assistant(finalContent);
            state = state.copyWith(
              messages: [...state.messages, assistantMsg],
              streamingText: '',
              activeToolCalls: [],
              isLoading: true,
            );
            _conversationsDao.saveMessage(conversationId, assistantMsg);
          } else {
            state = state.copyWith(
              streamingText: '',
              activeToolCalls: [],
              isLoading: true,
            );
          }
        } else {
          _handleEvent(agentEvent, conversationId);
          // AgentError/熔断由 AutonomousLoop 随后的 LoopError 统一结束。
          if (agentEvent is AgentError || agentEvent is AgentLoopLimitReached) {
            // Loop 模式下熔断后清空工具调用，避免跨轮累积
            state = state.copyWith(
              isLoading: true,
              activeToolCalls: agentEvent is AgentLoopLimitReached
                  ? []
                  : state.activeToolCalls,
            );
          }
        }
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

  /// 可视化文件路径累积器
  final List<String> _htmlFiles = [];
  final List<String> _svgFiles = [];
  final List<String> _videoFiles = [];

  void _handleEvent(AgentEvent event, int conversationId) {
    switch (event) {
      case AgentHtmlGenerated(path: final path):
        _htmlFiles.add(path);
        // 实时更新流式状态
        state = state.copyWith(streamingHtmlFiles: List.from(_htmlFiles));
      case AgentSvgGenerated(path: final path):
        _svgFiles.add(path);
        // 实时更新流式状态
        state = state.copyWith(streamingSvgFiles: List.from(_svgFiles));
      case AgentVideoGenerated(path: final path):
        _videoFiles.add(path);
        // 实时更新流式状态
        state = state.copyWith(streamingVideoFiles: List.from(_videoFiles));
      case AgentReasoningToken(text: final text):
        // 推理过程流式累积到 streamingThinking
        _currentTokenCount += ComputeService.estimateTokens(text);

        // 使用缓冲机制，减少 UI 更新频率
        _thinkingBuffer.write(text);
        _thinkingFlushTimer?.cancel();
        _thinkingFlushTimer = Timer(
          _thinkingFlushInterval,
          _flushThinkingBuffer,
        );
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
        var cleanedStream = state.streamingText.contains('DSML')
            ? ''
            : state.streamingText;

        // 自动补全未闭合的 <thinking> 标签
        // 某些模型在思考模式下调用工具时，会输出 <thinking> 但忘记闭合标签
        if (cleanedStream.contains('<thinking>') &&
            !cleanedStream.contains('</thinking>')) {
          cleanedStream += '\n</thinking>';
        }

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
        _flushThinkingBuffer();

        // 如果最终 content 为空，使用之前流式累积的文本
        // (某些模型在 tool_call 后的回复轮次不返回 content)
        final finalContent = content.isNotEmpty ? content : state.streamingText;
        final finalThinking = state.streamingThinking.isNotEmpty
            ? state.streamingThinking
            : null;

        // 准备消息对象
        final assistantMsg = ChatMessage.assistant(
          finalContent,
          thinkingContent: finalThinking,
          htmlFiles: List.from(_htmlFiles),
          svgFiles: List.from(_svgFiles),
          videoFiles: List.from(_videoFiles),
        );
        final toolMessages = state.activeToolCalls.map((tc) {
          return ChatMessage(
            role: ChatRole.assistant,
            content: '[工具调用] ${tc.name}',
            toolCalls: [
              ChatToolCall(id: tc.id, name: tc.name, arguments: tc.arguments),
            ],
          );
        }).toList();

        // ✅ 原子性更新：一次性完成状态切换，避免中间帧出现"空白"
        // 同时清空流式状态 + 添加最终消息，让工具UI消失的同时总结内容立即出现
        state = state.copyWith(
          messages: [...state.messages, ...toolMessages, assistantMsg],
          isLoading: false,
          streamingText: '',
          streamingThinking: '',
          streamingHtmlFiles: [],
          streamingSvgFiles: [],
          streamingVideoFiles: [],
          activeToolCalls: [],
        );

        // 清空可视化文件累积器
        _htmlFiles.clear();
        _svgFiles.clear();
        _videoFiles.clear();

        // 异步：数据库保存和其他耗时操作（不阻塞UI）
        Future.microtask(() async {
          // 保存助手消息到数据库（可能耗时）
          await _conversationsDao.saveMessage(conversationId, assistantMsg);

          // 触发 hooks: onAgentDone (记忆存储等后处理，可能耗时)
          for (final hook in _activeHooks) {
            await hook.onAgentDone(finalContent, []);
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
            final reward = await PetEconomy.instance.rewardForTokens(
              _currentTokenCount,
            );
            if (reward > 0) {
              // 通过宠物气泡通知用户
              PetChatService.instance.showCoinReward(reward);
            }
            _currentTokenCount = 0;
          }
        });
      case AgentError(message: final message):
        // 刷净缓冲，保留出错前已生成的部分文本
        _flushStreamBuffer();
        _flushThinkingBuffer();
        AppLogger.instance.log('[ChatProvider] AgentError: $message');

        final hasContent = state.streamingText.isNotEmpty;
        final hasThinking = state.streamingThinking.isNotEmpty;
        final hasToolCalls = state.activeToolCalls.isNotEmpty;

        // 统计工具调用次数
        final toolStats = <String, int>{};
        for (final tc in state.activeToolCalls) {
          toolStats[tc.name] = (toolStats[tc.name] ?? 0) + 1;
        }

        // 构建工具调用列表文本
        String toolCallsSection = '';
        if (hasToolCalls) {
          final statsText = toolStats.entries
              .map((e) => '- **${e.key}**: ${e.value}次')
              .join('\n');
          toolCallsSection =
              '\n\n📋 **已执行的工具调用**（共 ${state.activeToolCalls.length} 次）：\n$statsText';
        }

        // 构建错误总结消息
        final errorSummary =
            '''
⚠️ **LLM 响应异常中断**

$message
${hasContent ? '\n\n**已生成的部分内容：**\n\n${state.streamingText}' : ''}$toolCallsSection

💡 **建议：**
- 检查模型的 max_tokens 设置（可能输出超限）
- 减少工具调用数量或简化任务
- 检查网络连接和代理设置
- 尝试重新发送消息
'''
                .trim();

        // 保存工具调用记录
        final toolCallsData = state.activeToolCalls.map((tc) {
          return ChatToolCall(
            id: tc.id,
            name: tc.name,
            arguments: tc.arguments,
          );
        }).toList();

        // 创建 assistant 消息（包含工具调用记录）
        final assistantMsg = ChatMessage.assistant(
          errorSummary,
          thinkingContent: hasThinking ? state.streamingThinking : null,
          toolCalls: toolCallsData.isNotEmpty ? toolCallsData : null,
        );

        // 更新 UI 状态
        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          streamingText: '',
          streamingThinking: '',
          activeToolCalls: [],
          isLoading: false,
        );

        // 保存到数据库
        _conversationsDao.saveMessage(conversationId, assistantMsg);

        AppLogger.instance.log('[ChatProvider] AgentError 已保存总结消息到对话历史');
        PetObserver.instance.notifyAiError(error: message);
      case AgentLoopLimitReached(rounds: final rounds):
        // 单轮对话内部工具调用轮次熔断：保留已生成的部分文本和工具调用记录，
        // 生成友好的总结消息并保存到对话历史，让用户看到 AI 做了什么。
        _flushStreamBuffer();
        _flushThinkingBuffer();

        final hasContent = state.streamingText.isNotEmpty;
        final hasThinking = state.streamingThinking.isNotEmpty;
        final hasToolCalls = state.activeToolCalls.isNotEmpty;

        // 统计工具调用次数
        final toolStats = <String, int>{};
        for (final tc in state.activeToolCalls) {
          toolStats[tc.name] = (toolStats[tc.name] ?? 0) + 1;
        }

        // 构建工具调用列表文本
        String toolCallsSection = '';
        if (hasToolCalls) {
          final statsText = toolStats.entries
              .map((e) => '- **${e.key}**: ${e.value}次')
              .join('\n');
          toolCallsSection =
              '\n\n📋 **已执行的工具调用**（共 ${state.activeToolCalls.length} 次）：\n$statsText';
        }

        // 构建熔断总结消息
        final summaryMessage =
            '''
⚠️ **工具调用次数已达上限（$rounds 次），已自动中止**
${hasContent ? '\n\n**以下是已完成的部分内容：**\n\n${state.streamingText}' : ''}$toolCallsSection

💡 **建议：**
- 请将任务拆分为更小的步骤
- 提供更明确的目标描述
- 或者手动执行部分步骤后再继续
'''
                .trim();

        // 保存工具调用记录
        final toolCallsData = state.activeToolCalls.map((tc) {
          return ChatToolCall(
            id: tc.id,
            name: tc.name,
            arguments: tc.arguments,
          );
        }).toList();

        // 创建 assistant 消息（包含工具调用记录）
        final assistantMsg = ChatMessage.assistant(
          summaryMessage,
          thinkingContent: hasThinking ? state.streamingThinking : null,
          toolCalls: toolCallsData.isNotEmpty ? toolCallsData : null,
        );

        // 更新 UI 状态
        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          streamingText: '',
          streamingThinking: '',
          activeToolCalls: [],
          isLoading: false,
        );

        // 保存到数据库
        _conversationsDao.saveMessage(conversationId, assistantMsg);

        AppLogger.instance.log(
          '[ChatProvider] AgentLoopLimitReached: $rounds，已保存总结消息',
        );
        PetObserver.instance.notifyAiError(error: '工具调用熔断: $rounds 次');
    }
  }

  /// 中断当前流式响应 — 保留已生成的部分输出并标记为「用户中断」
  void cancelResponse() {
    _subscription?.cancel();
    _subscription = null;

    // ✅ 停止所有定时器，防止 UI 继续渲染
    _flushTimer?.cancel();
    _flushTimer = null;
    _thinkingFlushTimer?.cancel();
    _thinkingFlushTimer = null;

    // 先判断是否有任何输出（在刷缓冲之前）
    final hasContent =
        state.streamingText.isNotEmpty || _streamBuffer.isNotEmpty;
    final hasThinking =
        state.streamingThinking.isNotEmpty || _thinkingBuffer.isNotEmpty;
    final hasToolCalls = state.activeToolCalls.isNotEmpty;

    AppLogger.instance.log(
      '[cancelResponse] hasContent=$hasContent, hasThinking=$hasThinking, '
      'hasToolCalls=$hasToolCalls, streamingText.length=${state.streamingText.length}, '
      'buffer.length=${_streamBuffer.length}',
    );

    // 中断前刷净缓冲，保留已生成的部分输出
    _flushStreamBuffer();
    _flushThinkingBuffer(); // ✅ 刷新思考缓冲
    // 清理 AgentLoop 可能已写入的不完整 tool_calls 序列
    _sanitizeAgentMessages();

    final partial = state.streamingText;
    final convId = state.currentConversationId;

    // 只要有部分文本或正在执行的工具调用，都应保留到消息列表
    if (hasContent || hasToolCalls) {
      // 构建已中断的助手消息
      final content = partial.isNotEmpty
          ? partial
          : state.activeToolCalls.map((tc) => '[工具调用中] ${tc.name}').join('\n');
      final thinkingContent = state.streamingThinking.isNotEmpty
          ? state.streamingThinking
          : null;

      // 将工具调用历史包含到消息中（用于持久化和恢复显示）
      final toolCalls = state.activeToolCalls
          .where(
            (tc) =>
                tc.status == ToolCallStatus.done ||
                tc.status == ToolCallStatus.executing,
          )
          .map(
            (tc) =>
                ChatToolCall(id: tc.id, name: tc.name, arguments: tc.arguments),
          )
          .toList();

      final assistantMsg = ChatMessage.assistant(
        content,
        interrupted: true,
        thinkingContent: thinkingContent,
        toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
        streamingText: '',
        streamingThinking: '', // 清空 thinking 缓冲
        activeToolCalls: [],
        loopRunning: false, // ✅ 释放 loop 锁
        loopIteration: 0, // ✅ 重置迭代计数
      );

      // 持久化（包含工具调用信息，供 UI 展示历史）
      if (convId != null) {
        _conversationsDao.saveMessage(convId, assistantMsg);
      }

      // 同步 agentMessages 上下文（给 LLM 的历史）
      // ⚠️ 关键决策：中断时如果有 tool_calls，有两种选择：
      // 1. 只保存 content，不保存 tool_calls（避免 400 错误）
      // 2. 保存 tool_calls + 为每个添加虚拟 tool response
      //
      // 这里选择方案 1：中断的工具调用不应该影响后续对话的消息链完整性。
      // UI 层（state.messages）仍然会展示工具调用记录，但 LLM 看不到。
      if (toolCalls.isNotEmpty) {
        // 有工具调用时，为每个已完成的工具添加 tool response
        // 只保留真正执行完成的工具结果
        final completedToolCalls = state.activeToolCalls
            .where(
              (tc) => tc.status == ToolCallStatus.done && tc.result != null,
            )
            .toList();

        if (completedToolCalls.isNotEmpty) {
          // 添加 assistant 消息（带 tool_calls）
          final agentMsg = <String, dynamic>{
            'role': 'assistant',
            'content': content,
            'tool_calls': completedToolCalls.map((tc) {
              return {
                'id': tc.id,
                'type': 'function',
                'function': {
                  'name': tc.name,
                  'arguments': jsonEncode(tc.arguments),
                },
              };
            }).toList(),
          };
          _agentMessages.add(agentMsg);

          // 为每个完成的工具添加 tool response
          for (final tc in completedToolCalls) {
            _agentMessages.add({
              'role': 'tool',
              'tool_call_id': tc.id,
              'content': tc.result ?? '',
            });
          }
        } else {
          // 所有工具都未完成，只保存 content（不含 tool_calls）
          _agentMessages.add({'role': 'assistant', 'content': content});
        }
      } else {
        // 没有工具调用，正常添加
        _agentMessages.add({'role': 'assistant', 'content': content});
      }
    } else {
      // 完全没有 content，但可能有 thinking
      if (hasThinking) {
        // 有 thinking 但无 content：保存 thinking
        final assistantMsg = ChatMessage.assistant(
          '', // content 为空
          interrupted: true,
          thinkingContent: state.streamingThinking,
        );

        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          isLoading: false,
          streamingText: '',
          streamingThinking: '',
          activeToolCalls: [],
          loopRunning: false, // ✅ 释放 loop 锁
          loopIteration: 0, // ✅ 重置迭代计数
        );

        // 持久化
        if (convId != null) {
          _conversationsDao.saveMessage(convId, assistantMsg);
        }
      } else {
        // 完全没有任何输出：显示"用户中断了输出"的消息
        AppLogger.instance.log('[cancelResponse] 走入"完全没有输出"分支');

        final assistantMsg = ChatMessage.assistant(
          '[用户中断了输出]',
          interrupted: true,
          thinkingContent: null,
        );

        AppLogger.instance.log(
          '[cancelResponse] 创建中断消息: content="${assistantMsg.content}", '
          'interrupted=${assistantMsg.interrupted}',
        );

        state = state.copyWith(
          messages: [...state.messages, assistantMsg],
          isLoading: false,
          streamingText: '',
          streamingThinking: '',
          activeToolCalls: [],
          loopRunning: false, // ✅ 释放 loop 锁
          loopIteration: 0, // ✅ 重置迭代计数
        );

        AppLogger.instance.log(
          '[cancelResponse] 状态已更新，消息数量=${state.messages.length}',
        );

        // 持久化（让用户知道确实点了停止）
        if (convId != null) {
          _conversationsDao.saveMessage(convId, assistantMsg);
          AppLogger.instance.log('[cancelResponse] 消息已保存到数据库');
        }
      }
    }

    // ─── 延迟防御清理 ───
    // _subscription?.cancel() 只是调度了取消，AgentLoop 的 async* generator
    // 在后续微任务中可能仍会往 _agentMessages 追加消息（比如 tool result 或
    // assistant(tool_calls)），导致消息链再次进入不合法状态。
    // 调度一个延迟微任务，在 generator 最终停止后做最后一遍 sanitize。
    Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
      if (mounted) _sanitizeAgentMessages();
    });
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
    _projectSkillsDirMtime = null;
    state = const ChatState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _flushTimer?.cancel();
    _thinkingFlushTimer?.cancel(); // ✅ 取消思考缓冲定时器
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

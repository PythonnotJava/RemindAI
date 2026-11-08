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
import '../../core/toolshell/budget.dart';
import '../../core/toolshell/read_only_executor.dart';
import '../../core/toolshell/sub_readers_orchestrator.dart';
import '../../core/utils/file_processor.dart';
import '../../core/pet/pet_observer.dart';
import '../../providers/database_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/session_provider.dart';
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

  /// 画图子 Agent 本轮生成的图片路径（实时更新）
  final List<String> streamingImageFiles;

  final String? error;
  final int? currentConversationId;
  final List<FileAttachment> attachments;
  final PendingPermission? pendingPermission;

  /// Loop 模式状态
  final bool loopEnabled;
  final int loopIteration;
  final int loopMaxIterations;
  final bool loopRunning;

  /// 预算档位（任务分档：简单问答 / 日常编码 / 大型重构 / 自定义）
  final AgentTaskTier budgetTier;

  /// 自定义档位的执行预算（仅 [budgetTier] == custom 时生效）
  final ExecutionLimits? customLimits;

  /// 最近一次预算快照（UI 实时显示"已用工具轮 / 预算"）
  final BudgetSnapshot? budget;

  /// 是否因预算耗尽暂停（暂停时 UI 提供"追加预算继续"入口）
  final bool budgetPaused;

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
    this.streamingImageFiles = const [],
    this.error,
    this.currentConversationId,
    this.attachments = const [],
    this.pendingPermission,
    this.loopEnabled = false,
    this.loopIteration = 0,
    this.loopMaxIterations = 20,
    this.loopRunning = false,
    this.budgetTier = AgentTaskTier.coding,
    this.customLimits,
    this.budget,
    this.budgetPaused = false,
    this.subReadersRun,
    this.hasMoreHistory = false,
    this.firstMessageId,
  });

  /// 当前生效的执行预算
  ExecutionLimits get effectiveLimits => budgetTier == AgentTaskTier.custom
      ? (customLimits ?? ExecutionLimits.coding)
      : ExecutionLimits.of(budgetTier);

  /// 当前生效的任务分档策略
  TaskTierPolicy get effectivePolicy => TaskTierPolicy.of(
    budgetTier == AgentTaskTier.custom ? AgentTaskTier.coding : budgetTier,
  ).withLimits(effectiveLimits);

  /// 是否处于可"追加预算继续"的状态
  bool get canExtendBudget => budgetPaused && budget != null;

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
    List<String>? streamingImageFiles,
    String? error,
    /// 显式清除 [error]。
    ///
    /// 为什么需要这个开关：`String?` 参数无法区分"没传"和"传了 null"，
    /// 早先这里是 `error: error`，导致任何没显式带上 error 的 copyWith
    /// 都会把当前错误提示静默抹掉（错误刚显示就消失，且难排查）。
    /// 现在语义是"不传则保留"，清错必须显式说 clearError。
    bool clearError = false,
    int? currentConversationId,
    bool clearConversationId = false,
    List<FileAttachment>? attachments,
    PendingPermission? pendingPermission,
    bool clearPermission = false,
    bool? loopEnabled,
    int? loopIteration,
    int? loopMaxIterations,
    bool? loopRunning,
    AgentTaskTier? budgetTier,
    ExecutionLimits? customLimits,
    BudgetSnapshot? budget,
    bool clearBudget = false,
    bool? budgetPaused,
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
    streamingImageFiles: streamingImageFiles ?? this.streamingImageFiles,
    error: clearError ? null : (error ?? this.error),
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
    budgetTier: budgetTier ?? this.budgetTier,
    customLimits: customLimits ?? this.customLimits,
    budget: clearBudget ? null : (budget ?? this.budget),
    budgetPaused: budgetPaused ?? this.budgetPaused,
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

  /// ─── 预算续跑上下文（"追加预算继续"用）───
  /// 预算耗尽时把规划预算与进展追踪器留下来，用户点"追加预算继续"后
  /// 带着已用额度接着跑，而不是从零重开一遍任务。
  PlanningBudget? _activePlanning;
  ToolProgressTracker? _activeTracker;

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
    _imageFiles.clear();
    _imageNotices.clear();
    _ref.read(sessionImageRegistryProvider).clear();
    _activeSkillSig = null;
    _projectSkillsDirMtime = null;
    _cachedAgentContext = null;
    _cachedContextBuilder = null;
    // 「本会话始终允许」(approveAlways) 只对**当前**会话有效。
    // 不复位的话，在 A 会话点过一次 auto，切到 B 会话后 B 也在无提示地
    // 自动执行写/删/命令——用户完全没对新会话授权。
    _sessionAutoApprove = false;
    state = const ChatState();
    // 刷新历史列表
    _ref.read(conversationsProvider.notifier).refresh();
  }

  /// 加载已有会话
  Future<void> loadConversation(int conversationId) async {
    _subscription?.cancel();
    _agentMessages.clear();
    _imageFiles.clear();
    _imageNotices.clear();
    _activeSkillSig = null;
    _projectSkillsDirMtime = null;
    _cachedAgentContext = null;
    _cachedContextBuilder = null;
    // 同 newConversation：换会话必须重新征求 auto 授权（见该方法注释）。
    _sessionAutoApprove = false;

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

    // 从历史消息恢复图片注册表：用户附件 → A 编号，生成图附件 → G 编号。
    // 这样应用重启/切换会话后，“上一张”仍然可以引用。
    _restoreImageRegistry(displayMessages);

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

  /// 从历史消息重建图片注册表（按时间顺序重新分配 A/G 编号）。
  ///
  /// 图片 ID 不持久化，重启后重新生成；但图片路径来自消息附件，
  /// 因此“上一张/刚才那张”在历史会话里仍然可用。
  void _restoreImageRegistry(Iterable<ChatMessage> messages) {
    final registry = _ref.read(sessionImageRegistryProvider);
    registry.clear();
    for (final message in messages) {
      if (message.attachments.isEmpty) continue;
      for (final attachment in message.attachments) {
        if (!attachment.isImage) continue;
        if (message.role == ChatRole.user) {
          registry.restoreAttachment(attachment.path, label: attachment.name);
        } else if (message.role == ChatRole.assistant) {
          registry.restoreGenerated(attachment.path);
        }
      }
    }
  }

  /// 切换模型
  void switchModel(ModelCard modelCard) {
    _ref.read(activeModelCardProvider.notifier).state = modelCard;
    // 模型变了需要重建 LLM 客户端和可能的 system prompt(token 限制不同)
    _cachedAgentContext = null;
    _cachedContextBuilder = null;
  }

  /// 使当前缓存的 AgentContext 失效。
  ///
  /// 会话级工具集变化时调用（例如用户中途切换子画图模型），
  /// 下一轮 sendMessage 会重新构建工具列表 / system prompt。
  void invalidateAgentContext() {
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
      _restoreImageRegistry(updatedMessages);
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
  ///
  /// 兼容旧 UI：现在这个数字等价于"外层重新规划次数"，不再等同工具轮次。
  void setLoopMaxIterations(int max) {
    // 对齐到步进 5
    final aligned = ((max / 5).round() * 5).clamp(10, 100);
    state = state.copyWith(loopMaxIterations: aligned);
  }

  /// 选择任务预算档位（简单问答 / 日常编码 / 大型重构 / 自定义）
  ///
  /// UI 从"最大轮次"改成"任务预算"预设：用户只需要说清这是哪类任务，
  /// 具体数字（软/硬轮次、工具调用、墙钟、token）由档位给出。
  void setBudgetTier(AgentTaskTier tier) {
    final policy = TaskTierPolicy.of(
      tier == AgentTaskTier.custom ? AgentTaskTier.coding : tier,
    );
    state = state.copyWith(
      budgetTier: tier,
      customLimits: tier == AgentTaskTier.custom
          ? (state.customLimits ?? state.effectiveLimits)
          : null,
      loopMaxIterations: policy.maxPlans,
    );
  }

  /// 自定义档位：软上限轮次
  void setCustomSoftRounds(int rounds) => _updateCustomLimits((base) {
    final soft = rounds.clamp(5, 400);
    return base.copyWith(
      softRounds: soft,
      hardRounds: soft > base.hardRounds ? soft + 20 : base.hardRounds,
    );
  });

  /// 自定义档位：硬上限轮次
  void setCustomHardRounds(int rounds) => _updateCustomLimits((base) {
    final hard = rounds.clamp(10, 500);
    return base.copyWith(
      hardRounds: hard,
      softRounds: hard < base.softRounds ? hard : base.softRounds,
    );
  });

  /// 自定义档位：工具调用硬上限
  void setCustomToolCalls(int calls) => _updateCustomLimits((base) {
    final hard = calls.clamp(10, 2000);
    return base.copyWith(
      hardToolCalls: hard,
      softToolCalls: hard < base.softToolCalls ? hard : base.softToolCalls,
    );
  });

  void _updateCustomLimits(
    ExecutionLimits Function(ExecutionLimits base) update,
  ) {
    final base = state.customLimits ?? state.effectiveLimits;
    state = state.copyWith(
      budgetTier: AgentTaskTier.custom,
      customLimits: update(base),
    );
  }

  /// 预算耗尽后"继续追加预算"
  ///
  /// 语义：带着已用额度（轮次/调用/token/时长）继续，预算按比例放大，
  /// 历史消息与工具记录全部保留，模型从中断点接着做——而不是从零重开。
  Future<void> extendLoopBudget() async {
    if (!state.budgetPaused) return;
    final snapshot = state.budget;
    if (snapshot == null) return;

    final agentContext = _cachedAgentContext;
    if (agentContext == null) {
      _setError('会话上下文已失效，请重新发送消息');
      return;
    }

    // 规划预算只属于 Loop 模式；普通模式的"追加预算"直接放大执行预算。
    var planning = _activePlanning;
    if (state.loopEnabled) {
      planning ??= PlanningBudget(
        maxPlans: state.effectivePolicy.maxPlans,
        maxContinuations: state.effectivePolicy.maxContinuations,
      );
      if (!planning.consumeContinuation()) {
        _setError('追加预算次数已用完，建议把任务拆小或新开一轮对话');
        return;
      }
      planning.grantBonus(plans: 2, continuations: 2);
      _activePlanning = planning;
    }

    // 必须以"当前真实生效的上限"（快照）为基准继续放大。
    // 用 state.effectiveLimits 会退回分档基准：每次点都算出同一个上限，
    // 已用额度却在继承 —— 第二、三次追加等于没加，最终一次点击会
    // 在第 1 轮就被 token/时长硬上限立刻掐断。
    final extended = snapshot.extendedLimits();
    final budget = ExecutionBudget.resume(limits: extended, snapshot: snapshot);
    AppLogger.instance.log(
      '[ChatProvider] 追加预算：软 ${extended.softRounds}/硬 ${extended.hardRounds} 轮，'
      '${extended.hardToolCalls} 次调用，${extended.wallClock.inMinutes} 分钟，'
      'token 上限 ${extended.tokens}（原 ${snapshot.tokenLimit}），'
      '继承已用 ${snapshot.usedRounds} 轮 / ${snapshot.usedToolCalls} 次调用 / '
      '${snapshot.tokens} token / ${snapshot.elapsed.inMinutes} 分钟',
    );

    final notice = ChatMessage.assistant(
      '─── 🔋 已追加预算：软 ${extended.softRounds} / 硬 ${extended.hardRounds} 轮 · '
      '${extended.hardToolCalls} 次调用 · ${extended.wallClock.inMinutes} 分钟 ───',
    );
    state = state.copyWith(
      messages: [...state.messages, notice],
      budgetPaused: false,
      isLoading: true,
      clearError: true,
    );
    final conversationId = state.currentConversationId;
    if (conversationId != null) {
      _conversationsDao.saveMessage(conversationId, notice);
    }

    // 让模型知道"预算变了、从哪继续"，且不污染用户可见的聊天内容
    _agentMessages.add({
      'role': 'system',
      'content':
          '[预算追加] 执行预算已上调：软上限 ${extended.softRounds} 轮 / '
          '硬上限 ${extended.hardRounds} 轮、工具调用 ${extended.hardToolCalls} 次、'
          '${extended.wallClock.inMinutes} 分钟。请从中断点继续推进未完成的工作，'
          '不要重复已经完成的步骤；互不依赖的操作尽量并行。',
    });

    const resumePrompt = '继续：预算已追加，从中断点接着推进未完成的工作（不要重复已完成的步骤）。';

    if (state.loopEnabled) {
      _launchLoop(
        resumePrompt,
        conversationId ?? 0,
        budget: budget,
        planning: planning,
      );
    } else {
      final loop = agentContext.createLoop(
        budget: budget,
        tracker: _activeTracker,
      );
      _subscription = loop
          .chat(resumePrompt)
          .listen(
            (event) => _handleEvent(event, conversationId ?? 0),
            onError: (e, stackTrace) {
              AppLogger.instance.log('[ChatProvider] 续跑 stream error: $e');
              _setError(e.toString());
            },
          );
    }
  }

  /// 清除错误提示
  void clearError() {
    _errorTimer?.cancel();
    _errorTimer = null;
    state = state.copyWith(clearError: true);
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
        state = state.copyWith(clearError: true);
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
      clearError: true,
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

    // ─── 图片注册：本轮附件分配 A 编号；如果启用了画图子 Agent，
    // 把当前可用图片清单（A/G 编号）随用户消息一起发给 LLM，
    // 让模型用 ID 精准引用“这张图/上一张图”，而不是复制磁盘路径。
    final imageRegistry = _ref.read(sessionImageRegistryProvider);
    var newImageIds = <String>[];
    try {
      newImageIds = imageRegistry.beginTurn(pendingAttachments);
    } catch (e) {
      AppLogger.instance.log('[ChatProvider] 登记本轮图片失败(忽略): $e');
    }
    var imageContext = '';
    if (_ref.read(sessionImageAgentModelIdProvider).trim().isNotEmpty) {
      try {
        imageContext = imageRegistry.buildContextNote(
          currentTurnIds: newImageIds.toSet(),
        );
      } catch (e) {
        // 图片上下文只是增强信息，失败不应阻断正常对话。
        AppLogger.instance.log('[ChatProvider] 构建图片上下文失败(忽略): $e');
      }
    }

    // ─── 立即更新 UI 状态 → 让按钮点击有即时视觉反馈，消除卡顿感 ───
    final userMsg = ChatMessage.user(input, attachments: pendingAttachments);
    _flushTimer?.cancel();
    _flushTimer = null;
    _streamBuffer.clear();
    _imageFiles.clear();
    _imageNotices.clear();
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      streamingText: '',
      streamingThinking: '',
      streamingHtmlFiles: [],
      streamingSvgFiles: [],
      streamingVideoFiles: [],
      streamingImageFiles: [],
      activeToolCalls: [],
      clearError: true,
      attachments: [],
      // 新的一轮对话：清掉上一次的"预算耗尽暂停"标志（进度显示保留到下次心跳）
      budgetPaused: false,
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
    if (hasAttachments || imageContext.isNotEmpty) {
      final fileParts = hasAttachments
          ? await FileProcessor.processAttachments(pendingAttachments)
          : const <Map<String, dynamic>>[];
      contentParts = [
        if (input.trim().isNotEmpty) {'type': 'text', 'text': input},
        ...fileParts,
        if (imageContext.isNotEmpty) {'type': 'text', 'text': imageContext},
      ];
    }

    // ─── MCP 连接变化检测：让"中途连上新服务器"立刻生效 ───
    // AgentContext 构建时把 MCP 客户端和工具缓存拍了快照并随后一直复用，
    // 于是用户在 MCP 页连上一台新服务器后，本会话里模型依然看不到它的工具
    // （表现为"明明连上了，模型却说没有这个工具"），必须手动切会话才行。
    // 这里用轻量签名（服务器 id + 工具数）比对，变了就作废缓存上下文。
    final mcpSignature = _mcpToolsSignature();
    if (_cachedAgentContext != null && mcpSignature != _mcpSignature) {
      print('[MCP] 已连接 MCP 发生变化，重建 AgentContext');
      AppLogger.instance.log('[ChatProvider] MCP 工具签名变化，作废缓存上下文');
      _cachedAgentContext = null;
      _cachedContextBuilder = null;
    }
    _mcpSignature = mcpSignature;

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
      // ─── Loop 模式（预算驱动）───
      _launchLoop(input, conversationId);
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

  /// 上一次构建上下文时已连接的 MCP 服务器签名（见 [_mcpToolsSignature]）。
  String _mcpSignature = '';

  /// 当前已连接 MCP 的轻量签名：`serverId#工具数`，按 id 排序。
  ///
  /// 只读内存态，不触发任何 IO；用于判断"上下文里缓存的 MCP 工具是不是过期了"。
  String _mcpToolsSignature() {
    final mcpState = _ref.read(mcpConnectionsProvider);
    final parts = <String>[];
    for (final entry in mcpState.clients.entries) {
      if (!entry.value.isConnected) continue;
      final toolCount = mcpState.toolsCache[entry.key]?.length ?? 0;
      parts.add('${entry.key}#$toolCount');
    }
    parts.sort();
    return parts.join('|');
  }

  /// 启动/恢复 Loop 模式（预算驱动）
  ///
  /// [budget] / [planning] 传入时表示"带着已用额度续跑"。
  void _launchLoop(
    String input,
    int conversationId, {
    ExecutionBudget? budget,
    PlanningBudget? planning,
  }) {
    final agentContext = _cachedAgentContext;
    if (agentContext == null) {
      _setError('会话上下文已失效，请重新发送消息');
      return;
    }

    final policy = state.effectivePolicy;
    final execBudget = budget ?? ExecutionBudget(limits: policy.limits);
    final progression =
        planning ??
        PlanningBudget(
          maxPlans: policy.maxPlans,
          maxContinuations: policy.maxContinuations,
        );
    final tracker = agentContext.progressTracker ?? ToolProgressTracker();

    _activePlanning = progression;
    _activeTracker = tracker;

    final loopConfig = LoopConfig(
      tier: state.budgetTier,
      limitsOverride: state.budgetTier == AgentTaskTier.custom
          ? state.customLimits
          : null,
      maxPlansOverride: progression.maxPlans,
      autoApprove: true,
    );

    state = state.copyWith(
      loopRunning: true,
      loopIteration: progression.plansUsed,
      loopMaxIterations: progression.maxPlans,
      budget: execBudget.snapshot(
        plansUsed: progression.plansUsed,
        planLimit: progression.maxPlans,
      ),
      budgetPaused: false,
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
        .run(
          input,
          budget: execBudget,
          planning: progression,
          progress: tracker,
        )
        .listen(
          (event) => _handleLoopEvent(event, conversationId),
          onError: (e, stackTrace) {
            AppLogger.instance.log('[ChatProvider] Loop stream error: $e');
            PetObserver.instance.notifyAiError(error: e.toString());
            state = state.copyWith(loopRunning: false);
            _setError(e.toString());
          },
        );
  }

  /// 处理 Loop 模式事件
  void _handleLoopEvent(LoopEvent event, int conversationId) {
    switch (event) {
      case LoopPlanStart(
        plan: final plan,
        maxPlans: final max,
        snapshot: final snapshot,
      ):
        state = state.copyWith(
          loopIteration: plan,
          loopMaxIterations: max,
          budget: snapshot,
        );
        // 添加一条分隔消息到 UI（第 N 次规划 = 真正的"重新规划"，与工具轮无关）
        final planMsg = ChatMessage.assistant('─── 第 $plan/$max 次规划 ───');
        state = state.copyWith(messages: [...state.messages, planMsg]);
      case LoopIterStart(
        iteration: final iter,
        maxIterations: final max,
        snapshot: final snapshot,
      ):
        state = state.copyWith(
          loopIteration: iter,
          loopMaxIterations: max,
          budget: snapshot,
        );
        final iterMsg = ChatMessage.assistant('─── Loop 第 $iter/$max 轮 ───');
        state = state.copyWith(messages: [...state.messages, iterMsg]);
      case LoopBudgetTick(snapshot: final snapshot):
        // 预算心跳：只更新显示，不刷聊天记录
        state = state.copyWith(budget: snapshot);
      case LoopBudgetExtended(
        snapshot: final snapshot,
        grantedRounds: final granted,
      ):
        state = state.copyWith(budget: snapshot);
        final extMsg = ChatMessage.assistant(
          '─── 🔋 上一轮有进展，原地续预算 +$granted 轮（不占重新规划次数）───',
        );
        state = state.copyWith(messages: [...state.messages, extMsg]);
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
      case LoopDone(
        totalIterations: final iters,
        summary: final summary,
        snapshot: final snapshot,
      ):
        _flushStreamBuffer();
        final usage = snapshot == null
            ? ''
            : '（已用 ${snapshot.usedRounds} 轮 / ${snapshot.usedToolCalls} 次调用）';
        final doneMsg = ChatMessage.assistant(
          '─── ✅ 任务完成（$iters 次规划$usage）───\n\n$summary',
          attachments: _collectImageAttachments(),
        );
        _imageFiles.clear();
        _imageNotices.clear();
        state = state.copyWith(
          messages: [...state.messages, doneMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
          budget: snapshot,
          budgetPaused: false,
        );
        _conversationsDao.saveMessage(conversationId, doneMsg);
        // 触发 hooks: onAgentDone（记忆存储等后处理）。
        // 之前这条链路只在普通模式（_handleEvent 的 AgentDone）里触发，
        // Loop 模式下 onAgentDone 从来不跑 —— 等于 Loop 会话不写长期记忆。
        Future.microtask(() async {
          for (final hook in _activeHooks) {
            try {
              await hook.onAgentDone(summary, []);
            } catch (e) {
              AppLogger.instance.log('[ChatProvider] Loop onAgentDone 失败(忽略): $e');
            }
          }
        });
        PetObserver.instance.notifyAiCompleted(summary: '任务完成: $iters 次规划');
        // 宠物奖励
        if (_currentTokenCount > 0) {
          PetEconomy.instance.rewardForTokens(_currentTokenCount).then((
            reward,
          ) {
            if (reward > 0) PetChatService.instance.showCoinReward(reward);
          });
          _currentTokenCount = 0;
        }
      case LoopExhausted(
        reason: final reason,
        snapshot: final snapshot,
        checkpoint: final checkpoint,
        hadProgress: final hadProgress,
      ):
        // 预算耗尽不再"静默换轮"：给出检查点摘要 + 明确归因 + 追加预算入口
        _flushStreamBuffer();
        final exhaustedMsg = ChatMessage.assistant(
          _buildBudgetStopMessage(
            reason: reason,
            checkpoint: checkpoint,
            snapshot: snapshot,
            hadProgress: hadProgress,
          ),
          attachments: _collectImageAttachments(),
        );
        _imageFiles.clear();
        _imageNotices.clear();
        state = state.copyWith(
          messages: [...state.messages, exhaustedMsg],
          isLoading: false,
          streamingText: '',
          activeToolCalls: [],
          loopRunning: false,
          loopIteration: 0,
          budget: snapshot,
          budgetPaused: true,
        );
        _conversationsDao.saveMessage(conversationId, exhaustedMsg);
        PetObserver.instance.notifyAiError(
          error: '预算停止: ${_stopHeadline(reason)}',
        );
      case LoopAbort(iteration: final iter, reason: final reason):
        _flushStreamBuffer();
        final abortMsg = ChatMessage.assistant(
          '─── ❌ Loop 放弃 (第 $iter 轮) ───\n\n原因：$reason',
          attachments: _collectImageAttachments(),
        );
        _imageFiles.clear();
        _imageNotices.clear();
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
      case LoopStalled(
        iteration: final iter,
        checkpoint: _,
        snapshot: final snapshot,
      ):
        // 只更新状态：紧跟其后的 LoopExhausted 会统一渲染检查点摘要，
        // 避免同一次停止刷出两条重复消息。
        AppLogger.instance.log('[ChatProvider] Loop 检测到无进展 (第 $iter 次规划)');
        state = state.copyWith(loopRunning: false, budget: snapshot);
    }
  }

  /// 预算停止时的"说人话"消息：为什么停 + 做了什么 + 怎么继续
  String _buildBudgetStopMessage({
    required BudgetStopReason reason,
    required LoopCheckpoint checkpoint,
    required BudgetSnapshot snapshot,
    required bool hadProgress,
  }) {
    final headline = hadProgress
        ? '─── 🔋 预算用尽，任务停在半途（仍在推进）───'
        : '─── ⚠️ 已停止：${_stopHeadline(reason)} ───';
    final buffer = StringBuffer()
      ..writeln(headline)
      ..writeln()
      ..writeln(checkpoint.toMarkdown(reason: reason))
      ..writeln()
      ..writeln(
        '**预算使用**：工具轮 ${snapshot.roundText} · '
        '工具调用 ${snapshot.toolCallText} · '
        '用时 ${snapshot.elapsedText}'
        '${snapshot.planLimit > 0 ? ' · 重新规划 ${snapshot.planText}' : ''}',
      );
    if (snapshot.softExtensions > 0) {
      buffer
        ..writeln()
        ..writeln('（过程中有 ${snapshot.softExtensions} 次"有进展→原地续预算"，未占用重新规划次数）');
    }
    buffer
      ..writeln()
      ..writeln('💡 **怎么继续**：')
      ..writeln();
    if (hadProgress) {
      buffer.writeln('- 点下方「追加预算继续」，会带着已完成的进度接着跑；');
    } else {
      buffer.writeln('- 先补充一句方向（例如换个实现思路 / 指定文件），再点「追加预算继续」；');
    }
    buffer.writeln('- 或者把任务拆小一点，我按新预算重跑这一段。');
    return buffer.toString().trim();
  }

  /// 预算停止原因的一句话标题
  String _stopHeadline(BudgetStopReason reason) => switch (reason) {
    BudgetStopReason.noProgress => '连续没有实质进展',
    BudgetStopReason.repeatedOperations => '检测到空转（重复操作）',
    BudgetStopReason.hardRounds => '工具轮次达到硬上限',
    BudgetStopReason.toolCalls => '工具调用次数达到上限',
    BudgetStopReason.wallClock => '执行时间达到预算上限',
    BudgetStopReason.tokens => 'token 达到预算上限',
    BudgetStopReason.planningBudget => '重新规划次数用完',
    BudgetStopReason.userCancelled => '用户中断',
    BudgetStopReason.none => '已停止',
  };

  /// 可视化文件路径累积器
  final List<String> _htmlFiles = [];
  final List<String> _svgFiles = [];
  final List<String> _videoFiles = [];

  /// 画图子 Agent 生成的图片路径累积器（本轮）
  final List<String> _imageFiles = [];

  /// 画图失败/兜底提示（本轮），最终附到助手消息正文末尾
  final List<String> _imageNotices = [];

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
      case AgentImageGenerated(path: final path):
        _imageFiles.add(path);
        state = state.copyWith(streamingImageFiles: List.from(_imageFiles));
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
        // 画图结果：记录失败/兜底提示，最终会以引用块形式写进助手消息，
        // 避免工具卡片消失后用户看不到“子模型失败、主模型兜底”的信息。
        final lastTool = state.activeToolCalls.isEmpty
            ? null
            : state.activeToolCalls.last;
        if (lastTool?.name == 'image_generate') {
          _collectImageNotice(result);
        }
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
        final displayContent = _appendImageNotices(finalContent);
        final finalThinking = state.streamingThinking.isNotEmpty
            ? state.streamingThinking
            : null;

        // 画图子 Agent 生成的图片：作为助手消息附件，随消息持久化并展示。
        final imageAttachments = _collectImageAttachments();

        // 准备消息对象
        final assistantMsg = ChatMessage.assistant(
          displayContent,
          thinkingContent: finalThinking,
          htmlFiles: List.from(_htmlFiles),
          svgFiles: List.from(_svgFiles),
          videoFiles: List.from(_videoFiles),
          attachments: imageAttachments,
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
          streamingImageFiles: [],
          activeToolCalls: [],
        );

        // 清空可视化文件累积器
        _htmlFiles.clear();
        _svgFiles.clear();
        _videoFiles.clear();
        _imageFiles.clear();
        _imageNotices.clear();

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
              body: displayContent.isEmpty ? '助手已完成回复' : displayContent,
            );
          }
          PetObserver.instance.notifyAiCompleted(
            summary: displayContent.length > 50
                ? '${displayContent.substring(0, 50)}...'
                : displayContent,
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
      case AgentBudgetTick(snapshot: final snapshot):
        // 预算心跳：实时更新"已用工具轮 / 预算"
        state = state.copyWith(budget: snapshot);
      case AgentBudgetExtended(
        snapshot: final snapshot,
        grantedRounds: final granted,
      ):
        state = state.copyWith(budget: snapshot);
        AppLogger.instance.log('[ChatProvider] 有进展，原地续预算 +$granted 轮');
      case AgentBudgetStop(
        reason: final reason,
        snapshot: final snapshot,
        checkpoint: final checkpoint,
        hadProgress: final hadProgress,
      ):
        // 普通对话模式下的预算耗尽：同样给检查点摘要 + 追加预算入口
        _flushStreamBuffer();
        _flushThinkingBuffer();

        final hasThinkingContent = state.streamingThinking.isNotEmpty;
        final stoppedToolCalls = state.activeToolCalls
            .map(
              (tc) => ChatToolCall(
                id: tc.id,
                name: tc.name,
                arguments: tc.arguments,
              ),
            )
            .toList();

        final budgetMsg = ChatMessage.assistant(
          _buildBudgetStopMessage(
            reason: reason,
            checkpoint: checkpoint,
            snapshot: snapshot,
            hadProgress: hadProgress,
          ),
          thinkingContent: hasThinkingContent ? state.streamingThinking : null,
          toolCalls: stoppedToolCalls.isNotEmpty ? stoppedToolCalls : null,
        );

        state = state.copyWith(
          messages: [...state.messages, budgetMsg],
          streamingText: '',
          streamingThinking: '',
          activeToolCalls: [],
          isLoading: false,
          budget: snapshot,
          budgetPaused: true,
        );

        _conversationsDao.saveMessage(conversationId, budgetMsg);
        AppLogger.instance.log(
          '[ChatProvider] AgentBudgetStop: ${reason.name}，已保存检查点摘要',
        );
        PetObserver.instance.notifyAiError(error: _stopHeadline(reason));
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
      final displayContent = _appendImageNotices(content);
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
        displayContent,
        interrupted: true,
        thinkingContent: thinkingContent,
        toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
        attachments: _collectImageAttachments(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMsg],
        isLoading: false,
        streamingText: '',
        streamingThinking: '', // 清空 thinking 缓冲
        streamingImageFiles: [],
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
    _imageFiles.clear();
    _imageNotices.clear();
    Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
      if (mounted) _sanitizeAgentMessages();
    });
  }

  /// 把本轮生成的图片转成可持久化的消息附件。
  List<FileAttachment> _collectImageAttachments() {
    final result = <FileAttachment>[];
    for (final path in _imageFiles) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          result.add(FileAttachment.fromFile(file));
        }
      } catch (_) {}
    }
    return result;
  }

  /// 解析画图工具结果，收集失败/兜底提示。
  void _collectImageNotice(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map) return;
      final warning = decoded['warning'];
      if (warning is String && warning.trim().isNotEmpty) {
        _imageNotices.add(warning.trim());
        return;
      }
      if (decoded['status'] == 'error') {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          _imageNotices.add('画图失败：${detail.trim()}');
        }
      }
    } catch (_) {}
  }

  /// 把画图提示以引用块附加到正文，随消息持久化。
  String _appendImageNotices(String content) {
    if (_imageNotices.isEmpty) return content;
    final lines = _imageNotices
        .map((text) => '> ⚠️ ${text.replaceAll('\n', ' ')}')
        .join('\n');
    return content.trim().isEmpty ? lines : '$content\n\n$lines';
  }

  /// 删除指定索引的消息
  Future<void> deleteMessage(int index) async {
    if (index < 0 || index >= state.messages.length) return;

    final updated = List<ChatMessage>.from(state.messages);
    updated.removeAt(index);
    state = state.copyWith(messages: updated);
    _restoreImageRegistry(updated);

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
    _ref.read(sessionImageRegistryProvider).clear();
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

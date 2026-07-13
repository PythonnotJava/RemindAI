import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/llm/llm_provider.dart';
import '../../../core/db/tables/model_cards.dart';
import '../../../core/toolshell/agent_loop.dart';
import '../../../core/toolshell/combined_executor.dart';
import '../../../providers/database_provider.dart';
import '../models/agent_config.dart';
import '../models/agent_message.dart';

const _uuid = Uuid();

/// 单个 Agent 的运行时状态
class AgentRuntime {
  final AgentConfig config;
  final List<AgentMessage> messages;
  final List<Map<String, dynamic>> llmMessages; // OpenAI格式历史
  AgentStatus status;
  String streamingText; // 当前流式输出缓冲
  String draftText; // 输入框草稿（跨 rebuild 保持）
  StreamSubscription<AgentEvent>? _subscription;

  AgentRuntime({
    required this.config,
    List<AgentMessage>? messages,
    List<Map<String, dynamic>>? llmMessages,
    this.status = AgentStatus.idle,
    this.streamingText = '',
    this.draftText = '',
  }) : messages = messages ?? [],
       llmMessages = llmMessages ?? [];

  void dispose() {
    _subscription?.cancel();
  }
}

/// 多Agent协作的全局状态
class MultiAgentState {
  final Map<String, AgentRuntime> agents; // id -> runtime
  final Set<String> hiddenAgentIds; // 被"关闭"（隐藏）的Agent
  final List<AgentMessage> timeline; // 全局时间线
  final List<AgentTask> tasks; // 任务列表
  final String? commanderId; // 指挥部Agent id
  final String? workingDirectory; // 当前协作工作目录
  final int snapshotTimelineLength; // 恢复时的时间线长度（用于判断是否有新活动）

  const MultiAgentState({
    this.agents = const {},
    this.hiddenAgentIds = const {},
    this.timeline = const [],
    this.tasks = const [],
    this.commanderId,
    this.workingDirectory,
    this.snapshotTimelineLength = 0,
  });

  MultiAgentState copyWith({
    Map<String, AgentRuntime>? agents,
    Set<String>? hiddenAgentIds,
    List<AgentMessage>? timeline,
    List<AgentTask>? tasks,
    String? commanderId,
    String? workingDirectory,
    int? snapshotTimelineLength,
    bool clearWorkingDirectory = false,
  }) {
    return MultiAgentState(
      agents: agents ?? this.agents,
      hiddenAgentIds: hiddenAgentIds ?? this.hiddenAgentIds,
      timeline: timeline ?? this.timeline,
      tasks: tasks ?? this.tasks,
      commanderId: commanderId ?? this.commanderId,
      workingDirectory: clearWorkingDirectory
          ? null
          : (workingDirectory ?? this.workingDirectory),
      snapshotTimelineLength:
          snapshotTimelineLength ?? this.snapshotTimelineLength,
    );
  }

  /// 是否已配置工作目录
  bool get hasWorkspace =>
      workingDirectory != null && workingDirectory!.isNotEmpty;

  /// 获取可见（未隐藏）的Agent列表
  List<AgentRuntime> get visibleAgents => agents.entries
      .where((e) => !hiddenAgentIds.contains(e.key))
      .map((e) => e.value)
      .toList();

  /// 获取隐藏的Agent列表
  List<AgentRuntime> get hiddenAgentList => agents.entries
      .where((e) => hiddenAgentIds.contains(e.key))
      .map((e) => e.value)
      .toList();
}

/// 多Agent协作 StateNotifier
class MultiAgentNotifier extends StateNotifier<MultiAgentState> {
  final Ref _ref;

  MultiAgentNotifier(this._ref) : super(const MultiAgentState());

  /// 设置工作目录
  void setWorkingDirectory(String path) {
    state = state.copyWith(workingDirectory: path);
    // 广播系统消息
    final sysMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: 'system',
      type: AgentMessageType.system,
      content: '工作目录已设置: $path',
      timestamp: DateTime.now(),
    );
    state = state.copyWith(timeline: [...state.timeline, sysMsg]);
  }

  /// 清除工作目录 — 先自动备份当前状态到历史
  Future<void> clearWorkingDirectory() async {
    // 只有当有新活动（相比恢复时产生了新消息）时才保存快照
    final hasNewActivity =
        state.agents.isNotEmpty &&
        state.workingDirectory != null &&
        state.timeline.length > state.snapshotTimelineLength;
    if (hasNewActivity) {
      await _saveSnapshot();
    }
    // 销毁所有 Agent 运行时
    for (final rt in state.agents.values) {
      rt.dispose();
    }
    state = const MultiAgentState(); // 完全重置
  }

  /// 保存当前工作区快照到本地存储
  Future<void> _saveSnapshot() async {
    try {
      final dir = await _snapshotDir();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final dirName = state.workingDirectory!.split(RegExp(r'[/\\]')).last;
      final fileName = '${dirName}_$timestamp.json';
      final file = File(p.join(dir.path, fileName));

      final snapshot = {
        'workingDirectory': state.workingDirectory,
        'savedAt': DateTime.now().toIso8601String(),
        'agents': state.agents.entries.map((e) {
          final rt = e.value;
          return {
            'config': rt.config.toJson(),
            'messages': rt.messages.map((m) => m.toJson()).toList(),
            'status': rt.status.name,
          };
        }).toList(),
        'timeline': state.timeline.map((m) => m.toJson()).toList(),
      };

      await file.writeAsString(jsonEncode(snapshot));
      AppLogger.instance.log('[MultiAgent] 工作区快照已保存: ${file.path}');
    } catch (e) {
      AppLogger.instance.log('[MultiAgent] 保存快照失败: $e');
    }
  }

  /// 获取快照保存目录: < rootDir >/agent_snapshots/
  Future<Directory> _snapshotDir() async {
    final root = await AppSettings.getRootDir();
    final dir = Directory(p.join(root, 'agent_snapshots'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取历史快照列表
  Future<List<WorkspaceSnapshot>> listSnapshots() async {
    try {
      final dir = await _snapshotDir();
      final files = await dir
          .list()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      final snapshots = <WorkspaceSnapshot>[];
      for (final file in files) {
        try {
          final content = await File(file.path).readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          snapshots.add(
            WorkspaceSnapshot(
              filePath: file.path,
              workingDirectory: json['workingDirectory'] as String,
              savedAt: DateTime.parse(json['savedAt'] as String),
              agentCount: (json['agents'] as List).length,
              messageCount: (json['timeline'] as List).length,
            ),
          );
        } catch (_) {} // 跳过损坏的快照
      }
      // 按时间降序
      snapshots.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return snapshots;
    } catch (e) {
      return [];
    }
  }

  /// 从快照恢复工作区
  Future<bool> restoreSnapshot(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 先清理当前状态
      for (final rt in state.agents.values) {
        rt.dispose();
      }

      final restoredAgents = <String, AgentRuntime>{};
      String? commanderId;

      for (final agentJson in json['agents'] as List) {
        final config = AgentConfig.fromJson(
          agentJson['config'] as Map<String, dynamic>,
        );
        final messages = (agentJson['messages'] as List)
            .map((m) => AgentMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        final runtime = AgentRuntime(config: config, messages: messages);
        restoredAgents[config.id] = runtime;
        if (config.role == AgentRole.commander) commanderId = config.id;
      }

      final timeline = (json['timeline'] as List)
          .map((m) => AgentMessage.fromJson(m as Map<String, dynamic>))
          .toList();

      state = MultiAgentState(
        agents: restoredAgents,
        timeline: timeline,
        commanderId: commanderId,
        workingDirectory: json['workingDirectory'] as String,
        snapshotTimelineLength: timeline.length, // 记录恢复时的长度
      );

      // 添加恢复通知
      final sysMsg = AgentMessage(
        id: _uuid.v4(),
        fromAgentId: 'system',
        type: AgentMessageType.system,
        content: '✅ 工作区已从历史快照恢复',
        timestamp: DateTime.now(),
      );
      state = state.copyWith(timeline: [...state.timeline, sysMsg]);

      return true;
    } catch (e) {
      AppLogger.instance.log('[MultiAgent] 恢复快照失败: $e');
      return false;
    }
  }

  /// 删除指定快照
  Future<void> deleteSnapshot(String filePath) async {
    try {
      await File(filePath).delete();
    } catch (_) {}
  }

  /// 创建一个新的 Agent
  String createAgent(AgentConfig config) {
    final runtime = AgentRuntime(config: config);

    final newAgents = Map<String, AgentRuntime>.from(state.agents);
    newAgents[config.id] = runtime;

    // 注意: system prompt 在首次调用时由 _ensureTeamContext 动态注入
    // 这样可以确保包含最新的团队成员信息

    // 广播系统消息
    final sysMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: 'system',
      type: AgentMessageType.system,
      content: '${config.name} (${config.role.label}) 已加入协作',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      agents: newAgents,
      timeline: [...state.timeline, sysMsg],
      commanderId: config.role == AgentRole.commander
          ? config.id
          : state.commanderId,
    );

    return config.id;
  }

  /// 隐藏一个 Agent（关闭面板但保留状态）
  void hideAgent(String agentId) {
    if (agentId == state.commanderId) return; // 指挥部不可隐藏
    state = state.copyWith(hiddenAgentIds: {...state.hiddenAgentIds, agentId});
  }

  /// 显示一个被隐藏的 Agent
  void showAgent(String agentId) {
    final newHidden = Set<String>.from(state.hiddenAgentIds);
    newHidden.remove(agentId);
    state = state.copyWith(hiddenAgentIds: newHidden);
  }

  /// 彻底删除一个 Agent
  void removeAgent(String agentId) {
    if (agentId == state.commanderId) return;
    final agent = state.agents[agentId];
    if (agent == null) return;

    final agentName = agent.config.name;
    final agentRole = agent.config.role.label;
    agent.dispose();

    final newAgents = Map<String, AgentRuntime>.from(state.agents);
    newAgents.remove(agentId);
    final newHidden = Set<String>.from(state.hiddenAgentIds);
    newHidden.remove(agentId);

    // 在指挥部时间线显示"开除"消息
    final fireMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: 'system',
      type: AgentMessageType.system,
      content: '🔥 $agentName ($agentRole) 已被开除，收拾东西走人！',
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      agents: newAgents,
      hiddenAgentIds: newHidden,
      timeline: [...state.timeline, fireMsg],
    );
  }

  /// 向指定 Agent 发送用户消息并触发LLM调用
  Future<void> sendMessageToAgent(String agentId, String content) async {
    final runtime = state.agents[agentId];
    if (runtime == null) return;

    // 添加用户消息
    final userMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: 'user',
      toAgentId: agentId,
      type: AgentMessageType.user,
      content: content,
      timestamp: DateTime.now(),
    );
    runtime.messages.add(userMsg);

    // 同步到时间线
    final newTimeline = [...state.timeline, userMsg];
    state = state.copyWith(timeline: newTimeline);
    _notifyUpdate();

    // 触发LLM调用
    await _runAgentLoop(agentId, content);
  }

  /// 指挥部广播消息给所有工作Agent
  Future<void> broadcastFromCommander(String content) async {
    if (state.commanderId == null) return;

    final broadcastMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: state.commanderId!,
      type: AgentMessageType.broadcast,
      content: content,
      timestamp: DateTime.now(),
    );

    final newTimeline = [...state.timeline, broadcastMsg];
    state = state.copyWith(timeline: newTimeline);

    // 将广播内容注入每个工作Agent的上下文
    for (final entry in state.agents.entries) {
      if (entry.key == state.commanderId) continue;
      final rt = entry.value;
      rt.llmMessages.add({'role': 'user', 'content': '[指挥部广播] $content'});
    }
    _notifyUpdate();
  }

  /// Agent 间直接通信
  void sendDirectMessage(String fromId, String toId, String content) {
    final msg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: fromId,
      toAgentId: toId,
      type: AgentMessageType.direct,
      content: content,
      timestamp: DateTime.now(),
    );

    // 注入到目标Agent的LLM上下文
    final targetRuntime = state.agents[toId];
    if (targetRuntime != null) {
      final fromName = state.agents[fromId]?.config.name ?? fromId;
      targetRuntime.llmMessages.add({
        'role': 'user',
        'content': '[$fromName 对你说] $content',
      });
    }

    state = state.copyWith(timeline: [...state.timeline, msg]);
    _notifyUpdate();
  }

  /// 向指定Agent发送文件
  void sendFileToAgent(String agentId, List<String> filePaths) {
    final runtime = state.agents[agentId];
    if (runtime == null) return;

    final fileNames = filePaths
        .map((p) => p.split(RegExp(r'[/\\]')).last)
        .join(', ');
    final userMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: 'user',
      toAgentId: agentId,
      type: AgentMessageType.user,
      content: '📎 已发送文件: $fileNames',
      timestamp: DateTime.now(),
      metadata: {'files': filePaths},
    );
    runtime.messages.add(userMsg);

    // 注入到LLM上下文
    runtime.llmMessages.add({
      'role': 'user',
      'content': '用户发送了以下文件（路径在工作目录下）:\n${filePaths.join('\n')}\n请确认收到并分析这些文件。',
    });

    state = state.copyWith(timeline: [...state.timeline, userMsg]);
    _notifyUpdate();
  }

  /// 指挥部全局分发文件给所有Agent
  void broadcastFiles(List<String> filePaths) {
    if (state.commanderId == null) return;

    final fileNames = filePaths
        .map((p) => p.split(RegExp(r'[/\\]')).last)
        .join(', ');
    final broadcastMsg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: state.commanderId!,
      type: AgentMessageType.broadcast,
      content: '📎 全局分发文件: $fileNames',
      timestamp: DateTime.now(),
      metadata: {'files': filePaths},
    );

    // 注入每个工作Agent的上下文
    for (final entry in state.agents.entries) {
      if (entry.key == state.commanderId) continue;
      entry.value.llmMessages.add({
        'role': 'user',
        'content': '[指挥部分发文件] 以下文件供你参考:\n${filePaths.join('\n')}',
      });
    }

    state = state.copyWith(timeline: [...state.timeline, broadcastMsg]);
    _notifyUpdate();
  }

  /// 根据 Agent 配置的 enabledSkills 和 permissions 加载工具列表
  Future<List<Map<String, dynamic>>> _loadToolsForAgent(
    AgentConfig config,
  ) async {
    final tools = <Map<String, dynamic>>[];
    final permissions = config.permissions;

    // 权限 → 工具名映射 (用于过滤)
    const permToolFilter = <String, List<String>>{
      'fileRead': ['toolshell_read', 'toolshell_search'],
      'fileWrite': ['toolshell_write'],
      'fileDelete': ['toolshell_delete'],
      'exec': ['toolshell_exec', 'toolshell_run_python'],
      'network': [], // 暂无独立网络工具
    };

    // 根据权限展开允许的工具名
    final allowedToolNames = <String>{};
    for (final perm in permissions) {
      final names = permToolFilter[perm];
      if (names != null) allowedToolNames.addAll(names);
    }
    // memory 工具不受权限限制
    allowedToolNames.addAll([
      'toolshell_memory_store',
      'toolshell_memory_recall',
    ]);

    for (final skill in config.enabledSkills) {
      try {
        final String json;
        switch (skill) {
          case 'toolshell':
            json = await rootBundle.loadString(
              'assets/default_skills/toolshell/tools.json',
            );
          case 'system':
            json = await rootBundle.loadString(
              'assets/default_skills/system/tools.json',
            );
          case 'schedule':
            json = await rootBundle.loadString(
              'assets/default_skills/schedule/tools.json',
            );
          default:
            continue; // 未知技能跳过
        }
        final skillTools = (jsonDecode(json) as List)
            .cast<Map<String, dynamic>>();

        // 按权限过滤 (system 技能不过滤)
        for (final tool in skillTools) {
          final name = (tool['function'] as Map)['name'] as String;
          if (skill == 'system' || allowedToolNames.contains(name)) {
            tools.add(tool);
          }
        }
      } catch (e) {
        AppLogger.instance.log('[MultiAgent] 加载技能 $skill 工具失败: $e');
      }
    }

    // 如果有额外的 enabledTools 显式指定，合并进来
    // (未来可扩展：从用户技能/MCP加载)

    AppLogger.instance.log(
      '[MultiAgent] Agent "${config.name}" 加载了 ${tools.length} 个工具: '
      '${tools.map((t) => (t['function'] as Map)['name']).join(', ')}',
    );
    return tools;
  }

  /// 为 Agent 构建包含团队上下文的增强系统提示词
  String _buildEnhancedSystemPrompt(AgentConfig config) {
    final buf = StringBuffer();

    // 原始系统提示词
    buf.writeln(config.systemPrompt);

    // 注入身份信息
    buf.writeln();
    buf.writeln('─── 你的身份 ───');
    buf.writeln('名称: ${config.name}');
    buf.writeln('角色: ${config.role.label}');
    buf.writeln(
      '权限: ${config.permissions.isEmpty ? "无特殊权限" : config.permissions.join(", ")}',
    );
    buf.writeln(
      '可用技能: ${config.enabledSkills.isEmpty ? "无" : config.enabledSkills.join(", ")}',
    );

    // 注入工作目录
    if (state.workingDirectory != null) {
      buf.writeln('工作目录: ${state.workingDirectory}');
    }

    // 注入团队信息
    final teammates = state.agents.entries
        .where((e) => e.key != config.id)
        .map((e) => e.value)
        .toList();
    if (teammates.isNotEmpty) {
      buf.writeln();
      buf.writeln('─── 协作团队 ───');
      buf.writeln('你当前在一个多Agent协作团队中工作。团队成员:');
      for (final tm in teammates) {
        final c = tm.config;
        buf.writeln(
          '  • ${c.name} (${c.role.label}) — 权限: ${c.permissions.isEmpty ? "无" : c.permissions.join(",")}',
        );
      }
      buf.writeln();
      buf.writeln('协作规则:');
      buf.writeln('1. 你只能处理你权限范围内的任务');
      buf.writeln('2. 如果任务超出你的能力，在回复中说明需要哪个队友协助');
      buf.writeln('3. 收到指挥部广播时优先处理');
      buf.writeln('4. 完成任务后主动汇报进度和结果');
    }

    return buf.toString();
  }

  /// 内部：运行 Agent Loop
  Future<void> _runAgentLoop(String agentId, String userInput) async {
    final runtime = state.agents[agentId];
    if (runtime == null) return;

    // 查找 ModelCard
    final modelCard = _findModelCard(runtime.config.modelCardId);
    if (modelCard == null) {
      _addAssistantMessage(agentId, '错误：未找到配置的模型卡片');
      return;
    }

    // 创建 LlmClient
    final llm = LlmClient(
      baseUrl: modelCard.baseUrl,
      apiKey: modelCard.apiKey,
      model: modelCard.modelId,
      provider: LlmProvider.values.firstWhere(
        (p) => p.name == modelCard.provider,
        orElse: () => LlmProvider.openai,
      ),
    );

    // 创建 Executor
    // 注意: 多智能体全自动执行 (无权限中间件确认)，故保持目录边界沙箱
    // (allowOutsideRoot 默认 false)，避免子智能体无确认地越界写/删。
    final executor = CombinedExecutor(
      projectRoot: state.workingDirectory ?? '',
      mcpClients: {},
      mcpToolsCache: {},
    );

    // 加载工具 (根据 enabledSkills + permissions 过滤)
    final tools = await _loadToolsForAgent(runtime.config);

    // 确保系统提示词含团队上下文 (首次或团队变化时更新)
    _ensureTeamContext(runtime);

    // 构建 AgentLoop
    final loop = AgentLoop(
      llm: llm,
      executor: executor,
      tools: tools,
      messages: runtime.llmMessages,
    );

    runtime.status = AgentStatus.thinking;
    runtime.streamingText = '';
    _notifyUpdate();

    try {
      await for (final event in loop.chat(userInput)) {
        switch (event) {
          case AgentReasoningToken():
            // 推理过程不混入最终正文；保持 thinking 状态即可。
            runtime.status = AgentStatus.thinking;
          case AgentToken(text: final text):
            runtime.streamingText += text;
            _notifyUpdate();
          case AgentToolStart():
            runtime.status = AgentStatus.tooling;
            _notifyUpdate();
          case AgentToolResult():
            runtime.status = AgentStatus.thinking;
            _notifyUpdate();
          case AgentDone(content: final content):
            _addAssistantMessage(agentId, content);
            // 自动路由：将此 Agent 的产出广播给其他 Agent
            _routeOutputToTeam(agentId, content);
            runtime.status = AgentStatus.idle;
            runtime.streamingText = '';
            _notifyUpdate();
          case AgentError(message: final msg):
            _addAssistantMessage(agentId, '⚠️ ${_friendlyError(msg)}');
            runtime.status = AgentStatus.error;
            runtime.streamingText = '';
            _notifyUpdate();
          case AgentLoopLimitReached(rounds: final rounds):
            _addAssistantMessage(
              agentId,
              '⚠️ 本轮回复内部工具调用次数过多(已达上限 $rounds 次)，已中止，请换个方式重新提问',
            );
            runtime.status = AgentStatus.error;
            runtime.streamingText = '';
            _notifyUpdate();
        }
      }
    } catch (e) {
      runtime.status = AgentStatus.error;
      _addAssistantMessage(agentId, '⚠️ ${_friendlyError('$e')}');
      _notifyUpdate();
    }
  }

  /// 确保 Agent 的 LLM 历史中的 system 消息包含最新的团队上下文
  void _ensureTeamContext(AgentRuntime runtime) {
    final enhanced = _buildEnhancedSystemPrompt(runtime.config);
    if (runtime.llmMessages.isNotEmpty &&
        runtime.llmMessages.first['role'] == 'system') {
      // 更新已有的 system 消息
      runtime.llmMessages.first['content'] = enhanced;
    } else {
      // 插入 system 消息到最前面
      runtime.llmMessages.insert(0, {'role': 'system', 'content': enhanced});
    }
  }

  /// 自动路由：Agent 产出后将摘要注入到其他 Agent 的上下文中
  ///
  /// 策略：
  /// - 内容过短（< 10字）或错误信息不路由
  /// - 短内容（≤ 300字）直接转发
  /// - 长内容（> 300字）调用 LLM 提炼核心摘要后转发
  /// - 注入带时间戳，保证因果可追溯
  void _routeOutputToTeam(String fromAgentId, String content) {
    // 过滤：过短、错误信息不路由
    if (content.length < 10) return;
    if (content.startsWith('⚠️') || content.startsWith('错误')) return;

    final fromRuntime = state.agents[fromAgentId];
    if (fromRuntime == null) return;
    final fromName = fromRuntime.config.name;
    final fromRole = fromRuntime.config.role.label;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    if (content.length <= 300) {
      // 短内容直接路由
      _injectRouteMessage(fromAgentId, fromName, fromRole, timeStr, content);
    } else {
      // 长内容异步压缩后路由
      _compressAndRoute(fromAgentId, fromName, fromRole, timeStr, content);
    }
  }

  /// 直接注入路由消息到其他 Agent
  void _injectRouteMessage(
    String fromAgentId,
    String fromName,
    String fromRole,
    String timeStr,
    String summary,
  ) {
    final routeContent =
        '─── 团队动态 [$timeStr] ───\n'
        '$fromName ($fromRole) 的产出:\n'
        '$summary\n'
        '────────────────\n'
        '如果这与你当前的任务相关，可以基于此继续工作。无关则忽略。';

    for (final entry in state.agents.entries) {
      if (entry.key == fromAgentId) continue;
      entry.value.llmMessages.add({'role': 'system', 'content': routeContent});
    }
  }

  /// 长文本通过 LLM 压缩为核心摘要后路由
  Future<void> _compressAndRoute(
    String fromAgentId,
    String fromName,
    String fromRole,
    String timeStr,
    String fullContent,
  ) async {
    // 使用产出 Agent 同款模型来做摘要（复用已有配置）
    final fromRuntime = state.agents[fromAgentId];
    if (fromRuntime == null) return;

    final modelCard = _findModelCard(fromRuntime.config.modelCardId);
    if (modelCard == null) {
      // fallback: 截取后400字
      final tail = fullContent.length > 400
          ? fullContent.substring(fullContent.length - 400)
          : fullContent;
      final fallback = '...(截取尾部)\n$tail';
      _injectRouteMessage(fromAgentId, fromName, fromRole, timeStr, fallback);
      return;
    }

    try {
      final llm = LlmClient(
        baseUrl: modelCard.baseUrl,
        apiKey: modelCard.apiKey,
        model: modelCard.modelId,
        provider: LlmProvider.values.firstWhere(
          (p) => p.name == modelCard.provider,
          orElse: () => LlmProvider.openai,
        ),
      );

      // 单轮摘要请求
      final summaryMessages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content':
              '你是一个信息压缩器。将用户给出的内容提炼为简洁的核心摘要，'
              '保留关键结论、数据、文件路径、代码片段等重要信息，'
              '去除冗余解释和过渡语句。输出不超过 200 字。只输出摘要本身，不要加前缀。',
        },
        {'role': 'user', 'content': fullContent},
      ];

      String summary = '';
      await for (final event in llm.chatStreamFull(
        summaryMessages,
        tools: [],
      )) {
        switch (event) {
          case ContentToken(text: final text):
            summary += text;
          case StreamComplete(content: final c):
            if (summary.isEmpty && c != null) summary = c;
          default:
            break;
        }
      }

      if (summary.isEmpty) {
        final tail = fullContent.length > 400
            ? fullContent.substring(fullContent.length - 400)
            : fullContent;
        summary = '...(摘要生成失败，截取尾部)\n$tail';
      }

      _injectRouteMessage(fromAgentId, fromName, fromRole, timeStr, summary);
    } catch (e) {
      AppLogger.instance.log('[MultiAgent] 摘要压缩失败: $e');
      // fallback: 截取后400字
      final tail = fullContent.length > 400
          ? fullContent.substring(fullContent.length - 400)
          : fullContent;
      final fallback = '...(摘要失败，截取尾部)\n$tail';
      _injectRouteMessage(fromAgentId, fromName, fromRole, timeStr, fallback);
    }
  }

  void _addAssistantMessage(String agentId, String content) {
    final runtime = state.agents[agentId];
    if (runtime == null) return;

    final msg = AgentMessage(
      id: _uuid.v4(),
      fromAgentId: agentId,
      type: AgentMessageType.assistant,
      content: content,
      timestamp: DateTime.now(),
    );
    runtime.messages.add(msg);

    state = state.copyWith(timeline: [...state.timeline, msg]);
  }

  ModelCard? _findModelCard(String modelCardId) {
    try {
      final cardsAsync = _ref.read(modelCardsProvider);
      return cardsAsync.valueOrNull?.firstWhere((c) => c.id == modelCardId);
    } catch (_) {
      return null;
    }
  }

  /// 将原始错误信息转换为用户友好的提示
  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();

    // 余额不足
    if (lower.contains('insufficient_balance') ||
        lower.contains('insufficient balance') ||
        lower.contains('402')) {
      return '模型 API 余额不足，请充值后重试';
    }
    // 频率限制
    if (lower.contains('rate_limit') || lower.contains('429')) {
      return '请求频率过高，请稍后重试';
    }
    // 认证失败
    if (lower.contains('unauthorized') ||
        lower.contains('invalid_api_key') ||
        lower.contains('401')) {
      return 'API Key 无效或已过期，请检查模型卡片配置';
    }
    // 模型不存在
    if (lower.contains('model_not_found') ||
        lower.contains('does not exist') ||
        lower.contains('404')) {
      return '模型不存在或已下线，请更换模型';
    }
    // 上下文超长
    if (lower.contains('context_length') ||
        lower.contains('max_tokens') ||
        lower.contains('too long')) {
      return '对话上下文过长，请清理历史消息后重试';
    }
    // 网络错误
    if (lower.contains('timeout') ||
        lower.contains('connection') ||
        lower.contains('socketexception')) {
      return '网络连接失败，请检查网络或代理设置';
    }
    // 服务端错误
    if (lower.contains('500') || lower.contains('internal_server_error')) {
      return '模型服务端内部错误，请稍后重试';
    }
    // 服务不可用
    if (lower.contains('503') || lower.contains('overloaded')) {
      return '模型服务暂时不可用（过载），请稍后重试';
    }

    // 兜底：去掉 Exception 前缀，保留核心信息
    String cleaned = raw;
    if (cleaned.startsWith('LLM 调用失败: ')) {
      cleaned = cleaned.substring('LLM 调用失败: '.length);
    }
    if (cleaned.startsWith('Exception: ')) {
      cleaned = cleaned.substring('Exception: '.length);
    }
    // 尝试提取 JSON 中的 message 字段
    final msgMatch = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(cleaned);
    if (msgMatch != null) {
      return msgMatch.group(1)!;
    }
    // 截断过长的原始错误
    if (cleaned.length > 100) {
      return '${cleaned.substring(0, 100)}...';
    }
    return cleaned;
  }

  /// 强制触发rebuild（因为我们直接修改了 runtime 内部状态）
  void _notifyUpdate() {
    state = state.copyWith(agents: Map.from(state.agents));
  }

  @override
  void dispose() {
    for (final rt in state.agents.values) {
      rt.dispose();
    }
    super.dispose();
  }
}

/// Provider
final multiAgentProvider =
    StateNotifierProvider<MultiAgentNotifier, MultiAgentState>(
      (ref) => MultiAgentNotifier(ref),
    );

/// 工作区历史快照摘要
class WorkspaceSnapshot {
  final String filePath;
  final String workingDirectory;
  final DateTime savedAt;
  final int agentCount;
  final int messageCount;

  const WorkspaceSnapshot({
    required this.filePath,
    required this.workingDirectory,
    required this.savedAt,
    required this.agentCount,
    required this.messageCount,
  });

  String get dirName => workingDirectory.split(RegExp(r'[/\\]')).last;
}

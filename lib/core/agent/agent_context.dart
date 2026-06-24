import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/daos/memory_dao.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../logger/app_logger.dart';
import '../llm/models.dart';
import '../memory/memory_manager.dart';
import '../memory/project_config.dart';
import '../memory/qdrant_service.dart';
import '../search/search_capability.dart';
import '../toolshell/agent_loop.dart';
import '../toolshell/executor.dart';
import '../../providers/database_provider.dart';
import '../../providers/experts_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
import '../../features/chat/chat_provider.dart';
import 'agent_capability.dart';
import 'agent_hook.dart';
import 'message_pipeline.dart';
import 'tool_middleware.dart';
import 'tool_pipeline.dart';
import 'hooks/memory_recall_hook.dart';
import 'hooks/memory_store_hook.dart';
import 'middleware/logging_middleware.dart';
import 'middleware/permission_middleware.dart';
import 'transformers/context_compactor.dart';

/// Agent 执行上下文 — 封装一次对话所需的全部运行时资源
///
/// 由 [AgentContextBuilder] 构建,将 chat_provider 中散落的
/// 600+ 行 setup 逻辑收敛到一处。
class AgentContext {
  final LlmClient llm;
  final ToolPipeline pipeline;
  final List<AgentHook> hooks;
  final List<Map<String, dynamic>> tools;
  final String systemPrompt;

  /// system prompt 的稳定前缀（领域专家 + 元技能），会话期间不随用户技能变化。
  /// 用于中途刷新 system prompt 时保留专家角色与元技能说明。
  final String systemPromptPrefix;

  /// system prompt 的用户技能区（可能随会话中途启用/停用技能而变化）。
  final String skillsSection;

  final List<Map<String, dynamic>> messages;
  final MessagePipeline messagePipeline;

  AgentContext({
    required this.llm,
    required this.pipeline,
    required this.hooks,
    required this.tools,
    required this.systemPrompt,
    this.systemPromptPrefix = '',
    this.skillsSection = '',
    required this.messages,
    this.messagePipeline = const MessagePipeline(),
  });

  /// 创建 AgentLoop 实例
  AgentLoop createLoop() => AgentLoop(
    llm: llm,
    executor: _PipelineAsExecutor(pipeline),
    tools: tools,
    messages: messages,
    messagePipeline: messagePipeline,
    hooks: hooks,
  );
}

/// 适配器: 让 ToolPipeline 满足 AgentLoop 要求的 Executor 接口
class _PipelineAsExecutor extends Executor {
  final ToolPipeline _pipeline;

  _PipelineAsExecutor(this._pipeline) : super(projectRoot: '.');

  @override
  Future<String> run(String toolName, Map<String, dynamic> args) =>
      _pipeline.run(toolName, args);
}

/// Agent 上下文构建器
///
/// 从 Riverpod Ref 中读取各种 Provider 状态,
/// 构建出完整的 AgentContext。
class AgentContextBuilder {
  final Ref _ref;

  AgentContextBuilder(this._ref);

  /// 构建 AgentContext
  ///
  /// [modelCard] 当前使用的模型卡
  /// [existingMessages] 已有的 agent 消息历史 (续对话时传入)
  /// [sessionAutoApprove] 本次会话是否已切换为 auto 模式
  /// [onPermissionRequest] 权限确认回调
  Future<AgentContext> build({
    required ModelCard modelCard,
    required List<Map<String, dynamic>> existingMessages,
    required bool sessionAutoApprove,
    Future<bool> Function(String, Map<String, dynamic>)? onPermissionRequest,
  }) async {
    // ─── 工作目录 ───
    var workDir = _ref.read(workingDirectoryProvider);
    if (workDir.isEmpty) {
      final documentsDir = await getApplicationDocumentsDirectory();
      workDir = p.join(documentsDir.path, '.RemindAI', 'workspace');
    }

    // ─── 项目配置 ───
    final projectConfig = await ProjectConfig.load(workDir);
    final sessionRecall = _ref.read(sessionMemoryRecallProvider);
    final sessionStore = _ref.read(sessionMemoryStoreProvider);
    final effectiveRecall = sessionRecall ?? projectConfig.longTermRecall;
    final effectiveStore = sessionStore ?? projectConfig.longTermStore;
    final effectiveMode = sessionAutoApprove
        ? PermissionMode.auto
        : projectConfig.mode;

    AppLogger.instance.log(
      '[AgentContext] workDir=$workDir, '
      'effectiveRecall=$effectiveRecall, effectiveStore=$effectiveStore, '
      'mode=$effectiveMode',
    );

    // ─── LLM 客户端 ───
    final llm = LlmClient(
      baseUrl: modelCard.baseUrl,
      apiKey: modelCard.apiKey,
      model: modelCard.model,
      provider: LlmProviderX.fromId(modelCard.provider),
    );

    // ─── 记忆系统 ───
    MemoryManager? memoryManager;
    String? memoryCollection;
    bool useQdrant = false;

    final settings = _ref.read(settingsProvider).valueOrNull;
    final embCfg = settings?.embedding;
    if (embCfg != null && embCfg.isConfigured) {
      final dao = MemoryDao(_ref.read(databaseProvider));

      if (projectConfig.embeddings || embCfg.useQdrant) {
        final qdrant = QdrantService.instance;
        if (!qdrant.isRunning) {
          try {
            await qdrant.start();
          } catch (_) {}
        }
        useQdrant = qdrant.isRunning;
      }

      memoryManager = MemoryManager(
        embeddingBaseUrl: embCfg.baseUrl,
        embeddingApiKey: embCfg.apiKey,
        embeddingModel: embCfg.model,
        memoryDao: dao,
      );
      memoryCollection = MemoryManager.globalCollection;
    }

    // ─── 工具加载 ───
    final tools = await _loadTools();
    final toolSourceMapping = _lastSourceMapping;

    // ─── 可插拔能力 (Capabilities) ───
    final capabilities = _collectCapabilities();
    final customHandlers = <String, CustomToolHandler>{};

    for (final cap in capabilities) {
      if (!cap.isActive) continue;
      // 注册工具定义
      tools.addAll(cap.toolDefinitions);
      // 注册执行器
      customHandlers.addAll(cap.toolHandlers);
      // 注册 source mapping
      toolSourceMapping.addAll(cap.sourceMapping);
      AppLogger.instance.log(
        '[AgentContext] Capability 已注册: ${cap.displayName}',
      );
    }

    // ─── 系统提示词 ───
    // 拆成稳定前缀（专家+元技能）与用户技能区两段，
    // 便于会话中途技能变化时只刷新技能区，保护 prompt cache。
    final systemPromptPrefix = await _buildSystemPromptPrefix();
    final skillsSection = await _buildSkillsSection();
    final systemPrompt = '$systemPromptPrefix$skillsSection';

    // ─── 初始化消息历史 ───
    if (existingMessages.isEmpty) {
      existingMessages.add({'role': 'system', 'content': systemPrompt});
    }

    // ─── 中间件链 ───
    final middlewares = <ToolMiddleware>[
      LoggingMiddleware(sourceMapping: toolSourceMapping),
      if (effectiveMode == PermissionMode.normal && onPermissionRequest != null)
        PermissionMiddleware(onPermissionRequest: onPermissionRequest),
    ];

    // ─── 收集 skill 可读路径 ───
    final skillsState = _ref.read(skillsProvider);
    final activeSkillPaths = (skillsState.valueOrNull ?? [])
        .where((s) => s.isActive && s.path.isNotEmpty)
        .map((s) => s.path)
        .toList();

    // ─── Executor (纯文件操作,不含权限/日志) ───
    final pythonPath = _ref.read(sessionPythonProvider);
    final npmPath = _ref.read(sessionNpmProvider);
    final executor = Executor(
      projectRoot: workDir,
      pythonPath: pythonPath,
      npmPath: npmPath,
      permissionMode: PermissionMode.auto, // 权限由中间件管理
      memoryManager: memoryManager,
      memoryCollection: memoryCollection,
      readableExtraPaths: activeSkillPaths,
      // 交互式桌面会话：解除目录边界限制，可跨工作目录操作；
      // 越界写/删/执行仍由权限中间件逐次确认。
      allowOutsideRoot: true,
    );

    // ─── ToolPipeline ───
    final mcpState = _ref.read(mcpConnectionsProvider);
    final pipeline = ToolPipeline(
      executor: executor,
      middlewares: middlewares,
      mcpClients: mcpState.clients,
      mcpToolsCache: mcpState.toolsCache,
      customHandlers: customHandlers,
    );

    // ─── Hooks ───
    final hooks = <AgentHook>[
      if (effectiveRecall && memoryManager != null && memoryCollection != null)
        MemoryRecallHook(
          manager: memoryManager,
          collection: memoryCollection,
          useQdrant: useQdrant,
        ),
      if (effectiveStore && memoryManager != null && memoryCollection != null)
        MemoryStoreHook(
          manager: memoryManager,
          collection: memoryCollection,
          llm: llm,
          messages: existingMessages,
          useQdrant: useQdrant,
        ),
      // 来自 Capabilities 的 hooks
      for (final cap in capabilities)
        if (cap.isActive) ...cap.hooks,
    ];

    return AgentContext(
      llm: llm,
      pipeline: pipeline,
      hooks: hooks,
      tools: tools,
      systemPrompt: systemPrompt,
      systemPromptPrefix: systemPromptPrefix,
      skillsSection: skillsSection,
      messages: existingMessages,
      messagePipeline: MessagePipeline([
        if (effectiveStore && memoryManager != null && memoryCollection != null)
          ContextCompactor(
            llm: llm,
            memoryManager: memoryManager,
            memoryCollection: memoryCollection,
            useQdrant: useQdrant,
            // contextWindow 为 0 时，ContextCompactor 用 128K 兜底
            contextWindow: modelCard.contextWindow,
          ),
      ])
    );
  }

  // ─── 工具加载 (从 chat_provider 提取) ───

  Map<String, String> _lastSourceMapping = {};

  Future<List<Map<String, dynamic>>> _loadTools() async {
    final tools = <Map<String, dynamic>>[];
    final sourceMapping = <String, String>{};

    final hasWorkspace = _ref.read(workingDirectoryProvider).isNotEmpty;
    if (hasWorkspace) {
      // toolshell
      final tsJson = await rootBundle.loadString(
        'assets/default_skills/toolshell/tools.json',
      );
      final tsTools = (jsonDecode(tsJson) as List).cast<Map<String, dynamic>>();
      for (final t in tsTools) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            '元技能:ToolShell';
      }
      tools.addAll(tsTools);

      // schedule
      final schJson = await rootBundle.loadString(
        'assets/default_skills/schedule/tools.json',
      );
      final schTools = (jsonDecode(schJson) as List)
          .cast<Map<String, dynamic>>();
      for (final t in schTools) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            '元技能:Schedule';
      }
      tools.addAll(schTools);

      // system
      final sysJson = await rootBundle.loadString(
        'assets/default_skills/system/tools.json',
      );
      final sysTools = (jsonDecode(sysJson) as List)
          .cast<Map<String, dynamic>>();
      for (final t in sysTools) {
        sourceMapping[(t['function'] as Map)['name'] as String] = '元技能:System';
      }
      tools.addAll(sysTools);
    }

    // 用户技能
    final registry = _ref.read(skillRegistryProvider);
    final skillsState = _ref.read(skillsProvider);
    final skills = skillsState.valueOrNull ?? [];
    final allSkillNames = skills
        .map((s) => '${s.name}(${s.isActive ? "激活" : "未启用"})')
        .toList();
    print('[SKILL] 技能列表(共${skills.length}): ${allSkillNames.join(", ")}');
    for (final skill in skills) {
      if (!skill.isActive) continue;
      final skillTools = await registry.loadSkillTools(skill);
      final toolNames = skillTools
          .map((t) => (t['function'] as Map)['name'])
          .join(", ");
      print(
        '[SKILL] ✓ 加载技能「${skill.name}」工具(${skillTools.length}个): $toolNames',
      );
      for (final t in skillTools) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            '技能:${skill.name}';
      }
      tools.addAll(skillTools);
    }

    // MCP 工具
    final mcpConnections = _ref.read(mcpConnectionsProvider.notifier);
    final mcpTools = mcpConnections.getAllConnectedTools();
    final mcpState = _ref.read(mcpConnectionsProvider);
    for (final entry in mcpState.toolsCache.entries) {
      for (final t in entry.value) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            'MCP:${entry.key}';
      }
    }
    tools.addAll(mcpTools);

    _lastSourceMapping = sourceMapping;
    AppLogger.instance.log('[AgentContext] 已加载 ${tools.length} 个工具');
    return tools;
  }

  /// 公开方法: 构建系统提示词 (供 loadConversation 等外部场景使用)
  Future<String> buildSystemPrompt() async {
    final prefix = await _buildSystemPromptPrefix();
    final skills = await _buildSkillsSection();
    return '$prefix$skills';
  }

  /// 计算当前激活用户技能的轻量签名。
  /// 用于判断会话中途技能集合是否变化，决定是否需要刷新 system prompt。
  /// 与 [_buildSkillsSection] 的数据来源保持一致。
  String computeSkillSignature() {
    final skills = _ref.read(skillsProvider).valueOrNull ?? [];
    final active =
        skills
            .where((s) => s.isActive)
            .map((s) => '${s.name}|${s.path}')
            .toList()
          ..sort();
    return active.join(';;');
  }

  /// 构建 system prompt 的稳定前缀：领域专家 + 元技能（或全局模式提示）。
  /// 注意：领域专家为一次性消费（读取后置空），仅在新会话首次构建时注入。
  Future<String> _buildSystemPromptPrefix() async {
    final parts = <String>[];
    final hasWorkspace = _ref.read(workingDirectoryProvider).isNotEmpty;

    // 领域专家
    final activeExpert = _ref.read(activeExpertProvider);
    if (activeExpert != null) {
      parts.add('# 当前角色: ${activeExpert.name}\n\n${activeExpert.systemPrompt}');
      parts.add('\n\n---\n');
      _ref.read(activeExpertProvider.notifier).state = null;
    }

    if (hasWorkspace) {
      final tsPrompt = await rootBundle.loadString(
        'assets/default_skills/toolshell/SKILL.md',
      );
      parts.add(tsPrompt);

      final schPrompt = await rootBundle.loadString(
        'assets/default_skills/schedule/SKILL.md',
      );
      parts.add('\n\n---\n# 元技能: Schedule\n$schPrompt');

      final sysPrompt = await rootBundle.loadString(
        'assets/default_skills/system/SKILL.md',
      );
      parts.add('\n\n---\n# 元技能: System\n$sysPrompt');
    } else {
      parts.add(
        '你是 RemindAI 智能助手。当前处于全局模式（无工作目录），'
        '可以回答问题、分析内容、进行对话。如果需要文件操作能力，'
        '请先在设置中选择一个工作目录。',
      );
    }

    return parts.join();
  }

  /// 构建 system prompt 的用户技能区。会话中途可能因启用/停用技能而变化。
  Future<String> _buildSkillsSection() async {
    final parts = <String>[];
    final registry = _ref.read(skillRegistryProvider);
    final skillsState = _ref.read(skillsProvider);
    final skills = skillsState.valueOrNull ?? [];
    for (final skill in skills) {
      if (!skill.isActive) continue;
      final prompt = await registry.loadSkillPrompt(skill);
      if (prompt.isNotEmpty) {
        parts.add(
          '\n\n---\n# 技能: ${skill.name}\n'
          '> 技能目录: ${skill.path}\n'
          '> 使用 toolshell_read 可直接读取该目录下的文件（绝对路径）\n\n'
          '$prompt',
        );
      }
    }
    return parts.join();
  }

  // ─── Capabilities 收集 ───

  /// 从当前 session 状态收集所有可插拔能力
  ///
  /// 新增能力时只需在此方法中追加实例化即可，
  /// AgentContextBuilder.build() 无需修改。
  List<AgentCapability> _collectCapabilities() {
    final capabilities = <AgentCapability>[];

    // 搜索能力
    final searchProviderState = _ref.read(sessionSearchProvider);
    final searchSettings = _ref.read(searchSettingsProvider).valueOrNull;
    if (searchProviderState != SearchProvider.none && searchSettings != null) {
      final searchConfig = searchSettings.getConfig(searchProviderState);
      capabilities.add(
        SearchCapability(
          provider: searchProviderState,
          apiKey: searchConfig.apiKey,
        ),
      );
    }

    // 未来新能力在此追加:
    // capabilities.add(SandboxCapability(...));
    // capabilities.add(ImageGenCapability(...));
    // capabilities.add(RAGCapability(...));

    return capabilities;
  }
}

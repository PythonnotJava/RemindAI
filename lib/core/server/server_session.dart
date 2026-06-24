import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_hook.dart';
import '../agent/hooks/memory_recall_hook.dart';
import '../agent/hooks/memory_store_hook.dart';
import '../agent/message_pipeline.dart';
import '../agent/tool_middleware.dart';
import '../agent/tool_pipeline.dart';
import '../agent/transformers/context_compactor.dart';
import '../db/daos/memory_dao.dart';
import '../db/tables/model_cards.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../logger/app_logger.dart';
import '../mcp/mcp_client.dart';
import '../memory/memory_manager.dart';
import '../memory/project_config.dart';
import '../memory/qdrant_service.dart';
import '../search/search_capability.dart';
import '../toolshell/agent_loop.dart';
import '../toolshell/executor.dart';
import '../../providers/database_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
import 'api_server_config.dart';

/// 服务端一次请求的运行时上下文 (无 UI)。
///
/// 与 [AgentContext] 平行, 但完全由 [ApiServerConfig] 驱动:
/// - 选择性挂载 skill / mcp / search
/// - 独立 collection 的记忆 (与主程序物理隔离)
/// - 不带 workDir → 不加载文件操作类元技能, 无文件系统暴露面
///
/// 用叶子积木 (LlmClient / Executor / ToolPipeline / MemoryManager / AgentLoop)
/// 独立组装, 不改动 AgentContextBuilder, 对主程序零侵入。
class ServerSession {
  final LlmClient llm;
  final ToolPipeline pipeline;
  final List<AgentHook> hooks;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, dynamic>> messages;
  final MessagePipeline messagePipeline;

  /// 本次会话实际使用的模型卡对外标识 (modelId), 用于响应回显。
  final String modelId;

  ServerSession._({
    required this.llm,
    required this.pipeline,
    required this.hooks,
    required this.tools,
    required this.messages,
    required this.modelId,
    this.messagePipeline = const MessagePipeline(),
  });

  AgentLoop createLoop() => AgentLoop(
    llm: llm,
    executor: _PipelineExecutor(pipeline),
    tools: tools,
    messages: messages,
    messagePipeline: messagePipeline,
    hooks: hooks,
  );
}

/// 适配器: 让 ToolPipeline 满足 AgentLoop 要求的 Executor 接口。
class _PipelineExecutor extends Executor {
  final ToolPipeline _pipeline;
  _PipelineExecutor(this._pipeline) : super(projectRoot: '.');

  @override
  Future<String> run(String toolName, Map<String, dynamic> args) =>
      _pipeline.run(toolName, args);
}

/// 服务端会话构建器。
///
/// 从 [Ref] 读取共享资源 (模型卡 / 技能 / MCP / 嵌入配置),
/// 按 [ApiServerConfig] 选择性组装。
class ServerSessionBuilder {
  final Ref _ref;
  final ApiServerConfig _config;

  ServerSessionBuilder(this._ref, this._config);

  /// 列出对外可用的模型卡 (供 /v1/models 暴露)。
  ///
  /// 受 [ApiServerConfig.allowedModelCardIds] 白名单约束:
  /// - 白名单为空 → 返回全部模型卡
  /// - 白名单非空 → 仅返回名单内的卡
  List<ModelCard> listModelCards() {
    final all = _ref.read(modelCardsProvider).valueOrNull ?? const [];
    final allow = _config.allowedModelCardIds;
    if (allow.isEmpty) return all;
    final allowSet = allow.toSet();
    return all.where((c) => allowSet.contains(c.id)).toList();
  }

  /// 解析服务端要用的模型卡。返回 null 表示无可用模型 (服务无法工作)。
  ///
  /// [requestedModel] 为客户端请求体里携带的 model 字段。优先按它匹配
  /// (依次比对 卡 id → modelId → 卡名), 命中即用; 未提供或未命中时,
  /// 回退到 config 指定卡 → 默认卡 → 第一张。
  /// 所有候选都限定在 [listModelCards] (已应用白名单) 范围内。
  ModelCard? resolveModelCard({String? requestedModel}) {
    final cards = listModelCards();
    if (cards.isEmpty) return null;

    // 1) 客户端显式请求的模型
    final req = requestedModel?.trim() ?? '';
    if (req.isNotEmpty) {
      for (final c in cards) {
        if (c.id == req) return c;
      }
      for (final c in cards) {
        if (c.modelId == req) return c;
      }
      for (final c in cards) {
        if (c.name == req) return c;
      }
    }

    // 2) config 指定卡
    if (_config.modelCardId.isNotEmpty) {
      for (final c in cards) {
        if (c.id == _config.modelCardId) return c;
      }
    }
    // 3) 默认卡 → 第一张
    for (final c in cards) {
      if (c.isDefault) return c;
    }
    return cards.first;
  }

  /// 构建一次会话。
  ///
  /// [requestedModel] 为客户端请求体里携带的 model 字段, 用于路由到对应模型卡。
  Future<ServerSession> build({
    List<Map<String, dynamic>>? history,
    String? requestedModel,
  }) async {
    final card = resolveModelCard(requestedModel: requestedModel);
    if (card == null) {
      throw StateError('服务端未配置可用模型卡');
    }

    // ─── LLM ───
    final llm = LlmClient(
      baseUrl: card.baseUrl,
      apiKey: card.apiKey,
      model: card.modelId,
      provider: LlmProviderX.fromId(card.provider),
    );

    // ─── 记忆 (按档位) ───
    MemoryManager? memoryManager;
    String? memoryCollection;
    var useQdrant = false;

    if (_config.memoryMode != ServerMemoryMode.none) {
      final settings = _ref.read(settingsProvider).valueOrNull;
      final embCfg = settings?.embedding;
      if (embCfg != null && embCfg.isConfigured) {
        final dao = MemoryDao(_ref.read(databaseProvider));

        // 独立档位用专属 collection; 共享档位用全局 collection。
        memoryCollection = _config.memoryMode == ServerMemoryMode.shared
            ? MemoryManager.globalCollection
            : _config.memoryCollection;

        if (embCfg.useQdrant) {
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
      } else {
        AppLogger.instance.log(
          '[ApiServer] 记忆档位=${_config.memoryMode.id} 但未配置嵌入模型, 跳过记忆挂载',
        );
      }
    }

    // ─── 工具: 选定技能 + 选定 MCP + 搜索 ───
    final tools = <Map<String, dynamic>>[];
    final sourceMapping = <String, String>{};
    final customHandlers = <String, CustomToolHandler>{};

    // 用户技能 (仅 config 选中的)
    final skillPromptParts = <String>[];
    final registry = _ref.read(skillRegistryProvider);
    final allSkills = _ref.read(skillsProvider).valueOrNull ?? const [];
    for (final skill in allSkills) {
      if (!_config.skillIds.contains(skill.id)) continue;
      final skillTools = await registry.loadSkillTools(skill);
      for (final t in skillTools) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            '技能:${skill.name}';
      }
      tools.addAll(skillTools);
      final prompt = await registry.loadSkillPrompt(skill);
      if (prompt.isNotEmpty) {
        skillPromptParts.add('\n\n---\n# 技能: ${skill.name}\n\n$prompt');
      }
    }

    // MCP 工具 (仅 config 选中的已连接 server)
    final mcpState = _ref.read(mcpConnectionsProvider);
    final selectedMcpClients = <String, McpClient>{};
    final selectedMcpCache = <String, List<Map<String, dynamic>>>{};
    for (final serverId in _config.mcpServerIds) {
      final client = mcpState.clients[serverId];
      final cached = mcpState.toolsCache[serverId];
      if (client == null || cached == null) continue;
      selectedMcpClients[serverId] = client;
      selectedMcpCache[serverId] = cached;
      for (final t in cached) {
        sourceMapping[(t['function'] as Map)['name'] as String] =
            'MCP:$serverId';
        tools.add(t);
      }
    }

    // 搜索能力
    final searchProvider = SearchProvider.fromId(_config.searchProviderId);
    if (searchProvider != SearchProvider.none) {
      final searchSettings = _ref.read(searchSettingsProvider).valueOrNull;
      final searchConfig = searchSettings?.getConfig(searchProvider);
      if (searchConfig != null && searchConfig.apiKey.isNotEmpty) {
        final cap = SearchCapability(
          provider: searchProvider,
          apiKey: searchConfig.apiKey,
        );
        if (cap.isActive) {
          tools.addAll(cap.toolDefinitions);
          customHandlers.addAll(cap.toolHandlers);
          sourceMapping.addAll(cap.sourceMapping);
        }
      }
    }

    // ─── system prompt ───
    final systemPrompt =
        '你是通过 RemindAI 对外 API 提供服务的智能助手。'
        '可使用已挂载的技能、MCP 工具与搜索能力回答问题。'
        '当前为无工作目录的服务模式, 不具备本地文件读写能力。'
        '${skillPromptParts.join()}';

    final messages = history != null && history.isNotEmpty
        ? List<Map<String, dynamic>>.from(history)
        : <Map<String, dynamic>>[];
    // 确保首条为 system
    if (messages.isEmpty || messages.first['role'] != 'system') {
      messages.insert(0, {'role': 'system', 'content': systemPrompt});
    }

    // ─── Executor + Pipeline ───
    // 服务端不带 workDir, projectRoot 给临时占位, 文件类元技能未加载, 不会触达。
    final executor = Executor(
      projectRoot: '.',
      permissionMode: PermissionMode.auto,
      memoryManager: memoryManager,
      memoryCollection: memoryCollection,
    );

    final pipeline = ToolPipeline(
      executor: executor,
      middlewares: <ToolMiddleware>[],
      mcpClients: selectedMcpClients,
      mcpToolsCache: selectedMcpCache,
      customHandlers: customHandlers,
    );

    // ─── Hooks (记忆召回/存储) ───
    final hooks = <AgentHook>[];
    if (memoryManager != null && memoryCollection != null) {
      hooks.add(
        MemoryRecallHook(
          manager: memoryManager,
          collection: memoryCollection,
          useQdrant: useQdrant,
        ),
      );
      hooks.add(
        MemoryStoreHook(
          manager: memoryManager,
          collection: memoryCollection,
          llm: llm,
          messages: messages,
          useQdrant: useQdrant,
        ),
      );
    }

    AppLogger.instance.log(
      '[ApiServer] 会话已组装: model=${card.modelId}, tools=${tools.length}, '
      'skills=${_config.skillIds.length}, mcp=${selectedMcpClients.length}, '
      'memory=${_config.memoryMode.id}(collection=$memoryCollection), '
      'sources=${sourceMapping.length}',
    );

    // ─── 消息变换管线 (上下文压缩) ───
    final msgPipeline = MessagePipeline([
      if (memoryManager != null && memoryCollection != null)
        ContextCompactor(
          llm: llm,
          memoryManager: memoryManager,
          memoryCollection: memoryCollection,
          useQdrant: useQdrant,
          // contextWindow 为 0 时，ContextCompactor 用 128K 兜底
          contextWindow: card.contextWindow,
        ),
    ]);

    return ServerSession._(
      llm: llm,
      pipeline: pipeline,
      hooks: hooks,
      tools: tools,
      messages: messages,
      modelId: card.modelId,
      messagePipeline: msgPipeline,
    );
  }
}

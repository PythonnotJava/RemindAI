import 'dart:convert';
import 'dart:io';

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
import '../skill/skill_injector.dart';
import '../skill/skill_model.dart';
import '../skill/skill_registry.dart';
import '../toolshell/agent_loop.dart';
import '../toolshell/executor.dart';
import '../toolshell/worktree_manager.dart';
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
import 'hooks/schedule_hook.dart';
import 'hooks/system_probe_hook.dart';
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

  /// 获取 Executor 实例（用于 AutonomousLoop 等外部消费）
  Executor get executor => _PipelineAsExecutor(pipeline);
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

  /// 技能注入器 — 跨轮次复用以维护 pin 状态和 prompt 缓存
  SkillInjector? _skillInjector;

  AgentContextBuilder(this._ref);

  /// 构建 AgentContext
  ///
  /// [modelCard] 当前使用的模型卡
  /// [existingMessages] 已有的 agent 消息历史 (续对话时传入)
  /// [sessionAutoApprove] 本次会话是否已切换为 auto 模式
  /// [onPermissionRequest] 权限确认回调
  /// [userInput] 当前用户输入（用于 SkillRouter 相关性匹配）
  Future<AgentContext> build({
    required ModelCard modelCard,
    required List<Map<String, dynamic>> existingMessages,
    required bool sessionAutoApprove,
    Future<bool> Function(String, Map<String, dynamic>)? onPermissionRequest,
    String userInput = '',
  }) async {
    // ─── 工作目录 ───
    var workDir = _ref.read(workingDirectoryProvider);
    final hasRealWorkDir = workDir.isNotEmpty;
    if (workDir.isEmpty) {
      final documentsDir = await getApplicationDocumentsDirectory();
      workDir = p.join(documentsDir.path, '.RemindAI', 'workspace');
    }

    // ─── Worktree 隔离: 若存在有效的活跃隔离工作树，Executor 的实际
    // 根目录重定向到那里，而不是 workDir。这是唯一的重定向点——
    // 是否"进入/离开隔离"完全由 LLM 通过 toolshell_worktree_start/finish
    // 工具决定，框架这里只负责在每次构建上下文时校验并生效。
    // 只在真正有工作目录时才可能生效 (纯对话模式没有 .toolshell，也没有该功能)。
    var effectiveRoot = workDir;
    if (hasRealWorkDir) {
      final activeWorktree = _ref.read(activeWorktreeProvider);
      if (activeWorktree.isNotEmpty) {
        final worktreesRoot = p.join(workDir, '.toolshell', 'worktrees');
        final normalized = p.normalize(activeWorktree);
        final stillValid =
            p.isWithin(worktreesRoot, normalized) &&
            await Directory(normalized).exists();
        if (stillValid) {
          effectiveRoot = normalized;
        } else {
          // 工作树已被移除(finish 完成或被手动删除)，清掉失效状态，
          // 避免下一轮继续错误地定向到一个不存在的目录。
          _ref.read(activeWorktreeProvider.notifier).state = '';
        }
      }
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

    // 技能安装工具 (toolshell_install_skill): 把工作目录里临时做好的技能
    // 提升到全局技能库。仅在工作目录模式注册 (其工具定义也只在 toolshell/tools.json)。
    if (hasRealWorkDir) {
      final registry = _ref.read(skillRegistryProvider);
      customHandlers['toolshell_install_skill'] = (args) =>
          _installSkill(registry, args);
      toolSourceMapping['toolshell_install_skill'] = '元技能:ToolShell';

      // Worktree 隔离工具: 是否/何时使用完全由 LLM 判断，框架不做自动触发。
      // 始终针对真实的主工作目录 workDir 操作 (而不是可能已被重定向的
      // effectiveRoot)，因为 git 仓库根在主工作目录，隔离工作树是从它派生的。
      customHandlers['toolshell_worktree_start'] = (args) =>
          _worktreeStart(workDir, args);
      toolSourceMapping['toolshell_worktree_start'] = '元技能:ToolShell';
      customHandlers['toolshell_worktree_finish'] = (args) =>
          _worktreeFinish(workDir, args);
      toolSourceMapping['toolshell_worktree_finish'] = '元技能:ToolShell';
    }

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
    final skillsSection = await _buildSkillsSection(
      userInput: userInput,
      existingMessages: existingMessages,
      memoryManager: memoryManager,
    );
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

    // ─── 收集 skill 可读路径 (全局 + 项目级) ───
    final activeSkillPaths = _collectAllSkills()
        .where((s) => s.isActive && s.path.isNotEmpty)
        .map((s) => s.path)
        .toList();

    // ─── Executor (纯文件操作,不含权限/日志) ───
    final pythonPath = _ref.read(sessionPythonProvider);
    final npmPath = _ref.read(sessionNpmProvider);
    final executor = Executor(
      projectRoot: effectiveRoot,
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
    final hasWorkDir = _ref.read(workingDirectoryProvider).isNotEmpty;
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
      // Schedule 元技能 Hook — 强制驱动计划回顾
      if (hasWorkDir) ScheduleHook(projectRoot: workDir),
      // System 元技能 Hook — 首次会话自动探测开发环境
      if (hasWorkDir) SystemProbeHook(),
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
      ]),
    );
  }

  // ─── 工具加载 (从 chat_provider 提取) ───

  Map<String, String> _lastSourceMapping = {};

  /// 自定义工具 `toolshell_install_skill` 的执行体。
  ///
  /// 把工作目录里临时做好的技能目录 (须直接含 SKILL.md) 提升为全局技能，
  /// 落在 `Skills/` 目录、出现在技能页。安装后刷新 [skillsProvider] 让技能页即时更新。
  ///
  /// 安装成功后，若源目录位于 `<工作目录>/.toolshell/` 内（即模型用 /skill-cti 流程
  /// 搭建的临时 staging 目录），会删除该源目录——技能从"项目临时"毕业为"全局可复用"，
  /// 不在工作目录留副本。这样避免同一技能被项目技能扫描器重复加载（双载）。
  /// 内容已存入全局 Skills/，删除不丢数据；仅删模型显式传入、且确属工作目录 .toolshell 下的目录。
  ///
  /// 返回 JSON 字符串供模型解析。
  Future<String> _installSkill(
    SkillRegistry registry,
    Map<String, dynamic> args,
  ) async {
    final sourceDir = (args['source_dir'] as String?)?.trim() ?? '';
    final name = (args['name'] as String?)?.trim();
    if (sourceDir.isEmpty) {
      return jsonEncode({
        'status': 'error',
        'message': '缺少必需参数 source_dir (技能源目录的绝对路径)',
      });
    }
    try {
      final skill = await registry.installFromDirectory(
        sourceDir,
        name: (name != null && name.isNotEmpty) ? name : null,
      );
      // 刷新技能页数据源，让新技能立即出现在技能管理 UI
      _ref.invalidate(skillsProvider);
      AppLogger.instance.log(
        '[AgentContext] 技能已安装到全局: ${skill.name} (${skill.path})',
      );

      // 清理 staging 源目录：仅当其位于 <工作目录>/.toolshell/ 内时删除，
      // 避免技能在工作目录里残留成无法关闭的项目临时副本（导致双载）。
      final cleaned = await _cleanupStagingDir(sourceDir);
      if (cleaned) {
        _ref.invalidate(projectSkillsProvider);
      }

      return jsonEncode({
        'status': 'ok',
        'name': skill.name,
        'path': skill.path,
        'tool_count': skill.toolCount,
        'staging_cleaned': cleaned,
        'message':
            '技能「${skill.name}」已安装到全局技能库，可在技能页管理并在任意工作目录复用'
            '${cleaned ? "（工作目录的临时副本已清理）" : ""}。',
      });
    } catch (e) {
      AppLogger.instance.log('[AgentContext] 技能安装失败: $e');
      return jsonEncode({'status': 'error', 'message': '安装失败: $e'});
    }
  }

  /// 自定义工具 `toolshell_worktree_start` 的执行体。
  ///
  /// 在 `<工作目录>/.toolshell/worktrees/<name>_<时间戳>/` 创建一个基于当前
  /// HEAD 的新分支+新工作树，成功后把 [activeWorktreeProvider] 指向它——
  /// 下一次(以及本次调用之后同一轮内)构建 AgentContext 时，Executor 的
  /// projectRoot 会重定向到这个工作树，后续文件操作/命令执行自动隔离。
  ///
  /// 触发时机完全由 LLM 判断，本方法不做任何"是否该隔离"的启发式判断。
  Future<String> _worktreeStart(
    String workDir,
    Map<String, dynamic> args,
  ) async {
    final name = (args['name'] as String?)?.trim();
    final manager = WorktreeManager(workDir: workDir);
    final result = await manager.start(
      name: (name?.isNotEmpty ?? false) ? name : null,
    );

    if (result['status'] == 'ok') {
      _ref.read(activeWorktreeProvider.notifier).state =
          result['worktree_path'] as String;
      AppLogger.instance.log(
        '[AgentContext] Worktree 隔离已启动: ${result['worktree_path']} '
        '(分支 ${result['branch']})',
      );
    }
    return jsonEncode(result);
  }

  /// 自定义工具 `toolshell_worktree_finish` 的执行体。
  ///
  /// [args.worktree_path] 可选：不传则使用当前活跃的隔离工作树。
  /// [args.action] 必需："merge" 或 "discard"。
  /// [args.commit_message] 可选：merge 前若有未提交改动，用它做提交信息。
  ///
  /// 成功后清空 [activeWorktreeProvider]，恢复对主工作目录的正常操作。
  Future<String> _worktreeFinish(
    String workDir,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] as String?)?.trim() ?? '';
    final explicitPath = (args['worktree_path'] as String?)?.trim();
    final worktreePath = (explicitPath != null && explicitPath.isNotEmpty)
        ? explicitPath
        : _ref.read(activeWorktreeProvider);

    if (worktreePath.isEmpty) {
      return jsonEncode({
        'status': 'error',
        'code': 'NO_ACTIVE_WORKTREE',
        'detail': '当前没有活跃的隔离工作树，也未显式传入 worktree_path',
      });
    }

    final manager = WorktreeManager(workDir: workDir);
    final result = await manager.finish(
      worktreePath: worktreePath,
      action: action,
      commitMessage: (args['commit_message'] as String?)?.trim(),
    );

    if (result['status'] == 'ok') {
      // 只有在结束的是"当前活跃"的那个工作树时才清空全局状态；
      // 若模型显式传了别的 worktree_path，不动当前活跃状态。
      if (_ref.read(activeWorktreeProvider) == worktreePath) {
        _ref.read(activeWorktreeProvider.notifier).state = '';
      }
      AppLogger.instance.log(
        '[AgentContext] Worktree 隔离已结束: $worktreePath (${result['action']})',
      );
    }
    return jsonEncode(result);
  }

  /// 若 [sourceDir] 位于当前工作目录的 `.toolshell/` 下，则删除它并返回 true；
  /// 否则不动并返回 false。用于 /skill-cti 安装后清理临时 staging 目录。
  ///
  /// 边界保护：解析为绝对/规范化路径后，严格校验 sourceDir 在
  /// `<工作目录>/.toolshell/` 之内，绝不删除工作目录本身或其外部路径。
  Future<bool> _cleanupStagingDir(String sourceDir) async {
    try {
      final workDir = _ref.read(workingDirectoryProvider);
      if (workDir.isEmpty) return false;

      final toolshellRoot = p.canonicalize(p.join(workDir, '.toolshell'));
      final src = p.canonicalize(sourceDir);

      // src 必须严格在 .toolshell/ 之内（且不等于 .toolshell 本身）
      final isInside = p.isWithin(toolshellRoot, src);
      if (!isInside) return false;

      final dir = Directory(src);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        AppLogger.instance.log('[AgentContext] 已清理 staging 技能目录: $src');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.instance.log('[AgentContext] 清理 staging 目录失败(忽略): $e');
      return false;
    }
  }

  /// 合并全局技能与项目级临时技能，供 Agent 运行时统一消费。
  ///
  /// 全局技能来自 [skillsProvider]（技能页可管理），项目技能来自
  /// [projectSkillsProvider]（仅扫描工作目录 `.toolshell/skills/`，恒定激活）。
  /// 两者数据源隔离：项目技能只在此处合并挂载，不污染任何全局技能管理 UI。
  ///
  /// 去重安全网：项目技能与全局技能同名时丢弃项目版（全局优先）。避免某技能既装到
  /// 全局、又在工作目录 `.toolshell/skills/` 留有同名副本时被重复加载（工具名注册两遍、
  /// 提示词注入两段）。这是纯内存去重，不删除任何文件。
  List<Skill> _collectAllSkills() {
    final global = _ref.read(skillsProvider).valueOrNull ?? const [];
    final project = _ref.read(projectSkillsProvider).valueOrNull ?? const [];
    final globalNames = global.map((s) => s.name).toSet();
    final dedupedProject = project
        .where((s) => !globalNames.contains(s.name))
        .toList();
    return [...global, ...dedupedProject];
  }

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

    // 用户技能 (全局 + 项目级临时技能)
    final registry = _ref.read(skillRegistryProvider);
    final skills = _collectAllSkills();
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
  ///
  /// [userInput] 可选的用户输入，用于 SkillRouter 相关性匹配。
  /// 不传时退回全量注入所有激活技能。
  Future<String> buildSystemPrompt({String userInput = ''}) async {
    final prefix = await _buildSystemPromptPrefix();
    final skills = await _buildSkillsSection(userInput: userInput);
    return '$prefix$skills';
  }

  /// 计算当前激活用户技能的轻量签名。
  /// 用于判断会话中途技能集合是否变化，决定是否需要刷新 system prompt。
  /// 与 [_buildSkillsSection] 的数据来源保持一致（全局 + 项目级）。
  String computeSkillSignature() {
    final skills = _collectAllSkills();
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

  /// 构建 system prompt 的用户技能区（基于 SkillInjector 相关性路由）。
  ///
  /// 使用统一的 [SkillInjector] API 对当前用户输入进行相关性匹配，
  /// 只注入相关的 skill（最多 10 个），避免 token 浪费。
  /// 每次载入的 skill 会打印到终端方便调试验证。
  Future<String> _buildSkillsSection({
    String userInput = '',
    List<Map<String, dynamic>>? existingMessages,
    MemoryManager? memoryManager,
  }) async {
    final registry = _ref.read(skillRegistryProvider);
    final skills = _collectAllSkills().where((s) => s.isActive).toList();

    if (skills.isEmpty) return '';

    // 初始化/复用 SkillInjector
    _skillInjector ??= SkillInjector(
      registry: registry,
      memoryManager: memoryManager,
      source: 'Chat',
    );

    // 提取最近上下文
    final recentContext = _extractRecentContext(existingMessages);

    // 统一调用 SkillInjector
    final injection = await _skillInjector!.inject(
      userInput: userInput,
      skillPool: skills,
      context: recentContext,
      forceAll: userInput.isEmpty,
    );

    return injection.systemPrompt;
  }

  /// 从消息历史中提取最近 2 轮用户/助手内容作为辅助上下文
  List<String> _extractRecentContext(List<Map<String, dynamic>>? messages) {
    if (messages == null || messages.isEmpty) return [];
    final recent = <String>[];
    final userAssistant = messages
        .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
        .toList();
    final tail = userAssistant.length > 4
        ? userAssistant.sublist(userAssistant.length - 4)
        : userAssistant;
    for (final msg in tail) {
      final content = msg['content'];
      if (content is String && content.isNotEmpty) {
        recent.add(content.length > 200 ? content.substring(0, 200) : content);
      }
    }
    return recent;
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

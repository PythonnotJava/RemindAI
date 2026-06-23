import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../search/search_capability.dart';
import '../../providers/database_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/skills_provider.dart';
import 'online_service_config.dart';
import 'online_session.dart';
import 'web_assets.dart';

/// 在线服务 WebSocket 服务器
class OnlineServer {
  final Ref _ref;
  HttpServer? _server;
  int? _boundPort;
  OnlineServiceConfig _config;

  /// 活跃会话表: sessionId -> OnlineSession
  final Map<String, OnlineSession> _sessions = {};

  /// 服务器事件流 (供 UI 监听)
  final _eventController = StreamController<OnlineServerEvent>.broadcast();
  Stream<OnlineServerEvent> get events => _eventController.stream;

  OnlineServer(this._ref, this._config);

  bool get isRunning => _server != null;
  int? get boundPort => _boundPort;
  int get connectionCount => _sessions.length;
  List<OnlineSession> get activeSessions => _sessions.values.toList();
  OnlineServiceConfig get config => _config;

  // ─── 生命周期 ────────────────────────────────────────

  Future<void> start() async {
    await stop();
    final address = InternetAddress.anyIPv4; // 局域网可访问
    _server = await HttpServer.bind(address, _config.port);
    _boundPort = _server!.port;
    _server!.listen(_handleRequest, onError: (e) {
      _emit(OnlineServerEvent.error('Server error: $e'));
    });
    _emit(OnlineServerEvent.started(_boundPort!));
  }

  Future<void> stop() async {
    // 关闭所有活跃会话
    for (final session in _sessions.values.toList()) {
      await _closeSession(session, reason: 'server_shutdown');
    }
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
    _boundPort = null;
    _emit(OnlineServerEvent.stopped());
  }

  Future<void> applyConfig(OnlineServiceConfig config) async {
    _config = config;
    await config.save();
    await stop();
    if (config.canStart) await start();
  }

  /// 仅更新配置 (不触发启停)
  void updateConfig(OnlineServiceConfig config) {
    _config = config;
  }

  void dispose() {
    stop();
    _eventController.close();
  }

  // ─── 运维操作 ────────────────────────────────────────

  /// 踢出指定用户
  Future<void> kickSession(String sessionId, {String reason = 'kicked'}) async {
    final session = _sessions[sessionId];
    if (session != null) {
      await _closeSession(session, reason: reason);
      _sessions.remove(sessionId);
      _emit(OnlineServerEvent.userLeft(session));
    }
  }

  /// 拉闸 / 恢复
  void setAccepting(bool accepting) {
    _config = _config.copyWith(accepting: accepting);
    _emit(OnlineServerEvent.configChanged(_config));
  }

  // ─── HTTP 请求路由 ──────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // CORS
    request.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..add('Access-Control-Allow-Headers', '*');

    if (method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    try {
      if (path == '/ws') {
        await _handleWebSocket(request);
      } else if (path == '/' || path == '/index.html') {
        _serveString(request, WebAssets.indexHtml, 'text/html; charset=utf-8');
      } else if (path == '/style.css') {
        _serveString(request, WebAssets.css, 'text/css; charset=utf-8');
      } else if (path == '/app.js') {
        _serveString(request, WebAssets.js, 'application/javascript; charset=utf-8');
      } else if (path == '/health') {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          'status': 'ok',
          'connections': connectionCount,
          'maxConnections': _config.maxConnections,
        }));
        await request.response.close();
      } else if (path.startsWith('/download/')) {
        await _handleDownload(request);
      } else {
        request.response.statusCode = 404;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Internal Error');
      await request.response.close();
    }
  }

  // ─── 静态内容响应 ──────────────────────────────────

  void _serveString(HttpRequest request, String content, String contentType) {
    request.response.headers.set('Content-Type', contentType);
    request.response.statusCode = 200;
    request.response.write(content);
    request.response.close();
  }

  // ─── WebSocket 连接处理 ─────────────────────────────

  Future<void> _handleWebSocket(HttpRequest request) async {
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    // 拉闸检查
    if (!_config.accepting) {
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'error': '服务暂停接受新连接'}));
      await request.response.close();
      return;
    }

    // 连接数限制
    if (_sessions.length >= _config.maxConnections) {
      request.response.statusCode = 503;
      request.response.write(jsonEncode({'error': '连接数已满'}));
      await request.response.close();
      return;
    }

    // 白名单检查 (本机始终放行)
    final isLocalhost = clientIp == '127.0.0.1' || clientIp == '::1' ||
        clientIp == 'localhost';
    final entry = _config.matchIp(clientIp);
    if (!isLocalhost && _config.whitelist.isNotEmpty && entry == null) {
      request.response.statusCode = 403;
      request.response.write(jsonEncode({'error': '不在白名单中'}));
      await request.response.close();
      return;
    }

    // 升级 WebSocket
    final ws = await WebSocketTransformer.upgrade(request);
    final sessionId = const Uuid().v4();

    final session = OnlineSession(
      id: sessionId,
      clientIp: clientIp,
      nickname: isLocalhost ? '管理员' : (entry?.nickname ?? clientIp),
      ws: ws,
      allowedModelCardIds: entry?.allowedModelCardIds ?? [],
      mcpEnabled: entry?.mcpEnabled ?? false,
      mcpServerIds: entry?.mcpServerIds ?? [],
      skillEnabled: entry?.skillEnabled ?? false,
      skillIds: entry?.skillIds ?? [],
      searchProvider: entry?.searchProvider ?? 'none',
      isAdmin: isLocalhost,
    );

    _sessions[sessionId] = session;
    _emit(OnlineServerEvent.userJoined(session));

    // 发送欢迎消息
    _wsSend(ws, {
      'type': 'welcome',
      'sessionId': sessionId,
      'nickname': session.nickname,
      'isAdmin': session.isAdmin,
      'searchProvider': session.searchProvider,
    });

    // 监听消息
    ws.listen(
      (data) => _handleWsMessage(session, data),
      onDone: () {
        _sessions.remove(sessionId);
        _emit(OnlineServerEvent.userLeft(session));
      },
      onError: (e) {
        _sessions.remove(sessionId);
        _emit(OnlineServerEvent.userLeft(session));
      },
    );
  }

  // ─── WebSocket 消息处理 ─────────────────────────────

  Future<void> _handleWsMessage(OnlineSession session, dynamic raw) async {
    if (raw is! String) return;

    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _wsSend(session.ws, {'type': 'error', 'message': '无效 JSON'});
      return;
    }

    final type = msg['type'] as String? ?? '';

    switch (type) {
      case 'chat':
        await _handleChat(session, msg);
      case 'stop':
        session.busy = false;
      case 'clear':
        session.messages.clear();
        session.artifacts.clear();
        _wsSend(session.ws, {'type': 'cleared'});
      case 'sync_history':
        _handleSyncHistory(session, msg);
      case 'list_models':
        await _handleListModels(session);
      case 'add_model':
        _handleAddModel(session, msg);
      case 'remove_model':
        _handleRemoveModel(session, msg);
      case 'test_model':
        await _handleTestModel(session, msg);
      case 'list_artifacts':
        _handleListArtifacts(session);
      case 'get_artifact':
        _handleGetArtifact(session, msg);
      // ─── 管理员专用: MCP / Skill 热插拔 ───
      case 'list_mcp_servers':
        if (session.isAdmin) _handleListMcpServers(session);
      case 'toggle_mcp':
        if (session.isAdmin) await _handleToggleMcp(session, msg);
      case 'list_skills':
        if (session.isAdmin) await _handleListSkills(session);
      case 'toggle_skill':
        if (session.isAdmin) _handleToggleSkill(session, msg);
      case 'set_search':
        if (session.isAdmin) _handleSetSearch(session, msg);
      default:
        _wsSend(session.ws, {'type': 'error', 'message': '未知消息类型: $type'});
    }
  }

  void _handleSyncHistory(OnlineSession session, Map<String, dynamic> msg) {
    final messages = msg['messages'] as List?;
    // 清空当前上下文并重新填入
    session.messages.clear();
    if (messages == null || messages.isEmpty) return;
    for (final m in messages) {
      if (m is Map<String, dynamic>) {
        final role = m['role'] as String? ?? '';
        final content = m['content'] as String? ?? '';
        if ((role == 'user' || role == 'assistant') && content.isNotEmpty) {
          session.messages.add({'role': role, 'content': content});
        }
      }
    }
  }

  Future<void> _handleChat(OnlineSession session, Map<String, dynamic> msg) async {
    if (session.busy) {
      _wsSend(session.ws, {'type': 'error', 'message': '正在处理中，请等待'});
      return;
    }

    final content = msg['content'] as String? ?? '';
    final modelCardId = msg['modelId'] as String?;
    if (content.isEmpty) return;

    session.busy = true;
    session.messages.add({'role': 'user', 'content': content});
    _wsSend(session.ws, {'type': 'ack', 'role': 'user'});

    try {
      final llm = await _createLlmForSession(session, modelCardId);
      if (llm == null) {
        _wsSend(session.ws, {'type': 'error', 'message': '无可用模型'});
        session.busy = false;
        return;
      }

      // 收集可用工具
      final tools = await _collectTools(session);
      final toolHandlers = _collectToolHandlers(session);

      // 注入 Skill 系统提示
      final skillSystemPrompt = await _buildSkillSystemPrompt(session);

      // 通知客户端当前激活的 Skill (用于调试终端)
      final activeSkillNames = await _getActiveSkillNames(session);
      if (activeSkillNames.isNotEmpty) {
        _wsSend(session.ws, {
          'type': 'debug_skills',
          'skills': activeSkillNames,
          'toolCount': tools.length,
          'promptLength': skillSystemPrompt.length,
        });
      }

      // 构建发送给 LLM 的消息 (在用户消息前注入 system)
      List<Map<String, dynamic>> buildMessages() {
        final msgs = <Map<String, dynamic>>[];
        if (skillSystemPrompt.isNotEmpty) {
          msgs.add({'role': 'system', 'content': skillSystemPrompt});
        }
        msgs.addAll(session.messages);
        return msgs;
      }

      // Tool-call 循环 (最多 8 轮工具调用)
      var stopped = false;
      final fullBuffer = StringBuffer();
      for (var round = 0; round < 8; round++) {
        if (!session.busy) { stopped = true; break; }

        final buffer = StringBuffer();
        StreamComplete? complete;

        await for (final event in llm.chatStreamFull(
          buildMessages(),
          tools: tools.isNotEmpty ? tools : null,
        )) {
          if (!session.busy) { stopped = true; break; }
          switch (event) {
            case ContentToken(:final text):
              buffer.write(text);
              _wsSend(session.ws, {'type': 'token', 'text': text});
            case ReasoningToken():
              break;
            case StreamComplete():
              complete = event;
          }
        }

        if (stopped) break;

        final hasToolCalls = complete?.toolCalls?.isNotEmpty == true;

        if (hasToolCalls) {
          // 把 assistant 带 tool_calls 的消息加入历史
          session.messages.add(complete!.toMessageJson());

          // 逐个执行工具
          for (final tc in complete.toolCalls!) {
            if (!session.busy) { stopped = true; break; }
            _wsSend(session.ws, {'type': 'tool_call', 'name': tc.name, 'args': tc.arguments});
            final result = await _executeTool(session, toolHandlers, tc.name, tc.arguments);
            session.messages.add({
              'role': 'tool',
              'tool_call_id': tc.id,
              'content': result,
            });
            _wsSend(session.ws, {'type': 'tool_result', 'name': tc.name, 'truncated': result.length > 200 ? '${result.substring(0, 200)}...' : result});
          }
          if (stopped) break;
          fullBuffer.write(buffer.toString());
          // 继续下一轮循环让 LLM 看到工具结果
          continue;
        }

        // 无工具调用 — 正常结束
        fullBuffer.write(buffer.toString());
        break;
      }

      final response = fullBuffer.toString();
      if (response.isNotEmpty) {
        session.messages.add({'role': 'assistant', 'content': response});
        final newArtifacts = _extractArtifacts(response);
        if (newArtifacts.isNotEmpty) {
          session.artifacts.addAll(newArtifacts);
          _wsSend(session.ws, {
            'type': 'artifacts_updated',
            'artifacts': session.artifacts.map((a) => a.toJson()).toList(),
          });
        }
      }

      if (stopped) {
        _wsSend(session.ws, {'type': 'stopped'});
      } else {
        _wsSend(session.ws, {'type': 'done', 'content': response});
      }

    } catch (e) {
      _wsSend(session.ws, {'type': 'error', 'message': 'LLM 调用失败: $e'});
    }

    session.busy = false;
  }

  // ─── 工具收集与执行 ────────────────────────────────────

  /// 收集当前 session 可用的工具定义 (OpenAI function format)
  Future<List<Map<String, dynamic>>> _collectTools(OnlineSession session) async {
    final tools = <Map<String, dynamic>>[];

    // 1) 联网搜索
    final searchCap = _getSearchCapability(session);
    if (searchCap != null && searchCap.isActive) {
      tools.addAll(searchCap.toolDefinitions);
    }

    // 2) MCP 工具 (管理员热插拔 / 普通用户按白名单)
    final mcpConn = _ref.read(mcpConnectionsProvider);
    final mcpIds = session.isAdmin
        ? session.activeMcpServerIds.toList()
        : (session.mcpEnabled ? session.mcpServerIds : <String>[]);
    for (final serverId in mcpIds) {
      final serverTools = mcpConn.toolsCache[serverId] ?? [];
      if (mcpConn.statuses[serverId] == McpConnectionStatus.connected) {
        tools.addAll(serverTools);
      }
    }

    // 3) Skill 工具 (tools.json)
    final skillIds = session.isAdmin
        ? session.activeSkillIds.toList()
        : (session.skillEnabled ? session.skillIds : <String>[]);
    if (skillIds.isNotEmpty) {
      final registry = _ref.read(skillRegistryProvider);
      final allSkills = _ref.read(skillsProvider).valueOrNull ?? [];
      for (final skillId in skillIds) {
        final skill = allSkills.where((s) => s.id == skillId).firstOrNull;
        if (skill != null) {
          final skillTools = await registry.loadSkillTools(skill);
          tools.addAll(skillTools);
        }
      }
    }

    return tools;
  }

  /// 收集工具处理器映射 (name -> handler)
  Map<String, Future<String> Function(Map<String, dynamic>)> _collectToolHandlers(OnlineSession session) {
    final handlers = <String, Future<String> Function(Map<String, dynamic>)>{};

    // 搜索
    final searchCap = _getSearchCapability(session);
    if (searchCap != null && searchCap.isActive) {
      for (final entry in searchCap.toolHandlers.entries) {
        handlers[entry.key] = entry.value;
      }
    }

    // MCP
    final mcpConn = _ref.read(mcpConnectionsProvider.notifier);
    final mcpState = _ref.read(mcpConnectionsProvider);
    final mcpIds = session.isAdmin
        ? session.activeMcpServerIds.toList()
        : (session.mcpEnabled ? session.mcpServerIds : <String>[]);
    for (final serverId in mcpIds) {
      if (mcpState.statuses[serverId] != McpConnectionStatus.connected) continue;
      final serverTools = mcpState.toolsCache[serverId] ?? [];
      for (final tool in serverTools) {
        final fn = tool['function'] as Map<String, dynamic>?;
        final name = fn?['name'] as String?;
        if (name != null) {
          handlers[name] = (args) => mcpConn.callTool(serverId, name, args);
        }
      }
    }

    return handlers;
  }

  /// 执行单个工具
  Future<String> _executeTool(
    OnlineSession session,
    Map<String, Future<String> Function(Map<String, dynamic>)> handlers,
    String name,
    Map<String, dynamic> args,
  ) async {
    final handler = handlers[name];
    if (handler == null) {
      return jsonEncode({'error': '工具不存在: $name'});
    }
    try {
      return await handler(args);
    } catch (e) {
      return jsonEncode({'error': '工具执行失败: $e'});
    }
  }

  /// 获取 session 对应的搜索能力
  SearchCapability? _getSearchCapability(OnlineSession session) {
    final providerName = session.isAdmin
        ? _adminSearchProvider
        : session.searchProvider;
    if (providerName == 'none') return null;

    final provider = SearchProvider.fromId(providerName);
    if (provider == SearchProvider.none) return null;

    final settings = _ref.read(searchSettingsProvider).valueOrNull;
    if (settings == null) return null;

    final config = settings.getConfig(provider);
    if (!config.isConfigured) return null;

    return SearchCapability(provider: provider, apiKey: config.apiKey);
  }

  /// 构建 Skill 系统提示 (合并所有激活 skill 的 SKILL.md)
  Future<String> _buildSkillSystemPrompt(OnlineSession session) async {
    final skillIds = session.isAdmin
        ? session.activeSkillIds.toList()
        : (session.skillEnabled ? session.skillIds : <String>[]);
    if (skillIds.isEmpty) return '';

    final registry = _ref.read(skillRegistryProvider);
    final allSkills = _ref.read(skillsProvider).valueOrNull ?? [];
    final parts = <String>[];

    for (final skillId in skillIds) {
      final skill = allSkills.where((s) => s.id == skillId).firstOrNull;
      if (skill != null) {
        try {
          final prompt = await registry.loadSkillPrompt(skill);
          if (prompt.isNotEmpty) {
            parts.add('## Skill: ${skill.name}\n$prompt');
          } else {
            _wsSend(session.ws, {'type': 'debug_skills_warn', 'message': 'Skill [${skill.name}] SKILL.md 为空, path=${skill.path}'});
          }
        } catch (e) {
          _wsSend(session.ws, {'type': 'debug_skills_warn', 'message': 'Skill [${skill.name}] 读取失败: $e'});
        }
      }
    }
    return parts.join('\n\n');
  }

  /// 获取当前激活的 Skill 名称列表 (用于调试输出)
  Future<List<String>> _getActiveSkillNames(OnlineSession session) async {
    final skillIds = session.isAdmin
        ? session.activeSkillIds.toList()
        : (session.skillEnabled ? session.skillIds : <String>[]);
    if (skillIds.isEmpty) return [];
    final allSkills = _ref.read(skillsProvider).valueOrNull ?? [];
    return skillIds
        .map((id) => allSkills.where((s) => s.id == id).firstOrNull?.name)
        .where((n) => n != null)
        .cast<String>()
        .toList();
  }

  /// 管理员的搜索设置 (可动态切换)
  String _adminSearchProvider = 'none';

  Future<void> _handleListModels(OnlineSession session) async {
    final allCards = _ref.read(modelCardsProvider).valueOrNull ?? [];
    final allowed = session.allowedModelCardIds;

    // 服务端分配的模型
    final serverModels = (allowed.isEmpty ? allCards : allCards.where(
      (c) => allowed.contains(c.id),
    )).map((c) => <String, dynamic>{
      'id': c.id,
      'name': c.name,
      'modelId': c.modelId,
      'provider': c.provider,
      'source': 'server',
    }).toList();

    // 用户自定义模型
    final userModels = session.userModels.map((m) => <String, dynamic>{
      'id': m.id,
      'name': m.name,
      'modelId': m.modelId,
      'provider': m.provider,
      'source': 'user',
    }).toList();

    _wsSend(session.ws, {
      'type': 'models',
      'data': [...serverModels, ...userModels],
    });
  }

  // ─── 用户自定义模型管理 ──────────────────────────────

  void _handleAddModel(OnlineSession session, Map<String, dynamic> msg) {
    try {
      final config = UserModelConfig.fromJson(msg['model'] as Map<String, dynamic>);
      // 移除已有同 id 的
      session.userModels.removeWhere((m) => m.id == config.id);
      session.userModels.add(config);
      _wsSend(session.ws, {'type': 'model_added', 'model': config.toJson()});
      // 刷新模型列表
      _handleListModels(session);
    } catch (e) {
      _wsSend(session.ws, {'type': 'error', 'message': '添加模型失败: $e'});
    }
  }

  void _handleRemoveModel(OnlineSession session, Map<String, dynamic> msg) {
    final modelId = msg['modelId'] as String? ?? '';
    session.userModels.removeWhere((m) => m.id == modelId);
    _wsSend(session.ws, {'type': 'model_removed', 'modelId': modelId});
    _handleListModels(session);
  }

  Future<void> _handleTestModel(OnlineSession session, Map<String, dynamic> msg) async {
    final baseUrl = (msg['baseUrl'] as String? ?? '').replaceAll(RegExp(r'/$'), '');
    final apiKey = msg['apiKey'] as String? ?? '';
    final provider = msg['provider'] as String? ?? 'openai';

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _wsSend(session.ws, {'type': 'test_result', 'success': false, 'error': '请填写完整信息'});
      return;
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      List<String> models = [];
      switch (provider) {
        case 'anthropic':
          final resp = await dio.get(
            '$baseUrl/v1/models',
            options: Options(headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'}),
          );
          if (resp.data is Map && resp.data['data'] is List) {
            models = (resp.data['data'] as List).map((m) => (m['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
          }
        case 'gemini':
          final resp = await dio.get('$baseUrl/models', queryParameters: {'key': apiKey});
          if (resp.data is Map && resp.data['models'] is List) {
            models = (resp.data['models'] as List)
                .map((m) => (m['name'] ?? '').toString())
                .map((n) => n.startsWith('models/') ? n.substring(7) : n)
                .where((s) => s.isNotEmpty).toList();
          }
        default: // openai
          final resp = await dio.get(
            '$baseUrl/models',
            options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
          );
          if (resp.data is Map && resp.data['data'] is List) {
            models = (resp.data['data'] as List).map((m) => (m['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
          } else if (resp.data is List) {
            models = (resp.data as List).map((m) => (m is Map ? (m['id'] ?? '') : m).toString()).where((s) => s.isNotEmpty).toList();
          }
      }

      models.sort();
      _wsSend(session.ws, {
        'type': 'test_result',
        'success': true,
        'models': models,
      });
    } on DioException catch (e) {
      _wsSend(session.ws, {
        'type': 'test_result',
        'success': false,
        'error': e.response?.statusCode != null ? 'HTTP ${e.response!.statusCode}' : (e.message ?? '网络错误'),
      });
    } catch (e) {
      _wsSend(session.ws, {'type': 'test_result', 'success': false, 'error': '$e'});
    }
  }

  // ─── 管理员: MCP / Skill / Search 热插拔 ─────────────────

  void _handleListMcpServers(OnlineSession session) {
    final servers = _ref.read(mcpServersProvider).valueOrNull ?? [];
    final connState = _ref.read(mcpConnectionsProvider);
    final list = servers.map((s) => <String, dynamic>{
      'id': s.id,
      'name': s.name,
      'transportType': s.transportType.name,
      'connected': connState.statuses[s.id] == McpConnectionStatus.connected,
      'active': session.activeMcpServerIds.contains(s.id),
      'toolCount': (connState.toolsCache[s.id] ?? []).length,
    }).toList();
    _wsSend(session.ws, {'type': 'mcp_servers', 'data': list});
  }

  Future<void> _handleToggleMcp(OnlineSession session, Map<String, dynamic> msg) async {
    final serverId = msg['serverId'] as String? ?? '';
    final active = msg['active'] as bool? ?? false;
    if (serverId.isEmpty) return;

    if (active) {
      // 激活: 如果未连接则尝试连接
      final connState = _ref.read(mcpConnectionsProvider);
      if (connState.statuses[serverId] != McpConnectionStatus.connected) {
        final servers = _ref.read(mcpServersProvider).valueOrNull ?? [];
        final server = servers.where((s) => s.id == serverId).firstOrNull;
        if (server != null) {
          try {
            await _ref.read(mcpConnectionsProvider.notifier).connect(server);
          } catch (e) {
            _wsSend(session.ws, {'type': 'error', 'message': 'MCP 连接失败: $e'});
            return;
          }
        }
      }
      session.activeMcpServerIds.add(serverId);
    } else {
      session.activeMcpServerIds.remove(serverId);
    }
    _handleListMcpServers(session);
  }

  Future<void> _handleListSkills(OnlineSession session) async {
    final skills = _ref.read(skillsProvider).valueOrNull ?? [];
    final list = skills.map((s) => <String, dynamic>{
      'id': s.id,
      'name': s.name,
      'description': s.description,
      'isActive': s.isActive,
      'active': session.activeSkillIds.contains(s.id),
    }).toList();
    _wsSend(session.ws, {'type': 'skills', 'data': list});
  }

  void _handleToggleSkill(OnlineSession session, Map<String, dynamic> msg) {
    final skillId = msg['skillId'] as String? ?? '';
    final active = msg['active'] as bool? ?? false;
    if (skillId.isEmpty) return;

    if (active) {
      session.activeSkillIds.add(skillId);
    } else {
      session.activeSkillIds.remove(skillId);
    }
    _handleListSkills(session);
  }

  void _handleSetSearch(OnlineSession session, Map<String, dynamic> msg) {
    final provider = msg['provider'] as String? ?? 'none';
    _adminSearchProvider = provider;
    _wsSend(session.ws, {'type': 'search_updated', 'provider': provider});
  }

  // ─── 产物管理 ─────────────────────────────────────────

  void _handleListArtifacts(OnlineSession session) {
    _wsSend(session.ws, {
      'type': 'artifacts',
      'data': session.artifacts.map((a) => a.toJson()).toList(),
    });
  }

  void _handleGetArtifact(OnlineSession session, Map<String, dynamic> msg) {
    final id = msg['artifactId'] as String? ?? '';
    final artifact = session.artifacts.where((a) => a.id == id).firstOrNull;
    if (artifact == null) {
      _wsSend(session.ws, {'type': 'error', 'message': '产物不存在'});
      return;
    }
    _wsSend(session.ws, {
      'type': 'artifact_content',
      'id': artifact.id,
      'filename': artifact.filename,
      'content': artifact.content,
      'language': artifact.language,
    });
  }

  /// 从 LLM 回复中提取带文件名的代码块作为产物
  /// 支持格式: ```lang:filename 或 ```filename.ext 或 带注释标记 // file: xxx
  List<SessionArtifact> _extractArtifacts(String response) {
    final artifacts = <SessionArtifact>[];
    // 匹配 ```lang 或 ```lang:filename 格式
    final codeBlockRegex = RegExp(
      r'```(\w+)?(?::([^\n]+))?\n([\s\S]*?)```',
      multiLine: true,
    );

    for (final match in codeBlockRegex.allMatches(response)) {
      final lang = match.group(1) ?? '';
      var filename = match.group(2)?.trim() ?? '';
      final content = match.group(3) ?? '';

      if (content.trim().isEmpty) continue;

      // 尝试从内容首行提取文件名 (// file: xxx 或 # file: xxx)
      if (filename.isEmpty) {
        final firstLine = content.split('\n').first.trim();
        final fileHint = RegExp(r'^(?://|#|/\*)\s*(?:file|filename|path):\s*(.+)', caseSensitive: false);
        final hintMatch = fileHint.firstMatch(firstLine);
        if (hintMatch != null) {
          filename = hintMatch.group(1)!.trim();
        }
      }

      // 如果有文件名或代码长度足够大 (>5行)，认为是产物
      if (filename.isNotEmpty || content.split('\n').length > 5) {
        if (filename.isEmpty) {
          final ext = _langToExt(lang);
          filename = 'file_${artifacts.length + 1}$ext';
        }
        artifacts.add(SessionArtifact(
          id: const Uuid().v4(),
          filename: filename,
          content: content,
          language: lang,
        ));
      }
    }
    return artifacts;
  }

  String _langToExt(String lang) {
    const map = {
      'dart': '.dart', 'python': '.py', 'py': '.py',
      'javascript': '.js', 'js': '.js', 'typescript': '.ts', 'ts': '.ts',
      'java': '.java', 'kotlin': '.kt', 'swift': '.swift',
      'rust': '.rs', 'go': '.go', 'c': '.c', 'cpp': '.cpp',
      'html': '.html', 'css': '.css', 'json': '.json', 'yaml': '.yaml',
      'sql': '.sql', 'shell': '.sh', 'bash': '.sh', 'xml': '.xml',
      'markdown': '.md', 'md': '.md', 'toml': '.toml',
    };
    return map[lang.toLowerCase()] ?? '.txt';
  }

  // ─── LLM 客户端创建 ────────────────────────────────

  Future<LlmClient?> _createLlmForSession(
    OnlineSession session, String? requestedModelId,
  ) async {
    // 优先检查是否请求的是用户自定义模型
    if (requestedModelId != null) {
      final userModel = session.userModels.where((m) => m.id == requestedModelId).firstOrNull;
      if (userModel != null) {
        return LlmClient(
          baseUrl: userModel.baseUrl,
          apiKey: userModel.apiKey,
          model: userModel.modelId,
          provider: LlmProvider.values.firstWhere(
            (p) => p.name == userModel.provider,
            orElse: () => LlmProvider.openai,
          ),
        );
      }
    }

    // 服务端模型
    final allCards = _ref.read(modelCardsProvider).valueOrNull ?? [];
    if (allCards.isEmpty && session.userModels.isEmpty) return null;

    final allowed = session.allowedModelCardIds;
    final candidates = allowed.isEmpty
        ? allCards
        : allCards.where((c) => allowed.contains(c.id)).toList();

    if (candidates.isEmpty) {
      // 如果服务端无可用模型, fallback 到用户自定义的第一个
      if (session.userModels.isNotEmpty) {
        final m = session.userModels.first;
        return LlmClient(
          baseUrl: m.baseUrl,
          apiKey: m.apiKey,
          model: m.modelId,
          provider: LlmProvider.values.firstWhere(
            (p) => p.name == m.provider,
            orElse: () => LlmProvider.openai,
          ),
        );
      }
      return null;
    }

    // 选择模型: 请求指定 > 第一个可用
    final card = requestedModelId != null
        ? candidates.firstWhere(
            (c) => c.id == requestedModelId || c.modelId == requestedModelId,
            orElse: () => candidates.first,
          )
        : candidates.first;

    return LlmClient(
      baseUrl: card.baseUrl,
      apiKey: card.apiKey,
      model: card.modelId,
      provider: LlmProvider.values.firstWhere(
        (p) => p.name == card.provider,
        orElse: () => LlmProvider.openai,
      ),
    );
  }

  // ─── 文件下载 ──────────────────────────────────────

  Future<void> _handleDownload(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    // /download/{sessionId} → ZIP all artifacts
    // /download/{sessionId}/{artifactId} → single file
    if (segments.length < 2) {
      request.response.statusCode = 400;
      request.response.write('Bad request');
      await request.response.close();
      return;
    }

    final sessionId = segments[1];
    final session = _sessions[sessionId];

    if (session == null) {
      request.response.statusCode = 404;
      request.response.write('Session not found');
      await request.response.close();
      return;
    }

    if (segments.length >= 3) {
      // 单文件下载
      final artifactId = segments[2];
      final artifact = session.artifacts.where((a) => a.id == artifactId).firstOrNull;
      if (artifact == null) {
        request.response.statusCode = 404;
        request.response.write('Artifact not found');
        await request.response.close();
        return;
      }
      final bytes = utf8.encode(artifact.content);
      request.response.headers
        ..contentType = ContentType('application', 'octet-stream')
        ..add('Content-Disposition', 'attachment; filename="${artifact.filename}"');
      request.response.statusCode = 200;
      request.response.add(bytes);
      await request.response.close();
      return;
    }

    // ZIP 打包全部产物
    if (session.artifacts.isEmpty) {
      request.response.statusCode = 404;
      request.response.write('No artifacts to download');
      await request.response.close();
      return;
    }

    final archive = Archive();
    for (final artifact in session.artifacts) {
      final data = utf8.encode(artifact.content);
      archive.addFile(ArchiveFile(artifact.filename, data.length, data));
    }
    final zipBytes = ZipEncoder().encode(archive);

    request.response.headers
      ..contentType = ContentType('application', 'zip')
      ..add('Content-Disposition', 'attachment; filename="artifacts_${session.nickname}.zip"');
    request.response.statusCode = 200;
    request.response.add(zipBytes);
    await request.response.close();
  }

  // ─── 工具方法 ──────────────────────────────────────

  Future<void> _closeSession(OnlineSession session, {String? reason}) async {
    try {
      _wsSend(session.ws, {'type': 'disconnect', 'reason': reason ?? 'closed'});
      await session.ws.close();
    } catch (_) {}
  }

  void _wsSend(WebSocket ws, Map<String, dynamic> data) {
    try {
      ws.add(jsonEncode(data));
    } catch (_) {}
  }

  void _emit(OnlineServerEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}

// ─── 事件模型 ──────────────────────────────────────────

sealed class OnlineServerEvent {
  factory OnlineServerEvent.started(int port) = ServerStarted;
  factory OnlineServerEvent.stopped() = ServerStopped;
  factory OnlineServerEvent.userJoined(OnlineSession session) = UserJoined;
  factory OnlineServerEvent.userLeft(OnlineSession session) = UserLeft;
  factory OnlineServerEvent.error(String message) = ServerError;
  factory OnlineServerEvent.configChanged(OnlineServiceConfig config) = ConfigChanged;
}

class ServerStarted implements OnlineServerEvent {
  final int port;
  ServerStarted(this.port);
}

class ServerStopped implements OnlineServerEvent {
  ServerStopped();
}

class UserJoined implements OnlineServerEvent {
  final OnlineSession session;
  UserJoined(this.session);
}

class UserLeft implements OnlineServerEvent {
  final OnlineSession session;
  UserLeft(this.session);
}

class ServerError implements OnlineServerEvent {
  final String message;
  ServerError(this.message);
}

class ConfigChanged implements OnlineServerEvent {
  final OnlineServiceConfig config;
  ConfigChanged(this.config);
}

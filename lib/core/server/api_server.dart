import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger/app_logger.dart';
import '../llm/llm_client.dart';
import '../llm/llm_provider.dart';
import '../toolshell/agent_loop.dart';
import 'anthropic_proxy.dart';
import 'api_server_config.dart';
import 'server_session.dart';

/// 对外 HTTP API 服务。
///
/// 暴露 OpenAI 兼容接口, 让任意兼容客户端即插即用地调用 RemindAI 聚合的
/// 模型 + 技能 + MCP + 记忆 + 搜索能力。
///
/// 安全约束:
/// - 默认仅绑定 127.0.0.1 (仅本机)
/// - 强制 Bearer token 鉴权
/// - 不带 workDir → 无本地文件读写
class ApiServer {
  final Ref _ref;
  ApiServerConfig _config;

  HttpServer? _server;

  /// 绑定成功后缓存的端口。不直接读 `_server.port`,
  /// 因为 socket 处于关闭/未绑定瞬态时该 getter 会抛 HttpException。
  int? _boundPort;

  bool get isRunning => _server != null;
  int? get boundPort => _boundPort;

  ApiServer(this._ref, this._config);

  /// 启动服务。已运行则先停。配置不完整则抛错。
  Future<void> start() async {
    if (!_config.canStart) {
      throw StateError('服务未启用或 token/端口未配置');
    }
    await stop();

    final address = _config.bindAll
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;

    final server = await HttpServer.bind(address, _config.port);
    _server = server;
    _boundPort = server.port;
    AppLogger.instance.log(
      '[ApiServer] 已启动 ${address.address}:${_config.port} '
      '(bindAll=${_config.bindAll})',
    );

    server.listen(
      _handle,
      onError: (Object e) => AppLogger.instance.log('[ApiServer] 监听错误: $e'),
    );
  }

  /// 停止服务。
  Future<void> stop() async {
    final s = _server;
    if (s != null) {
      await s.close(force: true);
      _server = null;
      _boundPort = null;
      AppLogger.instance.log('[ApiServer] 已停止');
    }
  }

  /// 用新配置重启 (仅在原本就该运行时才重新拉起)。
  Future<void> applyConfig(ApiServerConfig config) async {
    _config = config;
    await stop();
    if (config.canStart) {
      await start();
    }
  }

  // ─── 请求分发 ───

  Future<void> _handle(HttpRequest req) async {
    try {
      _setCors(req.response);

      // IP 白名单 (早于一切, 含探活)
      if (!_ipAllowed(req)) {
        final ip = req.connectionInfo?.remoteAddress.address ?? 'unknown';
        AppLogger.instance.log('[ApiServer] 拒绝非白名单 IP: $ip');
        await _error(req.response, HttpStatus.forbidden, 'ip not allowed');
        return;
      }

      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      final path = req.uri.path;

      // 健康检查 (无需鉴权, 便于客户端探活)
      if (req.method == 'GET' && (path == '/health' || path == '/v1/health')) {
        await _json(req.response, {'status': 'ok'});
        return;
      }

      // 鉴权
      if (!_authorized(req)) {
        await _error(req.response, HttpStatus.unauthorized, 'invalid token');
        return;
      }

      // 模型列表 (OpenAI 兼容)
      if (req.method == 'GET' && path == '/v1/models') {
        await _handleModels(req);
        return;
      }

      // 对话补全 (OpenAI 聚合): 跑 RemindAI 自己的 Agent
      if (req.method == 'POST' &&
          _config.enableOpenAi &&
          path == '/v1/chat/completions') {
        await _handleChatCompletions(req);
        return;
      }

      // 对话 (Claude 聚合): Anthropic 协议输出, 跑 RemindAI 自己的 Agent
      if (req.method == 'POST' &&
          _config.enableClaudeAgent &&
          path == '/v1/agent/messages') {
        await _handleAnthropicAgent(req);
        return;
      }

      // 对话 (Claude 纯代理): 透传客户端工具, 仅做协议转换
      if (req.method == 'POST' &&
          _config.enableClaudeProxy &&
          path == '/v1/messages') {
        await _handleAnthropicMessages(req);
        return;
      }

      await _error(req.response, HttpStatus.notFound, 'not found: $path');
    } catch (e, st) {
      AppLogger.instance.log('[ApiServer] 处理异常: $e\n$st');
      try {
        await _error(
          req.response,
          HttpStatus.internalServerError,
          e.toString(),
        );
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest req) {
    if (_config.token.isEmpty) return false;
    // OpenAI 风格: Authorization: Bearer <token>
    final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (auth == 'Bearer ${_config.token}') return true;
    // Anthropic 风格: x-api-key: <token>
    final apiKey = req.headers.value('x-api-key') ?? '';
    if (apiKey == _config.token) return true;
    return false;
  }

  // ─── IP 白名单 ───

  /// 判断请求来源 IP 是否允许访问。
  ///
  /// 规则:
  /// - 白名单为空 → 全部放行 (默认, 仅本机时无需限制)
  /// - 本机回环地址 (127.0.0.1 / ::1) → 始终放行, 避免把自己锁在外面
  /// - 否则需精确命中某条 IP 或落入某个 CIDR 网段
  bool _ipAllowed(HttpRequest req) {
    final list = _config.ipWhitelist;
    if (list.isEmpty) return true;

    final remote = req.connectionInfo?.remoteAddress;
    if (remote == null) return false;
    if (remote.isLoopback) return true;

    final ip = remote.address;
    for (final entry in list) {
      final rule = entry.trim();
      if (rule.isEmpty) continue;
      if (rule.contains('/')) {
        if (_ipInCidr(ip, rule)) return true;
      } else if (rule == ip) {
        return true;
      }
    }
    return false;
  }

  /// 判断 IPv4 地址是否落入 CIDR 网段 (如 192.168.1.0/24)。
  /// 解析失败或非 IPv4 一律视为不匹配。
  bool _ipInCidr(String ip, String cidr) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) return false;
      final prefix = int.parse(parts[1]);
      if (prefix < 0 || prefix > 32) return false;

      final addr = _ipv4ToInt(ip);
      final base = _ipv4ToInt(parts[0]);
      if (addr == null || base == null) return false;

      // mask 为 0 时放行整个 IPv4 空间
      final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
      return (addr & mask) == (base & mask);
    } catch (_) {
      return false;
    }
  }

  /// IPv4 点分十进制 → 32 位整数。非合法 IPv4 返回 null。
  int? _ipv4ToInt(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return null;
    var result = 0;
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null || v < 0 || v > 255) return null;
      result = (result << 8) | v;
    }
    return result & 0xffffffff;
  }

  // ─── /v1/models ───

  Future<void> _handleModels(HttpRequest req) async {
    final builder = ServerSessionBuilder(_ref, _config);
    final cards = builder.listModelCards();
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = cards.isEmpty
        ? [
            {
              'id': 'remind-ai',
              'object': 'model',
              'created': created,
              'owned_by': 'remind-ai',
            },
          ]
        : cards
              .map(
                (c) => {
                  'id': c.modelId,
                  'object': 'model',
                  'created': created,
                  'owned_by': 'remind-ai',
                  // 自定义扩展, 便于客户端展示更友好的名字
                  'remind_card_name': c.name,
                },
              )
              .toList();
    await _json(req.response, {'object': 'list', 'data': data});
  }

  // ─── /v1/chat/completions ───

  Future<void> _handleChatCompletions(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      await _error(req.response, HttpStatus.badRequest, 'invalid JSON body');
      return;
    }

    final rawMessages = (payload['messages'] as List?) ?? const [];
    if (rawMessages.isEmpty) {
      await _error(req.response, HttpStatus.badRequest, 'messages is empty');
      return;
    }

    // 拆出历史与最后一条 user input
    final history = <Map<String, dynamic>>[];
    String userInput = '';
    for (var i = 0; i < rawMessages.length; i++) {
      final m = Map<String, dynamic>.from(rawMessages[i] as Map);
      if (i == rawMessages.length - 1 && m['role'] == 'user') {
        userInput = _contentToText(m['content']);
      } else {
        history.add(m);
      }
    }

    final stream = payload['stream'] == true;
    // 自定义扩展: 是否透出工具调用过程 (默认否, 保证 OpenAI 兼容)
    final exposeTools = payload['remind_expose_tools'] == true;
    final requestedModel = payload['model']?.toString();

    final ServerSession session;
    try {
      session = await ServerSessionBuilder(_ref, _config).build(
        history: history,
        requestedModel: requestedModel,
        userInput: userInput,
      );
    } catch (e) {
      await _error(req.response, HttpStatus.serviceUnavailable, e.toString());
      return;
    }

    final loop = session.createLoop();
    final modelId = session.modelId;

    if (stream) {
      await _streamCompletion(
        req.response,
        loop.chat(userInput),
        modelId,
        exposeTools,
      );
    } else {
      await _blockingCompletion(req.response, loop.chat(userInput), modelId);
    }
  }

  /// 非流式: 聚合所有 token, 一次性返回标准 OpenAI 响应。
  Future<void> _blockingCompletion(
    HttpResponse res,
    Stream<AgentEvent> events,
    String modelId,
  ) async {
    final buf = StringBuffer();
    String? errMsg;
    await for (final ev in events) {
      switch (ev) {
        case AgentToken(text: final t):
          buf.write(t);
        case AgentDone(content: final c):
          if (buf.isEmpty && c.isNotEmpty) buf.write(c);
        case AgentError(message: final m):
          errMsg = m;
        case AgentLoopLimitReached(rounds: final rounds):
          errMsg = '单轮对话内部工具调用次数达到上限($rounds)，未能收敛到最终回复';
        default:
          break;
      }
    }

    if (errMsg != null) {
      await _error(res, HttpStatus.internalServerError, errMsg);
      return;
    }

    await _json(res, {
      'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': modelId,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': buf.toString()},
          'finish_reason': 'stop',
        },
      ],
    });
  }

  /// 流式: 以 SSE 推送 OpenAI 风格 chunk。
  Future<void> _streamCompletion(
    HttpResponse res,
    Stream<AgentEvent> events,
    String modelId,
    bool exposeTools,
  ) async {
    res.statusCode = HttpStatus.ok;
    res.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive');

    final id = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    void sendChunk(Map<String, dynamic> delta, {String? finish}) {
      final chunk = {
        'id': id,
        'object': 'chat.completion.chunk',
        'created': created,
        'model': modelId,
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      };
      res.write('data: ${jsonEncode(chunk)}\n\n');
    }

    // 首个 chunk 带 role
    sendChunk({'role': 'assistant', 'content': ''});

    try {
      await for (final ev in events) {
        switch (ev) {
          case AgentToken(text: final t):
            sendChunk({'content': t});
          case AgentToolStart(name: final n, args: final a):
            if (exposeTools) {
              sendChunk({
                'remind_tool_start': {'name': n, 'arguments': a},
              });
            }
          case AgentToolResult(toolCallId: final cid, result: final r):
            if (exposeTools) {
              sendChunk({
                'remind_tool_result': {'id': cid, 'result': r},
              });
            }
          case AgentError(message: final m):
            sendChunk({'content': '\n[错误] $m'});
          case AgentLoopLimitReached(rounds: final rounds):
            sendChunk({
              'content': '\n[错误] 单轮对话内部工具调用次数达到上限($rounds)，未能收敛到最终回复',
            });
          case AgentDone():
            break;
        }
      }
      sendChunk({}, finish: 'stop');
      res.write('data: [DONE]\n\n');
    } catch (e) {
      sendChunk({'content': '\n[服务异常] $e'}, finish: 'stop');
      res.write('data: [DONE]\n\n');
    }
    await res.close();
  }

  // ─── /v1/agent/messages (Anthropic / Claude 协议, 聚合 Agent 模式) ───
  //
  // 与纯代理端点相反: 本端点跑 RemindAI 自己的 AgentLoop (技能/MCP/记忆/搜索),
  // 工具在服务端内部执行, 客户端只拿到最终的 assistant 文本。
  // 输出走 Anthropic 协议, 让仅支持 Anthropic 的客户端 (如 CherryStudio Agent)
  // 也能直接调用 RemindAI 的聚合能力。

  Future<void> _handleAnthropicAgent(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      await _anthropicError(
        req.response,
        HttpStatus.badRequest,
        'invalid JSON body',
      );
      return;
    }

    final rawMessages = (payload['messages'] as List?) ?? const [];
    if (rawMessages.isEmpty) {
      await _anthropicError(
        req.response,
        HttpStatus.badRequest,
        'messages is empty',
      );
      return;
    }

    // 拆出历史与最后一条 user input (Anthropic content 可能是 block 数组)
    final history = <Map<String, dynamic>>[];
    String userInput = '';
    for (var i = 0; i < rawMessages.length; i++) {
      final m = Map<String, dynamic>.from(rawMessages[i] as Map);
      if (i == rawMessages.length - 1 && m['role'] == 'user') {
        userInput = AnthropicProxy.blocksToText(m['content']);
      } else {
        // 统一压平为纯文本历史 (聚合 Agent 不消费客户端工具)
        history.add({
          'role': m['role'],
          'content': AnthropicProxy.blocksToText(m['content']),
        });
      }
    }

    final stream = payload['stream'] == true;
    final requestedModel = payload['model']?.toString();

    final ServerSession session;
    try {
      session = await ServerSessionBuilder(_ref, _config).build(
        history: history,
        requestedModel: requestedModel,
        userInput: userInput,
      );
    } catch (e) {
      await _anthropicError(
        req.response,
        HttpStatus.serviceUnavailable,
        e.toString(),
      );
      return;
    }

    final loop = session.createLoop();
    final modelId = session.modelId;

    AppLogger.instance.log(
      '[ApiServer] /v1/agent/messages 聚合: model=$modelId, '
      'history=${history.length}, stream=$stream',
    );

    if (stream) {
      await _streamAnthropicAgent(req.response, loop.chat(userInput), modelId);
    } else {
      await _blockingAnthropicAgent(
        req.response,
        loop.chat(userInput),
        modelId,
      );
    }
  }

  /// 把聚合 Agent 的事件流聚合为终态文本。
  Future<({String text, String? error})> _collectAgent(
    Stream<AgentEvent> events,
  ) async {
    final buf = StringBuffer();
    String? error;
    try {
      await for (final ev in events) {
        switch (ev) {
          case AgentToken(text: final t):
            buf.write(t);
          case AgentDone(content: final c):
            if (buf.isEmpty && c.isNotEmpty) buf.write(c);
          case AgentError(message: final m):
            error = m;
          case AgentLoopLimitReached(rounds: final rounds):
            error = '单轮对话内部工具调用次数达到上限($rounds)，未能收敛到最终回复';
          default:
            break;
        }
      }
    } catch (e) {
      error = e.toString();
    }
    return (text: buf.toString(), error: error);
  }

  /// 非流式 Anthropic 响应 (聚合 Agent)。
  Future<void> _blockingAnthropicAgent(
    HttpResponse res,
    Stream<AgentEvent> events,
    String modelId,
  ) async {
    final r = await _collectAgent(events);
    if (r.error != null) {
      await _anthropicError(res, HttpStatus.internalServerError, r.error!);
      return;
    }
    await _json(res, {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'model': modelId,
      'content': [
        {'type': 'text', 'text': r.text},
      ],
      'stop_reason': 'end_turn',
      'stop_sequence': null,
      'usage': {'input_tokens': 0, 'output_tokens': 0},
    });
  }

  /// 流式 Anthropic 响应 (聚合 Agent, 标准 SSE 事件序列)。
  /// 工具在服务端内部执行, 这里仅逐 token 推送最终文本。
  Future<void> _streamAnthropicAgent(
    HttpResponse res,
    Stream<AgentEvent> events,
    String modelId,
  ) async {
    res.statusCode = HttpStatus.ok;
    res.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive');

    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    void sendEvent(String event, Map<String, dynamic> data) {
      res.write('event: $event\n');
      res.write('data: ${jsonEncode(data)}\n\n');
    }

    sendEvent('message_start', {
      'type': 'message_start',
      'message': {
        'id': msgId,
        'type': 'message',
        'role': 'assistant',
        'model': modelId,
        'content': <dynamic>[],
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {'input_tokens': 0, 'output_tokens': 0},
      },
    });
    sendEvent('ping', {'type': 'ping'});
    sendEvent('content_block_start', {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });

    try {
      await for (final ev in events) {
        switch (ev) {
          case AgentToken(text: final t):
            sendEvent('content_block_delta', {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': t},
            });
          case AgentError(message: final m):
            sendEvent('content_block_delta', {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': '\n[错误] $m'},
            });
          case AgentLoopLimitReached(rounds: final rounds):
            sendEvent('content_block_delta', {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {
                'type': 'text_delta',
                'text': '\n[错误] 单轮对话内部工具调用次数达到上限($rounds)，未能收敛到最终回复',
              },
            });
          default:
            break;
        }
      }
    } catch (e) {
      sendEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': '\n[服务异常] $e'},
      });
    }

    sendEvent('content_block_stop', {'type': 'content_block_stop', 'index': 0});
    sendEvent('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
      'usage': {'output_tokens': 0},
    });
    sendEvent('message_stop', {'type': 'message_stop'});
    await res.close();
  }

  // ─── /v1/messages (Anthropic / Claude 协议, 纯代理模式) ───
  //
  // 与 OpenAI 端点的"聚合 Agent"不同: 本端点不跑内部循环、不执行工具,
  // 而是把客户端 (CherryStudio Agent) 携带的 tools 透传给底层模型, 再把模型
  // 返回的 tool_calls 翻译回 Anthropic tool_use 块, 交还客户端执行。
  // 目的: 让 CherryStudio Agent 能驱动 Kimi/GPT/Gemini 等非 Anthropic 模型。

  Future<void> _handleAnthropicMessages(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      await _anthropicError(
        req.response,
        HttpStatus.badRequest,
        'invalid JSON body',
      );
      return;
    }

    final rawMessages = (payload['messages'] as List?) ?? const [];
    if (rawMessages.isEmpty) {
      await _anthropicError(
        req.response,
        HttpStatus.badRequest,
        'messages is empty',
      );
      return;
    }

    // 解析模型卡 (按请求 model 路由)
    final builder = ServerSessionBuilder(_ref, _config);
    final card = builder.resolveModelCard(
      requestedModel: payload['model']?.toString(),
    );
    if (card == null) {
      await _anthropicError(
        req.response,
        HttpStatus.serviceUnavailable,
        '服务端未配置可用模型卡',
      );
      return;
    }

    // 直接构建裸 LLM 客户端 (不组装 Agent / 工具 / 记忆)
    final llm = LlmClient(
      baseUrl: card.baseUrl,
      apiKey: card.apiKey,
      model: card.modelId,
      provider: LlmProviderX.fromId(card.provider),
    );

    // 消息历史 (含 tool_use / tool_result 双向还原) + 顶层 system
    final systemText = AnthropicProxy.blocksToText(payload['system']);
    final messages = AnthropicProxy.convertMessages(
      rawMessages,
      systemText: systemText,
    );

    // 透传客户端工具
    final tools = AnthropicProxy.convertTools(payload['tools']);

    final stream = payload['stream'] == true;
    final modelId = card.modelId;

    AppLogger.instance.log(
      '[ApiServer] /v1/messages 代理: model=$modelId, msgs=${messages.length}, '
      'tools=${tools?.length ?? 0}, stream=$stream',
    );

    if (stream) {
      await _streamAnthropic(
        req.response,
        llm.chatStreamFull(messages, tools: tools),
        modelId,
      );
    } else {
      await _blockingAnthropic(
        req.response,
        llm.chatStreamFull(messages, tools: tools),
        modelId,
      );
    }
  }

  /// 把一次 LLM 流聚合为终态 (content + 工具调用)。
  /// 兼容标准 tool_calls 与 Kimi K2 文本内嵌 token。
  Future<({String text, List<ToolCall> calls, String? error})> _collectStream(
    Stream<StreamEvent> events,
  ) async {
    final buf = StringBuffer();
    List<ToolCall> calls = const [];
    String? error;
    try {
      await for (final ev in events) {
        switch (ev) {
          case ContentToken(text: final t):
            buf.write(t);
          case ReasoningToken():
            break; // 推理 token 不计入对外正文
          case StreamComplete(content: final c, toolCalls: final tc):
            if (buf.isEmpty && c != null) buf.write(c);
            if (tc != null && tc.isNotEmpty) calls = tc;
        }
      }
    } catch (e) {
      error = e.toString();
    }

    // 标准协议未返回工具调用时, 尝试解析 Kimi 文本内嵌 token
    var text = buf.toString();
    if (calls.isEmpty && AnthropicProxy.hasKimiToolCalls(text)) {
      final (cleaned, kimiCalls) = AnthropicProxy.parseKimiToolCalls(text);
      if (kimiCalls.isNotEmpty) {
        text = cleaned;
        calls = kimiCalls;
      }
    }
    return (text: text, calls: calls, error: error);
  }

  /// 把工具调用列表构造为 Anthropic content blocks (text + tool_use)。
  List<Map<String, dynamic>> _buildAnthropicBlocks(
    String text,
    List<ToolCall> calls,
  ) {
    final blocks = <Map<String, dynamic>>[];
    if (text.trim().isNotEmpty) {
      blocks.add({'type': 'text', 'text': text});
    }
    for (final c in calls) {
      blocks.add({
        'type': 'tool_use',
        'id': c.id,
        'name': c.name,
        'input': c.arguments,
      });
    }
    if (blocks.isEmpty) {
      blocks.add({'type': 'text', 'text': ''});
    }
    return blocks;
  }

  /// 非流式 Anthropic 响应 (代理)。
  Future<void> _blockingAnthropic(
    HttpResponse res,
    Stream<StreamEvent> events,
    String modelId,
  ) async {
    final r = await _collectStream(events);
    if (r.error != null) {
      await _anthropicError(res, HttpStatus.internalServerError, r.error!);
      return;
    }

    final stopReason = r.calls.isNotEmpty ? 'tool_use' : 'end_turn';
    await _json(res, {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'model': modelId,
      'content': _buildAnthropicBlocks(r.text, r.calls),
      'stop_reason': stopReason,
      'stop_sequence': null,
      'usage': {'input_tokens': 0, 'output_tokens': 0},
    });
  }

  /// 流式 Anthropic 响应 (代理, 标准 SSE 事件序列)。
  ///
  /// 实现策略: 先聚合整段输出 (因工具调用需完整 JSON 参数才能成块),
  /// 再按 Anthropic 块序列回放。文本块逐字回放, tool_use 块整体下发。
  Future<void> _streamAnthropic(
    HttpResponse res,
    Stream<StreamEvent> events,
    String modelId,
  ) async {
    res.statusCode = HttpStatus.ok;
    res.headers
      ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive');

    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    void sendEvent(String event, Map<String, dynamic> data) {
      res.write('event: $event\n');
      res.write('data: ${jsonEncode(data)}\n\n');
    }

    final r = await _collectStream(events);
    final stopReason = r.calls.isNotEmpty ? 'tool_use' : 'end_turn';

    // message_start
    sendEvent('message_start', {
      'type': 'message_start',
      'message': {
        'id': msgId,
        'type': 'message',
        'role': 'assistant',
        'model': modelId,
        'content': <dynamic>[],
        'stop_reason': null,
        'stop_sequence': null,
        'usage': {'input_tokens': 0, 'output_tokens': 0},
      },
    });
    sendEvent('ping', {'type': 'ping'});

    var blockIndex = 0;

    // 文本块
    final text = r.error != null ? '[错误] ${r.error}' : r.text;
    if (text.trim().isNotEmpty || r.calls.isEmpty) {
      sendEvent('content_block_start', {
        'type': 'content_block_start',
        'index': blockIndex,
        'content_block': {'type': 'text', 'text': ''},
      });
      if (text.isNotEmpty) {
        sendEvent('content_block_delta', {
          'type': 'content_block_delta',
          'index': blockIndex,
          'delta': {'type': 'text_delta', 'text': text},
        });
      }
      sendEvent('content_block_stop', {
        'type': 'content_block_stop',
        'index': blockIndex,
      });
      blockIndex++;
    }

    // tool_use 块 (input 通过 input_json_delta 整体下发)
    for (final c in r.calls) {
      sendEvent('content_block_start', {
        'type': 'content_block_start',
        'index': blockIndex,
        'content_block': {
          'type': 'tool_use',
          'id': c.id,
          'name': c.name,
          'input': <String, dynamic>{},
        },
      });
      sendEvent('content_block_delta', {
        'type': 'content_block_delta',
        'index': blockIndex,
        'delta': {
          'type': 'input_json_delta',
          'partial_json': jsonEncode(c.arguments),
        },
      });
      sendEvent('content_block_stop', {
        'type': 'content_block_stop',
        'index': blockIndex,
      });
      blockIndex++;
    }

    sendEvent('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason, 'stop_sequence': null},
      'usage': {'output_tokens': 0},
    });
    sendEvent('message_stop', {'type': 'message_stop'});
    await res.close();
  }

  // ─── 工具方法 ───

  String _contentToText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      // 多模态数组: 抽取 text 片段
      final parts = <String>[];
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          parts.add(item['text']?.toString() ?? '');
        }
      }
      return parts.join('\n');
    }
    return content?.toString() ?? '';
  }

  void _setCors(HttpResponse res) {
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, x-api-key, anthropic-version, anthropic-beta',
      );
  }

  Future<void> _json(HttpResponse res, Map<String, dynamic> data) async {
    res
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data));
    await res.close();
  }

  Future<void> _error(HttpResponse res, int status, String message) async {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'error': {'message': message, 'type': 'remind_ai_error'},
        }),
      );
    await res.close();
  }

  /// Anthropic 风格错误体。
  Future<void> _anthropicError(
    HttpResponse res,
    int status,
    String message,
  ) async {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'type': 'error',
          'error': {'type': 'api_error', 'message': message},
        }),
      );
    await res.close();
  }
}

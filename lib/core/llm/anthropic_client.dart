import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

import 'llm_client.dart';

/// Anthropic (Claude) 原生客户端 — /v1/messages 协议。
///
/// 对上层暴露与 [OpenAiClient] 相同的接口：输入/输出均使用 OpenAI 风格的
/// 消息与工具格式，内部负责双向翻译。
///
/// **URL 约定**: 用户填写完整的 endpoint URL（如 `https://api.anthropic.com/v1/messages`
/// 或中转站的 `https://relay.example.com/v1/messages`），客户端直接 POST 到该地址，
/// 不再在代码中拼接路径。
class AnthropicClient implements LlmClient {
  final Dio _dio;
  final String baseUrl;
  final String apiKey;

  @override
  final String model;

  /// Anthropic 要求显式 max_tokens。
  final int maxTokens;

  /// Anthropic API 版本头。
  static const _apiVersion = '2023-06-01';

  AnthropicClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.maxTokens = 4096,
  }) : _endpointUrl = _normalizeEndpoint(baseUrl),
       _dio = Dio(
         BaseOptions(
           // 不设 baseUrl — 使用绝对 URL 直接 POST
           headers: {
             'x-api-key': apiKey,
             'anthropic-version': _apiVersion,
             'content-type': 'application/json',
           },
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(minutes: 5),
         ),
       );

  /// 规范化后的完整 endpoint URL（用于 POST 请求）。
  final String _endpointUrl;

  /// 规范化 endpoint URL：只去掉末尾斜杠。
  /// 用户应填写完整地址如 `https://api.anthropic.com/v1/messages`。
  /// 兼容旧数据：如果用户填的是不含 /v1/messages 的 base URL，自动补全。
  static String _normalizeEndpoint(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    // 兼容旧数据：用户可能存的是 base URL (如 https://api.anthropic.com)
    // 如果 URL 不以 /messages 结尾，认为是 base URL，自动追加 /v1/messages
    if (!u.endsWith('/messages')) {
      // 如果已有 /v1 后缀，只追加 /messages
      if (u.endsWith('/v1')) {
        u = '$u/messages';
      } else {
        u = '$u/v1/messages';
      }
    }
    return u;
  }

  // ─── OpenAI → Anthropic 请求翻译 ──────────────────────────────

  /// 把 OpenAI 风格 messages 拆成 (system 提示, anthropic messages)。
  ({String? system, List<Map<String, dynamic>> messages}) _convertMessages(
    List<Map<String, dynamic>> openaiMessages,
  ) {
    final systemParts = <String>[];
    final out = <Map<String, dynamic>>[];

    // tool_call_id → 工具名，Anthropic tool_result 需要回指 tool_use id
    for (final msg in openaiMessages) {
      final role = msg['role'] as String;
      switch (role) {
        case 'system':
          final c = msg['content'];
          if (c is String) systemParts.add(c);
          break;
        case 'user':
          out.add({
            'role': 'user',
            'content': _convertUserContent(msg['content']),
          });
          break;
        case 'assistant':
          out.add({
            'role': 'assistant',
            'content': _convertAssistantContent(msg),
          });
          break;
        case 'tool':
          // OpenAI 的 tool 消息 → Anthropic 的 user 角色 tool_result block
          final block = {
            'type': 'tool_result',
            'tool_use_id': msg['tool_call_id'],
            'content': (msg['content'] ?? '').toString(),
          };
          // 合并到上一条 user(若也是 tool_result) 否则新开
          if (out.isNotEmpty &&
              out.last['role'] == 'user' &&
              out.last['content'] is List &&
              (out.last['content'] as List).isNotEmpty &&
              (out.last['content'] as List).first is Map &&
              ((out.last['content'] as List).first as Map)['type'] ==
                  'tool_result') {
            (out.last['content'] as List).add(block);
          } else {
            out.add({
              'role': 'user',
              'content': [block],
            });
          }
          break;
      }
    }

    return (
      system: systemParts.isEmpty ? null : systemParts.join('\n\n'),
      messages: out,
    );
  }

  /// 用户 content：字符串直接用；OpenAI 多模态 parts → Anthropic blocks。
  dynamic _convertUserContent(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final blocks = <Map<String, dynamic>>[];
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type'];
        if (type == 'text') {
          blocks.add({'type': 'text', 'text': part['text'] ?? ''});
        } else if (type == 'image_url') {
          final url = (part['image_url']?['url'] ?? '').toString();
          final block = _imageBlockFromUrl(url);
          if (block != null) blocks.add(block);
        }
      }
      return blocks;
    }
    return content?.toString() ?? '';
  }

  /// data URL → Anthropic base64 image block；http(s) URL → url image block。
  Map<String, dynamic>? _imageBlockFromUrl(String url) {
    if (url.startsWith('data:')) {
      // data:<mime>;base64,<data>
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      final header = url.substring(5, comma); // mime;base64
      final data = url.substring(comma + 1);
      final mime = header.split(';').first;
      return {
        'type': 'image',
        'source': {'type': 'base64', 'media_type': mime, 'data': data},
      };
    }
    if (url.startsWith('http')) {
      return {
        'type': 'image',
        'source': {'type': 'url', 'url': url},
      };
    }
    return null;
  }

  /// assistant content：可能含 text + tool_calls。
  dynamic _convertAssistantContent(Map<String, dynamic> msg) {
    final blocks = <Map<String, dynamic>>[];
    final content = msg['content'];
    if (content is String && content.isNotEmpty) {
      blocks.add({'type': 'text', 'text': content});
    }
    final toolCalls = msg['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'] as Map<String, dynamic>?;
        final argsRaw = fn?['arguments'];
        Map<String, dynamic> input;
        if (argsRaw is String) {
          try {
            input = jsonDecode(argsRaw) as Map<String, dynamic>;
          } catch (_) {
            input = {};
          }
        } else if (argsRaw is Map<String, dynamic>) {
          input = argsRaw;
        } else {
          input = {};
        }
        blocks.add({
          'type': 'tool_use',
          'id': tc['id'],
          'name': fn?['name'],
          'input': input,
        });
      }
    }
    // 全空时给个空文本，避免 Anthropic 报错
    if (blocks.isEmpty) return '';
    return blocks;
  }

  /// OpenAI tools → Anthropic tools (扁平化 input_schema)。
  List<Map<String, dynamic>>? _convertTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return null;
    return tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>? ?? t;
      return {
        'name': fn['name'],
        'description': fn['description'] ?? '',
        'input_schema':
            fn['parameters'] ?? {'type': 'object', 'properties': {}},
      };
    }).toList();
  }

  Map<String, dynamic> _buildBody(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools, {
    required bool stream,
  }) {
    final converted = _convertMessages(messages);
    final anthropicTools = _convertTools(tools);
    return {
      'model': model,
      'max_tokens': maxTokens,
      'messages': converted.messages,
      // ignore: use_null_aware_elements
      if (converted.system != null) 'system': converted.system,
      // ignore: use_null_aware_elements
      if (anthropicTools != null) 'tools': anthropicTools,
      if (stream) 'stream': true,
    };
  }

  // ─── 调用 ─────────────────────────────────────────────────────

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final body = _buildBody(messages, tools, stream: false);
    try {
      final response = await _dio.post(_endpointUrl, data: body);
      return _parseNonStream(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      String detail = e.response?.data?.toString() ?? e.message ?? e.type.name;
      final status = e.response?.statusCode;

      // 500/502/503: 中转站或上游服务问题
      if (status == 500 || status == 502 || status == 503) {
        String hint = '';
        if (status == 503) {
          hint =
              '\n\n可能原因:\n'
              '1. 中转站过载或限流\n'
              '2. 上游 Anthropic API 暂时不可用\n'
              '3. 中转站不支持 Anthropic 原生协议\n\n'
              '建议: 切换到「OpenAI」协议类型，或更换中转站';
        } else {
          hint =
              '\n\n提示: 如果你使用的是 API 中转站/代理，请将模型卡的「协议类型」改为 OpenAI，'
              '中转站通常只兼容 OpenAI 格式。';
        }
        throw Exception('HTTP $status: $detail$hint');
      }

      // 429: 速率限制
      if (status == 429) {
        throw Exception('HTTP 429: 请求过于频繁，请稍后重试\n\n$detail');
      }

      // 401/403: 认证问题
      if (status == 401 || status == 403) {
        throw Exception('HTTP $status: API Key 无效或权限不足\n\n$detail');
      }

      throw Exception('HTTP ${status ?? '?'}: $detail');
    }
  }

  ChatResponse _parseNonStream(Map<String, dynamic> json) {
    final contentBlocks = json['content'] as List? ?? [];
    final textBuf = StringBuffer();
    final calls = <ToolCall>[];
    for (final block in contentBlocks) {
      if (block is! Map) continue;
      if (block['type'] == 'text') {
        textBuf.write(block['text'] ?? '');
      } else if (block['type'] == 'tool_use') {
        calls.add(
          ToolCall(
            id: (block['id'] ?? '').toString(),
            name: (block['name'] ?? '').toString(),
            arguments: (block['input'] as Map<String, dynamic>?) ?? {},
          ),
        );
      }
    }
    return ChatResponse(
      content: textBuf.isEmpty ? null : textBuf.toString(),
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: (json['stop_reason'] ?? 'stop').toString(),
    );
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final body = _buildBody(messages, tools, stream: true);

    final Response response;
    try {
      response = await _dio.post(
        _endpointUrl,
        data: body,
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      String detail = e.message ?? e.type.name;
      if (e.response?.data != null) {
        try {
          final errorStream = e.response!.data.stream as Stream<List<int>>;
          final bytes = await errorStream.fold<List<int>>(
            [],
            (prev, chunk) => prev..addAll(chunk),
          );
          detail = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {}
      }
      final status = e.response?.statusCode;

      // 500/502/503: 中转站或上游服务问题
      if (status == 500 || status == 502 || status == 503) {
        String hint = '';
        if (status == 503) {
          hint =
              '\n\n可能原因:\n'
              '1. 中转站过载或限流\n'
              '2. 上游 Anthropic API 暂时不可用\n'
              '3. 中转站不支持流式请求或 Anthropic 协议\n\n'
              '建议:\n'
              '- 切换到「OpenAI」协议类型\n'
              '- 更换中转站\n'
              '- 稍后重试';
        } else {
          hint =
              '\n\n提示: 如果你使用的是 API 中转站/代理，请将模型卡的「协议类型」改为 OpenAI，'
              '中转站通常只兼容 OpenAI 格式。';
        }
        throw Exception('HTTP $status: $detail$hint');
      }

      // 429: 速率限制
      if (status == 429) {
        throw Exception('HTTP 429: 请求过于频繁，请稍后重试\n\n$detail');
      }

      // 401/403: 认证问题
      if (status == 401 || status == 403) {
        throw Exception('HTTP $status: API Key 无效或权限不足\n\n$detail');
      }

      throw Exception('HTTP ${status ?? '?'}: $detail');
    }

    yield* _parseSse(response.data.stream as Stream<List<int>>);
  }

  /// 解析 Anthropic SSE：content_block_delta(text) → ContentToken；
  /// thinking block → ReasoningToken；tool_use block 累积 input_json_delta；
  /// message_stop → StreamComplete。
  Stream<StreamEvent> _parseSse(Stream<List<int>> rawStream) async* {
    String buffer = '';
    final contentBuf = StringBuffer();
    final thinkingBuf = StringBuffer(); // 扩展思考内容
    String finishReason = 'stop';

    // index → 正在累积的 tool_use block
    final toolBlocks = <int, _AnthropicToolBlock>{};

    await for (final chunk in rawStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      final lines = buffer.split(RegExp(r'\r?\n'));
      buffer = lines.removeLast();

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || !line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;

        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final type = json['type'] as String?;
        switch (type) {
          case 'content_block_start':
            final block = json['content_block'] as Map<String, dynamic>?;
            final idx = json['index'] as int? ?? 0;
            if (block != null && block['type'] == 'tool_use') {
              toolBlocks[idx] = _AnthropicToolBlock(
                id: (block['id'] ?? '').toString(),
                name: (block['name'] ?? '').toString(),
              );
            }
            // 注意：thinking block 在 start 时没有内容，在 delta 中传输
            break;
          case 'content_block_delta':
            final idx = json['index'] as int? ?? 0;
            final delta = json['delta'] as Map<String, dynamic>?;
            if (delta == null) break;

            final deltaType = delta['type'] as String?;
            if (deltaType == 'text_delta') {
              final text = (delta['text'] ?? '').toString();
              if (text.isNotEmpty) {
                contentBuf.write(text);
                yield ContentToken(text);
              }
            } else if (deltaType == 'thinking_delta') {
              // 扩展思考内容
              final text = (delta['thinking'] ?? '').toString();
              if (text.isNotEmpty) {
                thinkingBuf.write(text);
                yield ReasoningToken(text);
              }
            } else if (deltaType == 'input_json_delta') {
              toolBlocks[idx]?.argsBuf.write(delta['partial_json'] ?? '');
            }
            break;
          case 'message_delta':
            final delta = json['delta'] as Map<String, dynamic>?;
            if (delta?['stop_reason'] != null) {
              finishReason = delta!['stop_reason'].toString();
            }
            break;
          case 'message_stop':
            yield _complete(contentBuf, thinkingBuf, toolBlocks, finishReason);
            return;
          case 'error':
            final msg = json['error']?['message'] ?? 'Anthropic stream error';
            throw Exception(msg.toString());
        }
      }
    }

    // 流未显式 message_stop：返回截断标记，上层不得当作正常完成。
    final fallback = _complete(
      contentBuf,
      thinkingBuf,
      toolBlocks,
      finishReason,
    );
    yield StreamComplete(
      content: fallback.content,
      reasoningContent: fallback.reasoningContent,
      toolCalls: fallback.toolCalls,
      finishReason: 'stream_incomplete',
      isTruncated: true,
    );
  }

  StreamComplete _complete(
    StringBuffer contentBuf,
    StringBuffer thinkingBuf,
    Map<int, _AnthropicToolBlock> toolBlocks,
    String finishReason,
  ) {
    List<ToolCall>? calls;
    if (toolBlocks.isNotEmpty) {
      calls = toolBlocks.values.map((b) => b.build()).toList();
    }
    return StreamComplete(
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      reasoningContent: thinkingBuf.isEmpty ? null : thinkingBuf.toString(),
      toolCalls: calls,
      finishReason: finishReason,
    );
  }
}

class _AnthropicToolBlock {
  final String id;
  final String name;
  final StringBuffer argsBuf = StringBuffer();

  _AnthropicToolBlock({required this.id, required this.name});

  ToolCall build() {
    Map<String, dynamic> args;
    final raw = argsBuf.toString();
    try {
      args = raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      args = {};
    }
    return ToolCall(id: id, name: name, arguments: args);
  }
}

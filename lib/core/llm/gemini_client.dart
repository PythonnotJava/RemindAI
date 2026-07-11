import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

import 'llm_client.dart';

/// Google Gemini 原生客户端 — generateContent / streamGenerateContent。
///
/// 对上层暴露与 [OpenAiClient] 相同的接口，内部做 OpenAI ↔ Gemini 双向翻译。
class GeminiClient implements LlmClient {
  final Dio _dio;
  final String baseUrl;
  final String apiKey;
  final String model;

  GeminiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: _normalizeBase(baseUrl),
           headers: {'content-type': 'application/json'},
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(minutes: 5),
         ),
       );

  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    // 缺省补一个标准 base
    if (u.isEmpty) {
      u = 'https://generativelanguage.googleapis.com/v1beta';
    }
    return u;
  }

  // ─── OpenAI → Gemini 请求翻译 ────────────────────────────────

  ({
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> contents,
  })
  _convertMessages(List<Map<String, dynamic>> openaiMessages) {
    final systemParts = <String>[];
    final contents = <Map<String, dynamic>>[];

    // tool_call_id → function name (用于 Gemini functionResponse 回指)
    final idToName = <String, String>{};
    for (final msg in openaiMessages) {
      if (msg['role'] == 'assistant' && msg['tool_calls'] is List) {
        for (final tc in msg['tool_calls'] as List) {
          if (tc is Map) {
            final id = tc['id']?.toString();
            final name = (tc['function'] as Map?)?['name']?.toString();
            if (id != null && name != null) idToName[id] = name;
          }
        }
      }
    }

    for (final msg in openaiMessages) {
      final role = msg['role'] as String;
      switch (role) {
        case 'system':
          final c = msg['content'];
          if (c is String) systemParts.add(c);
          break;
        case 'user':
          contents.add({
            'role': 'user',
            'parts': _convertUserParts(msg['content']),
          });
          break;
        case 'assistant':
          contents.add({'role': 'model', 'parts': _convertAssistantParts(msg)});
          break;
        case 'tool':
          // OpenAI tool 消息 → Gemini functionResponse part (role: user)
          final callId = msg['tool_call_id']?.toString();
          final fnName = idToName[callId] ?? callId ?? 'tool';
          final part = {
            'functionResponse': {
              'name': fnName,
              'response': {'result': (msg['content'] ?? '').toString()},
            },
          };
          if (contents.isNotEmpty &&
              contents.last['role'] == 'user' &&
              contents.last['parts'] is List &&
              (contents.last['parts'] as List).isNotEmpty &&
              ((contents.last['parts'] as List).first as Map).containsKey(
                'functionResponse',
              )) {
            (contents.last['parts'] as List).add(part);
          } else {
            contents.add({
              'role': 'user',
              'parts': [part],
            });
          }
          break;
      }
    }

    return (
      systemInstruction: systemParts.isEmpty
          ? null
          : {
              'parts': [
                {'text': systemParts.join('\n\n')},
              ],
            },
      contents: contents,
    );
  }

  List<Map<String, dynamic>> _convertUserParts(dynamic content) {
    if (content is String) {
      return [
        {'text': content},
      ];
    }
    if (content is List) {
      final parts = <Map<String, dynamic>>[];
      for (final p in content) {
        if (p is! Map) continue;
        if (p['type'] == 'text') {
          parts.add({'text': p['text'] ?? ''});
        } else if (p['type'] == 'image_url') {
          final url = (p['image_url']?['url'] ?? '').toString();
          final inline = _inlineDataFromUrl(url);
          if (inline != null) parts.add(inline);
        }
      }
      return parts.isEmpty
          ? [
              {'text': ''},
            ]
          : parts;
    }
    return [
      {'text': content?.toString() ?? ''},
    ];
  }

  Map<String, dynamic>? _inlineDataFromUrl(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    final header = url.substring(5, comma); // mime;base64
    final data = url.substring(comma + 1);
    final mime = header.split(';').first;
    return {
      'inlineData': {'mimeType': mime, 'data': data},
    };
  }

  List<Map<String, dynamic>> _convertAssistantParts(Map<String, dynamic> msg) {
    final parts = <Map<String, dynamic>>[];
    final content = msg['content'];
    if (content is String && content.isNotEmpty) {
      parts.add({'text': content});
    }
    final toolCalls = msg['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'] as Map<String, dynamic>?;
        final argsRaw = fn?['arguments'];
        Map<String, dynamic> args;
        if (argsRaw is String) {
          try {
            args = jsonDecode(argsRaw) as Map<String, dynamic>;
          } catch (_) {
            args = {};
          }
        } else if (argsRaw is Map<String, dynamic>) {
          args = argsRaw;
        } else {
          args = {};
        }
        parts.add({
          'functionCall': {'name': fn?['name'], 'args': args},
        });
      }
    }
    return parts.isEmpty
        ? [
            {'text': ''},
          ]
        : parts;
  }

  /// OpenAI tools → Gemini functionDeclarations。
  List<Map<String, dynamic>>? _convertTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return null;
    final decls = tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>? ?? t;
      return {
        'name': fn['name'],
        'description': fn['description'] ?? '',
        'parameters':
            _sanitizeSchema(fn['parameters']) ??
            {'type': 'object', 'properties': {}},
      };
    }).toList();
    return [
      {'functionDeclarations': decls},
    ];
  }

  /// Gemini 的 schema 不接受部分 JSON-Schema 关键字 (如 additionalProperties)，
  /// 这里做一个浅清洗，去掉已知不支持的字段。
  dynamic _sanitizeSchema(dynamic schema) {
    if (schema is Map) {
      final out = <String, dynamic>{};
      for (final entry in schema.entries) {
        final k = entry.key.toString();
        if (k == 'additionalProperties' || k == r'$schema') continue;
        out[k] = _sanitizeSchema(entry.value);
      }
      return out;
    }
    if (schema is List) {
      return schema.map(_sanitizeSchema).toList();
    }
    return schema;
  }

  Map<String, dynamic> _buildBody(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  ) {
    final converted = _convertMessages(messages);
    final geminiTools = _convertTools(tools);
    return {
      'contents': converted.contents,
      // ignore: use_null_aware_elements
      if (converted.systemInstruction != null)
        'systemInstruction': converted.systemInstruction,
      // ignore: use_null_aware_elements
      if (geminiTools != null) 'tools': geminiTools,
    };
  }

  // ─── 调用 ─────────────────────────────────────────────────────

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final body = _buildBody(messages, tools);
    final response = await _dio.post(
      '/models/$model:generateContent',
      queryParameters: {'key': apiKey},
      data: body,
    );
    return _parseNonStream(response.data as Map<String, dynamic>);
  }

  ChatResponse _parseNonStream(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List? ?? [];
    final textBuf = StringBuffer();
    final calls = <ToolCall>[];
    String finishReason = 'stop';

    if (candidates.isNotEmpty) {
      final cand = candidates.first as Map<String, dynamic>;
      finishReason = (cand['finishReason'] ?? 'stop').toString();
      final parts = (cand['content']?['parts'] as List?) ?? [];
      for (final part in parts) {
        if (part is! Map) continue;
        if (part['text'] != null) {
          textBuf.write(part['text']);
        } else if (part['functionCall'] != null) {
          final fc = part['functionCall'] as Map<String, dynamic>;
          calls.add(
            ToolCall(
              id: 'call_${DateTime.now().microsecondsSinceEpoch}_${calls.length}',
              name: (fc['name'] ?? '').toString(),
              arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
            ),
          );
        }
      }
    }
    return ChatResponse(
      content: textBuf.isEmpty ? null : textBuf.toString(),
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: finishReason,
    );
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final body = _buildBody(messages, tools);

    final Response response;
    try {
      response = await _dio.post(
        '/models/$model:streamGenerateContent',
        queryParameters: {'key': apiKey, 'alt': 'sse'},
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
      throw Exception('HTTP ${e.response?.statusCode ?? '?'}: $detail');
    }

    yield* _parseSse(response.data.stream as Stream<List<int>>);
  }

  /// 解析 Gemini SSE (alt=sse)：每个 data 行是一个 GenerateContentResponse 分片。
  Stream<StreamEvent> _parseSse(Stream<List<int>> rawStream) async* {
    String buffer = '';
    final contentBuf = StringBuffer();
    final calls = <ToolCall>[];
    String? finishReason;

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

        final candidates = json['candidates'] as List? ?? [];
        if (candidates.isEmpty) continue;
        final cand = candidates.first as Map<String, dynamic>;
        if (cand['finishReason'] != null) {
          finishReason = cand['finishReason'].toString();
        }
        final parts = (cand['content']?['parts'] as List?) ?? [];
        for (final part in parts) {
          if (part is! Map) continue;
          if (part['text'] != null) {
            final text = part['text'].toString();
            if (text.isNotEmpty) {
              contentBuf.write(text);
              yield ContentToken(text);
            }
          } else if (part['functionCall'] != null) {
            final fc = part['functionCall'] as Map<String, dynamic>;
            calls.add(
              ToolCall(
                id: 'call_${DateTime.now().microsecondsSinceEpoch}_${calls.length}',
                name: (fc['name'] ?? '').toString(),
                arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
              ),
            );
          }
        }
      }
    }

    yield StreamComplete(
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: finishReason ?? 'stream_incomplete',
      isTruncated: finishReason == null,
    );
  }
}

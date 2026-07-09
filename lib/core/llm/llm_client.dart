import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

import '../logger/app_logger.dart';
import 'anthropic_client.dart';
import 'gemini_client.dart';
import 'llm_provider.dart';

/// 流式响应事件
sealed class StreamEvent {}

/// 内容 token
class ContentToken extends StreamEvent {
  final String text;
  ContentToken(this.text);
}

/// 思考/推理 token (DeepSeek reasoning_content 等)
class ReasoningToken extends StreamEvent {
  final String text;
  ReasoningToken(this.text);
}

/// 流结束 — 携带完整的响应信息 (content + tool_calls)
class StreamComplete extends StreamEvent {
  final String? content;
  final String? reasoningContent;
  final List<ToolCall>? toolCalls;
  final String finishReason;
  StreamComplete({
    this.content,
    this.reasoningContent,
    this.toolCalls,
    required this.finishReason,
  });

  /// 转换为 assistant 消息 JSON (用于追加到 messages 历史)
  Map<String, dynamic> toMessageJson() {
    final msg = <String, dynamic>{'role': 'assistant'};
    final hasToolCalls = toolCalls != null && toolCalls!.isNotEmpty;
    if (content != null) msg['content'] = content;
    if (hasToolCalls) {
      msg['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }
    // 防御：assistant 消息必须至少有 content 或 tool_calls 之一，否则
    // OpenAI 兼容 API 会报 400 "content or tool_calls must be set"。
    // 思维链模型(DeepSeek 等)可能只产出 reasoning_content、content 为空且无工具调用，
    // 此时补一个空字符串 content，保证消息合法（不改变有内容/有工具调用时的行为）。
    if (!hasToolCalls && msg['content'] == null) {
      msg['content'] = '';
    }
    return msg;
  }
}

/// LLM 客户端抽象接口。
///
/// 上层 (AgentLoop / chat_provider) 统一使用 OpenAI 风格的消息与工具格式，
/// 各协议实现负责在内部翻译成自己的原生请求，再把响应翻译回统一的
/// [StreamEvent] / [ChatResponse]。
abstract class LlmClient {
  /// 按协议类型创建对应的客户端实现。
  factory LlmClient({
    required String baseUrl,
    required String apiKey,
    required String model,
    LlmProvider provider = LlmProvider.openai,
  }) {
    switch (provider) {
      case LlmProvider.anthropic:
        return AnthropicClient(baseUrl: baseUrl, apiKey: apiKey, model: model);
      case LlmProvider.gemini:
        return GeminiClient(baseUrl: baseUrl, apiKey: apiKey, model: model);
      case LlmProvider.openai:
        return OpenAiClient(baseUrl: baseUrl, apiKey: apiKey, model: model);
    }
  }

  /// 非流式调用 (备用，简单场景如记忆抽取)
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  });

  /// 完整流式调用 — 同时处理 content tokens 和 tool_calls
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  });
}

/// 判断错误体是否为「模型不支持多模态输入」的典型 400 报错。
/// 例如 OpenAI 兼容端返回 unknown variant `image_url` / expected `text`。
bool _looksLikeMultimodalUnsupported(String detail) {
  final d = detail.toLowerCase();
  return (d.contains('image_url') &&
          (d.contains('unknown variant') ||
              d.contains("expected `text`") ||
              d.contains('expected text'))) ||
      (d.contains('image') && d.contains('not support'));
}

/// 将消息列表中的多模态 content (image_url) 降级为纯文本。
///
/// 用于模型不支持视觉输入时，保留历史对话的文本部分而非报错。
/// 只修改含有 image_url 的 content 列表，不影响纯文本消息。
List<Map<String, dynamic>> _stripImageParts(
  List<Map<String, dynamic>> messages,
) {
  return messages.map((msg) {
    final content = msg['content'];
    if (content is! List) return msg;

    // content 是 multimodal parts 列表
    final textParts = <String>[];
    bool hasImage = false;
    for (final part in content) {
      if (part is Map) {
        if (part['type'] == 'text') {
          textParts.add(part['text'] as String? ?? '');
        } else if (part['type'] == 'image_url') {
          hasImage = true;
          textParts.add('[图片]');
        }
      }
    }
    if (!hasImage) return msg;

    // 降级为纯文本
    return {...msg, 'content': textParts.join('\n')};
  }).toList();
}

/// 对历史消息中的图片做降级，只保留最后一条用户消息的图片不动。
///
/// 这样当前用户刚发的图片能被模型看到（如果模型支持的话），
/// 但历史中残留的图片不会干扰不支持视觉的模型。
List<Map<String, dynamic>> _stripHistoryImages(
  List<Map<String, dynamic>> messages,
) {
  if (messages.isEmpty) return messages;

  // 找到最后一条用户消息的索引
  int lastUserIdx = -1;
  for (int i = messages.length - 1; i >= 0; i--) {
    if (messages[i]['role'] == 'user') {
      lastUserIdx = i;
      break;
    }
  }

  return messages.asMap().entries.map((entry) {
    final i = entry.key;
    final msg = entry.value;
    // 最后一条用户消息保持原样（用户刚发的可能就想让模型看图）
    if (i == lastUserIdx) return msg;

    final content = msg['content'];
    if (content is! List) return msg;

    // 降级历史中的图片
    final textParts = <String>[];
    bool hasImage = false;
    for (final part in content) {
      if (part is Map) {
        if (part['type'] == 'text') {
          textParts.add(part['text'] as String? ?? '');
        } else if (part['type'] == 'image_url') {
          hasImage = true;
          textParts.add('[图片]');
        }
      }
    }
    if (!hasImage) return msg;
    return {...msg, 'content': textParts.join('\n')};
  }).toList();
}

/// OpenAI 兼容的 LLM 客户端，支持 SSE 流式输出
class OpenAiClient implements LlmClient {
  final Dio _dio;
  final String baseUrl;
  final String apiKey;
  final String model;

  OpenAiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  }) : _base = _normalizeBase(baseUrl),
       _dio = Dio(
         BaseOptions(
           // 注意：不在此设置 baseUrl。Dio 在解析以 "/" 开头的 path 时会把它当作
           // host 根绝对路径，从而丢弃 baseUrl 里的 "/v1" 等子路径
           // (例如 "https://x/v1" + "/chat/completions" → "https://x/chat/completions")。
           // 因此统一改用绝对 URL 拼接，避免该坑。
           headers: {
             'Authorization': 'Bearer $apiKey',
             'Content-Type': 'application/json',
           },
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(minutes: 5),
         ),
       );

  /// 规范化后的 base（去掉末尾斜杠）。
  final String _base;

  /// 去掉末尾斜杠，避免拼出双斜杠。
  /// 同时处理用户误填完整 endpoint 路径的情况(如填了 /v1/chat/completions)，
  /// 自动剥离——代码内部会拼 `/chat/completions`，重复拼接导致 404。
  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    // 常见误填: 用户从文档或 curl 里复制了完整 endpoint URL
    if (u.endsWith('/chat/completions')) {
      u = u.substring(0, u.length - '/chat/completions'.length);
    }
    // 用户可能误把 Anthropic endpoint 填到 OpenAI 协议里
    if (u.endsWith('/v1/messages')) {
      u = u.substring(0, u.length - '/messages'.length);
    }
    return u;
  }

  /// chat/completions 完整绝对地址。
  String get _chatUrl => '$_base/chat/completions';

  /// 非流式调用 (备用，简单场景)
  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    };

    try {
      final response = await _dio.post(_chatUrl, data: body);
      return ChatResponse.fromJson(response.data);
    } on DioException catch (e) {
      String detail = e.message ?? e.type.name;
      if (e.response?.data != null) {
        try {
          if (e.response!.data is Map || e.response!.data is String) {
            detail = e.response!.data.toString();
          }
        } catch (_) {}
      }
      final status = e.response?.statusCode;
      if (status == null) {
        final innerError = e.error?.toString() ?? '';
        final typeLabel = switch (e.type) {
          DioExceptionType.connectionTimeout => '连接超时',
          DioExceptionType.sendTimeout => '发送超时',
          DioExceptionType.receiveTimeout => '接收超时',
          DioExceptionType.connectionError => '连接失败',
          _ => '网络异常',
        };
        throw Exception(
          '$typeLabel: ${innerError.isNotEmpty ? innerError : detail}',
        );
      }
      throw Exception('HTTP $status: $detail');
    } on HttpException catch (e) {
      throw Exception(
        '连接被关闭: $e\n'
        '可能原因: 请求内容超出模型上下文窗口限制或网络不稳定',
      );
    }
  }

  /// 流式调用 (纯 content tokens，不处理 tool_calls)
  Stream<String> chatStream(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    };

    final response = await _dio.post(
      _chatUrl,
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    final rawStream = response.data.stream as Stream<List<int>>;
    String buffer = '';

    await for (final chunk in rawStream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final delta = json['choices']?[0]?['delta'];
            if (delta != null && delta['content'] != null) {
              yield delta['content'] as String;
            }
          } catch (_) {}
        }
      }
    }
  }

  /// 完整流式调用 — 同时处理 content tokens 和 tool_calls
  ///
  /// yield ContentToken: 文本 token (实时展示)
  /// yield StreamComplete: 流结束 (携带完整 content + tool_calls)
  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    // 预处理：对历史消息中的图片做降级（只保留最后一条用户消息的图片）。
    // 避免不支持视觉的模型看到历史图片后产生困惑回复。
    final processedMessages = _stripHistoryImages(messages);

    final body = <String, dynamic>{
      'model': model,
      'messages': processedMessages,
      'stream': true,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
    };

    // 诊断：记录请求体大小，帮助排查因 payload 超限导致的连接关闭问题
    final bodyJson = jsonEncode(body);
    final bodySize = bodyJson.length;
    final toolCount = tools?.length ?? 0;
    final msgCount = processedMessages.length;
    AppLogger.instance.log(
      '[LLM Request] POST $_chatUrl | body=${(bodySize / 1024).toStringAsFixed(1)}KB '
      '(messages=$msgCount, tools=$toolCount, model=$model)',
    );

    final Response response;
    try {
      response = await _dio.post(
        _chatUrl,
        data: body,
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      // 网络/HTTP 错误 — 尝试读取 response body
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
      // 友好提示：纯文本模型收到图片等多模态内容时的常见 400
      // 自动降级历史中的图片并重试
      if (_looksLikeMultimodalUnsupported(detail)) {
        final stripped = _stripImageParts(messages);
        // 检查降级后是否还有图片（不应该，但以防万一）
        final stillHasImage = stripped.any((m) => m['content'] is List);
        if (!stillHasImage) {
          // 用降级后的消息重试
          yield* chatStreamFull(stripped, tools: tools);
          return;
        }
        throw Exception(
          '当前模型不支持图片/多模态输入，请改用支持视觉(vision)的模型，'
          '或移除消息中的图片后重试。',
        );
      }
      // 连接级别错误 (无 HTTP 状态码)
      if (status == null) {
        final innerError = e.error?.toString() ?? '';
        final typeLabel = switch (e.type) {
          DioExceptionType.connectionTimeout => '连接超时',
          DioExceptionType.sendTimeout => '发送超时',
          DioExceptionType.receiveTimeout => '接收超时 (模型响应过慢，可能需要增加超时时间)',
          DioExceptionType.connectionError => '连接失败 (无法访问中转站)',
          _ => '网络异常',
        };
        throw Exception(
          '$typeLabel: ${innerError.isNotEmpty ? innerError : detail}',
        );
      }
      throw Exception('HTTP $status: $detail');
    }

    final rawStream = response.data.stream as Stream<List<int>>;
    String buffer = '';

    // 累积器
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolCallsMap = <int, _ToolCallAccumulator>{}; // index → accumulator
    String finishReason = 'stop';
    int chunkCount = 0;
    int tokenCount = 0;
    bool firstChunk = true;

    try {
    await for (final chunk in rawStream) {
      final decoded = utf8.decode(chunk, allowMalformed: true);
      chunkCount++;
      if (firstChunk) {
        AppLogger.instance.log(
          '[LLM Stream] 首个chunk (${decoded.length}字符): ${decoded.substring(0, decoded.length.clamp(0, 200))}',
        );
        firstChunk = false;
      }
      buffer += decoded;
      // 兼容 \r\n 和 \n 换行
      final lines = buffer.split(RegExp(r'\r?\n'));
      buffer = lines.removeLast();

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // 兼容 "data: {...}" 和 "data:{...}"
        String data;
        if (line.startsWith('data: ')) {
          data = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data = line.substring(5).trim();
        } else {
          continue;
        }

        if (data == '[DONE]') {
          AppLogger.instance.log(
            '[LLM Stream] 完成: chunks=$chunkCount, tokens=$tokenCount, content=${contentBuf.length}字符, reasoning=${reasoningBuf.length}字符',
          );
          // 构建最终结果
          List<ToolCall>? calls;
          if (toolCallsMap.isNotEmpty) {
            calls = toolCallsMap.entries.map((e) => e.value.build()).toList();
          }
          yield StreamComplete(
            content: contentBuf.isEmpty ? null : contentBuf.toString(),
            reasoningContent: reasoningBuf.isEmpty
                ? null
                : reasoningBuf.toString(),
            toolCalls: calls,
            finishReason: finishReason,
          );
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choice = json['choices']?[0] as Map<String, dynamic>?;
          if (choice == null) continue;

          // 更新 finishReason
          if (choice['finish_reason'] != null) {
            finishReason = choice['finish_reason'] as String;
          }

          final delta = choice['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // Reasoning token (DeepSeek 等思维链模型)
          if (delta['reasoning_content'] != null) {
            final text = delta['reasoning_content'] as String;
            if (text.isNotEmpty) {
              reasoningBuf.write(text);
              yield ReasoningToken(text);
            }
          }

          // Content token
          if (delta['content'] != null) {
            final text = delta['content'] as String;
            if (text.isNotEmpty) {
              tokenCount++;
              contentBuf.write(text);
              yield ContentToken(text);
            }
          }

          // Tool calls delta
          if (delta['tool_calls'] != null) {
            final tcList = delta['tool_calls'] as List;
            for (final tcDelta in tcList) {
              final tc = tcDelta as Map<String, dynamic>;
              final idx = tc['index'] as int;
              toolCallsMap.putIfAbsent(idx, () => _ToolCallAccumulator());
              toolCallsMap[idx]!.addDelta(tc);
            }
          }
        } catch (e) {
          AppLogger.instance.log(
            '[LLM Stream] JSON解析异常: $e | data: ${data.substring(0, data.length.clamp(0, 100))}',
          );
        }
      }
    }
    } on HttpException catch (e) {
      // "Connection closed while receiving data" — 连接在流传输中途被对端关闭。
      // 常见原因:
      // 1. 请求 body 超过模型的 context window 限制(服务端直接断开)
      // 2. 代理/CDN 层的 idle timeout 被触发(模型思考时间过长,中间无数据传输)
      // 3. 不稳定的网络环境导致 TCP 连接中断
      //
      // 如果已经收到了部分内容(chunkCount > 0)，视为"部分成功"——
      // 把已累积的内容作为截断响应发出(比直接报错体验好，用户至少看到了部分回答)。
      // 如果一个 chunk 都没收到(chunkCount == 0)，那就是一开始就断了，才抛异常。
      AppLogger.instance.log(
        '[LLM Stream] 连接中断: $e (已收到 $chunkCount 个chunk, $tokenCount 个token)',
      );
      if (chunkCount == 0) {
        throw Exception(
          '连接被关闭(未收到任何数据)。可能原因：\n'
          '1. 请求内容超出模型上下文窗口限制(当前 body ${(bodySize / 1024).toStringAsFixed(1)}KB, '
          '含 $toolCount 个工具、$msgCount 条消息)\n'
          '2. 网络不稳定或代理超时\n'
          '请尝试: 减少工具/技能数量、清理过长的对话历史、或检查网络连接',
        );
      }
      // 有部分内容——作为截断响应发出
    }

    // 流异常结束(包括正常跑完无[DONE]、以及 HttpException 被 catch 后落到这里)
    // 仍然发出已累积的内容
    AppLogger.instance.log(
      '[LLM Stream] 流结束(无[DONE]): chunks=$chunkCount, tokens=$tokenCount, buffer剩余=${buffer.length}字符',
    );
    List<ToolCall>? calls;
    if (toolCallsMap.isNotEmpty) {
      calls = toolCallsMap.entries.map((e) => e.value.build()).toList();
    }
    yield StreamComplete(
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      reasoningContent: reasoningBuf.isEmpty ? null : reasoningBuf.toString(),
      toolCalls: calls,
      finishReason: finishReason,
    );
  }
}

/// Tool call 分片累积器
class _ToolCallAccumulator {
  String? id;
  String name = '';
  final _argsBuf = StringBuffer();

  void addDelta(Map<String, dynamic> delta) {
    if (delta['id'] != null) id = delta['id'] as String;
    final fn = delta['function'] as Map<String, dynamic>?;
    if (fn != null) {
      if (fn['name'] != null) name = fn['name'] as String;
      if (fn['arguments'] != null) _argsBuf.write(fn['arguments'] as String);
    }
  }

  ToolCall build() {
    Map<String, dynamic> args;
    try {
      args = jsonDecode(_argsBuf.toString()) as Map<String, dynamic>;
    } catch (_) {
      args = {};
    }
    return ToolCall(
      id: id ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      arguments: args,
    );
  }
}

/// LLM 响应模型
class ChatResponse {
  final String? content;
  final List<ToolCall>? toolCalls;
  final String finishReason;

  ChatResponse({this.content, this.toolCalls, required this.finishReason});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final choice = json['choices'][0];
    final message = choice['message'];

    List<ToolCall>? calls;
    if (message['tool_calls'] != null) {
      calls = (message['tool_calls'] as List)
          .map((tc) => ToolCall.fromJson(tc))
          .toList();
    }

    return ChatResponse(
      content: message['content'],
      toolCalls: calls,
      finishReason: choice['finish_reason'] ?? '',
    );
  }

  Map<String, dynamic> toMessageJson() {
    final msg = <String, dynamic>{'role': 'assistant'};
    final hasToolCalls = toolCalls != null && toolCalls!.isNotEmpty;
    if (content != null) msg['content'] = content;
    if (hasToolCalls) {
      msg['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }
    // 防御：assistant 消息至少需 content 或 tool_calls 之一，避免 400。
    if (!hasToolCalls && msg['content'] == null) {
      msg['content'] = '';
    }
    return msg;
  }
}

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ToolCall({required this.id, required this.name, required this.arguments});

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'],
      name: json['function']['name'],
      arguments: jsonDecode(json['function']['arguments']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}

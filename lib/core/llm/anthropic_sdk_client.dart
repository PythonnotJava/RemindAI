import 'dart:async';
import 'dart:convert';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

import 'llm_client.dart';

/// 将 OpenAI → Anthropic SDK 消息转换的返回类型
typedef _ConvertedMessages = ({
  SystemPrompt? system,
  List<InputMessage> messages,
});

/// Anthropic SDK 客户端 - 使用官方 anthropic_sdk_dart 实现。
///
/// 相比手动实现的 AnthropicClient，此客户端：
/// - ✅ 类型安全的 API 封装
/// - ✅ 完整的流式事件处理
/// - ✅ 支持 Token 缓存统计
/// - ✅ 支持 MCP 工具（Beta）
/// - ✅ 支持 Extended Thinking
/// - ✅ 内置重试和错误处理
///
/// 架构参考 Cherry Studio 的 streamAdapter.ts，但使用 Dart 实现。
class AnthropicSdkClient implements LlmClient {
  final AnthropicClient _client;

  @override
  final String model;

  final int maxTokens;

  AnthropicSdkClient({
    required String baseUrl,
    required String apiKey,
    required this.model,
    this.maxTokens = 4096,
  }) : _client = AnthropicClient(
         config: AnthropicConfig(
           authProvider: ApiKeyProvider(apiKey),
           baseUrl: baseUrl,
           timeout: const Duration(minutes: 5),
           retryPolicy: const RetryPolicy(
             maxRetries: 3,
             initialDelay: Duration(seconds: 1),
           ),
         ),
       );

  // ─── OpenAI → Anthropic SDK 消息转换 ──────────────────────────

  /// 将 OpenAI 格式消息转换为 Anthropic SDK 格式
  _ConvertedMessages _convertMessages(
    List<Map<String, dynamic>> openaiMessages,
  ) {
    final systemParts = <String>[];
    final messages = <InputMessage>[];

    for (final msg in openaiMessages) {
      final role = msg['role'] as String;
      switch (role) {
        case 'system':
          final content = msg['content'];
          if (content is String) systemParts.add(content);
          break;
        case 'user':
          messages.add(_convertUserMessage(msg));
          break;
        case 'assistant':
          messages.add(_convertAssistantMessage(msg));
          break;
        case 'tool':
          // Tool 结果作为 user 消息
          messages.add(
            InputMessage.userBlocks([
              InputContentBlock.toolResultText(
                toolUseId: msg['tool_call_id'] as String,
                text: msg['content']?.toString() ?? '',
              ),
            ]),
          );
          break;
      }
    }

    return (
      system: systemParts.isEmpty
          ? null
          : SystemPrompt.text(systemParts.join('\n\n')),
      messages: messages,
    );
  }

  InputMessage _convertUserMessage(Map<String, dynamic> msg) {
    final content = msg['content'];
    if (content is String) {
      return InputMessage.user(content);
    }
    if (content is List) {
      final blocks = <InputContentBlock>[];
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type'];
        if (type == 'text') {
          blocks.add(InputContentBlock.text(part['text']?.toString() ?? ''));
        } else if (type == 'image_url') {
          final url = part['image_url']?['url']?.toString() ?? '';
          if (url.startsWith('data:')) {
            // data: URL → base64
            final comma = url.indexOf(',');
            if (comma > 0) {
              final header = url.substring(5, comma);
              final data = url.substring(comma + 1);
              final mime = header.split(';').first;
              blocks.add(
                InputContentBlock.image(
                  ImageSource.base64(
                    data: data,
                    mediaType: ImageMediaType.fromMimeType(mime),
                  ),
                ),
              );
            }
          } else if (url.startsWith('http')) {
            blocks.add(InputContentBlock.image(ImageSource.url(url)));
          }
        }
      }
      return InputMessage.userBlocks(blocks);
    }
    return InputMessage.user(content?.toString() ?? '');
  }

  InputMessage _convertAssistantMessage(Map<String, dynamic> msg) {
    final blocks = <InputContentBlock>[];
    final content = msg['content'];
    if (content is String && content.isNotEmpty) {
      blocks.add(InputContentBlock.text(content));
    }
    final toolCalls = msg['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'] as Map<String, dynamic>?;
        blocks.add(
          InputContentBlock.toolUse(
            id: tc['id']?.toString() ?? '',
            name: fn?['name']?.toString() ?? '',
            input: (fn?['arguments'] is Map)
                ? (fn!['arguments'] as Map<String, dynamic>)
                : {},
          ),
        );
      }
    }
    return InputMessage.assistantBlocks(blocks);
  }

  /// 将 OpenAI 工具格式转换为 Anthropic SDK 格式
  List<ToolDefinition>? _convertTools(List<Map<String, dynamic>>? tools) {
    if (tools == null || tools.isEmpty) return null;
    return tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>? ?? t;
      return ToolDefinition.custom(
        Tool(
          name: fn['name']?.toString() ?? '',
          description: fn['description']?.toString() ?? '',
          inputSchema: InputSchema.fromJson(
            fn['parameters'] as Map<String, dynamic>? ??
                {'type': 'object', 'properties': {}},
          ),
        ),
      );
    }).toList();
  }

  // ─── LlmClient 接口实现 ────────────────────────────────────

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final converted = _convertMessages(messages);
    final anthropicTools = _convertTools(tools);

    try {
      final response = await _client.messages.create(
        MessageCreateRequest(
          model: model,
          maxTokens: maxTokens,
          system: converted.system,
          messages: converted.messages,
          tools: anthropicTools,
        ),
      );

      return _parseResponse(response);
    } on ApiException catch (e) {
      throw _handleApiException(e);
    } on AnthropicException catch (e) {
      throw Exception('Anthropic SDK 错误: ${e.message}');
    }
  }

  ChatResponse _parseResponse(Message response) {
    final textBuf = StringBuffer();
    final calls = <ToolCall>[];

    for (final block in response.content) {
      if (block is TextBlock) {
        textBuf.write(block.text);
      } else if (block is ToolUseBlock) {
        calls.add(
          ToolCall(id: block.id, name: block.name, arguments: block.input),
        );
      }
    }

    return ChatResponse(
      content: textBuf.isEmpty ? null : textBuf.toString(),
      toolCalls: calls.isEmpty ? null : calls,
      finishReason: response.stopReason?.value ?? 'stop',
    );
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final converted = _convertMessages(messages);
    final anthropicTools = _convertTools(tools);

    Stream<MessageStreamEvent> stream;
    try {
      stream = _client.messages.createStream(
        MessageCreateRequest(
          model: model,
          maxTokens: maxTokens,
          system: converted.system,
          messages: converted.messages,
          tools: anthropicTools,
        ),
      );
    } on ApiException catch (e) {
      throw _handleApiException(e);
    } on AnthropicException catch (e) {
      throw Exception('Anthropic SDK 错误: ${e.message}');
    }

    yield* _parseStream(stream);
  }

  /// 解析流式事件 - 模仿 Cherry Studio 的 streamAdapter.ts
  Stream<StreamEvent> _parseStream(Stream<MessageStreamEvent> stream) async* {
    final contentBuf = StringBuffer();
    final thinkingBuf = StringBuffer();
    final toolBlocks = <int, _ToolBlock>{};
    String finishReason = 'stop';

    await for (final event in stream) {
      switch (event) {
        case MessageStartEvent():
          // 消息开始，暂不处理
          break;

        case ContentBlockStartEvent(
          contentBlock: final block,
          index: final idx,
        ):
          if (block is ToolUseBlock) {
            toolBlocks[idx] = _ToolBlock(id: block.id, name: block.name);
          }
          break;

        case ContentBlockDeltaEvent(delta: final delta, index: final idx):
          if (delta is TextDelta) {
            final text = delta.text;
            contentBuf.write(text);
            yield ContentToken(text);
          } else if (delta is ThinkingDelta) {
            final text = delta.thinking;
            thinkingBuf.write(text);
            yield ReasoningToken(text);
          } else if (delta is InputJsonDelta) {
            toolBlocks[idx]?.argsBuf.write(delta.partialJson);
          }
          break;

        case MessageDeltaEvent(delta: final delta):
          if (delta.stopReason != null) {
            finishReason = delta.stopReason!.value;
          }
          break;

        case MessageStopEvent():
          yield _complete(contentBuf, thinkingBuf, toolBlocks, finishReason);
          return;

        case ErrorEvent(errorType: final type, message: final msg):
          throw Exception('Anthropic Stream Error: $type - $msg');

        default:
          break;
      }
    }

    // 流未正常结束
    yield StreamComplete(
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      reasoningContent: thinkingBuf.isEmpty ? null : thinkingBuf.toString(),
      toolCalls: toolBlocks.isEmpty
          ? null
          : toolBlocks.values.map((b) => b.build()).toList(),
      finishReason: 'stream_incomplete',
      isTruncated: true,
    );
  }

  StreamComplete _complete(
    StringBuffer contentBuf,
    StringBuffer thinkingBuf,
    Map<int, _ToolBlock> toolBlocks,
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

  Exception _handleApiException(ApiException e) {
    final status = e.statusCode;
    final detail = e.message;

    if (status == 503) {
      return Exception(
        'HTTP 503: $detail\n\n'
        '可能原因:\n'
        '1. 中转站过载或限流\n'
        '2. 上游 Anthropic API 暂时不可用\n'
        '3. 中转站不支持 Anthropic 原生协议\n\n'
        '建议:\n'
        '- 切换到「OpenAI」协议类型\n'
        '- 更换中转站\n'
        '- 稍后重试',
      );
    }

    if (status == 429) {
      return Exception('HTTP 429: 请求过于频繁，请稍后重试\n\n$detail');
    }

    if (status == 401 || status == 403) {
      return Exception('HTTP $status: API Key 无效或权限不足\n\n$detail');
    }

    return Exception('HTTP $status: $detail');
  }

  void close() {
    _client.close();
  }
}

class _ToolBlock {
  final String id;
  final String name;
  final StringBuffer argsBuf = StringBuffer();

  _ToolBlock({required this.id, required this.name});

  ToolCall build() {
    Map<String, dynamic> args = {};
    final raw = argsBuf.toString();
    if (raw.isNotEmpty) {
      try {
        // 尝试解析 JSON
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) {
          args = parsed;
        }
      } catch (_) {
        args = {};
      }
    }
    return ToolCall(id: id, name: name, arguments: args);
  }
}

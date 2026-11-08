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

  /// 流是否在协议结束标记前异常中断。
  ///
  /// true 表示仅收到了部分数据，不能把本次响应当作正常完成。
  final bool isTruncated;

  /// 提供方返回的真实用量（可能为 null：部分中转不回传 usage）。
  ///
  /// 用于把"估算 token"校正成实测值——上下文上限的自学习依赖它。
  final UsageInfo? usage;

  StreamComplete({
    this.content,
    this.reasoningContent,
    this.toolCalls,
    required this.finishReason,
    this.isTruncated = false,
    this.usage,
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

/// 模型卡未配置「最大输出 Token」时使用的兜底值。
///
/// 三种协议共用同一个兜底（历史实现各写一份：OpenAI/Gemini 12800、
/// Anthropic 只有 4096，导致同一个模型换协议就换一个输出预算）。
///
/// 这里只是"请求里声明的输出上限"，并非所有模型都接受这么大的
/// `max_tokens`（多数模型的单次输出上限在 8K~64K，且要求
/// `输入 + max_tokens` 不超过上下文窗口）。上游因此返回 4xx 时，
/// 各客户端会按 [kMaxTokensDegradeLadder] 自动降档并重试，
/// 不需要用户手动修改模型卡。
const int kDefaultMaxOutputTokens = 128000;

/// `max_tokens` 被上游拒绝时的自动降档梯度（从高到低）。
///
/// 只用于"被拒绝后往回收"，不会主动用来抬高用户配置的值。
const List<int> kMaxTokensDegradeLadder = <int>[
  128000,
  64000,
  32000,
  16384,
  8192,
];

/// 取 [current] 的下一档（比它小的第一档）；已经是最小档时返回 null。
int? nextLowerMaxTokens(int current) {
  for (final v in kMaxTokensDegradeLadder) {
    if (v < current) return v;
  }
  return null;
}

/// 判断上游错误体是否为「max_tokens / max_output_tokens 不合法或超出上限」。
///
/// 覆盖三类常见报错：
/// 1. 超过模型单次输出上限：`max_tokens: 128000 > 64000`、`too large`；
/// 2. 输入+输出超过上下文窗口：`max_tokens too large given prompt`、
///    `input length and max_tokens exceed context limit`；
/// 3. 部分中转站直接回 `invalid max_tokens` / `不支持的 max_tokens`。
///
/// 必须同时命中"提到 max_tokens 类字段"与"超限/非法语义"，避免把无关的
/// 400 误判成降档场景（降档本身是安全的，但会让错误信息变得难懂）。
bool looksLikeMaxTokensRejected(String detail) {
  final d = detail.toLowerCase();
  final mentionsField =
      d.contains('max_tokens') ||
      d.contains('maxtokens') ||
      d.contains('max_output_tokens') ||
      d.contains('maxoutputtokens') ||
      d.contains('max output tokens') ||
      d.contains('maxoutputtoken');
  if (!mentionsField) return false;
  return d.contains('too large') ||
      d.contains('too long') ||
      d.contains('too big') ||
      d.contains('exceed') ||
      d.contains('greater than') ||
      d.contains('maximum') ||
      d.contains('out of range') ||
      d.contains('must be') ||
      d.contains('invalid') ||
      d.contains('not support') ||
      d.contains('unsupported') ||
      d.contains('超出') ||
      d.contains('上限') ||
      d.contains('过大') ||
      d.contains('不支持');
}

/// LLM 客户端抽象接口。
///
/// 上层 (AgentLoop / chat_provider) 统一使用 OpenAI 风格的消息与工具格式，
/// 各协议实现负责在内部翻译成自己的原生请求，再把响应翻译回统一的
/// [StreamEvent] / [ChatResponse]。
abstract class LlmClient {
  /// 获取当前使用的模型名称
  String get model;

  /// 按协议类型创建对应的客户端实现。
  factory LlmClient({
    required String baseUrl,
    required String apiKey,
    required String model,
    LlmProvider provider = LlmProvider.openai,
    int maxOutputTokens = 0,
  }) {
    switch (provider) {
      case LlmProvider.anthropic:
        return AnthropicClient(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          maxOutputTokens: maxOutputTokens,
        );
      case LlmProvider.gemini:
        return GeminiClient(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          maxOutputTokens: maxOutputTokens,
        );
      case LlmProvider.openai:
        return OpenAiClient(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          maxOutputTokens: maxOutputTokens,
        );
    }
  }

  /// 非流式调用 (备用，简单场景如记忆抽取)
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  });

  /// 本次请求实际使用的输出 token 预算。
  ///
  /// 来自模型卡的「最大输出 Token」；未配置时回落到 [kDefaultMaxOutputTokens]（128K）。
  /// 若上游拒绝了该值，会先按 [kMaxTokensDegradeLadder] 自动降档（降档结果对
  /// 本客户端实例常驻），所以这里返回的是"当前可用"的预算。
  /// AgentLoop 在输出被长度上限截断时会按倍数抬高它做自愈。
  int get outputTokenBudget;

  /// 完整流式调用 — 同时处理 content tokens 和 tool_calls
  ///
  /// [maxTokensOverride] 仅用于截断自愈时的临时抬高，不改变模型卡配置。
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    int? maxTokensOverride,
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

/// 判断错误体是否为「网关不认识 stream_options 字段」的典型 4xx。
///
/// 少数严格网关（或老版本 vLLM/Ollama 代理）会把未知字段当 400；
/// 命中后我们会关掉该字段重试，保证"拿 usage"不会把对话打死。
bool _looksLikeRejectedStreamOptions(String detail) {
  final d = detail.toLowerCase();
  return d.contains('stream_options') ||
      d.contains('stream options') ||
      d.contains('include_usage') ||
      d.contains('unknown field') ||
      d.contains('unrecognized field') ||
      d.contains('unsupported parameter') ||
      d.contains('extra fields not permitted');
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

  @override
  final String model;

  final int maxOutputTokens;

  OpenAiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.maxOutputTokens = 0,
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

  /// 网关是否接受 `stream_options.include_usage`
  ///
  /// 少数严格网关会把未知字段当 400，一旦被拒就永久关掉该字段并重试一次，
  /// 避免"为了拿 usage 反而把整条链路打死"。
  bool _streamUsageSupported = true;

  /// 获取最大输出 token 数
  ///
  /// 算法思想：
  /// 1. 优先使用用户配置的值（精确控制）
  /// 2. 未配置时使用 [kDefaultMaxOutputTokens]（128K）作为兜底
  /// 3. 若上游拒绝过该值，则记住降档后的上限（[_maxTokensCeiling]）并用它
  ///
  /// 关于兜底值：输出预算越大，单轮能写的东西越多，但 `max_tokens` 只是
  /// "声明"，并不保证上游接受——超出模型输出上限、或 `输入 + max_tokens`
  /// 超过上下文窗口时上游会直接 400。这类 400 由 [looksLikeMaxTokensRejected]
  /// 识别后自动降档重试，因此兜底值可以取得很大而不会把对话打死。
  int _getMaxTokens() {
    // 如果用户配置了值，使用用户值
    final configured = maxOutputTokens > 0
        ? maxOutputTokens
        : kDefaultMaxOutputTokens;
    // 降档学到的上限更小时，用更小的那个（避免每次请求都先撞一次 400）
    final ceiling = _maxTokensCeiling;
    return (ceiling != null && ceiling < configured) ? ceiling : configured;
  }

  /// 上次被上游拒绝 `max_tokens` 后学到的上限（null = 还没被拒过）。
  int? _maxTokensCeiling;

  /// 把输出预算往下降一档；没有更小的档位时返回 false。
  bool _degradeMaxTokens() {
    final next = nextLowerMaxTokens(_getMaxTokens());
    if (next == null) return false;
    _maxTokensCeiling = next;
    return true;
  }

  /// 把调用方传入的临时预算（截断自愈时抬高）夹到"上游接受过的上限"以内。
  ///
  /// 自愈抬高可能超过上游真实上限，夹一下可以省掉一次必然失败的 400：
  /// 学到的上限是多少，最多就只能申请多少。
  int _clampToCeiling(int value) {
    final ceiling = _maxTokensCeiling;
    return (ceiling != null && ceiling < value) ? ceiling : value;
  }

  /// 本模型当前请求使用的输出预算（供 AgentLoop 做截断自愈时按倍数抬高）。
  @override
  int get outputTokenBudget => _getMaxTokens();

  /// 非流式调用 (备用，简单场景)
  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': _getMaxTokens(),
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
      // 上游不接受声明的 max_tokens（超出模型输出上限 / 输入+输出超窗口）
      // → 自动降档重试，对用户透明。每次降一档，最小档仍被拒才把错误抛出去。
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          looksLikeMaxTokensRejected(detail) &&
          _degradeMaxTokens()) {
        AppLogger.instance.log(
          '[LLM] max_tokens 被上游拒绝，已降档到 ${_getMaxTokens()} 并重试: '
          '${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail}',
        );
        return chat(messages, tools: tools);
      }
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
      'max_tokens': _getMaxTokens(),
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
    int? maxTokensOverride,
  }) async* {
    // 预处理：对历史消息中的图片做降级（只保留最后一条用户消息的图片）。
    // 避免不支持视觉的模型看到历史图片后产生困惑回复。
    final processedMessages = _stripHistoryImages(messages);

    // maxTokensOverride：截断自愈时临时抬高输出预算（不影响模型卡配置）。
    final effectiveMaxTokens = _clampToCeiling(
      maxTokensOverride ?? _getMaxTokens(),
    );

    final body = <String, dynamic>{
      'model': model,
      'messages': processedMessages,
      'stream': true,
      // 让 OpenAI 兼容网关在流末尾回传 usage（多数实现支持；
      // 不支持的会忽略该字段，不影响正文）。自学习上下文上限依赖它。
      if (_streamUsageSupported) 'stream_options': {'include_usage': true},
      'max_tokens': effectiveMaxTokens,
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
      '(messages=$msgCount, tools=$toolCount, model=$model, '
      'max_tokens=$effectiveMaxTokens)',
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

      // 上游不接受声明的 max_tokens → 自动降档重试（每次降一档）。
      // 放在 stream_options 分支之前：这类 400 与 usage 无关，先解决输出预算。
      // 注意降档后不再复用调用方传入的 maxTokensOverride（那个值只会更大）。
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          looksLikeMaxTokensRejected(detail) &&
          _degradeMaxTokens()) {
        AppLogger.instance.log(
          '[LLM Stream] max_tokens 被上游拒绝，已降档到 ${_getMaxTokens()} 并重试: '
          '${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail}',
        );
        yield* chatStreamFull(messages, tools: tools);
        return;
      }

      // 网关不接受 stream_options → 关掉它并重试一次（拿不到 usage 不影响对话）
      if (_streamUsageSupported &&
          status != null &&
          status >= 400 &&
          status < 500 &&
          _looksLikeRejectedStreamOptions(detail)) {
        _streamUsageSupported = false;
        AppLogger.instance.log(
          '[LLM Stream] 网关不接受 stream_options，已关闭并重试: '
          '${detail.length > 120 ? '${detail.substring(0, 120)}…' : detail}',
        );
        yield* chatStreamFull(
          messages,
          tools: tools,
          maxTokensOverride: maxTokensOverride,
        );
        return;
      }

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
    String? finishReason;
    UsageInfo? usageInfo;
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
              finishReason: finishReason ?? 'stop',
              usage: usageInfo,
            );
            return;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            // usage 可能出现在普通 chunk 或末尾的 usage-only chunk 里
            if (json['usage'] != null && json['usage'] is Map) {
              usageInfo = UsageInfo.fromJson(
                (json['usage'] as Map).cast<String, dynamic>(),
              );
            }
            // 部分 OpenAI 兼容网关会在末尾发一个 usage-only chunk：
            // {"choices":[],"usage":{...}}。直接取 [0] 会抛 RangeError，
            // 虽然不影响正文，但会污染日志并可能漏掉 usage/finish 信息。
            final choices = json['choices'];
            if (choices is! List || choices.isEmpty) continue;
            final choice = choices[0] as Map<String, dynamic>?;
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
      finishReason: finishReason ?? 'stream_incomplete',
      isTruncated: true,
      usage: usageInfo,
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
      if (fn['arguments'] != null) {
        final argChunk = fn['arguments'];
        if (argChunk is String) {
          _argsBuf.write(argChunk);
        } else {
          // 非标准实现：arguments 不是 String（可能是 Map 或其他类型）
          print(
            '[LLM] ⚠️ tool_call arguments 类型异常: ${argChunk.runtimeType} (tool=$name)',
          );
          // 尝试转成 JSON 字符串
          try {
            _argsBuf.write(jsonEncode(argChunk));
          } catch (_) {
            _argsBuf.write(argChunk.toString());
          }
        }
      }
    }
  }

  ToolCall build() {
    Map<String, dynamic> args;
    final rawArgs = _argsBuf.toString();

    // ─── 诊断：arguments 累积情况 ───
    if (rawArgs.isEmpty) {
      // arguments 完全为空！说明流式传输中一个字符都没收到
      // 常见原因：
      // 1. 模型没有生成 arguments（只给了 function name）
      // 2. 代理/API 截断了 arguments 字段
      // 3. 模型把参数放到了 content 而不是 tool_calls
      print(
        '[LLM] ❌ tool_call arguments 为空 (tool=$name): '
        '模型未返回任何参数内容，可能是内容过长导致生成失败',
      );
    }

    try {
      args = rawArgs.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(rawArgs) as Map<String, dynamic>;
    } catch (e) {
      // ─── arguments JSON 解析失败：尝试修复 ───
      // 常见原因：
      // 1. 流式传输被截断（网络中断、代理超时）
      // 2. 模型输出不完整的 JSON（生成到一半就结束）
      // 3. 特殊字符未正确转义
      //
      // 修复策略：
      // 1. 尝试补全不完整的 JSON（添加缺少的 } 或 "）
      // 2. 如果仍然失败，尝试提取已有的键值对
      // 3. 最后兜底返回空 Map 并记录完整错误信息

      args = _tryFixIncompleteJson(rawArgs);

      if (args.isEmpty && rawArgs.isNotEmpty) {
        // 修复也失败了，记录详细日志供排查
        print(
          '[LLM] ⚠️ tool_call arguments 解析失败 (tool=$name): $e\n'
          '[LLM] 原始内容 (${rawArgs.length} chars): '
          '${rawArgs.length > 200 ? '${rawArgs.substring(0, 200)}...' : rawArgs}',
        );
      }
    }
    return ToolCall(
      id: id ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      arguments: args,
    );
  }

  /// 尝试修复不完整的 JSON 字符串
  ///
  /// 策略：
  /// 1. 如果缺少结尾的 } → 补全
  /// 2. 如果字符串值未闭合 → 补全引号
  /// 3. 如果末尾有多余的逗号 → 移除
  /// 4. 如果完全无效 → 返回空 Map
  static Map<String, dynamic> _tryFixIncompleteJson(String raw) {
    if (raw.isEmpty) return {};

    var fixed = raw.trim();

    // 移除末尾不完整的键值对（如 "key": 或 "key": "val）
    // 策略：从后向前找到最后一个完整的值
    if (!fixed.endsWith('}')) {
      // 尝试补全：移除末尾不完整的部分，加上 }
      // 找到最后一个完整的值结束位置（", 或 数字, 或 true/false/null, 或 }]）
      final lastComplete = RegExp(
        r'["\d\]}\w](,?)(?:\s*"[^"]*"\s*:\s*(?:"[^"]*$|[^,}\]]*$))?$',
      );
      final match = lastComplete.firstMatch(fixed);
      if (match != null) {
        // 截断到最后一个完整值
        fixed = fixed.substring(0, match.start + 1);
      }

      // 移除末尾的逗号
      fixed = fixed.trimRight();
      if (fixed.endsWith(',')) {
        fixed = fixed.substring(0, fixed.length - 1);
      }

      // 补全括号
      final openBraces = '{'.allMatches(fixed).length;
      final closeBraces = '}'.allMatches(fixed).length;
      for (var i = 0; i < openBraces - closeBraces; i++) {
        fixed += '}';
      }
    }

    // 尝试解析修复后的 JSON
    try {
      return jsonDecode(fixed) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

/// LLM 响应模型
class ChatResponse {
  final String? content;
  final List<ToolCall>? toolCalls;
  final String finishReason;
  final UsageInfo? usage;

  ChatResponse({
    this.content,
    this.toolCalls,
    required this.finishReason,
    this.usage,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final choice = json['choices'][0];
    final message = choice['message'];

    List<ToolCall>? calls;
    if (message['tool_calls'] != null) {
      calls = (message['tool_calls'] as List)
          .map((tc) => ToolCall.fromJson(tc))
          .toList();
    }

    UsageInfo? usage;
    if (json['usage'] != null) {
      usage = UsageInfo.fromJson(json['usage']);
    }

    return ChatResponse(
      content: message['content'],
      toolCalls: calls,
      finishReason: choice['finish_reason'] ?? '',
      usage: usage,
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

/// Token 使用统计信息
class UsageInfo {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  /// Prompt cache 读取的 tokens（DeepSeek: prompt_cache_hit_tokens, Claude: cache_read_input_tokens）
  final int? promptCacheReadInputTokens;

  /// Prompt cache 写入的 tokens（Claude: cache_creation_input_tokens）
  final int? promptCacheWriteInputTokens;

  UsageInfo({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.promptCacheReadInputTokens,
    this.promptCacheWriteInputTokens,
  });

  factory UsageInfo.fromJson(Map<String, dynamic> json) {
    return UsageInfo(
      promptTokens: json['prompt_tokens'],
      completionTokens: json['completion_tokens'],
      totalTokens: json['total_tokens'],
      // DeepSeek 使用 prompt_cache_hit_tokens
      // Claude 使用 cache_read_input_tokens
      promptCacheReadInputTokens:
          json['prompt_cache_hit_tokens'] ?? json['cache_read_input_tokens'],
      promptCacheWriteInputTokens: json['cache_creation_input_tokens'],
    );
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

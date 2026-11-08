import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../logger/app_logger.dart';
import '../settings/app_settings.dart';

/// 画图模型的最小描述。
///
/// 项目里存在两份 ModelCard（`core/db/tables` 与 `core/llm/models`），
/// 这里刻意不依赖其中任何一份，避免类型歧义；调用方按需转换。
class ImageModelSpec {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String provider;
  final String modelId;

  const ImageModelSpec({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.provider,
    required this.modelId,
  });
}

/// 画图子 Agent 调用失败时抛出的异常。
class ImageAgentException implements Exception {
  final String message;

  ImageAgentException(this.message);

  @override
  String toString() => message;
}

/// 一次画图调用的结果。
class ImageGenerationOutcome {
  /// 生成图片在磁盘上的绝对路径。
  final String path;

  /// 实际生成图片的模型 id。
  final String model;

  /// 实际使用的协议（openai / gemini）。
  final String provider;

  /// 是否使用了主模型兜底。
  final bool fallbackUsed;

  /// 兜底原因（子模型失败详情）。未兜底时为 null。
  final String? warning;

  const ImageGenerationOutcome({
    required this.path,
    required this.model,
    required this.provider,
    required this.fallbackUsed,
    this.warning,
  });
}

/// 画图子 Agent 服务。
///
/// 设计目标：
/// - 用「模型卡」作为子画图 Agent，不引入第二套密钥配置；
/// - 兼容两种主流图片协议：
///   1. OpenAI 兼容：`/images/generations`、`/images/edits`（gpt-image / dall-e 等），
///      若服务端不支持 Images API，再尝试 `/chat/completions` 的图片模态；
///   2. Gemini 原生：`/v1beta/models/{model}:generateContent` + `responseModalities: [IMAGE]`；
/// - 子模型失败（额度耗尽、模型下架、404/401、网络错误等）时，
///   自动用当前对话的主模型再试一次，并把失败原因带回给 UI。
class ImageAgentService {
  static const List<String> aspectRatios = [
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];

  static const List<String> qualities = ['1k', '2k', '4k'];

  /// 生成图片。
  ///
  /// [subCard] 为用户选择的子画图模型；为 null 表示已选模型卡被删除。
  /// [mainCard] 为当前对话的主模型，作为兜底。
  /// [workDir] 为空时图片写入 `.RemindAI/generated/images`。
  static Future<ImageGenerationOutcome> generate({
    required String prompt,
    required String workDir,
    ImageModelSpec? subCard,
    ImageModelSpec? mainCard,
    String aspectRatio = '1:1',
    String quality = '1k',
    List<String> inputImagePaths = const [],
    String? unavailableReason,
  }) async {
    final outputDir = await _resolveOutputDir(workDir);
    final ratio = _normalizeAspectRatio(aspectRatio);
    final q = _normalizeQuality(quality);
    final errors = <String>[];
    final inputPaths = inputImagePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();

    // ─── 1. 子画图模型 ───
    if (subCard != null) {
      try {
        final bytes = await _generateBytes(
          card: subCard,
          prompt: prompt,
          aspectRatio: ratio,
          quality: q,
          inputImagePaths: inputPaths,
        );
        final path = await _saveImage(bytes, outputDir);
        AppLogger.instance.log(
          '[ImageAgent] 调用子画图模型生成图: '
          'model=${subCard.modelId}, provider=${subCard.provider}, '
          'prompt="${_oneLine(prompt, 80)}", path=$path',
        );
        return ImageGenerationOutcome(
          path: path,
          model: subCard.modelId,
          provider: subCard.provider,
          fallbackUsed: false,
        );
      } catch (e) {
        final brief = _brief(e);
        errors.add('子画图模型 ${subCard.modelId}: $brief');
        AppLogger.instance.log(
          '[ImageAgent] 子画图模型调用失败: '
          'model=${subCard.modelId}, error=${_oneLine(brief)}',
        );
      }
    } else if (unavailableReason != null) {
      errors.add(unavailableReason);
      AppLogger.instance.log(
        '[ImageAgent] 子画图模型不可用: $unavailableReason，准备使用主模型兜底',
      );
    }

    if (mainCard == null) {
      // 默认不拿纯文本主模型兜底：它只能返回文本，不会生成图片。
      // 直接告诉用户/模型“不支持”，比再发一次注定失败的请求更清晰。
      errors.add('主模型不支持画图，已跳过兜底');
      AppLogger.instance.log('[ImageAgent] 主模型不支持画图，已跳过兜底');
    }

    // ─── 2. 主模型兜底 ───
    final canFallback =
        mainCard != null && (subCard == null || mainCard.id != subCard.id);
    if (canFallback) {
      try {
        final bytes = await _generateBytes(
          card: mainCard,
          prompt: prompt,
          aspectRatio: ratio,
          quality: q,
          inputImagePaths: inputPaths,
        );
        final path = await _saveImage(bytes, outputDir);
        AppLogger.instance.log(
          '[ImageAgent] 子画图模型失败，使用主模型兜底生成图: '
          'main=${mainCard.modelId}, '
          'sub=${subCard?.modelId ?? '(不可用)'}, '
          'reason=${_oneLine(errors.join('；'))}, path=$path',
        );
        return ImageGenerationOutcome(
          path: path,
          model: mainCard.modelId,
          provider: mainCard.provider,
          fallbackUsed: true,
          warning: '${errors.join('；')}；已用主模型 ${mainCard.modelId} 兜底生成',
        );
      } catch (e) {
        errors.add('主模型 ${mainCard.modelId}: ${_brief(e)}');
        AppLogger.instance.log(
          '[ImageAgent] 主模型兜底失败: '
          'model=${mainCard.modelId}, error=${_oneLine(e.toString())}',
        );
      }
    }

    AppLogger.instance.log(
      '[ImageAgent] 画图失败: ${_oneLine(errors.join(' | '), 300)}',
    );
    throw ImageAgentException(errors.isEmpty ? '没有可用的画图模型' : errors.join('\n'));
  }

  // ─── 协议分发 ─────────────────────────────────────────────

  static Future<Uint8List> _generateBytes({
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    required String quality,
    List<String> inputImagePaths = const [],
  }) {
    if (card.baseUrl.trim().isEmpty) {
      throw ImageAgentException('模型「${card.name}」未配置 Base URL');
    }
    if (card.apiKey.trim().isEmpty) {
      throw ImageAgentException('模型「${card.name}」未配置 API Key');
    }
    for (final path in inputImagePaths) {
      if (!File(path).existsSync()) {
        throw ImageAgentException('输入图片不存在：$path');
      }
    }

    switch (card.provider.toLowerCase()) {
      case 'gemini':
        return _geminiGenerate(
          card: card,
          prompt: prompt,
          aspectRatio: aspectRatio,
          quality: quality,
          inputImagePaths: inputImagePaths,
        );
      case 'anthropic':
        throw ImageAgentException(
          'Anthropic 协议不支持图片生成，请选择 OpenAI 兼容或 Gemini 图片模型',
        );
      default:
        return _openAiWithGeminiFallback(
          card: card,
          prompt: prompt,
          aspectRatio: aspectRatio,
          quality: quality,
          inputImagePaths: inputImagePaths,
        );
    }
  }

  /// 默认把卡当 OpenAI 兼容处理；若模型名明显是 Gemini/Imagen
  /// （用户常把 Gemini 图片模型中转填成 OpenAI 协议），再尝试 Gemini 原生接口。
  static Future<Uint8List> _openAiWithGeminiFallback({
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    required String quality,
    List<String> inputImagePaths = const [],
  }) async {
    Object? openAiError;
    try {
      return await _openAiGenerate(
        card: card,
        prompt: prompt,
        aspectRatio: aspectRatio,
        inputImagePaths: inputImagePaths,
      );
    } catch (e) {
      openAiError = e;
    }

    final modelId = card.modelId.toLowerCase();
    if (modelId.contains('gemini') || modelId.contains('imagen')) {
      try {
        return await _geminiGenerate(
          card: card,
          prompt: prompt,
          aspectRatio: aspectRatio,
          quality: quality,
          inputImagePaths: inputImagePaths,
        );
      } catch (_) {
        // 保留最初 OpenAI 路径的错误（通常更贴近用户配置）
      }
    }
    throw openAiError is ImageAgentException
        ? openAiError
        : ImageAgentException(openAiError.toString());
  }

  // ─── OpenAI 兼容 ──────────────────────────────────────────

  static Future<Uint8List> _openAiGenerate({
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    List<String> inputImagePaths = const [],
  }) async {
    final base = _normalizeOpenAiBase(card.baseUrl);
    final dio = _newDio();
    final jsonHeaders = _openAiHeaders(card.apiKey);
    final hasInput = inputImagePaths.isNotEmpty;
    const maxAttempts = 3;

    late Response<dynamic> response;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final stopwatch = Stopwatch()..start();
      try {
        response = hasInput
            ? await _sendOpenAiEdit(
                dio: dio,
                base: base,
                card: card,
                prompt: prompt,
                aspectRatio: aspectRatio,
                inputImagePaths: inputImagePaths,
              )
            : await _sendOpenAiGeneration(
                dio: dio,
                base: base,
                card: card,
                prompt: prompt,
                aspectRatio: aspectRatio,
                headers: jsonHeaders,
              );
      } on DioException catch (e) {
        stopwatch.stop();
        AppLogger.instance.log(
          '[ImageAgent] Images API 网络错误: model=${card.modelId}, '
          'attempt=$attempt/$maxAttempts, '
          'input_images=${inputImagePaths.length}, '
          'elapsed=${stopwatch.elapsedMilliseconds}ms, '
          'error=${_oneLine(e.message ?? e.type.name)}',
        );
        if (attempt >= maxAttempts) {
          throw ImageAgentException('网络请求失败: ${e.message ?? e.type.name}');
        }
        await Future<void>.delayed(_retryDelay(null, attempt));
        continue;
      }

      stopwatch.stop();
      final status = response.statusCode;
      final detail = _bodyText(response.data);
      AppLogger.instance.log(
        '[ImageAgent] Images API: model=${card.modelId}, '
        'attempt=$attempt/$maxAttempts, status=$status, '
        'elapsed=${stopwatch.elapsedMilliseconds}ms, '
        'input_images=${inputImagePaths.length}',
      );

      if (status == 200) {
        return _extractOpenAiImage(response.data, dio);
      }

      // 408/429/5xx（含中转的 524 网关超时）先短暂退避重试，
      // 很多中转是排队/瞬时超时，重试一次就能成功。
      if (_isRetryableImageStatus(status) && attempt < maxAttempts) {
        final delay = _retryDelay(response, attempt);
        AppLogger.instance.log(
          '[ImageAgent] Images API 失败(status=$status)，'
          '${delay.inSeconds}s 后重试 (第 ${attempt + 1}/$maxAttempts 次)',
        );
        await Future<void>.delayed(delay);
        continue;
      }

      // 5xx 或 Images 路由不可用：再给同一个模型一次
      // chat/completions 图片模态的机会（有些中转只开放这条路由）。
      if (_isServerError(status) ||
          _looksLikeImagesApiUnsupported(status, detail)) {
        AppLogger.instance.log(
          '[ImageAgent] Images API 不可用(status=$status)，'
          '尝试同一模型的 chat/completions 图片模态: model=${card.modelId}',
        );
        try {
          return await _openAiChatImage(
            card: card,
            prompt: prompt,
            dio: dio,
            base: base,
            headers: jsonHeaders,
            inputImagePaths: inputImagePaths,
          );
        } catch (chatError) {
          throw ImageAgentException(
            'Images API [$status] ${_truncate(detail, 160)}；'
            'chat/completions: ${_brief(chatError)}',
          );
        }
      }

      throw ImageAgentException('[$status] ${_truncate(detail, 320)}');
    }

    throw ImageAgentException('图片请求失败: 未获得响应');
  }

  static Future<Response<dynamic>> _sendOpenAiEdit({
    required Dio dio,
    required String base,
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    required List<String> inputImagePaths,
  }) async {
    // multipart 请求每次重试都要重新构建 FormData（文件流不能复用）。
    final form = FormData();
    form.fields.add(MapEntry('model', card.modelId));
    form.fields.add(MapEntry('prompt', prompt));
    form.fields.add(const MapEntry('n', '1'));
    form.fields.add(MapEntry('size', _openAiSize(aspectRatio)));
    for (final path in inputImagePaths) {
      form.files.add(
        MapEntry(
          'image',
          await MultipartFile.fromFile(path, filename: p.basename(path)),
        ),
      );
    }
    return dio.post(
      '$base/images/edits',
      data: form,
      options: Options(
        headers: _openAiAuthHeaders(card.apiKey),
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  static Future<Response<dynamic>> _sendOpenAiGeneration({
    required Dio dio,
    required String base,
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    required Map<String, String> headers,
  }) {
    // 不强制 response_format：gpt-image 默认返回 b64，dall-e 默认返回 URL，
    // 两种解析都支持；部分中转反而会因为不认识该字段而卡住/超时。
    final payload = <String, dynamic>{
      'model': card.modelId,
      'prompt': prompt,
      'n': 1,
      'size': _openAiSize(aspectRatio),
    };
    return dio.post(
      '$base/images/generations',
      data: jsonEncode(payload),
      options: Options(
        headers: headers,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  }

  static bool _isRetryableImageStatus(int? status) {
    if (status == null) return false;
    if (status == 408 || status == 429) return true;
    return status >= 500 && status <= 599;
  }

  static bool _isServerError(int? status) =>
      status != null && status >= 500 && status <= 599;

  static Duration _retryDelay(Response<dynamic>? response, int attempt) {
    final raw = response?.headers.value('retry-after');
    final seconds = raw != null ? int.tryParse(raw.trim()) : null;
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds.clamp(1, 30));
    }
    return Duration(seconds: attempt == 1 ? 2 : 5);
  }

  /// 通过 `/chat/completions` 的图片模态取图。
  /// 兼容 `message.images[*]`、`message.content` parts、以及 data URL。
  static Future<Uint8List> _openAiChatImage({
    required ImageModelSpec card,
    required String prompt,
    required Dio dio,
    required String base,
    required Map<String, String> headers,
    List<String> inputImagePaths = const [],
  }) async {
    final content = inputImagePaths.isEmpty
        ? prompt
        : <Map<String, dynamic>>[
            for (final path in inputImagePaths)
              {
                'type': 'image_url',
                'image_url': {'url': await _dataUrlForPath(path)},
              },
            {'type': 'text', 'text': prompt},
          ];

    late Response<dynamic> response;
    try {
      response = await dio.post(
        '$base/chat/completions',
        data: jsonEncode({
          'model': card.modelId,
          'messages': [
            {'role': 'user', 'content': content},
          ],
          'modalities': ['image', 'text'],
        }),
        options: Options(
          headers: headers,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    } on DioException catch (e) {
      throw ImageAgentException('网络请求失败: ${e.message ?? e.type.name}');
    }

    if (response.statusCode != 200) {
      throw ImageAgentException(
        '[${response.statusCode}] ${_truncate(_bodyText(response.data), 320)}',
      );
    }
    try {
      return await _extractOpenAiChatImage(response.data, dio);
    } on ImageAgentException catch (e) {
      throw ImageAgentException(
        '模型 ${card.modelId} 未返回图片（可能不支持画图）: ${_brief(e)}',
      );
    }
  }

  static Future<Uint8List> _extractOpenAiImage(dynamic raw, Dio dio) async {
    final map = _asMap(raw);
    final data = map?['data'];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final b64 =
              item['b64_json'] ??
              item['b64'] ??
              item['base64'] ??
              item['image'];
          if (b64 is String && b64.isNotEmpty) {
            return _decodeDataUrl(b64) ?? base64Decode(b64);
          }
          final url = item['url'];
          if (url is String && url.isNotEmpty) {
            return _bytesFromUrl(url, dio);
          }
        }
      }
    }
    // 部分中转把图片平铺在根节点
    final images = map?['images'];
    if (images is List) {
      for (final item in images) {
        final url = _extractUrlFromImageItem(item);
        if (url != null && url.isNotEmpty) return _bytesFromUrl(url, dio);
      }
    }
    throw ImageAgentException(
      '图片接口未返回图片数据: ${_truncate(raw?.toString() ?? 'null', 320)}',
    );
  }

  static Future<Uint8List> _extractOpenAiChatImage(dynamic raw, Dio dio) async {
    final map = _asMap(raw);
    final choices = map?['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      final message = choice is Map ? choice['message'] : null;
      if (message is Map) {
        // 1) message.images
        final images = message['images'];
        if (images is List) {
          for (final item in images) {
            if (item is Map) {
              final b64 = item['b64_json'] ?? item['b64'] ?? item['base64'];
              if (b64 is String && b64.isNotEmpty) return base64Decode(b64);
            }
            final url = _extractUrlFromImageItem(item);
            if (url != null && url.isNotEmpty) return _bytesFromUrl(url, dio);
          }
        }
        // 2) message.content 为 parts
        final content = message['content'];
        if (content is String && content.startsWith('data:image/')) {
          final bytes = _decodeDataUrl(content);
          if (bytes != null) return bytes;
        }
        if (content is List) {
          for (final part in content) {
            if (part is! Map) continue;
            final imageUrl = part['image_url'];
            if (imageUrl is Map && imageUrl['url'] is String) {
              return _bytesFromUrl(imageUrl['url'] as String, dio);
            }
            if (imageUrl is String) return _bytesFromUrl(imageUrl, dio);
            final inline =
                part['inline_data'] ?? part['inlineData'] ?? part['image'];
            if (inline is Map && inline['data'] is String) {
              return base64Decode(inline['data'] as String);
            }
          }
        }
      }
    }
    // 兜底：根节点 images
    final images = map?['images'];
    if (images is List) {
      for (final item in images) {
        final url = _extractUrlFromImageItem(item);
        if (url != null && url.isNotEmpty) return _bytesFromUrl(url, dio);
      }
    }
    throw ImageAgentException(
      'chat/completions 未返回图片: ${_truncate(raw?.toString() ?? 'null', 320)}',
    );
  }

  static String? _extractUrlFromImageItem(dynamic item) {
    if (item is String) return item;
    if (item is! Map) return null;
    final imageUrl = item['image_url'] ?? item['imageUrl'] ?? item['url'];
    if (imageUrl is String) return imageUrl;
    if (imageUrl is Map && imageUrl['url'] is String) {
      return imageUrl['url'] as String;
    }
    return null;
  }

  // ─── Gemini 原生 ──────────────────────────────────────────

  static Future<Uint8List> _geminiGenerate({
    required ImageModelSpec card,
    required String prompt,
    required String aspectRatio,
    required String quality,
    List<String> inputImagePaths = const [],
  }) async {
    final base = _normalizeGeminiBase(card.baseUrl);
    final url = '$base/v1beta/models/${card.modelId}:generateContent';
    final dio = _newDio();

    final parts = <Map<String, dynamic>>[];
    final inputPaths = inputImagePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();
    for (final path in inputPaths) {
      parts.add({
        'inlineData': {
          'mimeType': _mimeForPath(path),
          'data': base64Encode(await File(path).readAsBytes()),
        },
      });
    }
    if (inputPaths.isEmpty) {
      parts.add({'text': prompt});
    } else {
      parts.add({
        'text': '${inputPaths.length > 1 ? '基于这些图片' : '基于此图'}，$prompt',
      });
    }

    final contents = [
      {'role': 'user', 'parts': parts},
    ];

    Future<Response<dynamic>> post(Map<String, dynamic> generationConfig) {
      return dio.post(
        url,
        data: jsonEncode({
          'contents': contents,
          'generationConfig': generationConfig,
        }),
        options: Options(
          headers: _geminiHeaders(card.apiKey),
          validateStatus: (status) => status != null && status < 600,
        ),
      );
    }

    // 不同 Gemini 图片模型/中转对 generationConfig 的支持不一：
    // 先尝试完整的 IMAGE + imageConfig；如果 400 明确是配置字段不支持，
    // 再依次降级，尽量让请求成功，而不是直接放弃。
    final configs = <Map<String, dynamic>>[
      {
        'responseModalities': ['IMAGE'],
        'imageConfig': {
          'aspectRatio': aspectRatio,
          'imageSize': quality.toUpperCase(),
        },
      },
      {
        'responseModalities': ['IMAGE'],
      },
      {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
      const <String, dynamic>{},
    ];

    late Response<dynamic> response;
    try {
      response = await post(configs.first);
      for (var i = 1; i < configs.length; i++) {
        if (response.statusCode != 400) break;
        final detail = _bodyText(response.data).toLowerCase();
        if (!_looksLikeGeminiConfigError(detail)) break;
        response = await post(configs[i]);
      }
    } on DioException catch (e) {
      throw ImageAgentException('网络请求失败: ${e.message ?? e.type.name}');
    }

    if (response.statusCode != 200) {
      throw ImageAgentException(
        '[${response.statusCode}] ${_truncate(_bodyText(response.data), 320)}',
      );
    }

    final map = _asMap(response.data);
    final candidates = map?['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final candidate = candidates.first;
      final content = candidate is Map ? candidate['content'] : null;
      final respParts = content is Map ? content['parts'] : null;
      if (respParts is List) {
        final texts = <String>[];
        for (final part in respParts) {
          if (part is! Map) continue;
          final inline = part['inlineData'] ?? part['inline_data'];
          if (inline is Map) {
            final b64 = inline['data'];
            if (b64 is String && b64.isNotEmpty) {
              return base64Decode(b64);
            }
          }
          if (part['text'] is String) texts.add(part['text'] as String);
        }
        if (texts.isNotEmpty) {
          throw ImageAgentException(
            '模型未生成图片，回复: ${_truncate(texts.join('\n'), 300)}',
          );
        }
      }
      final finishReason = candidate is Map ? candidate['finishReason'] : null;
      if (finishReason != null && finishReason != 'STOP') {
        throw ImageAgentException('生成被终止: $finishReason');
      }
    }

    final feedback = map?['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw ImageAgentException('请求被安全过滤拒绝: ${feedback['blockReason']}');
    }
    throw ImageAgentException(
      '响应中未找到图片数据: ${_truncate(response.data?.toString() ?? 'null', 320)}',
    );
  }

  // ─── 通用工具 ─────────────────────────────────────────────

  static Dio _newDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      // 画图可能很慢（尤其是 4K / 排队），给足 10 分钟
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  static Map<String, String> _openAiHeaders(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  /// multipart 请求只带鉴权头，Content-Type 由 Dio 自动生成 boundary。
  static Map<String, String> _openAiAuthHeaders(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
  };

  /// 同时兼容 Google 官方（x-goog-api-key）与常见中转（Bearer）。
  static Map<String, String> _geminiHeaders(String apiKey) => {
    'x-goog-api-key': apiKey,
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  static String _normalizeOpenAiBase(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    for (final suffix in const [
      '/chat/completions',
      '/images/generations',
      '/images/edits',
      '/responses',
    ]) {
      if (u.endsWith(suffix)) {
        u = u.substring(0, u.length - suffix.length);
        break;
      }
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  static String _normalizeGeminiBase(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    for (final suffix in const ['/v1beta', '/v1', '/models']) {
      if (u.endsWith(suffix)) {
        u = u.substring(0, u.length - suffix.length);
        break;
      }
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  static String _normalizeAspectRatio(String value) {
    final v = value.trim();
    return aspectRatios.contains(v) ? v : '1:1';
  }

  static String _normalizeQuality(String value) {
    final v = value.trim().toLowerCase();
    return qualities.contains(v) ? v : '1k';
  }

  static String _openAiSize(String aspectRatio) {
    switch (aspectRatio) {
      case '16:9':
      case '4:3':
      case '3:2':
        return '1536x1024';
      case '9:16':
      case '3:4':
      case '2:3':
        return '1024x1536';
      default:
        return '1024x1024';
    }
  }

  static Future<String> _resolveOutputDir(String workDir) async {
    if (workDir.trim().isNotEmpty) {
      return p.join(workDir, '.toolshell', 'outputs', 'images');
    }
    final root = await AppSettings.getRootDir();
    return p.join(root, 'generated', 'images');
  }

  static Future<String> _saveImage(Uint8List bytes, String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final ext = _extensionFor(bytes);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(9999).toString().padLeft(4, '0');
    final file = File(p.join(dir, 'img_${stamp}_$rand.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _extensionFor(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    return 'png';
  }

  static Future<Uint8List> _bytesFromUrl(String url, Dio dio) async {
    final data = _decodeDataUrl(url);
    if (data != null) return data;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      throw ImageAgentException('不支持的图片地址: ${_truncate(url, 200)}');
    }
    try {
      final res = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw ImageAgentException('图片下载失败: 响应为空');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw ImageAgentException('图片下载失败: ${e.message ?? e.type.name}');
    }
  }

  static Uint8List? _decodeDataUrl(String value) {
    if (!value.startsWith('data:')) return null;
    final comma = value.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String _bodyText(dynamic data) {
    if (data is String) return data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      return jsonEncode(data);
    }
    return data?.toString() ?? '';
  }

  static bool _looksLikeImagesApiUnsupported(int? status, String detail) {
    final d = detail.toLowerCase();
    if (status == 404 || status == 405 || status == 501) return true;
    return d.contains('not supported') ||
        d.contains('unsupported') ||
        d.contains('unknown endpoint') ||
        d.contains('no such endpoint') ||
        d.contains('not implemented') ||
        d.contains('invalid url') ||
        d.contains('invalid model') ||
        d.contains('model not found') ||
        d.contains('does not exist');
  }

  /// Gemini 的 generationConfig 兼容性错误：只有这些才值得降级重试。
  static bool _looksLikeGeminiConfigError(String detail) {
    final d = detail.toLowerCase();
    return d.contains('imageconfig') ||
        d.contains('imagesize') ||
        d.contains('aspectratio') ||
        d.contains('responsemodalit') ||
        d.contains('generationconfig') ||
        d.contains('unknown name') ||
        d.contains('unknown field') ||
        d.contains('invalid json payload');
  }

  static String _mimeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.png':
      default:
        return 'image/png';
    }
  }

  /// 把本地图片编码成 data URL，供 chat/completions 图片输入使用。
  static Future<String> _dataUrlForPath(String path) async {
    final bytes = await File(path).readAsBytes();
    return 'data:${_mimeForPath(path)};base64,${base64Encode(bytes)}';
  }

  static String _brief(Object? error) {
    final text = error?.toString() ?? 'unknown error';
    return _truncate(text, 300);
  }

  /// 日志用：压成单行并截断，避免多行错误把日志文件撑乱。
  static String _oneLine(String text, [int max = 300]) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _truncate(single, max);
  }

  static String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}

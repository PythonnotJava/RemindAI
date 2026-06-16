import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_plugin.dart';
import '../../../core/tools/tool_config.dart';

/// Gemini 3.1 Flash Image 画图工具 — 文生图、图改图
class ImageGenTool extends ToolPlugin {
  @override
  String get id => 'image_gen';
  @override
  String get name => 'Gemini 3.1 Flash Image Preview';
  @override
  IconData get icon => Icons.palette;
  @override
  String get description => '文生图 / 图改图';
  @override
  String get category => '创作';

  @override
  String localizedName(BuildContext context) => context.s.imageGenName;
  @override
  String localizedDescription(BuildContext context) => context.s.imageGenDesc;
  @override
  String localizedCategory(BuildContext context) => context.s.imageGenCategory;

  @override
  List<ConfigField> get permanentFields => const [
    ConfigField(
      key: 'apiUrl',
      label: 'API 地址',
      type: ConfigFieldType.url,
      required: true,
      hint: '可以是中转站地址，如: https://yunwu.ai',
    ),
    ConfigField(
      key: 'apiKey',
      label: 'API Key',
      type: ConfigFieldType.secret,
      required: true,
    ),
  ];

  @override
  List<ConfigField> get temporaryFields => const [
    ConfigField(key: 'apiUrl', label: '临时 API 地址', type: ConfigFieldType.url),
    ConfigField(key: 'apiKey', label: '临时 Key', type: ConfigFieldType.secret),
  ];

  @override
  Widget buildUI(BuildContext context, ToolConfig config) =>
      _ImageGenUI(config: config);

  @override
  Widget? buildSettings(
    BuildContext context,
    ToolConfig config,
    void Function(ToolConfig) onSave,
  ) => _ImageGenSettings(config: config, onSave: onSave);
}

// ─── 分辨率预设 ─────────────────────────────────────────────────

enum ImageQuality { fast, recommended, ultra }

Map<ImageQuality, String> _qualityLabelsOf(BuildContext context) => {
  ImageQuality.fast: context.s.imageGenQuality1k,
  ImageQuality.recommended: context.s.imageGenQuality2k,
  ImageQuality.ultra: context.s.imageGenQuality4k,
};

/// API 支持的宽高比
const _aspectRatios = ['1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3'];

// ─── 画图主界面 ─────────────────────────────────────────────────

class _ImageGenUI extends StatefulWidget {
  const _ImageGenUI({required this.config});
  final ToolConfig config;

  @override
  State<_ImageGenUI> createState() => _ImageGenUIState();
}

class _ImageGenUIState extends State<_ImageGenUI> {
  final _promptController = TextEditingController();
  ImageQuality _quality = ImageQuality.fast;
  String _aspectRatio = '1:1';
  Uint8List? _resultImage;
  Uint8List? _inputImage; // 图改图的输入
  String? _inputImageName;
  String? _inputImageMime;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final apiUrl = widget.config.get<String>('apiUrl');
    final apiKey = widget.config.get<String>('apiKey');

    if (apiUrl == null || apiKey == null || apiUrl.isEmpty || apiKey.isEmpty) {
      setState(() => _error = context.s.imageGenNeedConfig);
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty && _inputImage == null) {
      setState(() => _error = context.s.imageGenNeedInput);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _resultImage = null;
    });

    try {
      final result = await _callGeminiImageGen(
        baseUrl: apiUrl,
        apiKey: apiKey,
        prompt: prompt,
        inputImage: _inputImage,
        inputImageMime: _inputImageMime,
        aspectRatio: _aspectRatio,
        imageSize: _qualityLabelsOf(context)[_quality]!.split(' ').first,
      );
      if (!mounted) return;
      setState(() => _resultImage = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.s.imageGenFailed(e.toString()));
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickInputImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: context.s.imageGenPickRef,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    // 检测 mime type
    final ext = result.files.single.extension?.toLowerCase() ?? '';
    final mime = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    setState(() {
      _inputImage = bytes;
      _inputImageName = result.files.single.name;
      _inputImageMime = mime;
    });
  }

  Future<void> _exportImage() async {
    if (_resultImage == null) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.s.imageGenExportTitle,
      fileName: 'generated_${DateTime.now().millisecondsSinceEpoch}.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (!mounted) return;
    if (path == null) return;
    await File(path).writeAsBytes(_resultImage!);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.s.imageGenExported(path))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // 左侧控制面板
        SizedBox(
          width: 320,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: theme.dividerColor, width: 0.5),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 提示词
                  Text(
                    context.s.imageGenSectionDesc,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _promptController,
                    maxLines: 5,
                    minLines: 3,
                    style: theme.textTheme.bodySmall,
                    decoration: InputDecoration(
                      hintText: context.s.imageGenDescHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 图改图输入
                  Text(
                    context.s.imageGenSectionRef,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_inputImage != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _inputImage!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            onPressed: () => setState(() {
                              _inputImage = null;
                              _inputImageName = null;
                              _inputImageMime = null;
                            }),
                            icon: const Icon(Icons.close, size: 16),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(4),
                              minimumSize: const Size(24, 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _inputImageName ?? '',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _pickInputImage,
                      icon: const Icon(Icons.image, size: 16),
                      label: Text(context.s.imageGenUploadRef),
                    ),
                  const SizedBox(height: 16),

                  // 画质选择
                  Text(
                    context.s.imageGenSectionQuality,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ImageQuality>(
                    segments: ImageQuality.values
                        .map(
                          (q) => ButtonSegment(
                            value: q,
                            label: Text(
                              _qualityLabelsOf(context)[q]!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_quality},
                    onSelectionChanged: (s) =>
                        setState(() => _quality = s.first),
                  ),
                  const SizedBox(height: 16),

                  // 宽高比
                  Text(
                    context.s.imageGenSectionRatio,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _aspectRatios.map((ratio) {
                      final selected = ratio == _aspectRatio;
                      return ChoiceChip(
                        label: Text(
                          ratio,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: selected,
                        onSelected: (_) => setState(() => _aspectRatio = ratio),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // 生成按钮
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _generate,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        _loading
                            ? context.s.imageGenGenerating
                            : context.s.imageGenGenerate,
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // 右侧预览区
        Expanded(
          child: Container(
            color: theme.colorScheme.surfaceContainerLow,
            child: _resultImage != null
                ? Stack(
                    children: [
                      Center(
                        child: InteractiveViewer(
                          child: Image.memory(
                            _resultImage!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: FilledButton.icon(
                          onPressed: _exportImage,
                          icon: const Icon(Icons.download, size: 16),
                          label: Text(context.s.imageGenExportPng),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.s.imageGenPlaceholder,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─── API 调用 ───────────────────────────────────────────────────

const _defaultModel = 'gemini-3.1-flash-image-preview';

Future<Uint8List> _callGeminiImageGen({
  required String baseUrl,
  required String apiKey,
  required String prompt,
  Uint8List? inputImage,
  String? inputImageMime,
  required String aspectRatio,
  required String imageSize,
}) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 600),
    ),
  );

  // 构建 parts（和 Python demo 一致：先图后文）
  final parts = <Map<String, dynamic>>[];

  if (inputImage != null) {
    parts.add({
      'inlineData': {
        'mimeType': inputImageMime ?? 'image/png',
        'data': base64Encode(inputImage),
      },
    });
  }

  // prompt
  if (prompt.isNotEmpty) {
    parts.add({'text': inputImage != null ? '基于此图，$prompt' : prompt});
  } else if (inputImage != null) {
    parts.add({'text': '基于此图，进行优化和美化'});
  }

  // 拼接完整 URL：baseUrl/v1beta/models/{model}:generateContent
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final url = '$base/v1beta/models/$_defaultModel:generateContent';

  late final Response response;
  try {
    response = await dio.post(
      url,
      data: jsonEncode({
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {
          'responseModalities': ['IMAGE'],
          'imageConfig': {'aspectRatio': aspectRatio, 'imageSize': imageSize},
        },
      }),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => status != null && status < 600,
      ),
    );
  } on DioException catch (e) {
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionTimeout) {
      throw Exception('Request timeout, please retry later');
    }
    throw Exception('网络请求失败: ${e.message}');
  }

  // 非 200 状态码处理
  if (response.statusCode != 200) {
    final body = response.data;
    String detail = '';
    if (body is Map) {
      final error = body['error'];
      if (error is Map) {
        detail = (error['message'] ?? '').toString();
      } else {
        detail = body.toString();
      }
    } else if (body is String) {
      detail = body.length > 300 ? body.substring(0, 300) : body;
    }
    throw Exception('[${response.statusCode}] $detail');
  }

  // 解析响应
  final dynamic rawData = response.data;
  late final Map<String, dynamic> data;
  if (rawData is Map<String, dynamic>) {
    data = rawData;
  } else if (rawData is Map) {
    data = Map<String, dynamic>.from(rawData);
  } else if (rawData is String) {
    try {
      data = jsonDecode(rawData) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('API 返回非 JSON: ${_truncate(rawData, 200)}');
    }
  } else {
    throw Exception('API 返回未知格式: ${rawData.runtimeType}');
  }

  final candidates = data['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) {
    final feedback = data['promptFeedback'];
    if (feedback is Map) {
      final reason = feedback['blockReason'] ?? '未知原因';
      throw Exception('请求被安全过滤拒绝: $reason');
    }
    throw Exception('API 未返回结果: ${_truncate(data.toString(), 200)}');
  }

  final candidate = candidates[0] as Map<String, dynamic>;
  final finishReason = candidate['finishReason'] as String?;
  if (finishReason != null && finishReason != 'STOP') {
    throw Exception('生成被终止: $finishReason');
  }

  final content = candidate['content'] as Map<String, dynamic>;
  final respParts = content['parts'] as List;

  // 提取图片
  for (final part in respParts) {
    if (part is Map) {
      final inlineData = part['inlineData'] ?? part['inline_data'];
      if (inlineData is Map) {
        final b64 = (inlineData['data'] ?? '') as String;
        if (b64.isNotEmpty) return base64Decode(b64);
      }
    }
  }

  // 收集文本回复作为错误信息
  for (final part in respParts) {
    if (part is Map && part.containsKey('text')) {
      throw Exception('模型未生成图片，回复:\n${_truncate(part['text'] as String, 300)}');
    }
  }

  // 输出实际响应结构帮助调试
  throw Exception(
    '响应中未找到图片数据。\n响应结构: ${_truncate(jsonEncode(candidate), 500)}',
  );
}

/// 截断文本
String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

// ─── 设置面板 ───────────────────────────────────────────────────

class _ImageGenSettings extends StatefulWidget {
  const _ImageGenSettings({required this.config, required this.onSave});
  final ToolConfig config;
  final void Function(ToolConfig) onSave;

  @override
  State<_ImageGenSettings> createState() => _ImageGenSettingsState();
}

class _ImageGenSettingsState extends State<_ImageGenSettings> {
  late final TextEditingController _apiUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _apiUrlCtrl = TextEditingController(
      text: widget.config.get<String>('apiUrl') ?? '',
    );
    _apiKeyCtrl = TextEditingController(
      text: widget.config.get<String>('apiKey') ?? '',
    );
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    var config = widget.config;
    config = config.setPermanent('apiUrl', _apiUrlCtrl.text.trim());
    config = config.setPermanent('apiKey', _apiKeyCtrl.text.trim());
    widget.onSave(config);
  }

  Future<void> _testConnection() async {
    final apiUrl = _apiUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();

    if (apiUrl.isEmpty || apiKey.isEmpty) {
      setState(() => _testResult = '❌ 请填写 API 地址和 Key');
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final base = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final url = '$base/v1beta/models/$_defaultModel:generateContent';

      // 用简单的 POST 请求测试连通性（Bearer 认证）
      await dio.post(
        url,
        data: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'hi'},
              ],
            },
          ],
          'generationConfig': {
            'responseModalities': ['TEXT'],
          },
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      if (!mounted) return;
      setState(() => _testResult = '✅ 连接成功，API 可用');
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      String detail = '';
      final body = e.response?.data;
      if (body is Map) {
        final error = body['error'];
        if (error is Map) {
          detail = (error['message'] ?? '').toString();
        }
      }
      setState(
        () => _testResult = detail.isNotEmpty
            ? '❌ [$statusCode] $detail'
            : '❌ [$statusCode] 请求失败',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _apiUrlCtrl,
          decoration: const InputDecoration(
            labelText: 'API 地址',
            hintText: 'https://yunwu.ai',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: '输入你的 Gemini API Key',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _save,
                child: Text(context.s.imageGenSaveConfig),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 16),
                label: Text(
                  _testing
                      ? context.s.imageGenTesting
                      : context.s.imageGenTestConn,
                ),
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Text(
            _testResult!,
            style: TextStyle(
              fontSize: 12,
              color: _testResult!.startsWith('✅')
                  ? Colors.green
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_plugin.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/settings/app_settings.dart';

/// Pix2Text 公式/文字 OCR 工具
class FormulaOcrTool extends ToolPlugin {
  @override
  String get id => 'formula_ocr';
  @override
  String get name => '公式 OCR';
  @override
  IconData get icon => Icons.functions;
  @override
  String get description => '图片识别文字与数学公式 (Pix2Text)';
  @override
  String get category => 'AI';

  @override
  String localizedName(BuildContext context) => context.s.formulaOcrName;
  @override
  String localizedDescription(BuildContext context) => context.s.formulaOcrDesc;
  @override
  String localizedCategory(BuildContext context) =>
      context.s.formulaOcrCategory;

  @override
  List<ConfigField> get permanentFields => const [
    ConfigField(
      key: 'apiKey',
      label: 'API Key',
      type: ConfigFieldType.secret,
      required: true,
      hint: 'p2t_live_xxx 格式',
    ),
  ];

  @override
  List<ConfigField> get temporaryFields => const [];

  @override
  Widget buildUI(BuildContext context, ToolConfig config) =>
      _FormulaOcrUI(config: config);

  @override
  Widget? buildSettings(
    BuildContext context,
    ToolConfig config,
    void Function(ToolConfig) onSave,
  ) => _FormulaOcrSettings(config: config, onSave: onSave);
}

// ─── 识别模式 ─────────────────────────────────────────────────

enum _FileType { textFormula, text, formula }

Map<_FileType, String> _fileTypeLabelsOf(BuildContext context) => {
  _FileType.textFormula: context.s.formulaOcrModeTextFormula,
  _FileType.text: context.s.formulaOcrModeText,
  _FileType.formula: context.s.formulaOcrModeFormula,
};

const _fileTypeApi = {
  _FileType.textFormula: 'text_formula',
  _FileType.text: 'text',
  _FileType.formula: 'formula',
};

// ─── 主界面 ───────────────────────────────────────────────────

class _FormulaOcrUI extends StatefulWidget {
  const _FormulaOcrUI({required this.config});
  final ToolConfig config;

  @override
  State<_FormulaOcrUI> createState() => _FormulaOcrUIState();
}

class _FormulaOcrUIState extends State<_FormulaOcrUI> {
  Uint8List? _imageBytes;
  String? _imageName;
  _FileType _fileType = _FileType.textFormula;
  String? _result;
  bool _loading = false;
  String? _error;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: context.s.formulaOcrPickImage,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = result.files.single.name;
      _result = null;
      _error = null;
    });
  }

  Future<void> _recognize() async {
    final apiKey = widget.config.get<String>('apiKey');
    if (apiKey == null || apiKey.isEmpty) {
      setState(() => _error = context.s.formulaOcrNeedApiKey);
      return;
    }
    if (_imageBytes == null) {
      setState(() => _error = context.s.formulaOcrNeedImage);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _callP2tApi(
        apiKey: apiKey,
        imageBytes: _imageBytes!,
        imageName: _imageName ?? 'image.png',
        fileType: _fileTypeApi[_fileType]!,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.s.formulaOcrFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportMd() async {
    if (_result == null) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.s.formulaOcrExportMd,
      fileName: 'ocr_${DateTime.now().millisecondsSinceEpoch}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (!mounted || path == null) return;
    await File(path).writeAsString(_result!);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.s.formulaOcrExported(path))));
  }

  Future<void> _exportWord() async {
    if (_result == null) return;

    // 读取设置中的 pandoc 路径
    final settings = await AppSettings.load();
    final pandocPath = settings.pandocPath;

    if (pandocPath.isEmpty) {
      if (!mounted) return;
      // pandoc 未配置，提示降级
      final fallback = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.s.formulaOcrPandocMissing),
          content: Text(context.s.formulaOcrPandocHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.s.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.s.formulaOcrExportMdBtn),
            ),
          ],
        ),
      );
      if (fallback == true) _exportMd();
      return;
    }

    // 使用 pandoc 转换
    if (!mounted) return;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: context.s.formulaOcrExportWord,
      fileName: 'ocr_${DateTime.now().millisecondsSinceEpoch}.docx',
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    if (!mounted || savePath == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempMd = File('${tempDir.path}/ocr_temp.md');
      await tempMd.writeAsString(_result!);

      final result = await Process.run(pandocPath, [
        tempMd.path,
        '-o',
        savePath,
      ]);

      // 清理临时文件
      if (await tempMd.exists()) await tempMd.delete();

      if (!mounted) return;

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String?)?.trim() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.formulaOcrPandocFailed(stderr))),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.formulaOcrExported(savePath))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.formulaOcrExportFailed(e.toString()))),
      );
    }
  }

  // PLACEHOLDER_BUILD_METHOD

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
                  // 图片上传
                  Text(
                    context.s.formulaOcrSectionImage,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_imageBytes != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _imageBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            onPressed: () => setState(() {
                              _imageBytes = null;
                              _imageName = null;
                              _result = null;
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
                    Text(_imageName ?? '', style: theme.textTheme.bodySmall),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, size: 16),
                      label: Text(context.s.formulaOcrUploadImage),
                    ),
                  const SizedBox(height: 16),

                  // 识别模式
                  Text(
                    context.s.formulaOcrSectionMode,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_FileType>(
                    segments: _FileType.values
                        .map(
                          (t) => ButtonSegment(
                            value: t,
                            label: Text(
                              _fileTypeLabelsOf(context)[t]!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_fileType},
                    onSelectionChanged: (s) =>
                        setState(() => _fileType = s.first),
                  ),
                  const SizedBox(height: 24),

                  // 识别按钮
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _recognize,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.document_scanner, size: 18),
                      label: Text(
                        _loading
                            ? context.s.formulaOcrRecognizing
                            : context.s.formulaOcrStartRecognize,
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

        // 右侧结果区
        Expanded(
          child: Container(
            color: theme.colorScheme.surfaceContainerLow,
            child: _result != null
                ? Column(
                    children: [
                      // 工具栏
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              context.s.formulaOcrSectionResult,
                              style: theme.textTheme.labelMedium,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () {
                                // 复制到剪贴板
                                _copyToClipboard(_result!);
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: Text(context.s.formulaOcrCopy),
                            ),
                            TextButton.icon(
                              onPressed: _exportMd,
                              icon: const Icon(Icons.download, size: 14),
                              label: Text(context.s.formulaOcrExportMdBtn),
                            ),
                            TextButton.icon(
                              onPressed: _exportWord,
                              icon: const Icon(Icons.description, size: 14),
                              label: Text(context.s.formulaOcrExportWord),
                            ),
                          ],
                        ),
                      ),
                      // Markdown 内容
                      Expanded(
                        child: SelectionArea(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: Text(
                                _result!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  height: 1.6,
                                ),
                              ),
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
                          Icons.functions,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.s.formulaOcrResultPlaceholder,
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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s.formulaOcrCopied)));
    }
  }
}

// ─── API 调用 ───────────────────────────────────────────────────

const _p2tApiBase = 'https://api.breezedeus.com/api';

Future<String> _callP2tApi({
  required String apiKey,
  required Uint8List imageBytes,
  required String imageName,
  required String fileType,
}) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  // 1. 提交识别任务
  final formData = FormData.fromMap({
    'image': MultipartFile.fromBytes(imageBytes, filename: imageName),
    'language': 'Simplified Chinese',
    'file_type': fileType,
    'server_type': 'pro',
  });

  final submitResp = await dio.post(
    '$_p2tApiBase/pix2text',
    data: formData,
    options: Options(headers: {'X-API-Key': apiKey}),
  );

  final submitData = submitResp.data as Map<String, dynamic>;
  if (submitData['status_code'] != 200) {
    throw Exception(submitData['message'] ?? 'Submit failed');
  }

  final taskId = submitData['task_id'] as String;

  // 2. 轮询获取结果
  for (int i = 0; i < 30; i++) {
    await Future.delayed(const Duration(seconds: 2));

    final resultResp = await dio.get(
      '$_p2tApiBase/result/$taskId',
      options: Options(headers: {'X-API-Key': apiKey}),
    );

    final resultData = resultResp.data as Map<String, dynamic>;
    final status = resultData['status'] as String?;

    if (status == 'FINISHED') {
      final results = resultData['results'];
      if (results is String) return results;
      if (results is List) {
        return results.map((r) => r['text'] ?? '').join('\n');
      }
      return results.toString();
    } else if (status == 'FAILED') {
      throw Exception(resultData['message'] ?? 'Recognition failed');
    }
    // 其他状态（PENDING/PROCESSING）继续等待
  }

  throw Exception('Recognition timeout, please retry later');
}

// ─── 设置面板 ───────────────────────────────────────────────────

class _FormulaOcrSettings extends StatefulWidget {
  const _FormulaOcrSettings({required this.config, required this.onSave});
  final ToolConfig config;
  final void Function(ToolConfig) onSave;

  @override
  State<_FormulaOcrSettings> createState() => _FormulaOcrSettingsState();
}

class _FormulaOcrSettingsState extends State<_FormulaOcrSettings> {
  late final TextEditingController _apiKeyCtrl;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(
      text: widget.config.get<String>('apiKey') ?? '',
    );
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    var config = widget.config;
    config = config.setPermanent('apiKey', _apiKeyCtrl.text.trim());
    widget.onSave(config);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _apiKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: 'p2t_live_xxx',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _save,
                child: Text(context.s.formulaOcrSaveConfig),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.breezedeus.com/pix2text'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(context.s.formulaOcrRegisterKey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.s.formulaOcrFreeQuota,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

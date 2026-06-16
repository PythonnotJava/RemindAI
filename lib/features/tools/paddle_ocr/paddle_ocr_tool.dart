import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_plugin.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/settings/app_settings.dart';

/// PaddleOCR 官方 API 工具
/// 支持 OCR 识别（PP-OCRv6）和文档解析（PaddleOCR-VL）
class PaddleOcrTool extends ToolPlugin {
  @override
  String get id => 'paddle_ocr';
  @override
  String get name => 'PaddleOCR';
  @override
  IconData get icon => Icons.document_scanner;
  @override
  String get description => '通用 OCR 与文档解析 (PaddleOCR 官方 API)';
  @override
  String get category => 'AI';

  @override
  String localizedName(BuildContext context) => context.s.paddleOcrName;
  @override
  String localizedDescription(BuildContext context) => context.s.paddleOcrDesc;
  @override
  String localizedCategory(BuildContext context) => context.s.paddleOcrCategory;

  @override
  List<ConfigField> get permanentFields => const [
    ConfigField(
      key: 'pythonPath',
      label: 'Python 路径',
      type: ConfigFieldType.text,
      required: true,
      hint: '如 python（需安装 requests 库）',
    ),
    ConfigField(
      key: 'accessToken',
      label: 'Access Token',
      type: ConfigFieldType.secret,
      required: true,
      hint: 'AI Studio 获取的 Access Token',
    ),
  ];

  @override
  List<ConfigField> get temporaryFields => const [];

  @override
  Widget buildUI(BuildContext context, ToolConfig config) =>
      _PaddleOcrUI(config: config);

  @override
  Widget? buildSettings(
    BuildContext context,
    ToolConfig config,
    void Function(ToolConfig) onSave,
  ) => _PaddleOcrSettings(config: config, onSave: onSave);
}

// ─── 任务模式 ─────────────────────────────────────────────────

enum _TaskMode { ocr, docParsing }

Map<_TaskMode, String> _taskModeLabelsOf(BuildContext context) => {
  _TaskMode.ocr: context.s.paddleOcrModeOcr,
  _TaskMode.docParsing: context.s.paddleOcrModeDoc,
};

Map<_TaskMode, String> _taskModeDescriptionsOf(BuildContext context) => {
  _TaskMode.ocr: context.s.paddleOcrModeOcrDesc,
  _TaskMode.docParsing: context.s.paddleOcrModeDocDesc,
};

// ─── OCR 模型选择 ─────────────────────────────────────────────

enum _OcrModel { ppOcrV5, ppOcrV6 }

const _ocrModelLabels = {
  _OcrModel.ppOcrV5: 'PP-OCRv5',
  _OcrModel.ppOcrV6: 'PP-OCRv6',
};

const _ocrModelApi = {
  _OcrModel.ppOcrV5: 'PP-OCRv5',
  _OcrModel.ppOcrV6: 'PP-OCRv6',
};

// ─── 文档解析模型选择 ────────────────────────────────────────

enum _DocModel { ppStructureV3, paddleOcrVL16 }

const _docModelLabels = {
  _DocModel.ppStructureV3: 'PP-StructureV3',
  _DocModel.paddleOcrVL16: 'PaddleOCR-VL-1.6',
};

const _docModelApi = {
  _DocModel.ppStructureV3: 'PP-StructureV3',
  _DocModel.paddleOcrVL16: 'PaddleOCR-VL-1.6',
};

// ─── 主界面 ───────────────────────────────────────────────────

class _PaddleOcrUI extends StatefulWidget {
  const _PaddleOcrUI({required this.config});
  final ToolConfig config;

  @override
  State<_PaddleOcrUI> createState() => _PaddleOcrUIState();
}

class _PaddleOcrUIState extends State<_PaddleOcrUI> {
  // 文件
  String? _filePath;
  String? _fileName;
  bool _isPdf = false;

  // 模式与模型
  _TaskMode _taskMode = _TaskMode.ocr;
  _OcrModel _ocrModel = _OcrModel.ppOcrV6;
  _DocModel _docModel = _DocModel.paddleOcrVL16;

  // 高级选项
  bool _useDocOrientation = false;
  bool _useDocUnwarping = false;
  bool _useChart = false;

  // 结果
  String? _result;
  bool _loading = false;
  String? _error;
  String? _statusText;

  // PLACEHOLDER_METHODS

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'tiff', 'pdf'],
      dialogTitle: context.s.paddleOcrPickFile,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() {
      _filePath = path;
      _fileName = result.files.single.name;
      _isPdf = path.toLowerCase().endsWith('.pdf');
      _result = null;
      _error = null;
    });
  }

  Future<void> _recognize() async {
    final pythonPath = widget.config.get<String>('pythonPath');
    final token = widget.config.get<String>('accessToken');

    if (pythonPath == null || pythonPath.isEmpty) {
      setState(() => _error = context.s.paddleOcrNeedPython);
      return;
    }
    if (token == null || token.isEmpty) {
      setState(() => _error = context.s.paddleOcrNeedToken);
      return;
    }
    if (_filePath == null) {
      setState(() => _error = context.s.paddleOcrNeedFile);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _statusText = context.s.paddleOcrSubmitting;
    });

    try {
      // 定位脚本路径（assets/scripts/paddle_ocr/）
      final scriptDir = _getScriptsDir();
      final String scriptPath;
      final List<String> args;

      if (_taskMode == _TaskMode.ocr) {
        scriptPath = '$scriptDir/ocr_task.py';
        final model = _ocrModelApi[_ocrModel]!;
        final opts = _buildOcrOpts();
        args = [
          '--file',
          _filePath!,
          '--model',
          model,
          '--token',
          token,
          '--opts',
          jsonEncode(opts),
        ];
      } else {
        scriptPath = '$scriptDir/doc_parse_task.py';
        final model = _docModelApi[_docModel]!;
        final opts = _buildDocOpts();
        args = [
          '--file',
          _filePath!,
          '--model',
          model,
          '--token',
          token,
          '--opts',
          jsonEncode(opts),
        ];
      }

      // 执行 Python 脚本
      setState(() => _statusText = context.s.paddleOcrCalling);
      final processResult = await Process.run(
        pythonPath,
        [scriptPath, ...args],
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );

      if (!mounted) return;

      if (processResult.exitCode != 0) {
        final stderr = (processResult.stderr as String).trim();
        setState(
          () => _error = context.s.paddleOcrExecFailed(
            '(exit ${processResult.exitCode}):\n$stderr',
          ),
        );
        return;
      }

      final stdout = (processResult.stdout as String).trim();
      if (stdout.isEmpty) {
        setState(() => _error = context.s.paddleOcrNoResult);
        return;
      }

      setState(() => _result = stdout);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.s.paddleOcrError(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusText = null;
        });
      }
    }
  }

  /// 获取 assets/scripts/paddle_ocr 目录的绝对路径
  String _getScriptsDir() {
    final candidates = [
      // flutter run 开发模式（从项目根）
      'assets/scripts/paddle_ocr',
      // 发布模式 Windows
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/scripts/paddle_ocr',
    ];
    for (final p in candidates) {
      if (Directory(p).existsSync()) return p;
    }
    return 'assets/scripts/paddle_ocr';
  }

  Map<String, dynamic> _buildOcrOpts() {
    final opts = <String, dynamic>{};
    if (_useDocOrientation) opts['useDocOrientationClassify'] = true;
    if (_useDocUnwarping) opts['useDocUnwarping'] = true;
    return opts;
  }

  Map<String, dynamic> _buildDocOpts() {
    final opts = <String, dynamic>{};
    if (_useDocOrientation) opts['useDocOrientationClassify'] = true;
    if (_useDocUnwarping) opts['useDocUnwarping'] = true;
    if (_useChart) opts['useChartRecognition'] = true;
    return opts;
  }

  Future<void> _exportMd() async {
    if (_result == null) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.s.formulaOcrExportMd,
      fileName: 'paddleocr_${DateTime.now().millisecondsSinceEpoch}.md',
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
    final settings = await AppSettings.load();
    final pandocPath = settings.pandocPath;

    if (pandocPath.isEmpty) {
      if (!mounted) return;
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

    if (!mounted) return;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: context.s.formulaOcrExportWord,
      fileName: 'paddleocr_${DateTime.now().millisecondsSinceEpoch}.docx',
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    if (!mounted || savePath == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempMd = File('${tempDir.path}/paddleocr_temp.md');
      await tempMd.writeAsString(_result!);

      final result = await Process.run(pandocPath, [
        tempMd.path,
        '-o',
        savePath,
      ]);
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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s.formulaOcrCopied)));
    }
  }

  // PLACEHOLDER_BUILD

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // ─── 左侧控制面板 ───
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
                  // 文件选择
                  Text(
                    context.s.paddleOcrSectionInput,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_filePath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isPdf ? Icons.picture_as_pdf : Icons.image,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fileName ?? '',
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _filePath = null;
                              _fileName = null;
                              _result = null;
                            }),
                            icon: const Icon(Icons.close, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(context.s.paddleOcrSelectFile),
                    ),
                  const SizedBox(height: 20),

                  // 任务模式
                  Text(
                    context.s.paddleOcrSectionMode,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_TaskMode>(
                    segments: _TaskMode.values
                        .map(
                          (t) => ButtonSegment(
                            value: t,
                            label: Text(
                              _taskModeLabelsOf(context)[t]!,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {_taskMode},
                    onSelectionChanged: (s) =>
                        setState(() => _taskMode = s.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _taskModeDescriptionsOf(context)[_taskMode]!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 模型选择
                  _buildModelSelector(theme),
                  const SizedBox(height: 16),

                  // 高级选项
                  _buildAdvancedOptions(theme),
                  const SizedBox(height: 24),

                  // 开始按钮
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
                          : const Icon(Icons.play_arrow, size: 18),
                      label: Text(
                        _loading
                            ? (_statusText ?? context.s.paddleOcrProcessing)
                            : context.s.paddleOcrStart,
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ─── 右侧结果区 ───
        Expanded(child: _buildResultPanel(theme)),
      ],
    );
  }

  // PLACEHOLDER_WIDGETS

  Widget _buildModelSelector(ThemeData theme) {
    if (_taskMode == _TaskMode.ocr) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.paddleOcrModelOcr,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_OcrModel>(
            segments: _OcrModel.values
                .map(
                  (m) => ButtonSegment(
                    value: m,
                    label: Text(
                      _ocrModelLabels[m]!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )
                .toList(),
            selected: {_ocrModel},
            onSelectionChanged: (s) => setState(() => _ocrModel = s.first),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.paddleOcrModelDoc,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_DocModel>(
            segments: _DocModel.values
                .map(
                  (m) => ButtonSegment(
                    value: m,
                    label: Text(
                      _docModelLabels[m]!,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )
                .toList(),
            selected: {_docModel},
            onSelectionChanged: (s) => setState(() => _docModel = s.first),
          ),
        ],
      );
    }
  }

  Widget _buildAdvancedOptions(ThemeData theme) {
    return ExpansionTile(
      title: Text(
        context.s.paddleOcrAdvanced,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 4),
      initiallyExpanded: false,
      children: [
        _OptionSwitch(
          label: context.s.paddleOcrRotateCorrect,
          value: _useDocOrientation,
          onChanged: (v) => setState(() => _useDocOrientation = v),
        ),
        _OptionSwitch(
          label: context.s.paddleOcrUnwarp,
          value: _useDocUnwarping,
          onChanged: (v) => setState(() => _useDocUnwarping = v),
        ),
        if (_taskMode == _TaskMode.docParsing)
          _OptionSwitch(
            label: context.s.paddleOcrChartRecognize,
            value: _useChart,
            onChanged: (v) => setState(() => _useChart = v),
          ),
      ],
    );
  }

  Widget _buildResultPanel(ThemeData theme) {
    if (_result != null) {
      return Container(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            // 工具栏
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _taskMode == _TaskMode.docParsing
                        ? context.s.paddleOcrResultDoc
                        : context.s.paddleOcrResultOcr,
                    style: theme.textTheme.labelMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _copyToClipboard(_result!),
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
            // 结果内容
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
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(
              context.s.paddleOcrResultPlaceholder,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.s.paddleOcrFileHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 选项开关组件 ─────────────────────────────────────────────

class _OptionSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// PLACEHOLDER_SETTINGS

// ─── 设置面板 ───────────────────────────────────────────────────

class _PaddleOcrSettings extends StatefulWidget {
  const _PaddleOcrSettings({required this.config, required this.onSave});
  final ToolConfig config;
  final void Function(ToolConfig) onSave;

  @override
  State<_PaddleOcrSettings> createState() => _PaddleOcrSettingsState();
}

class _PaddleOcrSettingsState extends State<_PaddleOcrSettings> {
  late final TextEditingController _pythonCtrl;
  late final TextEditingController _tokenCtrl;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _pythonCtrl = TextEditingController(
      text: widget.config.get<String>('pythonPath') ?? 'python',
    );
    _tokenCtrl = TextEditingController(
      text: widget.config.get<String>('accessToken') ?? '',
    );
  }

  @override
  void dispose() {
    _pythonCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _save() {
    var config = widget.config;
    config = config.setPermanent('pythonPath', _pythonCtrl.text.trim());
    config = config.setPermanent('accessToken', _tokenCtrl.text.trim());
    widget.onSave(config);
  }

  Future<void> _testConnection() async {
    final python = _pythonCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    if (python.isEmpty || token.isEmpty) {
      setState(() => _testResult = '❌ 请填写 Python 路径和 Token');
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      // 定位测试脚本
      final scriptPath = _findScript('test_connection.py');

      final result = await Process.run(
        python,
        [scriptPath, '--token', token],
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      );

      if (!mounted) return;

      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        setState(() => _testResult = '❌ Python 执行失败:\n$stderr');
        return;
      }

      final stdout = (result.stdout as String).trim();
      if (stdout == 'OK') {
        setState(() => _testResult = '✅ Token 有效，连接成功');
      } else if (stdout.startsWith('ERR:')) {
        setState(() => _testResult = '❌ ${stdout.substring(4)}');
      } else {
        setState(() => _testResult = '⚠️ 未知响应: $stdout');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// 查找 assets/scripts/paddle_ocr/ 下的脚本文件
  String _findScript(String name) {
    // 尝试多个可能的路径
    final candidates = [
      // flutter run 开发模式（从项目根）
      'assets/scripts/paddle_ocr/$name',
      // 发布模式 Windows
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/scripts/paddle_ocr/$name',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    // fallback：相对路径（依赖工作目录）
    return 'assets/scripts/paddle_ocr/$name';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _pythonCtrl,
          decoration: const InputDecoration(
            labelText: 'Python 路径',
            hintText: 'python 或完整路径',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tokenCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Access Token',
            hintText: 'AI Studio 获取',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _save,
                child: Text(context.s.paddleOcrSaveConfig),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                child: Text(
                  _testing
                      ? context.s.paddleOcrTesting
                      : context.s.paddleOcrTestConn,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.baidu.com/account/accessToken'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.key, size: 14),
                label: Text(context.s.paddleOcrGetToken),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.baidu.com/paddleocr'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('PaddleOCR'),
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              _testResult!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          context.s.paddleOcrApiDesc,
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

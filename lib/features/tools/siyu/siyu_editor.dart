import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n_ext.dart';
import 'siyu_markdown.dart';

/// 思宇项目的标识文件名
const _projectFileName = '.siyu';

/// 主文档文件名
const _mainDocFileName = 'main.md';

/// 思宇编辑器主页
class SiyuEditorPage extends StatefulWidget {
  const SiyuEditorPage({super.key});

  @override
  State<SiyuEditorPage> createState() => _SiyuEditorPageState();
}

class _SiyuEditorPageState extends State<SiyuEditorPage> {
  late QuillController _controller;
  String? _projectDir;
  bool _dirty = false;
  String _status = '';

  /// 图片缓存：相对路径 → 已解码的 ui.Image
  final Map<String, ui.Image> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _controller = QuillController.basic();
    _controller.addListener(_onDocChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final img in _imageCache.values) {
      img.dispose();
    }
    _imageCache.clear();
    super.dispose();
  }

  // ─── 项目操作 ───

  /// 新建项目：用户选择父目录 + 输入项目名 → 自动创建项目文件夹
  Future<void> _newProject() async {
    final parentDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.s.siyuPickLocation,
    );
    if (parentDir == null) return;

    if (!mounted) return;
    final name = await _inputDialog(
      context.s.siyuNewProject,
      context.s.siyuProjectName,
      context.s.siyuDefaultName,
    );
    if (name == null || name.trim().isEmpty) return;

    final dir = p.join(parentDir, name.trim());
    final folder = Directory(dir);
    if (await folder.exists()) {
      if (!mounted) return;
      _snack(context.s.siyuFolderExists(name));
      return;
    }
    await folder.create(recursive: true);

    // 创建项目标识、assets 目录、空 main.md
    final marker = File(p.join(dir, _projectFileName));
    await marker.writeAsString(
      jsonEncode({
        'version': 1,
        'name': name.trim(),
        'created': DateTime.now().toIso8601String(),
      }),
    );
    await Directory(p.join(dir, 'assets')).create();
    await File(p.join(dir, _mainDocFileName)).writeAsString('');

    setState(() {
      _projectDir = dir;
      _dirty = false;
      _status = p.basename(dir);
    });
  }

  // ─── 文档操作 ───

  void _onDocChanged() {
    if (!_dirty && _projectDir != null) setState(() => _dirty = true);
  }

  /// 保存：将 Delta 转为 Markdown 写入 main.md
  Future<void> _save() async {
    if (_projectDir == null || _controller.document.isEmpty()) return;

    try {
      final markdown = documentToMarkdown(_controller.document);
      final file = File(p.join(_projectDir!, _mainDocFileName));
      await file.writeAsString(markdown);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _status = context.s.siyuSaved(p.basename(_projectDir!));
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context.s.siyuSaveFailed(e.toString()));
    }
  }

  // ─── 图片插入 ───

  Future<void> _insertImage() async {
    if (_projectDir == null) {
      _snack('请先新建项目');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.siyuPickImage,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    final srcPath = result.files.single.path;
    if (srcPath == null) return;

    // 复制到项目 assets 目录
    final assetsDir = Directory(p.join(_projectDir!, 'assets'));
    if (!await assetsDir.exists()) await assetsDir.create();

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(srcPath)}';
    final destPath = p.join(assetsDir.path, fileName);
    await File(srcPath).copy(destPath);

    // 预解码并缓存
    final relativePath = 'assets/$fileName';
    try {
      final bytes = await File(destPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _imageCache[relativePath] = frame.image;
    } catch (_) {}

    _controller.document.insert(
      _controller.selection.extentOffset,
      BlockEmbed.image(relativePath),
    );
    setState(() => _dirty = true);
  }

  // ─── 导出 ───

  Future<void> _export() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.s.siyuExportTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('md'),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('Markdown (.md)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('txt'),
            child: ListTile(
              leading: const Icon(Icons.text_snippet),
              title: Text(context.s.siyuExportTxt),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;

    String content;
    String defaultName;
    String ext;

    if (choice == 'md') {
      content = documentToMarkdown(_controller.document);
      defaultName = 'export.md';
      ext = 'md';
    } else {
      content = _controller.document.toPlainText();
      defaultName = 'export.txt';
      ext = 'txt';
    }

    if (!mounted) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.s.siyuExportTitle,
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (result == null) return;
    await File(result).writeAsString(content);
    if (!mounted) return;
    _snack(context.s.siyuExported(p.basename(result)));
  }

  // ─── UI 辅助 ───

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<String?> _inputDialog(String title, String label, String hint) {
    final ctrl = TextEditingController(text: hint);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(context.s.commonConfirm),
          ),
        ],
      ),
    );
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 未创建项目时的欢迎界面
    if (_projectDir == null) {
      return _buildWelcome(cs);
    }

    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(cs),
          const Divider(height: 1),
          QuillSimpleToolbar(controller: _controller),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: QuillEditor.basic(
                controller: _controller,
                config: QuillEditorConfig(
                  placeholder: context.s.siyuPlaceholder,
                  embedBuilders: [
                    _SiyuImageEmbedBuilder(_projectDir!, _imageCache),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomBar(cs),
        ],
      ),
    );
  }

  Widget _buildWelcome(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_document,
            size: 64,
            color: cs.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.s.siyuWelcomeTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.siyuWelcomeDesc,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.create_new_folder),
            label: Text(context.s.siyuBtnNewProject),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.surface,
      child: Row(
        children: [
          _tbtn(Icons.save, context.s.siyuBtnSave, _save),
          _tbtn(
            Icons.image_outlined,
            context.s.siyuBtnInsertImage,
            _insertImage,
          ),
          _tbtn(Icons.upload, context.s.siyuBtnExport, _export),
        ],
      ),
    );
  }

  Widget _tbtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          if (_dirty) const Icon(Icons.circle, size: 8, color: Colors.orange),
          if (_dirty) const SizedBox(width: 6),
          Text(
            _status.isNotEmpty ? _status : context.s.siyuStatusReady,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          Text(
            _mainDocFileName,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图片嵌入渲染器 — 纯查缓存，不做任何异步操作
class _SiyuImageEmbedBuilder extends EmbedBuilder {
  final String projectDir;
  final Map<String, ui.Image> imageCache;
  _SiyuImageEmbedBuilder(this.projectDir, this.imageCache);

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final imageSource = embedContext.node.value.data as String;
    final cached = imageCache[imageSource];

    if (cached != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RawImage(
          image: cached,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      );
    }

    // 图片尚未解码或不存在
    final filePath = imageSource.startsWith('assets/')
        ? p.join(projectDir, imageSource)
        : imageSource;
    final exists = File(filePath).existsSync();

    if (!exists) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          context.s.siyuImageNotFound(imageSource),
          style: const TextStyle(color: Colors.red, fontSize: 12),
        ),
      );
    }

    return Container(
      height: 100,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        context.s.siyuImageLoading,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}

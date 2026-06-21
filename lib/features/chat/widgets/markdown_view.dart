import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart' as wv;

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/pet/pet_chat_service.dart';

import '../../../core/font/custom_font_loader.dart';

/// 统一的 Markdown 渲染组件（基于 gpt_markdown）。
///
/// 相比 flutter_markdown：对 AI 流式输出更鲁棒（未闭合的代码块/标记不会整体不渲染），
/// 内置 LaTeX、表格、任务列表，并支持图片与链接的自定义处理。
class MarkdownView extends StatelessWidget {
  final String data;
  final Color textColor;
  final String? fontFamily;
  final double? fontSize;

  const MarkdownView({
    super.key,
    required this.data,
    required this.textColor,
    this.fontFamily,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveSize = fontSize ?? 14.0;

    TextStyle baseStyle;
    if (fontFamily != null && fontFamily!.isNotEmpty) {
      final isCustom = CustomFontLoader.instance.loadedFonts.contains(
        fontFamily,
      );
      if (isCustom) {
        // 自定义字体通过 FontLoader 注册，直接使用 fontFamily
        baseStyle = TextStyle(
          fontFamily: fontFamily,
          color: textColor,
          fontSize: effectiveSize,
          height: 1.5,
        );
      } else {
        // Google Font
        try {
          baseStyle = GoogleFonts.getFont(
            fontFamily!,
            color: textColor,
            fontSize: effectiveSize,
            height: 1.5,
          );
        } catch (_) {
          baseStyle = TextStyle(
            color: textColor,
            fontSize: effectiveSize,
            height: 1.5,
          );
        }
      }
    } else {
      baseStyle = TextStyle(
        color: textColor,
        fontSize: effectiveSize,
        height: 1.5,
      );
    }

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        return _PetContextMenu(selectableRegionState: selectableRegionState);
      },
      child: GptMarkdown(
        data,
        style: baseStyle,
        useDollarSignsForLatex: true,
        onLinkTap: (url, title) => _openLink(url),
        // 代码块：自带的 CodeField 头部 Row 在窄容器下会溢出 100px，
        // 这里用自定义版本：language 名 Flexible+ellipsis，避免溢出。
        codeBuilder: (context, name, code, closed) =>
            _SafeCodeField(name: name, codes: code, colorScheme: colorScheme),
        // 图片：data: URL 与本地路径用内存/文件渲染，http(s) 用网络图片
        imageBuilder: (context, imageUrl, width, height) {
          return _MarkdownImage(
            url: imageUrl,
            width: width,
            height: height,
            colorScheme: colorScheme,
          );
        },
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

/// 自定义代码块 —— 修复 gpt_markdown 自带 CodeField 在窄容器下
/// 头部 Row 溢出（language 名过长 + Copy 按钮）的问题。
class _SafeCodeField extends StatefulWidget {
  final String name;
  final String codes;
  final ColorScheme colorScheme;

  const _SafeCodeField({
    required this.name,
    required this.codes,
    required this.colorScheme,
  });

  @override
  State<_SafeCodeField> createState() => _SafeCodeFieldState();
}

class _SafeCodeFieldState extends State<_SafeCodeField> {
  bool _copied = false;
  bool _showPreview = false;

  /// 是否为可预览的 HTML 代码块
  bool get _isHtml {
    final lang = widget.name.toLowerCase().trim();
    if (lang != 'html' && lang != 'htm') return false;
    final code = widget.codes.trim();
    return code.contains('<') && (code.contains('</') || code.contains('/>'));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final s = context.s;

    return Material(
      color: widget.colorScheme.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 语言标签
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8,
                  ),
                  child: Text(
                    widget.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              // HTML 预览切换按钮
              if (_isHtml) ...[
                _ToggleButton(
                  icon: Icons.code,
                  label: s.codeSource,
                  active: !_showPreview,
                  onTap: () => setState(() => _showPreview = false),
                  colorScheme: widget.colorScheme,
                ),
                _ToggleButton(
                  icon: Icons.visibility,
                  label: s.codePreview,
                  active: _showPreview,
                  onTap: () => setState(() => _showPreview = true),
                  colorScheme: widget.colorScheme,
                ),
                const SizedBox(width: 8),
              ],
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: widget.colorScheme.onSurface,
                  textStyle: const TextStyle(fontWeight: FontWeight.normal),
                ),
                onPressed: () => _copy(),
                icon: Icon(
                  (_copied) ? Icons.done : Icons.content_paste,
                  size: 15,
                ),
                label: Text((_copied) ? 'Copied!' : 'Copy code'),
              ),
            ],
          ),
          const Divider(height: 1),
          if (_showPreview && _isHtml)
            _HtmlPreview(html: widget.codes, colorScheme: widget.colorScheme)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              child: _buildHighlightedCode(theme),
            ),
        ],
      ),
    );
  }

  /// 构建语法高亮的代码 widget。
  /// 如果语言无法识别则 fallback 到自动检测或纯文本。
  Widget _buildHighlightedCode(Map<String, TextStyle> theme) {
    final language = widget.name.toLowerCase().trim();
    final defaultStyle =
        theme['root'] ??
        const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13);

    try {
      // 尝试使用指定语言解析；空字符串则自动检测
      final result = language.isNotEmpty
          ? highlight.parse(widget.codes, language: language)
          : highlight.parse(widget.codes, autoDetection: true);

      final spans = _buildSpans(result.nodes ?? [], theme, defaultStyle);
      return RichText(
        text: TextSpan(style: defaultStyle, children: spans),
      );
    } catch (_) {
      // 解析失败时 fallback 到纯文本
      return Text(widget.codes, style: defaultStyle);
    }
  }

  /// 递归遍历 highlight.js 的节点树，构建 TextSpan 列表。
  List<TextSpan> _buildSpans(
    List<Node> nodes,
    Map<String, TextStyle> theme,
    TextStyle defaultStyle,
  ) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        // 文本叶子节点
        spans.add(
          TextSpan(
            text: node.value,
            style: node.className != null
                ? theme[node.className] ?? defaultStyle
                : defaultStyle,
          ),
        );
      } else if (node.children != null) {
        // 嵌套节点
        final childStyle = node.className != null
            ? theme[node.className] ?? defaultStyle
            : defaultStyle;
        spans.add(
          TextSpan(
            style: childStyle,
            children: _buildSpans(node.children!, theme, defaultStyle),
          ),
        );
      }
    }
    return spans;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.codes));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }
}

/// 源代码/预览 切换小按钮
class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// HTML 内嵌 WebView 预览组件
class _HtmlPreview extends StatefulWidget {
  final String html;
  final ColorScheme colorScheme;

  const _HtmlPreview({required this.html, required this.colorScheme});

  @override
  State<_HtmlPreview> createState() => _HtmlPreviewState();
}

class _HtmlPreviewState extends State<_HtmlPreview> {
  final _controller = wv.WebviewController();
  bool _ready = false;
  bool _failed = false;
  double _height = 450;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      // 安全设置：禁止新窗口弹出、禁止导航离开
      _controller.setPopupWindowPolicy(wv.WebviewPopupWindowPolicy.deny);

      // 加载 HTML 内容
      await _controller.loadStringContent(widget.html);

      // 延迟获取页面高度实现自适应
      Future.delayed(const Duration(milliseconds: 800), _adjustHeight);

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 通过 JS 获取实际内容高度，自适应调整
  Future<void> _adjustHeight() async {
    if (!_ready || !mounted) return;
    try {
      final result = await _controller.executeScript(
        'Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)',
      );
      final h = double.tryParse(result?.toString() ?? '');
      if (h != null && h > 0 && mounted) {
        setState(() => _height = h.clamp(200, 600).toDouble());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: widget.colorScheme.error,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'WebView2 不可用，请安装 Microsoft Edge WebView2 Runtime',
              style: TextStyle(color: widget.colorScheme.error, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (!_ready) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.colorScheme.primary,
          ),
        ),
      );
    }

    return SizedBox(
      height: _height,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        child: wv.Webview(_controller),
      ),
    );
  }
}

/// Markdown 内联图片渲染：支持 http(s) / 本地文件路径 / file: URL。
class _MarkdownImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final ColorScheme colorScheme;

  const _MarkdownImage({
    required this.url,
    required this.width,
    required this.height,
    required this.colorScheme,
  });

  /// 解析出本地文件路径（网络图片返回 null）
  String? get _localPath {
    if (url.startsWith('http://') || url.startsWith('https://')) return null;
    return url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      image = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => _error(),
        loadingBuilder: (c, child, progress) {
          if (progress == null) return child;
          return _loading();
        },
      );
    } else {
      final path = _localPath!;
      final file = File(path);
      if (!file.existsSync()) {
        image = _error();
      } else {
        image = Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => _error(),
        );
      }
    }

    return GestureDetector(
      onTap: () => _showPreview(context),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360, maxWidth: 480),
            child: image,
          ),
        ),
      ),
    );
  }

  /// 点击 → 全屏预览
  void _showPreview(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _MarkdownImagePreview(
        url: url,
        localPath: _localPath,
        colorScheme: colorScheme,
      ),
    );
  }

  /// 右键 → 上下文菜单（另存为 / 复制路径）
  void _showContextMenu(BuildContext context, Offset position) {
    final s = context.s;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              const Icon(Icons.save_alt, size: 18),
              const SizedBox(width: 8),
              Text(s.imgSaveAs),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 18),
              const SizedBox(width: 8),
              Text(s.imgCopyPath),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_external',
          child: Row(
            children: [
              const Icon(Icons.open_in_new, size: 18),
              const SizedBox(width: 8),
              Text(s.imgOpenExternal),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      switch (value) {
        case 'save':
          _saveAs(context);
        case 'copy_path':
          _copyPath(context);
        case 'open_external':
          _openExternal();
      }
    });
  }

  /// 另存为 → 用户选择目标位置
  Future<void> _saveAs(BuildContext context) async {
    // 在任何 await 之前捕获本地化文案，避免跨 async gap 使用 context
    final saveAsTitle = context.s.imgSaveAs;
    try {
      Uint8List bytes;
      String defaultName;

      if (_localPath != null) {
        final file = File(_localPath!);
        if (!file.existsSync()) return;
        bytes = await file.readAsBytes();
        defaultName = p.basename(_localPath!);
      } else {
        // 网络图片 → 下载到内存
        final resp = await Dio().get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(resp.data!);
        defaultName = p.basename(Uri.parse(url).path);
        if (!defaultName.contains('.')) defaultName = 'image.png';
      }

      final result = await FilePicker.platform.saveFile(
        dialogTitle: saveAsTitle,
        fileName: defaultName,
        type: FileType.image,
      );

      if (result != null) {
        await File(result).writeAsBytes(bytes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.s.imgSaved),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  /// 复制路径/URL 到剪贴板
  void _copyPath(BuildContext context) {
    final text = _localPath ?? url;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.imgPathCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 用系统默认应用打开
  void _openExternal() {
    if (_localPath != null) {
      Process.run('explorer', ['/select,', _localPath!]);
    } else {
      launchUrl(Uri.parse(url));
    }
  }

  Widget _loading() => SizedBox(
    width: 80,
    height: 80,
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      ),
    ),
  );

  Widget _error() => Container(
    width: 120,
    height: 80,
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.broken_image_outlined, color: colorScheme.outline),
  );
}

/// Markdown 图片全屏预览 Dialog（可缩放 + 另存为 + 系统打开）
class _MarkdownImagePreview extends StatelessWidget {
  final String url;
  final String? localPath;
  final ColorScheme colorScheme;

  const _MarkdownImagePreview({
    required this.url,
    required this.localPath,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (localPath != null) {
      image = Image.file(File(localPath!));
    } else {
      image = Image.network(url);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: InteractiveViewer(maxScale: 8, child: Center(child: image)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.s.imgSaveAs,
                    icon: const Icon(
                      Icons.save_alt,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      // 复用 _MarkdownImage 的保存逻辑
                      _MarkdownImage(
                        url: url,
                        width: null,
                        height: null,
                        colorScheme: colorScheme,
                      )._saveAs(context);
                    },
                  ),
                  IconButton(
                    tooltip: context.s.imgOpenExternal,
                    icon: const Icon(
                      Icons.open_in_new,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () {
                      if (localPath != null) {
                        Process.run('explorer', ['/select,', localPath!]);
                      } else {
                        launchUrl(Uri.parse(url));
                      }
                    },
                  ),
                  IconButton(
                    tooltip: context.s.commonClose,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义右键菜单 — 在默认操作基础上加入"向小猫提问"
///
/// 不再依赖 onSelectionChanged 跟踪选中文本（会触发 ConcurrentModificationError），
/// 而是在用户点击菜单项时通过 clipboard 获取选中内容。
class _PetContextMenu extends StatelessWidget {
  final SelectableRegionState selectableRegionState;

  const _PetContextMenu({required this.selectableRegionState});

  @override
  Widget build(BuildContext context) {
    // 默认按钮
    final defaultButtons = selectableRegionState.contextMenuButtonItems;

    // 找到 Copy 按钮的 onPressed，用来将选中内容放入剪贴板
    final copyButton = defaultButtons.where(
      (b) => b.type == ContextMenuButtonType.copy,
    );

    // 上下文菜单只在有选中文本时才出现，所以始终追加"向小猫提问"
    final petButtons = PetChatService.instance.allAskModes.map((mode) {
      return ContextMenuButtonItem(
        label: context.s.petBubbleFeedSelected(mode.label),
        onPressed: () {
          // 触发 Copy 行为将选中内容放入剪贴板
          if (copyButton.isNotEmpty) {
            copyButton.first.onPressed?.call();
          }
          ContextMenuController.removeAny();
          // 从剪贴板读取选中的文本
          Clipboard.getData('text/plain').then((data) {
            final text = data?.text ?? '';
            if (text.isNotEmpty) {
              PetChatService.instance.ask(text, mode);
            }
          });
        },
      );
    }).toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: [...defaultButtons, ...petButtons],
    );
  }
}

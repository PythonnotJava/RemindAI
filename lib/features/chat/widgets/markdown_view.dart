import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:url_launcher/url_launcher.dart';

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
      final isCustom = CustomFontLoader.instance.loadedFonts.contains(fontFamily);
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
        return _PetContextMenu(
          selectableRegionState: selectableRegionState,
        );
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    return Material(
      color: widget.colorScheme.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 关键改动：Flexible + ellipsis，避免长 language 名撑爆宽度
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
      // 本地路径或 file: URL
      final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360, maxWidth: 480),
        child: image,
      ),
    );
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

/// 自定义右键菜单 — 在默认操作基础上加入"向小猫提问"
///
/// 不再依赖 onSelectionChanged 跟踪选中文本（会触发 ConcurrentModificationError），
/// 而是在用户点击菜单项时通过 clipboard 获取选中内容。
class _PetContextMenu extends StatelessWidget {
  final SelectableRegionState selectableRegionState;

  const _PetContextMenu({
    required this.selectableRegionState,
  });

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

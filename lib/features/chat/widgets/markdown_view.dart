import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:url_launcher/url_launcher.dart';

/// 统一的 Markdown 渲染组件（基于 gpt_markdown）。
///
/// 相比 flutter_markdown：对 AI 流式输出更鲁棒（未闭合的代码块/标记不会整体不渲染），
/// 内置 LaTeX、表格、任务列表，并支持图片与链接的自定义处理。
class MarkdownView extends StatelessWidget {
  final String data;
  final Color textColor;

  const MarkdownView({super.key, required this.data, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SelectionArea(
      child: GptMarkdown(
        data,
        style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
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

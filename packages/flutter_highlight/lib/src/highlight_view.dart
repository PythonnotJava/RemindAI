import 'package:flutter/material.dart';
import 'package:highlight/highlight_core.dart'
    show Highlight, HighlightResult, HljsTheme;

import 'line_number_gutter.dart';
import 'text_span_builder.dart';
import 'theme_map.dart';

/// A widget that renders syntax-highlighted source code using the highlight
/// engine and a theme map.
///
/// Uses [SelectableText.rich] so the rendered code is selectable and copyable.
/// Long lines scroll horizontally via a [SingleChildScrollView].
///
/// The built [TextSpan] is memoised: rebuilding with the same `code`,
/// `language`, `theme` and `textStyle` reuses the previous span instead of
/// re-running the highlight engine. That matters in chat UIs, where a
/// streaming message rebuilds every frame while most of an already-finished
/// code block never changes.
class HighlightView extends StatefulWidget {
  /// Source code to highlight.
  final String code;

  /// Language identifier (e.g. `'dart'`, `'python'`).
  /// If `null`, auto-detection is used.
  final String? language;

  /// Theme for syntax highlighting. Keys are scope names, values are
  /// `HljsStyle` instances with typed properties (color, bold, italic, etc.).
  final HljsTheme theme;

  /// Base text style applied to all code text (font family, size, height).
  final TextStyle? textStyle;

  /// Padding inside the code block container.
  final EdgeInsets? padding;

  /// Whether to show line numbers in a gutter on the left.
  final bool showLineNumbers;

  /// The number to display on the first line (default: 1).
  final int firstLineNumber;

  /// Style for line number text. Falls back to a dimmed version of the base
  /// text style if not provided.
  final TextStyle? lineNumberStyle;

  /// Highlight engine instance. When `null`, a fresh instance is used.
  /// Callers are responsible for registering languages on the engine before
  /// passing it in.
  final Highlight? highlighter;

  const HighlightView(
    this.code, {
    super.key,
    this.language,
    required this.theme,
    this.textStyle,
    this.padding,
    this.showLineNumbers = false,
    this.firstLineNumber = 1,
    this.lineNumberStyle,
    this.highlighter,
  });

  @override
  State<HighlightView> createState() => _HighlightViewState();
}

class _HighlightViewState extends State<HighlightView> {
  /// Memoised highlight result. `null` until the first build.
  TextSpan? _cachedSpan;

  // 缓存键：只有这四个输入全都没变时才能复用已解析的 span。
  // theme / textStyle 用 identical 比对——主题通常是顶层 const map，
  // 身份稳定；调用方若每帧新建主题对象，这里只是少一次命中，不会串色。
  String? _cachedCode;
  String? _cachedLanguage;
  HljsTheme? _cachedTheme;
  TextStyle? _cachedTextStyle;

  @override
  void didUpdateWidget(covariant HighlightView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换引擎（注册了别的语言）时旧 span 的解析结果不再可信。
    if (!identical(oldWidget.highlighter, widget.highlighter)) {
      _cachedSpan = null;
    }
  }

  bool get _cacheHit =>
      _cachedSpan != null &&
      _cachedCode == widget.code &&
      _cachedLanguage == widget.language &&
      identical(_cachedTheme, widget.theme) &&
      identical(_cachedTextStyle, widget.textStyle);

  @override
  Widget build(BuildContext context) {
    final themeMap = ThemeMap(widget.theme);

    final baseStyle = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.5,
    ).merge(widget.textStyle);

    if (!_cacheHit) {
      _cachedSpan = _buildSpan(themeMap, baseStyle);
      _cachedCode = widget.code;
      _cachedLanguage = widget.language;
      _cachedTheme = widget.theme;
      _cachedTextStyle = widget.textStyle;
    }
    final span = _cachedSpan!;
    final lineCount = '\n'.allMatches(widget.code).length + 1;

    final effectiveLineNumberStyle =
        widget.lineNumberStyle ??
        baseStyle.copyWith(
          color: (themeMap.rootStyle.color ?? const Color(0xFF888888))
              .withAlpha(128),
        );

    final Widget codeWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText.rich(
        span,
        style: baseStyle.merge(themeMap.rootStyle),
      ),
    );

    final Widget body;
    if (widget.showLineNumbers) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineNumberGutter(
            lineCount: lineCount,
            firstLineNumber: widget.firstLineNumber,
            style: effectiveLineNumberStyle,
            lineHeight: baseStyle.height,
          ),
          Expanded(child: codeWidget),
        ],
      );
    } else {
      body = codeWidget;
    }

    return Container(
      color: themeMap.backgroundColor,
      padding: widget.padding ?? const EdgeInsets.all(16),
      width: double.infinity,
      child: body,
    );
  }

  TextSpan _buildSpan(ThemeMap themeMap, TextStyle baseStyle) {
    final hl = widget.highlighter ?? Highlight();
    HighlightResult result;
    if (widget.language != null) {
      result = hl.highlight(widget.code, language: widget.language!);
    } else {
      result = hl.highlightAuto(widget.code);
    }

    final builder = TextSpanBuilder(themeMap: themeMap, baseStyle: baseStyle);
    return builder.build(result.emitter.rootNode);
  }
}

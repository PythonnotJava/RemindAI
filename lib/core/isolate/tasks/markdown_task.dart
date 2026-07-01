// Markdown 解析任务 — 在 Isolate 中执行重量级的 markdown 预处理。
//
// 适用场景:
// - 长消息 (>2000字符) 的流式渲染结束后的最终解析
// - 历史消息批量加载时的预解析
// - 代码块提取与语言检测

/// Markdown 预处理结果
class MarkdownPreprocessResult {
  /// 原始文本
  final String raw;

  /// 提取的代码块列表 [(language, code, startLine, endLine)]
  final List<CodeBlockInfo> codeBlocks;

  /// 纯文本段落（去除代码块后）
  final List<String> textSegments;

  /// 预估的渲染复杂度 (用于决定是否需要分段渲染)
  final int complexity;

  /// 是否包含数学公式
  final bool hasMath;

  /// 是否包含表格
  final bool hasTable;

  MarkdownPreprocessResult({
    required this.raw,
    required this.codeBlocks,
    required this.textSegments,
    required this.complexity,
    required this.hasMath,
    required this.hasTable,
  });
}

/// 代码块信息
class CodeBlockInfo {
  final String language;
  final String code;
  final int startOffset;
  final int endOffset;

  CodeBlockInfo({
    required this.language,
    required this.code,
    required this.startOffset,
    required this.endOffset,
  });
}

/// 顶层函数: Markdown 预处理（可传入 Isolate）
///
/// 提取代码块、检测特殊内容（公式/表格）、计算渲染复杂度。
/// 这些信息可以帮助 UI 层决定渲染策略（懒加载、分段等）。
MarkdownPreprocessResult markdownPreprocessTask(String markdown) {
  final codeBlocks = <CodeBlockInfo>[];
  final textSegments = <String>[];

  // 提取代码块
  final codeBlockRegex = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
  int lastEnd = 0;

  for (final match in codeBlockRegex.allMatches(markdown)) {
    // 代码块前的文本
    if (match.start > lastEnd) {
      textSegments.add(markdown.substring(lastEnd, match.start));
    }
    codeBlocks.add(
      CodeBlockInfo(
        language: match.group(1) ?? '',
        code: match.group(2) ?? '',
        startOffset: match.start,
        endOffset: match.end,
      ),
    );
    lastEnd = match.end;
  }
  // 最后一段文本
  if (lastEnd < markdown.length) {
    textSegments.add(markdown.substring(lastEnd));
  }

  // 检测特殊内容
  final hasMath =
      markdown.contains(r'$$') ||
      markdown.contains(r'\(') ||
      markdown.contains(r'\[') ||
      RegExp(r'\$[^$]+\$').hasMatch(markdown);

  final hasTable = RegExp(r'\|.*\|.*\|').hasMatch(markdown);

  // 计算渲染复杂度
  int complexity = 0;
  complexity += markdown.length ~/ 100; // 基础：每100字符 +1
  complexity += codeBlocks.length * 10; // 代码块权重
  if (hasMath) complexity += 20; // 数学公式权重
  if (hasTable) complexity += 15; // 表格权重
  complexity += markdown.split('\n').length ~/ 10; // 行数权重

  return MarkdownPreprocessResult(
    raw: markdown,
    codeBlocks: codeBlocks,
    textSegments: textSegments,
    complexity: complexity,
    hasMath: hasMath,
    hasTable: hasTable,
  );
}

/// 批量 Markdown 预处理（加载历史消息时使用）
List<MarkdownPreprocessResult> markdownBatchPreprocessTask(
  List<String> markdowns,
) {
  return markdowns.map(markdownPreprocessTask).toList();
}

/// Markdown 内容分段（用于超长消息的分段渲染）
///
/// 将超长 markdown 按逻辑边界（标题/空行/代码块结束）切割为合理段落，
/// 每段独立渲染，避免单次 build 耗时过长。
List<String> markdownSplitTask(MarkdownSplitParam param) {
  final markdown = param.markdown;
  final maxSegmentLength = param.maxSegmentLength;

  if (markdown.length <= maxSegmentLength) {
    return [markdown];
  }

  final segments = <String>[];
  final lines = markdown.split('\n');
  final buffer = StringBuffer();

  for (final line in lines) {
    // 在标题行或超长时切割
    if (buffer.length > maxSegmentLength &&
        (line.startsWith('#') || line.trim().isEmpty)) {
      segments.add(buffer.toString());
      buffer.clear();
    }
    buffer.writeln(line);
  }
  if (buffer.isNotEmpty) {
    segments.add(buffer.toString());
  }

  return segments;
}

/// Markdown 分段参数
class MarkdownSplitParam {
  final String markdown;
  final int maxSegmentLength;

  MarkdownSplitParam({required this.markdown, this.maxSegmentLength = 3000});
}

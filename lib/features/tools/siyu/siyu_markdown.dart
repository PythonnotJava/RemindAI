import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Markdown → Quill Document
Document markdownToDocument(String markdown) {
  final delta = Delta();
  final lines = markdown.split('\n');
  var inCodeBlock = false;
  final codeBuffer = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // 代码块
    if (line.startsWith('```')) {
      if (inCodeBlock) {
        // 结束代码块
        final code = codeBuffer.toString();
        if (code.isNotEmpty) {
          for (final codeLine in code.split('\n')) {
            delta.insert(codeLine);
            delta.insert('\n', {'code-block': true});
          }
        }
        codeBuffer.clear();
        inCodeBlock = false;
      } else {
        inCodeBlock = true;
      }
      continue;
    }

    if (inCodeBlock) {
      if (codeBuffer.isNotEmpty) codeBuffer.write('\n');
      codeBuffer.write(line);
      continue;
    }

    // 空行
    if (line.trim().isEmpty) {
      delta.insert('\n');
      continue;
    }

    // 图片 ![alt](path)
    final imgMatch = RegExp(r'!\[.*?\]\((.+?)\)').firstMatch(line);
    if (imgMatch != null) {
      delta.insert({'image': imgMatch.group(1)!});
      delta.insert('\n');
      continue;
    }

    // 标题
    final headerMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
    if (headerMatch != null) {
      final level = headerMatch.group(1)!.length;
      final text = headerMatch.group(2)!;
      _insertInlineMarkdown(delta, text);
      delta.insert('\n', {'header': level});
      continue;
    }

    // 无序列表
    final ulMatch = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line);
    if (ulMatch != null) {
      _insertInlineMarkdown(delta, ulMatch.group(1)!);
      delta.insert('\n', {'list': 'bullet'});
      continue;
    }

    // 有序列表
    final olMatch = RegExp(r'^\d+\.\s+(.+)$').firstMatch(line);
    if (olMatch != null) {
      _insertInlineMarkdown(delta, olMatch.group(1)!);
      delta.insert('\n', {'list': 'ordered'});
      continue;
    }

    // 引用
    final quoteMatch = RegExp(r'^>\s*(.*)$').firstMatch(line);
    if (quoteMatch != null) {
      _insertInlineMarkdown(delta, quoteMatch.group(1)!);
      delta.insert('\n', {'blockquote': true});
      continue;
    }

    // 分隔线
    if (RegExp(r'^---+$').hasMatch(line.trim())) {
      delta.insert({'divider': true});
      delta.insert('\n');
      continue;
    }

    // 普通段落
    _insertInlineMarkdown(delta, line);
    delta.insert('\n');
  }

  // 未关闭的代码块
  if (inCodeBlock && codeBuffer.isNotEmpty) {
    for (final codeLine in codeBuffer.toString().split('\n')) {
      delta.insert(codeLine);
      delta.insert('\n', {'code-block': true});
    }
  }

  // 确保文档以换行结尾
  if (delta.isEmpty) {
    delta.insert('\n');
  }

  return Document.fromDelta(delta);
}

/// 解析行内 Markdown 格式（粗体、斜体、行内代码、链接）
void _insertInlineMarkdown(Delta delta, String text) {
  // 匹配: **bold**, *italic*, `code`, [text](url)
  final pattern = RegExp(
    r'(\*\*(.+?)\*\*)' // 粗体
    r'|(\*(.+?)\*)' // 斜体
    r'|(`(.+?)`)' // 行内代码
    r'|(\[(.+?)\]\((.+?)\))', // 链接
  );

  var lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    // 插入匹配前的普通文本
    if (match.start > lastEnd) {
      delta.insert(text.substring(lastEnd, match.start));
    }

    if (match.group(2) != null) {
      // 粗体
      delta.insert(match.group(2)!, {'bold': true});
    } else if (match.group(4) != null) {
      // 斜体
      delta.insert(match.group(4)!, {'italic': true});
    } else if (match.group(6) != null) {
      // 行内代码
      delta.insert(match.group(6)!, {'code': true});
    } else if (match.group(8) != null) {
      // 链接
      delta.insert(match.group(8)!, {'link': match.group(9)!});
    }

    lastEnd = match.end;
  }

  // 剩余文本
  if (lastEnd < text.length) {
    delta.insert(text.substring(lastEnd));
  }
  // 如果整个文本为空，不插入任何内容
}

/// Quill Document → Markdown
String documentToMarkdown(Document doc) {
  final buf = StringBuffer();
  final delta = doc.toDelta();
  final ops = delta.toList();

  var i = 0;
  while (i < ops.length) {
    final op = ops[i];

    if (!op.isInsert) {
      i++;
      continue;
    }

    // 嵌入（图片等）
    if (op.data is Map) {
      final embed = op.data as Map;
      if (embed.containsKey('image')) {
        buf.writeln('![image](${embed['image']})');
        buf.writeln();
      } else if (embed.containsKey('divider')) {
        buf.writeln('---');
        buf.writeln();
      }
      i++;
      continue;
    }

    // 文本插入
    final text = op.data as String;
    final attrs = op.attributes;

    if (text == '\n' && attrs != null) {
      // 块级格式（应用到前面收集的行文本上）
      // 这种情况在正常遍历中处理
      buf.writeln();
      i++;
      continue;
    }

    // 收集一整行：从当前 op 到下一个 \n
    final lineOps = <Operation>[];
    Map<String, dynamic>? lineAttrs;
    var j = i;

    while (j < ops.length) {
      final curr = ops[j];
      if (!curr.isInsert) {
        j++;
        continue;
      }

      if (curr.data is Map) {
        // 嵌入，结束当前行收集
        break;
      }

      final currText = curr.data as String;
      final nlIndex = currText.indexOf('\n');

      if (nlIndex == -1) {
        lineOps.add(curr);
        j++;
      } else {
        // 换行前的部分
        if (nlIndex > 0) {
          lineOps.add(
            Operation.insert(currText.substring(0, nlIndex), curr.attributes),
          );
        }
        // 换行符可能带块属性
        lineAttrs = curr.attributes;
        // 检查是否换行符本身就是下一个 op
        if (nlIndex == 0 && currText.length == 1) {
          lineAttrs = curr.attributes;
          j++;
        } else if (nlIndex < currText.length - 1) {
          // 换行后还有剩余文本，需要拆分（但不前进 j，留到下轮）
          // 实际上 Quill 通常在换行处分割 op，这里做保护
          ops[j] = Operation.insert(
            currText.substring(nlIndex + 1),
            curr.attributes,
          );
        } else {
          j++;
        }
        break;
      }
    }

    // 构建行内文本
    final lineBuf = StringBuffer();
    for (final lop in lineOps) {
      final t = lop.data as String;
      final a = lop.attributes;
      if (a != null && a.containsKey('bold') && a['bold'] == true) {
        lineBuf.write('**$t**');
      } else if (a != null && a.containsKey('italic') && a['italic'] == true) {
        lineBuf.write('*$t*');
      } else if (a != null && a.containsKey('code') && a['code'] == true) {
        lineBuf.write('`$t`');
      } else if (a != null && a.containsKey('link')) {
        lineBuf.write('[$t](${a['link']})');
      } else {
        lineBuf.write(t);
      }
    }

    final lineText = lineBuf.toString();

    // 应用块级格式
    if (lineAttrs != null) {
      if (lineAttrs.containsKey('header')) {
        final level = lineAttrs['header'] as int;
        buf.writeln('${'#' * level} $lineText');
      } else if (lineAttrs.containsKey('list')) {
        final type = lineAttrs['list'];
        if (type == 'bullet') {
          buf.writeln('- $lineText');
        } else {
          buf.writeln('1. $lineText');
        }
      } else if (lineAttrs.containsKey('blockquote')) {
        buf.writeln('> $lineText');
      } else if (lineAttrs.containsKey('code-block')) {
        // 代码块需要特殊处理 - 先收集所有连续代码行
        buf.writeln('```');
        buf.writeln(lineText);
        // 往后看是否有更多代码行
        while (j < ops.length) {
          final next = ops[j];
          if (!next.isInsert || next.data is Map) break;
          final nextText = next.data as String;
          final nextNl = nextText.indexOf('\n');
          if (nextNl == -1) {
            j++;
            continue;
          }
          // 检查换行属性
          final nextAttrs = next.attributes;
          if (nextAttrs != null && nextAttrs.containsKey('code-block')) {
            if (nextNl > 0) {
              buf.writeln(nextText.substring(0, nextNl));
            } else {
              buf.writeln('');
            }
            if (nextNl < nextText.length - 1) {
              ops[j] = Operation.insert(nextText.substring(nextNl + 1), null);
            } else {
              j++;
            }
          } else {
            break;
          }
        }
        buf.writeln('```');
      } else {
        buf.writeln(lineText);
      }
    } else {
      if (lineText.isNotEmpty) buf.writeln(lineText);
      if (lineText.isEmpty && lineOps.isEmpty) buf.writeln();
    }

    i = j;
  }

  return buf.toString().trimRight();
}

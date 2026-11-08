import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../chat_provider.dart';

/// 工具调用卡片组件
class ToolCallCard extends StatefulWidget {
  final ToolCallDisplay toolCall;

  const ToolCallCard({super.key, required this.toolCall});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tc = widget.toolCall;

    final (icon, color) = _getIconAndColor(tc.name, colorScheme);
    final imagePath = _imagePathFromResult(tc.result);
    final warning = _warningFromResult(tc.result);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatToolName(tc.name),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      _buildStatusBadge(tc.status, context, colorScheme),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  // 画图结果预览（子 Agent 生成图片后实时展示）
                  if (imagePath != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => OpenFilex.open(imagePath),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 220,
                            maxWidth: 320,
                          ),
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Text(
                              '图片加载失败: $imagePath',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (warning != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      warning,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.tertiary,
                      ),
                    ),
                  ],
                  // Expanded content
                  if (_expanded) ...[
                    const SizedBox(height: 10),
                    _buildSection(
                      context.s.toolCardArgs,
                      _prettyJson(tc.arguments),
                      colorScheme,
                    ),
                    if (tc.result != null) ...[
                      const SizedBox(height: 8),
                      _buildSection(
                        context.s.toolCardResult,
                        _prettyJson(_tryParseJson(tc.result!)),
                        colorScheme,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    ToolCallStatus status,
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final (label, badgeColor) = switch (status) {
      ToolCallStatus.executing => (
        context.s.toolCardExecuting,
        colorScheme.tertiary,
      ),
      ToolCallStatus.done => (context.s.toolCardDone, Colors.green),
      ToolCallStatus.error => (context.s.toolCardError, colorScheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ToolCallStatus.executing)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: badgeColor,
              ),
            )
          else
            Icon(
              status == ToolCallStatus.done ? Icons.check_circle : Icons.error,
              size: 12,
              color: badgeColor,
            ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: badgeColor)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  (IconData, Color) _getIconAndColor(String name, ColorScheme colorScheme) {
    if (name.contains('image')) {
      return (Icons.auto_awesome, Colors.pink);
    } else if (name.contains('exec')) {
      return (Icons.terminal, Colors.blue);
    } else if (name.contains('memory')) {
      return (Icons.psychology, Colors.purple);
    } else if (name.contains('read')) {
      return (Icons.description, Colors.teal);
    } else if (name.contains('write')) {
      return (Icons.edit_note, Colors.orange);
    } else if (name.contains('delete')) {
      return (Icons.delete_outline, Colors.red);
    } else if (name.contains('search')) {
      return (Icons.search, Colors.green);
    }
    return (Icons.build, colorScheme.primary);
  }

  /// 从工具结果 JSON 中取出图片路径（画图子 Agent 的返回）。
  String? _imagePathFromResult(String? raw) {
    final map = _resultMap(raw);
    if (map == null) return null;
    final path = map['image_path'];
    if (path is String && path.isNotEmpty) return path;
    final files = map['image_files'];
    if (files is List && files.isNotEmpty && files.first is String) {
      return files.first as String;
    }
    return null;
  }

  /// 子模型失败后主模型兜底的提示。
  String? _warningFromResult(String? raw) {
    final warning = _resultMap(raw)?['warning'];
    return warning is String && warning.isNotEmpty ? warning : null;
  }

  Map<String, dynamic>? _resultMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String _formatToolName(String name) {
    return name.replaceAll('toolshell_', '').replaceAll('_', ' ').toUpperCase();
  }

  String _prettyJson(dynamic data) {
    if (data is Map || data is List) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    }
    return data.toString();
  }

  dynamic _tryParseJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }
}

import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/tools/tool_plugin.dart';
import 'siyu_editor.dart';

/// 思宇 - 富文本编辑器
class SiyuTool extends ToolPlugin {
  @override
  String get id => 'siyu';

  @override
  String get name => '思宇';

  @override
  IconData get icon => Icons.edit_document;

  @override
  String get description => '富文本文档编辑器，支持图片、格式、导出';

  @override
  String get category => '创作';

  @override
  String localizedName(BuildContext context) => context.s.siyuToolName;

  @override
  String localizedDescription(BuildContext context) => context.s.siyuToolDesc;

  @override
  String localizedCategory(BuildContext context) => context.s.siyuToolCategory;

  @override
  Widget buildUI(BuildContext context, ToolConfig config) {
    return const SiyuEditorPage();
  }
}

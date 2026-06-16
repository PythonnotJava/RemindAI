import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/tools/tool_plugin.dart';
import 'vpl_editor.dart';

/// VPL (Visual Programming Language) 可视化编程工具
class VplTool extends ToolPlugin {
  @override
  String get id => 'vpl';

  @override
  String get name => '可视化编程';

  @override
  IconData get icon => Icons.account_tree_outlined;

  @override
  String get description => '节点式流程编辑器，拖拽构建程序逻辑';

  @override
  String get category => '开发';

  @override
  String localizedName(BuildContext context) => context.s.vplToolName;

  @override
  String localizedDescription(BuildContext context) => context.s.vplToolDesc;

  @override
  String localizedCategory(BuildContext context) => context.s.vplToolCategory;

  @override
  Widget buildUI(BuildContext context, ToolConfig config) {
    return const VplEditorPage();
  }
}

import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/tools/tool_plugin.dart';
import 'flowchart_editor.dart';

/// 流程图工具 - Mermaid 风格可视化图表编辑器
class FlowchartTool extends ToolPlugin {
  @override
  String get id => 'flowchart';

  @override
  String get name => '流程图';

  @override
  IconData get icon => Icons.schema_outlined;

  @override
  String get description => '可视化流程图编辑，支持导出 Mermaid 语法';

  @override
  String get category => '开发';

  @override
  String localizedName(BuildContext context) => context.s.fcToolName;

  @override
  String localizedDescription(BuildContext context) => context.s.fcToolDesc;

  @override
  String localizedCategory(BuildContext context) => context.s.fcToolCategory;

  @override
  Widget buildUI(BuildContext context, ToolConfig config) {
    return const FlowchartEditorPage();
  }
}

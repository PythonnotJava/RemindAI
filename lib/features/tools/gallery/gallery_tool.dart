import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/tools/tool_config.dart';
import '../../../core/tools/tool_plugin.dart';
import 'gallery_viewer.dart';

/// Gallery - 星空特效展示
class GalleryTool extends ToolPlugin {
  @override
  String get id => 'gallery';

  @override
  String get name => 'Gallery';

  @override
  IconData get icon => Icons.auto_awesome;

  @override
  String get description => '星空特效展示与回忆';

  @override
  String get category => '创作';

  @override
  String localizedName(BuildContext context) => context.s.galleryToolName;

  @override
  String localizedDescription(BuildContext context) =>
      context.s.galleryToolDesc;

  @override
  String localizedCategory(BuildContext context) => context.s.siyuToolCategory; // 复用「创作」分类

  @override
  Widget buildUI(BuildContext context, ToolConfig config) {
    return const GalleryViewerPage();
  }
}

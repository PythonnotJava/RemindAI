import 'package:flutter/material.dart';
import 'tool_config.dart';

/// 工具基类 — 所有内置工具继承此类
abstract class ToolPlugin {
  /// 唯一标识
  String get id;

  /// 显示名称（fallback，优先使用 localizedName）
  String get name;

  /// 图标
  IconData get icon;

  /// 简短描述（fallback，优先使用 localizedDescription）
  String get description;

  /// 分类标签（fallback，优先使用 localizedCategory）
  String get category;

  /// 国际化显示名称（默认回退到 [name]）
  String localizedName(BuildContext context) => name;

  /// 国际化简短描述（默认回退到 [description]）
  String localizedDescription(BuildContext context) => description;

  /// 国际化分类标签（默认回退到 [category]）
  String localizedCategory(BuildContext context) => category;

  /// 永久配置字段声明
  List<ConfigField> get permanentFields => [];

  /// 临时配置字段声明（每次使用前可选填）
  List<ConfigField> get temporaryFields => [];

  /// 构建工具的主 UI（全屏面板）
  Widget buildUI(BuildContext context, ToolConfig config);

  /// 构建设置面板（编辑永久配置）
  Widget? buildSettings(
    BuildContext context,
    ToolConfig config,
    void Function(ToolConfig) onSave,
  ) => null;

  /// 生命周期：初始化
  Future<void> onInit(ToolConfig config) async {}

  /// 生命周期：销毁
  Future<void> onDispose() async {}
}

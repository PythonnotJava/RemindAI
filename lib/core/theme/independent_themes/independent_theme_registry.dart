import 'package:flutter/material.dart';
import 'last_twilight_theme.dart';

/// 独立主题元数据
class IndependentThemeMetadata {
  /// 主题ID（唯一标识符，用于设置保存）
  final String id;

  /// 主题名称（英文）
  final String nameEn;

  /// 主题名称（中文）
  final String nameZh;

  /// 主题描述
  final String description;

  /// 主题图标
  final IconData icon;

  /// 主题构建器（深色版）
  final ThemeData Function() buildDark;

  /// 主题构建器（浅色版，可选）
  final ThemeData Function()? buildLight;

  /// 是否支持明暗切换
  bool get supportsLightMode => buildLight != null;

  const IndependentThemeMetadata({
    required this.id,
    required this.nameEn,
    required this.nameZh,
    required this.description,
    required this.icon,
    required this.buildDark,
    this.buildLight,
  });

  /// 获取显示名称（根据语言环境）
  String getName(String languageCode) {
    return languageCode.startsWith('zh') ? nameZh : nameEn;
  }

  /// 构建主题
  ThemeData build(Brightness brightness) {
    if (brightness == Brightness.light && buildLight != null) {
      return buildLight!();
    }
    return buildDark();
  }
}

/// 独立主题注册表
///
/// 管理所有独立主题（如"最后的黄昏"、"赛博朋克"等）
/// 独立主题拥有完整的视觉设计，不依赖配色方案选择
class IndependentThemeRegistry {
  IndependentThemeRegistry._();

  /// 所有已注册的独立主题
  static final Map<String, IndependentThemeMetadata> _themes = {
    // 最后的黄昏
    LastTwilightTheme.id: IndependentThemeMetadata(
      id: LastTwilightTheme.id,
      nameEn: LastTwilightTheme.nameEn,
      nameZh: LastTwilightTheme.nameZh,
      description: LastTwilightTheme.description,
      icon: LastTwilightTheme.icon,
      buildDark: LastTwilightTheme.buildDark,
      buildLight: LastTwilightTheme.buildLight,
    ),

    // 未来可以添加更多独立主题：
    // 'cyberpunk': IndependentThemeMetadata(...),
    // 'neon_night': IndependentThemeMetadata(...),
    // 'aurora': IndependentThemeMetadata(...),
  };

  /// 获取所有独立主题
  static Map<String, IndependentThemeMetadata> get all =>
      Map.unmodifiable(_themes);

  /// 获取独立主题列表
  static List<IndependentThemeMetadata> get list => _themes.values.toList();

  /// 获取独立主题ID列表
  static List<String> get ids => _themes.keys.toList();

  /// 根据ID获取独立主题
  static IndependentThemeMetadata? getById(String id) => _themes[id];

  /// 检查是否为独立主题
  static bool isIndependentTheme(String id) => _themes.containsKey(id);

  /// 构建独立主题
  static ThemeData? buildTheme(String id, Brightness brightness) {
    final metadata = getById(id);
    return metadata?.build(brightness);
  }

  /// 注册新的独立主题（用于插件扩展）
  static void register(IndependentThemeMetadata metadata) {
    if (_themes.containsKey(metadata.id)) {
      throw ArgumentError('独立主题 ${metadata.id} 已存在');
    }
    _themes[metadata.id] = metadata;
  }

  /// 注销独立主题
  static void unregister(String id) {
    _themes.remove(id);
  }
}

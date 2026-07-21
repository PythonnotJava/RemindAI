import 'package:flutter/material.dart';

/// 最后的黄昏主题
///
/// 设计理念：落幕的美
/// - 橙红黄灰交织：真实夕阳的色彩层次
/// - 温暖的余晖：橙色和黄色的明亮光芒
/// - 深沉的暮色：红色和灰色的渐变过渡
/// - 宁静的氛围：灰色背景承托暖色光辉
/// - 色彩对比：冷暖交织，光影交错
class LastTwilightTheme {
  LastTwilightTheme._();

  /// 主题ID（用于设置保存）
  static const String id = 'last_twilight';

  /// 主题显示名称（英文）
  static const String nameEn = 'Afterglow';

  /// 主题显示名称（中文）
  static const String nameZh = '最后的黄昏';

  /// 主题描述
  static const String description = '温暖朦胧的独特主题，暮色渐变，落幕的美';

  /// 主题图标
  static const IconData icon = Icons.wb_twilight;

  // ==================== 核心色彩定义 ====================
  // 橙红黄灰交织的夕阳色谱

  /// 落日橙 - 地平线的主色调，明亮温暖
  static const Color _sunsetOrange = Color(0xFFFF8A65);

  /// 暮霞红 - 更深的红色暮光
  static const Color _twilightRed = Color(0xFFE57373);

  /// 余晖金黄 - 太阳最后的金光
  static const Color _sunsetGold = Color(0xFFFFD54F);

  /// 深灰紫 - 夜幕降临的灰紫色
  static const Color _duskGrayPurple = Color(0xFF757575);

  // ==================== 表面色彩（背景层次）====================
  // 灰色基调，融入暖色光晕

  /// 主表面 - 中灰带暖调
  static const Color _surfaceMain = Color(0xFF424242);

  /// 高层表面 - 浅灰暖调
  static const Color _surfaceHigh = Color(0xFF525252);

  /// 中层表面 - 中灰
  static const Color _surfaceMid = Color(0xFF484848);

  /// 低层表面 - 深灰
  static const Color _surfaceLow = Color(0xFF3A3A3A);

  /// 最低层表面 - 深灰紫
  static const Color _surfaceLowest = Color(0xFF303030);

  /// 背景 - 深沉的暮色灰
  static const Color _background = Color(0xFF2E2E2E);

  // ==================== 文字颜色 ====================

  /// 亮白色 - 主文字，像余晖中的明亮云层
  static const Color _textPrimary = Color(0xFFFAFAFA);

  /// 浅灰色 - 次要文字
  static const Color _textSecondary = Color(0xFFBDBDBD);

  /// 深灰色 - 深色文字（用于亮色背景）
  static const Color _textDark = Color(0xFF424242);

  // ==================== 边框颜色 ====================

  /// 中灰边框
  static const Color _outline = Color(0xFF757575);

  /// 深灰边框
  static const Color _outlineVariant = Color(0xFF616161);

  // ==================== 错误色 ====================

  /// 深红 - 错误色
  static const Color _error = Color(0xFFE53935);

  // ==================== 主题构建 ====================

  /// 构建深色主题（主要版本）
  static ThemeData buildDark() {
    final colorScheme = const ColorScheme.dark(
      // 主色调 - 落日橙，温暖明亮
      primary: _sunsetOrange,
      onPrimary: Colors.white,
      primaryContainer: _twilightRed,
      onPrimaryContainer: _textPrimary,

      // 次要色 - 暮霞红
      secondary: _twilightRed,
      onSecondary: Colors.white,
      secondaryContainer: _duskGrayPurple,
      onSecondaryContainer: _textPrimary,

      // 第三色 - 余晖金黄
      tertiary: _sunsetGold,
      onTertiary: _textDark,
      tertiaryContainer: Color(0xFFFFA726),
      onTertiaryContainer: _textPrimary,

      // 表面层次 - 灰色基调
      surface: _surfaceMain,
      onSurface: _textPrimary,
      surfaceContainerHighest: _surfaceHigh,
      surfaceContainer: _surfaceMid,
      surfaceContainerLow: _surfaceLow,
      surfaceContainerLowest: _surfaceLowest,
      onSurfaceVariant: _textSecondary,

      // 背景
      background: _background,
      onBackground: _textPrimary,

      // 错误
      error: _error,
      onError: Colors.white,
      errorContainer: Color(0xFF5D3030),
      onErrorContainer: Color(0xFFFFDAD6),

      // 边框
      outline: _outline,
      outlineVariant: _outlineVariant,

      // 其他
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: _textPrimary,
      inversePrimary: Color(0xFFFF6E40),
      surfaceTint: Color(0x10FFD54F), // 淡金色光泽
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,

      // 文本主题 - 怀旧质感
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.25,
          color: _textPrimary,
          height: 1.12,
        ),
        displayMedium: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          color: _textPrimary,
          height: 1.16,
        ),
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: _textPrimary,
          height: 1.22,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w400,
          color: _textPrimary,
          height: 1.25,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: _textPrimary,
          height: 1.29,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w400,
          color: _textPrimary,
          height: 1.33,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: _textPrimary,
          height: 1.27,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
          color: _textPrimary,
          height: 1.5,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: _textPrimary,
          height: 1.43,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
          color: _textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: _textSecondary,
          height: 1.43,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          color: _textSecondary,
          height: 1.33,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: _textPrimary,
          height: 1.43,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: _textSecondary,
          height: 1.33,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: _textSecondary,
          height: 1.45,
        ),
      ),

      // AppBar - 透明过渡
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: _surfaceMain,
        foregroundColor: _textPrimary,
        surfaceTintColor: _sunsetGold.withOpacity(0.05),
      ),

      // 卡片 - 柔和阴影
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.3),
        surfaceTintColor: _sunsetGold.withOpacity(0.08), // 淡金色光泽
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // 按钮 - 晚霞橙红主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _sunsetOrange,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _twilightRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _sunsetOrange),
      ),

      // 输入框 - 暮色质感
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceMid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _sunsetOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // 对话框 - 柔和背景
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceHigh,
        surfaceTintColor: _sunsetGold.withOpacity(0.05),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // 底部栏 - 暮色渐变
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _surfaceMain,
        selectedItemColor: _sunsetOrange,
        unselectedItemColor: _textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // Chip - 柔和边缘
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceMid,
        selectedColor: _twilightRed,
        deleteIconColor: _textSecondary,
        labelStyle: const TextStyle(color: _textPrimary),
        side: BorderSide(color: _outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      // 分隔线 - 暖色调
      dividerTheme: DividerThemeData(
        color: _outline.withOpacity(0.3),
        thickness: 1,
      ),

      // 图标主题
      iconTheme: const IconThemeData(color: _textSecondary, size: 24),

      // FAB - 金色点缀
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _sunsetGold,
        foregroundColor: _textDark,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Snackbar - 温暖提示
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHigh,
        contentTextStyle: const TextStyle(color: _textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      // Switch - 晚霞橙红
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _sunsetOrange;
          }
          return _textSecondary;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _sunsetOrange.withOpacity(0.5);
          }
          return _outline.withOpacity(0.3);
        }),
      ),

      // Checkbox - 晚霞橙红
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _sunsetOrange;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.white),
      ),

      // Radio - 晚霞橙红
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return _sunsetOrange;
          }
          return _outline;
        }),
      ),

      // Slider - 晚霞渐变
      sliderTheme: SliderThemeData(
        activeTrackColor: _sunsetOrange,
        inactiveTrackColor: _outline.withOpacity(0.3),
        thumbColor: _sunsetOrange,
        overlayColor: _sunsetOrange.withOpacity(0.2),
      ),

      // ProgressIndicator - 晚霞橙红
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _sunsetOrange,
        circularTrackColor: _surfaceMid,
      ),

      // TabBar - 暮色导航
      tabBarTheme: TabBarThemeData(
        labelColor: _sunsetOrange,
        unselectedLabelColor: _textSecondary,
        indicatorColor: _sunsetOrange,
        indicatorSize: TabBarIndicatorSize.label,
      ),

      // Tooltip - 柔和提示
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _surfaceHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _outline),
        ),
        textStyle: const TextStyle(color: _textPrimary),
      ),
    );
  }

  /// 构建浅色主题（备选版本 - "清晨黄昏"）
  ///
  /// 设计理念：黎明前的天空，温暖而明亮
  static ThemeData buildLight() {
    final colorScheme = const ColorScheme.light(
      // 主色调 - 更鲜艳的橙色
      primary: Color(0xFFE67E22),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFE0CC),
      onPrimaryContainer: Color(0xFF5D2916),

      // 次要色 - 柔和的紫色
      secondary: Color(0xFF9B59B6),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF3E5F5),
      onSecondaryContainer: Color(0xFF4A1F5F),

      // 第三色 - 明亮的金色
      tertiary: Color(0xFFF39C12),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFECB3),
      onTertiaryContainer: Color(0xFF5D3A00),

      // 表面层次 - 温暖的浅色
      surface: Color(0xFFFFF8F0),
      onSurface: Color(0xFF2D1B1B),
      surfaceContainerHighest: Color(0xFFF5EDE3),
      surfaceContainer: Color(0xFFFAF3E8),
      surfaceContainerLow: Color(0xFFFFFBF7),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      onSurfaceVariant: Color(0xFF6B5D52),

      // 背景
      background: Color(0xFFFFFBF5),
      onBackground: Color(0xFF2D1B1B),

      // 错误
      error: Color(0xFFD32F2F),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),

      // 边框
      outline: Color(0xFFB8A99A),
      outlineVariant: Color(0xFFD7C7B8),

      // 其他
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF3A2F25),
      inversePrimary: Color(0xFFFFB68C),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      // 其他主题配置与深色版类似，颜色使用 colorScheme 中的值
    );
  }
}

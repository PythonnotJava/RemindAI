import 'package:flutter/material.dart';
import 'package:dock_panel/dock_panel.dart';

/// 根据 app 的 ThemeData 生成对应的 DockThemeData
DockThemeData buildDockTheme(ThemeData theme) {
  final colorScheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;

  return DockThemeData(
    backgroundColor: colorScheme.surface,
    tabBarColor: isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerLow,
    activeTabColor: colorScheme.surface,
    inactiveTabColor: isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerLow,
    tabTextColor: colorScheme.onSurface.withValues(alpha: 0.6),
    activeTabTextColor: colorScheme.onSurface,
    dividerColor: colorScheme.outlineVariant,
    dropIndicatorColor: colorScheme.primary.withValues(alpha: 0.2),
    dropIndicatorBorderColor: colorScheme.primary,
    focusBorderColor: colorScheme.primary,
    dividerThickness: 4.0,
    tabHeight: 34.0,
    tabPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    tabBorderRadius: const BorderRadius.only(
      topLeft: Radius.circular(6),
      topRight: Radius.circular(6),
    ),
  );
}

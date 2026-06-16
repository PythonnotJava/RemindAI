import 'package:flutter/widgets.dart';

/// Tab shape style.
enum DockTabShape { square, rounded, pill }

/// Theme data for the dock panel system.
class DockThemeData {
  const DockThemeData({
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.tabBarColor = const Color(0xFF2D2D2D),
    this.activeTabColor = const Color(0xFF1E1E1E),
    this.inactiveTabColor = const Color(0xFF2D2D2D),
    this.tabTextColor = const Color(0xFFCCCCCC),
    this.activeTabTextColor = const Color(0xFFFFFFFF),
    this.dividerColor = const Color(0xFF3E3E3E),
    this.dropIndicatorColor = const Color(0x664FC3F7),
    this.dropIndicatorBorderColor = const Color(0xFF4FC3F7),
    this.focusBorderColor = const Color(0xFF4FC3F7),
    this.tabShape = DockTabShape.square,
    this.dividerThickness = 4.0,
    this.tabHeight = 36.0,
    this.tabPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.borderRadius = BorderRadius.zero,
    this.tabBorderRadius = const BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(4),
    ),
  });

  final Color backgroundColor;
  final Color tabBarColor;
  final Color activeTabColor;
  final Color inactiveTabColor;
  final Color tabTextColor;
  final Color activeTabTextColor;
  final Color dividerColor;
  final Color dropIndicatorColor;
  final Color dropIndicatorBorderColor;
  final Color focusBorderColor;
  final DockTabShape tabShape;
  final double dividerThickness;
  final double tabHeight;
  final EdgeInsets tabPadding;
  final BorderRadius borderRadius;
  final BorderRadius tabBorderRadius;

  /// A light theme preset.
  static const light = DockThemeData(
    backgroundColor: Color(0xFFF5F5F5),
    tabBarColor: Color(0xFFE8E8E8),
    activeTabColor: Color(0xFFFFFFFF),
    inactiveTabColor: Color(0xFFE8E8E8),
    tabTextColor: Color(0xFF616161),
    activeTabTextColor: Color(0xFF212121),
    dividerColor: Color(0xFFD0D0D0),
    dropIndicatorColor: Color(0x662196F3),
    dropIndicatorBorderColor: Color(0xFF2196F3),
    focusBorderColor: Color(0xFF2196F3),
  );

  DockThemeData copyWith({
    Color? backgroundColor,
    Color? tabBarColor,
    Color? activeTabColor,
    Color? inactiveTabColor,
    Color? tabTextColor,
    Color? activeTabTextColor,
    Color? dividerColor,
    Color? dropIndicatorColor,
    Color? dropIndicatorBorderColor,
    Color? focusBorderColor,
    DockTabShape? tabShape,
    double? dividerThickness,
    double? tabHeight,
    EdgeInsets? tabPadding,
    BorderRadius? borderRadius,
    BorderRadius? tabBorderRadius,
  }) {
    return DockThemeData(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      tabBarColor: tabBarColor ?? this.tabBarColor,
      activeTabColor: activeTabColor ?? this.activeTabColor,
      inactiveTabColor: inactiveTabColor ?? this.inactiveTabColor,
      tabTextColor: tabTextColor ?? this.tabTextColor,
      activeTabTextColor: activeTabTextColor ?? this.activeTabTextColor,
      dividerColor: dividerColor ?? this.dividerColor,
      dropIndicatorColor: dropIndicatorColor ?? this.dropIndicatorColor,
      dropIndicatorBorderColor:
          dropIndicatorBorderColor ?? this.dropIndicatorBorderColor,
      focusBorderColor: focusBorderColor ?? this.focusBorderColor,
      tabShape: tabShape ?? this.tabShape,
      dividerThickness: dividerThickness ?? this.dividerThickness,
      tabHeight: tabHeight ?? this.tabHeight,
      tabPadding: tabPadding ?? this.tabPadding,
      borderRadius: borderRadius ?? this.borderRadius,
      tabBorderRadius: tabBorderRadius ?? this.tabBorderRadius,
    );
  }
}

/// Provides [DockThemeData] to the dock widget tree.
class DockTheme extends InheritedWidget {
  const DockTheme({super.key, required this.data, required super.child});

  final DockThemeData data;

  static DockThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<DockTheme>();
    return theme?.data ?? const DockThemeData();
  }

  @override
  bool updateShouldNotify(DockTheme oldWidget) => data != oldWidget.data;
}

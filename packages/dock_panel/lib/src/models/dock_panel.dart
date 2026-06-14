import 'package:flutter/widgets.dart';

/// A single panel that lives inside a [DockGroup].
class DockPanel {
  DockPanel({
    required this.id,
    required this.title,
    required this.builder,
    this.icon,
    this.closable = true,
  });

  final String id;
  final String title;
  final IconData? icon;
  final bool closable;
  final WidgetBuilder builder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DockPanel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

import 'dock_panel.dart';

/// Axis for a split node.
enum DockAxis { horizontal, vertical }

/// Drop position when dragging a panel onto a group.
enum DockPosition { top, bottom, left, right, center }

/// Base class for all nodes in the dock layout tree.
sealed class DockNode {
  DockNode({required this.id});

  final String id;
}

/// A leaf node holding a group of tabbed panels.
class DockGroup extends DockNode {
  DockGroup({required super.id, required this.panels, this.activeIndex = 0});

  final List<DockPanel> panels;
  int activeIndex;

  DockPanel? get activePanel => panels.isNotEmpty && activeIndex < panels.length
      ? panels[activeIndex]
      : null;

  DockGroup copyWith({List<DockPanel>? panels, int? activeIndex}) {
    return DockGroup(
      id: id,
      panels: panels ?? this.panels,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

/// A branch node that splits space between children along an axis.
class DockSplit extends DockNode {
  DockSplit({
    required super.id,
    required this.axis,
    required this.children,
    List<double>? flexes,
  }) : flexes = flexes ?? List.filled(children.length, 1.0 / children.length);

  final DockAxis axis;
  final List<DockNode> children;

  /// Flex ratios for each child. Sum should be 1.0.
  final List<double> flexes;

  DockSplit copyWith({
    DockAxis? axis,
    List<DockNode>? children,
    List<double>? flexes,
  }) {
    return DockSplit(
      id: id,
      axis: axis ?? this.axis,
      children: children ?? this.children,
      flexes: flexes ?? this.flexes,
    );
  }
}

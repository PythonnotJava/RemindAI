import 'dock_node.dart';

/// The root layout state for the entire dock area.
class DockLayout {
  const DockLayout({this.root, this.maximizedPanelId});

  /// The root node of the layout tree. Null means empty.
  final DockNode? root;

  /// If non-null, this panel is maximized and fills the entire dock area.
  final String? maximizedPanelId;

  bool get isMaximized => maximizedPanelId != null;

  DockLayout copyWith({
    DockNode? root,
    String? maximizedPanelId,
    bool clearMaximized = false,
  }) {
    return DockLayout(
      root: root ?? this.root,
      maximizedPanelId: clearMaximized
          ? null
          : (maximizedPanelId ?? this.maximizedPanelId),
    );
  }

  static const empty = DockLayout();
}

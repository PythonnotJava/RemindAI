import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../storage/dock_storage.dart';

const _uuid = Uuid();

/// Generates a unique node ID.
String generateNodeId() => _uuid.v4();

/// The central state manager for the dock layout.
/// Use [dockManagerProvider] to access it in your widget tree.
class DockManager extends Notifier<DockLayout> {
  DockStorage? _storage;

  /// Panel registry: id -> DockPanel (for rebuild after restore).
  final Map<String, DockPanel> _registry = {};

  @override
  DockLayout build() => const DockLayout();

  /// Configure optional persistent storage.
  void setStorage(DockStorage storage) {
    _storage = storage;
  }

  /// Register a panel so it can be referenced by id during restore.
  void registerPanel(DockPanel panel) {
    _registry[panel.id] = panel;
  }

  /// Unregister a panel.
  void unregisterPanel(String panelId) {
    _registry.remove(panelId);
  }

  /// Get a registered panel by id.
  DockPanel? getPanel(String id) => _registry[id];

  // ─── Mutations ────────────────────────────────────────────

  /// Add a panel to an existing group, or create the root group.
  void addPanel(DockPanel panel, {String? targetGroupId}) {
    registerPanel(panel);

    final current = state;
    if (current.root == null) {
      // First panel: create root group.
      state = DockLayout(
        root: DockGroup(id: generateNodeId(), panels: [panel]),
      );
    } else if (targetGroupId != null) {
      state = DockLayout(
        root: _addPanelToGroup(current.root!, targetGroupId, panel),
      );
    } else {
      // Add to the first group found.
      final firstGroup = _findFirstGroup(current.root!);
      if (firstGroup != null) {
        state = DockLayout(
          root: _addPanelToGroup(current.root!, firstGroup.id, panel),
        );
      }
    }
    _persist();
  }

  /// Remove a panel by id. Cleans up empty groups/splits.
  void removePanel(String panelId) {
    final current = state;
    if (current.root == null) return;
    final newRoot = _removePanelFromTree(current.root!, panelId);
    state = DockLayout(root: newRoot);
    _persist();
  }

  /// Move a panel to a target group at a given position.
  void movePanel(String panelId, String targetGroupId, DockPosition position) {
    final panel = _findPanelInTree(state.root, panelId);
    if (panel == null) return;

    // Remove from current location.
    var newRoot = _removePanelFromTree(state.root!, panelId);

    // Add to new location.
    if (newRoot == null) {
      newRoot = DockGroup(id: generateNodeId(), panels: [panel]);
    } else if (position == DockPosition.center) {
      newRoot = _addPanelToGroup(newRoot, targetGroupId, panel);
    } else {
      newRoot = _splitGroup(newRoot, targetGroupId, panel, position);
    }

    state = DockLayout(root: newRoot);
    _persist();
  }

  /// Set the active tab index in a group.
  void setActiveIndex(String groupId, int index) {
    final current = state;
    if (current.root == null) return;
    state = DockLayout(root: _setActiveIndex(current.root!, groupId, index));
    _persist();
  }

  /// Reorder a panel within a group (intra-group tab drag).
  void reorderPanel(String groupId, int oldIndex, int newIndex) {
    final current = state;
    if (current.root == null) return;
    state = DockLayout(
      root: _reorderPanel(current.root!, groupId, oldIndex, newIndex),
    );
    _persist();
  }

  /// Resize a split's children by updating flex ratios.
  void resizeSplit(String splitId, List<double> flexes) {
    final current = state;
    if (current.root == null) return;
    state = DockLayout(root: _resizeSplit(current.root!, splitId, flexes));
    _persist();
  }

  /// Replace the entire layout (e.g. after restore).
  void setLayout(DockLayout layout) {
    state = layout;
    _persist();
  }

  /// Maximize a panel to fill the entire dock area.
  void maximizePanel(String panelId) {
    state = DockLayout(root: state.root, maximizedPanelId: panelId);
  }

  /// Restore from maximized state back to normal layout.
  void restoreFromMaximized() {
    state = DockLayout(root: state.root);
  }

  /// Toggle maximize: if already maximized, restore; otherwise maximize.
  void toggleMaximize(String panelId) {
    if (state.maximizedPanelId == panelId) {
      restoreFromMaximized();
    } else {
      maximizePanel(panelId);
    }
  }

  /// Restore layout from storage.
  Future<void> restore() async {
    if (_storage == null) return;
    final data = await _storage!.read();
    if (data != null) {
      final restored = _deserializeNode(data);
      if (restored != null) {
        state = DockLayout(root: restored);
      }
    }
  }

  // ─── Private helpers ──────────────────────────────────────

  void _persist() {
    if (_storage == null) return;
    final root = state.root;
    if (root == null) {
      _storage!.write({});
    } else {
      _storage!.write(_serializeNode(root));
    }
  }

  DockGroup? _findFirstGroup(DockNode node) {
    return switch (node) {
      DockGroup() => node,
      DockSplit(:final children) =>
        children.map(_findFirstGroup).where((g) => g != null).firstOrNull,
    };
  }

  DockPanel? _findPanelInTree(DockNode? node, String panelId) {
    if (node == null) return null;
    return switch (node) {
      DockGroup(:final panels) =>
        panels.where((p) => p.id == panelId).firstOrNull,
      DockSplit(:final children) =>
        children
            .map((c) => _findPanelInTree(c, panelId))
            .where((p) => p != null)
            .firstOrNull,
    };
  }

  DockNode _addPanelToGroup(DockNode node, String groupId, DockPanel panel) {
    return switch (node) {
      DockGroup() when node.id == groupId => DockGroup(
        id: node.id,
        panels: [...node.panels, panel],
        activeIndex: node.panels.length,
      ),
      DockGroup() => node,
      DockSplit() => DockSplit(
        id: node.id,
        axis: node.axis,
        children: node.children
            .map((c) => _addPanelToGroup(c, groupId, panel))
            .toList(),
        flexes: node.flexes,
      ),
    };
  }

  DockNode? _removePanelFromTree(DockNode node, String panelId) {
    switch (node) {
      case DockGroup():
        final newPanels = node.panels.where((p) => p.id != panelId).toList();
        if (newPanels.isEmpty) return null;
        return DockGroup(
          id: node.id,
          panels: newPanels,
          activeIndex: node.activeIndex.clamp(0, newPanels.length - 1),
        );
      case DockSplit():
        final newChildren = <DockNode>[];
        final newFlexes = <double>[];
        for (var i = 0; i < node.children.length; i++) {
          final result = _removePanelFromTree(node.children[i], panelId);
          if (result != null) {
            newChildren.add(result);
            newFlexes.add(node.flexes[i]);
          }
        }
        if (newChildren.isEmpty) return null;
        if (newChildren.length == 1) return newChildren.first;
        // Normalize flexes.
        final sum = newFlexes.fold(0.0, (a, b) => a + b);
        final normalized = newFlexes.map((f) => f / sum).toList();
        return DockSplit(
          id: node.id,
          axis: node.axis,
          children: newChildren,
          flexes: normalized,
        );
    }
  }

  DockNode _splitGroup(
    DockNode node,
    String targetGroupId,
    DockPanel panel,
    DockPosition position,
  ) {
    switch (node) {
      case DockGroup() when node.id == targetGroupId:
        final newGroup = DockGroup(id: generateNodeId(), panels: [panel]);
        final axis =
            (position == DockPosition.left || position == DockPosition.right)
            ? DockAxis.horizontal
            : DockAxis.vertical;
        final isAfter =
            position == DockPosition.right || position == DockPosition.bottom;
        return DockSplit(
          id: generateNodeId(),
          axis: axis,
          children: isAfter ? [node, newGroup] : [newGroup, node],
          flexes: [0.5, 0.5],
        );
      case DockGroup():
        return node;
      case DockSplit():
        return DockSplit(
          id: node.id,
          axis: node.axis,
          children: node.children
              .map((c) => _splitGroup(c, targetGroupId, panel, position))
              .toList(),
          flexes: node.flexes,
        );
    }
  }

  DockNode _setActiveIndex(DockNode node, String groupId, int index) {
    return switch (node) {
      DockGroup() when node.id == groupId => DockGroup(
        id: node.id,
        panels: node.panels,
        activeIndex: index.clamp(0, node.panels.length - 1),
      ),
      DockGroup() => node,
      DockSplit() => DockSplit(
        id: node.id,
        axis: node.axis,
        children: node.children
            .map((c) => _setActiveIndex(c, groupId, index))
            .toList(),
        flexes: node.flexes,
      ),
    };
  }

  DockNode _reorderPanel(
    DockNode node,
    String groupId,
    int oldIndex,
    int newIndex,
  ) {
    return switch (node) {
      DockGroup() when node.id == groupId => _reorderGroupPanels(
        node,
        oldIndex,
        newIndex,
      ),
      DockGroup() => node,
      DockSplit() => DockSplit(
        id: node.id,
        axis: node.axis,
        children: node.children
            .map((c) => _reorderPanel(c, groupId, oldIndex, newIndex))
            .toList(),
        flexes: node.flexes,
      ),
    };
  }

  DockGroup _reorderGroupPanels(DockGroup group, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return group;
    if (oldIndex < 0 || oldIndex >= group.panels.length) return group;
    if (newIndex < 0 || newIndex >= group.panels.length) return group;

    final panels = List<DockPanel>.from(group.panels);
    final panel = panels.removeAt(oldIndex);
    panels.insert(newIndex, panel);

    // Adjust activeIndex to follow the active panel.
    int activeIndex = group.activeIndex;
    if (activeIndex == oldIndex) {
      activeIndex = newIndex;
    } else {
      if (oldIndex < activeIndex && newIndex >= activeIndex) {
        activeIndex--;
      } else if (oldIndex > activeIndex && newIndex <= activeIndex) {
        activeIndex++;
      }
    }

    return DockGroup(
      id: group.id,
      panels: panels,
      activeIndex: activeIndex.clamp(0, panels.length - 1),
    );
  }

  DockNode _resizeSplit(DockNode node, String splitId, List<double> flexes) {
    return switch (node) {
      DockGroup() => node,
      DockSplit() when node.id == splitId => DockSplit(
        id: node.id,
        axis: node.axis,
        children: node.children,
        flexes: flexes,
      ),
      DockSplit() => DockSplit(
        id: node.id,
        axis: node.axis,
        children: node.children
            .map((c) => _resizeSplit(c, splitId, flexes))
            .toList(),
        flexes: node.flexes,
      ),
    };
  }

  // ─── Serialization ────────────────────────────────────────

  Map<String, dynamic> _serializeNode(DockNode node) {
    return switch (node) {
      DockGroup() => {
        'type': 'group',
        'id': node.id,
        'panels': node.panels.map((p) => p.id).toList(),
        'activeIndex': node.activeIndex,
      },
      DockSplit() => {
        'type': 'split',
        'id': node.id,
        'axis': node.axis == DockAxis.horizontal ? 'h' : 'v',
        'children': node.children.map(_serializeNode).toList(),
        'flexes': node.flexes,
      },
    };
  }

  DockNode? _deserializeNode(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'group') {
      final panelIds = (data['panels'] as List).cast<String>();
      final panels = panelIds
          .map((id) => _registry[id])
          .where((p) => p != null)
          .cast<DockPanel>()
          .toList();
      if (panels.isEmpty) return null;
      return DockGroup(
        id: data['id'] as String,
        panels: panels,
        activeIndex: (data['activeIndex'] as int?) ?? 0,
      );
    } else if (type == 'split') {
      final axis = data['axis'] == 'h'
          ? DockAxis.horizontal
          : DockAxis.vertical;
      final childrenData = (data['children'] as List)
          .cast<Map<String, dynamic>>();
      final flexes = (data['flexes'] as List).cast<double>();
      final children = <DockNode>[];
      final validFlexes = <double>[];
      for (var i = 0; i < childrenData.length; i++) {
        final child = _deserializeNode(childrenData[i]);
        if (child != null) {
          children.add(child);
          validFlexes.add(flexes[i]);
        }
      }
      if (children.isEmpty) return null;
      if (children.length == 1) return children.first;
      final sum = validFlexes.fold(0.0, (a, b) => a + b);
      final normalized = validFlexes.map((f) => f / sum).toList();
      return DockSplit(
        id: data['id'] as String,
        axis: axis,
        children: children,
        flexes: normalized,
      );
    }
    return null;
  }
}

/// The main Riverpod provider for the dock layout manager.
final dockManagerProvider = NotifierProvider<DockManager, DockLayout>(
  DockManager.new,
);

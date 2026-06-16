import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/dock_manager.dart';
import '../theme/dock_theme.dart';
import 'dock_group_view.dart';

/// Tab bar for a [DockGroup]. Tabs are draggable and support intra-group
/// reordering via DragTarget on each tab.
class DockTabBar extends ConsumerStatefulWidget {
  const DockTabBar({super.key, required this.group});

  final DockGroup group;

  @override
  ConsumerState<DockTabBar> createState() => _DockTabBarState();
}

class _DockTabBarState extends ConsumerState<DockTabBar> {
  /// The index where the insertion indicator should appear.
  /// null means no indicator is visible.
  int? _insertionIndex;

  @override
  Widget build(BuildContext context) {
    final theme = DockTheme.of(context);
    final group = widget.group;

    return Container(
      height: theme.tabHeight,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: theme.tabBarColor),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const actionsWidth = 32.0; // maximize button + spacing
          final tabsWidth = constraints.maxWidth - actionsWidth;

          return Row(
            children: [
              SizedBox(
                width: tabsWidth.clamp(0.0, constraints.maxWidth),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  itemCount: group.panels.length,
                  itemBuilder: (context, index) {
                    final panel = group.panels[index];
                    final isActive = index == group.activeIndex;
                    return _ReorderableDockTab(
                      panel: panel,
                      groupId: group.id,
                      index: index,
                      panels: group.panels,
                      isActive: isActive,
                      insertionIndex: _insertionIndex,
                      onTap: () {
                        ref
                            .read(dockManagerProvider.notifier)
                            .setActiveIndex(group.id, index);
                      },
                      onClose: panel.closable
                          ? () {
                              ref
                                  .read(dockManagerProvider.notifier)
                                  .removePanel(panel.id);
                            }
                          : null,
                      onReorder: (oldIndex, newIndex) {
                        ref
                            .read(dockManagerProvider.notifier)
                            .reorderPanel(group.id, oldIndex, newIndex);
                        setState(() => _insertionIndex = null);
                      },
                      onInsertionIndexChanged: (idx) {
                        setState(() => _insertionIndex = idx);
                      },
                      onDragLeave: () {
                        setState(() => _insertionIndex = null);
                      },
                    );
                  },
                ),
              ),
              // Maximize button for the active panel.
              if (group.activePanel != null)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: Icon(
                      Icons.fullscreen,
                      size: 16,
                      color: theme.tabTextColor,
                    ),
                    onPressed: () {
                      ref
                          .read(dockManagerProvider.notifier)
                          .toggleMaximize(group.activePanel!.id);
                    },
                    tooltip: 'Maximize',
                    splashRadius: 12,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }
}

/// A single tab wrapped with DragTarget for intra-group reorder detection.
class _ReorderableDockTab extends StatefulWidget {
  const _ReorderableDockTab({
    required this.panel,
    required this.groupId,
    required this.index,
    required this.panels,
    required this.isActive,
    required this.insertionIndex,
    required this.onTap,
    required this.onReorder,
    required this.onInsertionIndexChanged,
    required this.onDragLeave,
    this.onClose,
  });

  final DockPanel panel;
  final String groupId;
  final int index;
  final List<DockPanel> panels;
  final bool isActive;
  final int? insertionIndex;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onInsertionIndexChanged;
  final VoidCallback onDragLeave;

  @override
  State<_ReorderableDockTab> createState() => _ReorderableDockTabState();
}

class _ReorderableDockTabState extends State<_ReorderableDockTab> {
  bool _isDragging = false;

  /// Determine the insertion index based on horizontal position within the tab.
  int _computeInsertionIndex(Offset globalPosition, BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final local = renderBox.globalToLocal(globalPosition);
    final halfWidth = renderBox.size.width / 2;
    // If dragging over the left half, insert before; right half, insert after.
    return local.dx < halfWidth ? widget.index : widget.index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = DockTheme.of(context);
    final bgColor = widget.isActive
        ? theme.activeTabColor
        : theme.inactiveTabColor;
    final textColor = widget.isActive
        ? theme.activeTabTextColor
        : theme.tabTextColor;

    // Show insertion indicator on the left side of this tab.
    final showLeftIndicator = widget.insertionIndex == widget.index;
    // Show insertion indicator on the right side of this tab (only for last tab).
    final showRightIndicator = widget.insertionIndex == widget.index + 1;

    final tabContent = GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: theme.tabPadding,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: theme.tabBorderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.panel.icon != null) ...[
              Icon(widget.panel.icon, size: 14, color: textColor),
              const SizedBox(width: 6),
            ],
            Text(
              widget.panel.title,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: widget.isActive
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            if (widget.onClose != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onClose,
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final draggableTab = Draggable<DockDragData>(
      data: DockDragData(
        panelId: widget.panel.id,
        sourceGroupId: widget.groupId,
        title: widget.panel.title,
        icon: widget.panel.icon,
      ),
      onDragStarted: () => setState(() => _isDragging = true),
      onDragEnd: (_) => setState(() => _isDragging = false),
      onDraggableCanceled: (_, _) => setState(() => _isDragging = false),
      feedback: _AnimatedDragFeedback(
        activeTabColor: theme.activeTabColor,
        activeTabTextColor: theme.activeTabTextColor,
        icon: widget.panel.icon,
        title: widget.panel.title,
      ),
      childWhenDragging: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: 0.4,
        child: tabContent,
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isDragging ? 0.4 : 1.0,
        child: tabContent,
      ),
    );

    // Wrap with DragTarget to detect intra-group reordering.
    return DragTarget<DockDragData>(
      onWillAcceptWithDetails: (details) {
        // Only handle intra-group drags at the tab level.
        return details.data.sourceGroupId == widget.groupId;
      },
      onAcceptWithDetails: (details) {
        // Find the source panel index.
        final sourceIndex = _findPanelIndex(details.data.panelId);
        if (sourceIndex == null) return;
        final targetIndex = widget.insertionIndex;
        if (targetIndex == null) return;

        // Adjust newIndex: if moving forward, account for removal.
        var newIndex = targetIndex;
        if (sourceIndex < newIndex) {
          newIndex -= 1;
        }
        if (sourceIndex != newIndex) {
          widget.onReorder(sourceIndex, newIndex);
        } else {
          widget.onDragLeave();
        }
      },
      onMove: (details) {
        final insertIdx = _computeInsertionIndex(details.offset, context);
        widget.onInsertionIndexChanged(insertIdx);
      },
      onLeave: (_) {
        widget.onDragLeave();
      },
      builder: (context, candidateData, rejectedData) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left insertion indicator.
            _InsertionIndicator(visible: showLeftIndicator),
            draggableTab,
            // Right insertion indicator (only shown on the rightmost tab).
            _InsertionIndicator(visible: showRightIndicator),
          ],
        );
      },
    );
  }

  int? _findPanelIndex(String panelId) {
    for (var i = 0; i < widget.panels.length; i++) {
      if (widget.panels[i].id == panelId) return i;
    }
    return null;
  }
}

/// A thin vertical indicator shown during tab reordering.
class _InsertionIndicator extends StatelessWidget {
  const _InsertionIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = DockTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      width: visible ? 2.0 : 0.0,
      height: theme.tabHeight * 0.6,
      decoration: BoxDecoration(
        color: visible ? theme.focusBorderColor : Colors.transparent,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Feedback widget that animates in with a scale and opacity transition.
class _AnimatedDragFeedback extends StatefulWidget {
  const _AnimatedDragFeedback({
    required this.activeTabColor,
    required this.activeTabTextColor,
    required this.title,
    this.icon,
  });

  final Color activeTabColor;
  final Color activeTabTextColor;
  final String title;
  final IconData? icon;

  @override
  State<_AnimatedDragFeedback> createState() => _AnimatedDragFeedbackState();
}

class _AnimatedDragFeedbackState extends State<_AnimatedDragFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(scale: _scaleAnimation.value, child: child),
        );
      },
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.activeTabColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: widget.activeTabTextColor),
                const SizedBox(width: 6),
              ],
              Text(
                widget.title,
                style: TextStyle(
                  color: widget.activeTabTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

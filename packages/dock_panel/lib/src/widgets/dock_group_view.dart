import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/dock_manager.dart';
import '../theme/dock_theme.dart';
import 'dock_drop_overlay.dart';
import 'dock_tab_bar.dart';

/// Renders a [DockGroup]: tab bar + active panel content + drop targets.
class DockGroupView extends ConsumerStatefulWidget {
  const DockGroupView({super.key, required this.group});

  final DockGroup group;

  @override
  ConsumerState<DockGroupView> createState() => _DockGroupViewState();
}

class _DockGroupViewState extends ConsumerState<DockGroupView> {
  DockPosition? _dropPosition;

  /// Compute the drop position from the drag pointer's global position
  /// relative to this widget's bounds.
  DockPosition _computeDropPosition(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox;
    final local = renderBox.globalToLocal(globalPosition);
    final size = renderBox.size;

    final x = local.dx;
    final y = local.dy;
    final w = size.width;
    final h = size.height;

    // Edge zone: 25% of each dimension.
    final edgeX = w * 0.25;
    final edgeY = h * 0.25;

    if (x < edgeX) return DockPosition.left;
    if (x > w - edgeX) return DockPosition.right;
    if (y < edgeY) return DockPosition.top;
    if (y > h - edgeY) return DockPosition.bottom;
    return DockPosition.center;
  }

  @override
  Widget build(BuildContext context) {
    final theme = DockTheme.of(context);
    final group = widget.group;

    return DragTarget<DockDragData>(
      onWillAcceptWithDetails: (details) {
        // Don't accept drops from the same group if it's the only panel
        // (can't split a single panel off from itself).
        if (details.data.sourceGroupId == group.id &&
            group.panels.length == 1) {
          return false;
        }
        return true;
      },
      onMove: (details) {
        final newPos = _computeDropPosition(details.offset);
        if (newPos != _dropPosition) {
          setState(() => _dropPosition = newPos);
        }
      },
      onAcceptWithDetails: (details) {
        final position = _dropPosition ?? DockPosition.center;

        // Same group + center = no-op (tab reorder is handled at tab level).
        if (details.data.sourceGroupId == group.id &&
            position == DockPosition.center) {
          setState(() => _dropPosition = null);
          return;
        }

        ref
            .read(dockManagerProvider.notifier)
            .movePanel(details.data.panelId, group.id, position);
        setState(() {
          _dropPosition = null;
        });
      },
      onLeave: (_) {
        setState(() {
          _dropPosition = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final hasCandidates = candidateData.isNotEmpty;

        return ClipRect(
          child: Stack(
            children: [
              // Main content — manually split vertical space to avoid overflow.
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalHeight = constraints.maxHeight;
                  final tabH = theme.tabHeight.clamp(0.0, totalHeight);
                  final contentH = (totalHeight - tabH).clamp(0.0, totalHeight);

                  return Column(
                    children: [
                      SizedBox(
                        height: tabH,
                        child: DockTabBar(group: group),
                      ),
                      SizedBox(
                        height: contentH,
                        child: Container(
                          color: theme.backgroundColor,
                          child: group.activePanel != null
                              ? KeyedSubtree(
                                  key: ValueKey(group.activePanel!.id),
                                  child: group.activePanel!.builder(context),
                                )
                              : const SizedBox.expand(),
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Drop overlay showing where the panel will land.
              if (hasCandidates && _dropPosition != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DockDropIndicator(position: _dropPosition!),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Data carried during a panel drag operation.
class DockDragData {
  const DockDragData({
    required this.panelId,
    required this.sourceGroupId,
    required this.title,
    this.icon,
  });

  final String panelId;
  final String sourceGroupId;
  final String title;
  final IconData? icon;
}

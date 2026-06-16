import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/dock_theme.dart';

/// A purely visual indicator showing where a dragged panel will dock.
/// Position is determined by the parent via [position].
class DockDropIndicator extends StatelessWidget {
  const DockDropIndicator({super.key, required this.position});

  final DockPosition position;

  @override
  Widget build(BuildContext context) {
    final theme = DockTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const margin = 4.0;
        final rect = _getHighlightRect(position, w, h, margin);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: theme.dropIndicatorColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.dropIndicatorBorderColor,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Rect _getHighlightRect(
    DockPosition position,
    double w,
    double h,
    double margin,
  ) {
    return switch (position) {
      DockPosition.left => Rect.fromLTWH(
        margin,
        margin,
        w * 0.5 - margin,
        h - margin * 2,
      ),
      DockPosition.right => Rect.fromLTWH(
        w * 0.5,
        margin,
        w * 0.5 - margin,
        h - margin * 2,
      ),
      DockPosition.top => Rect.fromLTWH(
        margin,
        margin,
        w - margin * 2,
        h * 0.5 - margin,
      ),
      DockPosition.bottom => Rect.fromLTWH(
        margin,
        h * 0.5,
        w - margin * 2,
        h * 0.5 - margin,
      ),
      DockPosition.center => Rect.fromLTWH(
        margin,
        margin,
        w - margin * 2,
        h - margin * 2,
      ),
    };
  }
}

/// Legacy overlay widget — kept for backward compat but deprecated.
/// Use [DockDropIndicator] with position computed from DragTarget.onMove.
@Deprecated('Use DockDropIndicator instead')
class DockDropOverlay extends StatefulWidget {
  const DockDropOverlay({super.key, required this.onPositionChanged});

  final ValueChanged<DockPosition> onPositionChanged;

  @override
  State<DockDropOverlay> createState() => _DockDropOverlayState();
}

class _DockDropOverlayState extends State<DockDropOverlay> {
  @override
  Widget build(BuildContext context) {
    // This widget is deprecated — drop overlay is now driven by DragTarget.onMove.
    return const SizedBox.expand();
  }
}

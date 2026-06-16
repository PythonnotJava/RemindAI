import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/dock_theme.dart';

/// A draggable divider between two split children.
class DockDivider extends StatefulWidget {
  const DockDivider({
    super.key,
    required this.axis,
    required this.thickness,
    required this.color,
    required this.onDrag,
    required this.onDragEnd,
  });

  final DockAxis axis;
  final double thickness;
  final Color color;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  State<DockDivider> createState() => _DockDividerState();
}

class _DockDividerState extends State<DockDivider> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.axis == DockAxis.horizontal;
    final theme = DockTheme.of(context);

    // Use the focus border color as the highlight on hover/drag.
    final Color effectiveColor;
    if (_isDragging) {
      effectiveColor = theme.focusBorderColor;
    } else if (_isHovered) {
      effectiveColor = Color.lerp(widget.color, theme.focusBorderColor, 0.5)!;
    } else {
      effectiveColor = widget.color;
    }

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          final delta = isHorizontal ? details.delta.dx : details.delta.dy;
          widget.onDrag(delta);
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
          widget.onDragEnd();
        },
        onPanCancel: () => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: isHorizontal ? widget.thickness : double.infinity,
          height: isHorizontal ? double.infinity : widget.thickness,
          color: effectiveColor,
        ),
      ),
    );
  }
}

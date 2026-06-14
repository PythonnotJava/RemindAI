import 'package:flutter/material.dart';

/// 通用可拖拽重排卡片网格。
///
/// 使用 Flutter 内置的 [LongPressDraggable] + [DragTarget] + [Wrap] 实现，
/// 不依赖外部包。长按某张卡片拖动到另一张卡片上即可交换位置，
/// 松手后通过 [onReorder] 回调返回重排后的新列表。
///
/// - [items]      数据列表
/// - [itemBuilder] 构建单张卡片（不含拖拽逻辑）
/// - [keyOf]      返回每个 item 的稳定唯一键（用于定位拖拽目标）
/// - [onReorder]  拖拽完成后返回重排后的完整列表
/// - [cardWidth]  卡片宽度（用于 Wrap 布局）
/// - [trailing]   末尾追加的固定组件（如"新增"卡片），不参与拖拽
class ReorderableCardGrid<T extends Object> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Object Function(T item) keyOf;
  final void Function(List<T> reordered) onReorder;
  final double cardWidth;
  final double spacing;
  final double runSpacing;
  final Widget? trailing;

  const ReorderableCardGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.keyOf,
    required this.onReorder,
    this.cardWidth = 280,
    this.spacing = 12,
    this.runSpacing = 12,
    this.trailing,
  });

  @override
  State<ReorderableCardGrid<T>> createState() => _ReorderableCardGridState<T>();
}

class _ReorderableCardGridState<T extends Object>
    extends State<ReorderableCardGrid<T>> {
  // 当前拖拽中的 item 键，null 表示无拖拽
  Object? _draggingKey;

  void _handleDrop(T dragged, T target) {
    if (widget.keyOf(dragged) == widget.keyOf(target)) return;
    final list = List<T>.from(widget.items);
    final from = list.indexWhere(
      (e) => widget.keyOf(e) == widget.keyOf(dragged),
    );
    final to = list.indexWhere((e) => widget.keyOf(e) == widget.keyOf(target));
    if (from < 0 || to < 0) return;
    final moved = list.removeAt(from);
    list.insert(to, moved);
    widget.onReorder(list);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      children: [
        for (final item in widget.items) _buildDraggable(item),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
  }

  Widget _buildDraggable(T item) {
    final key = widget.keyOf(item);
    final card = SizedBox(
      width: widget.cardWidth,
      child: widget.itemBuilder(context, item),
    );

    return DragTarget<T>(
      onWillAcceptWithDetails: (details) => widget.keyOf(details.data) != key,
      onAcceptWithDetails: (details) => _handleDrop(details.data, item),
      builder: (context, candidate, rejected) {
        final isTarget = candidate.isNotEmpty;
        final isDragging = _draggingKey == key;

        return LongPressDraggable<T>(
          data: item,
          delay: const Duration(milliseconds: 200),
          onDragStarted: () => setState(() => _draggingKey = key),
          onDragEnd: (_) => setState(() => _draggingKey = null),
          onDraggableCanceled: (_, _) => setState(() => _draggingKey = null),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.9,
              child: Transform.scale(scale: 1.04, child: card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isTarget
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Opacity(opacity: isDragging ? 0.4 : 1.0, child: card),
          ),
        );
      },
    );
  }
}

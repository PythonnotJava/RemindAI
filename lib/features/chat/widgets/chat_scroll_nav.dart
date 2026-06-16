import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';

/// 对话列表右侧浮动导航按钮组。
///
/// 鼠标移入右侧边缘区域时淡入显示，移出后延迟淡出。
/// 点击：翻一页；长按：持续平滑滚动。
class ChatScrollNav extends StatefulWidget {
  final ScrollController scrollController;

  const ChatScrollNav({super.key, required this.scrollController});

  @override
  State<ChatScrollNav> createState() => _ChatScrollNavState();
}

class _ChatScrollNavState extends State<ChatScrollNav> {
  bool _hovered = false;
  Timer? _scrollTimer;

  /// 持续滚动速度
  static const double _scrollSpeed = 100.0;

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _startContinuousScroll(double direction) {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!widget.scrollController.hasClients) return;
      final pos = widget.scrollController.position;
      final target = (pos.pixels + direction * _scrollSpeed).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      widget.scrollController.jumpTo(target);
    });
  }

  void _stopContinuousScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _pageUp() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    final target = (pos.pixels - pos.viewportDimension * 0.85).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _pageDown() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    final target = (pos.pixels + pos.viewportDimension * 0.85).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    widget.scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      right: 12,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          width: 40,
          child: Center(
            child: IgnorePointer(
              ignoring: !_hovered,
              child: AnimatedOpacity(
                opacity: _hovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NavButton(
                        icon: Icons.keyboard_arrow_up,
                        tooltip: context.s.scrollUp,
                        onTap: _pageUp,
                        onLongPressStart: () => _startContinuousScroll(-1),
                        onLongPressEnd: _stopContinuousScroll,
                      ),
                      const SizedBox(height: 2),
                      _NavButton(
                        icon: Icons.keyboard_arrow_down,
                        tooltip: context.s.scrollDown,
                        onTap: _pageDown,
                        onLongPressStart: () => _startContinuousScroll(1),
                        onLongPressEnd: _stopContinuousScroll,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onTap,
          onLongPressStart: (_) => onLongPressStart(),
          onLongPressEnd: (_) => onLongPressEnd(),
          onLongPressCancel: onLongPressEnd,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: null, // handled by GestureDetector
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

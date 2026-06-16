import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

/// 全局主题切换动画控制器。
///
/// 流程：截图 → 显示 loading spinner → 等待新主题 rebuild 稳定 → 涟漪扩散揭示新主题。
class ThemeTransitionController {
  ThemeTransitionController._();
  static final instance = ThemeTransitionController._();

  _ThemeTransitionState? _state;

  void _attach(_ThemeTransitionState state) => _state = state;
  void _detach(_ThemeTransitionState state) {
    if (_state == state) _state = null;
  }

  /// 开始主题切换。截图完成后 resolve，调用方应在此后修改主题。
  Future<void> startTransition(Offset center) async {
    await _state?.captureAndAnimate(center);
  }
}

class ThemeTransition extends StatefulWidget {
  final Widget child;
  const ThemeTransition({super.key, required this.child});

  @override
  State<ThemeTransition> createState() => _ThemeTransitionState();
}

class _ThemeTransitionState extends State<ThemeTransition>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();
  late final AnimationController _controller;

  ui.Image? _snapshot;
  Offset _center = Offset.zero;
  double _maxRadius = 0;
  bool _loading = false; // 显示 spinner 阶段

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() {
              _snapshot?.dispose();
              _snapshot = null;
              _loading = false;
            });
          }
        });
    ThemeTransitionController.instance._attach(this);
  }

  @override
  void dispose() {
    ThemeTransitionController.instance._detach(this);
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  /// 截取当前画面。返回后调用方切换主题，我们稍后启动动画。
  Future<void> captureAndAnimate(Offset center) async {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;

    // 用较低的 pixelRatio 降低截图内存和 GPU 压力
    final image = await boundary.toImage(pixelRatio: 0.8);

    final size = boundary.size;
    final dx = math.max(center.dx, size.width - center.dx);
    final dy = math.max(center.dy, size.height - center.dy);
    _maxRadius = math.sqrt(dx * dx + dy * dy);

    setState(() {
      _snapshot = image;
      _center = center;
      _loading = true; // 进入 loading 阶段
    });

    // 等待足够的帧让新主题完成全量 rebuild + layout + paint
    // 用 3 个 postFrameCallback 确保帧流水线完全稳定
    await _waitFrames(3);
    // 额外等一小段时间让 GPU 光栅化完成
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    // 开始涟漪动画
    setState(() => _loading = false);
    _controller.reset();
    _controller.forward();
  }

  /// 等待 [count] 个 vsync 帧完成
  Future<void> _waitFrames(int count) async {
    for (int i = 0; i < count; i++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 无动画时正常渲染
    if (_snapshot == null) {
      return RepaintBoundary(key: _boundaryKey, child: widget.child);
    }

    return Stack(
      children: [
        // 底层：新主题内容（被截图遮住，先 rebuild 好）
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        // 覆盖层：旧截图（loading 阶段全屏显示，动画阶段用 CustomPainter 挖洞）
        Positioned.fill(
          child: _loading
              ? _buildLoadingOverlay()
              : IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _CircleRevealPainter(
                          image: _snapshot!,
                          center: _center,
                          progress: Curves.easeOutCubic.transform(
                            _controller.value,
                          ),
                          maxRadius: _maxRadius,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return IgnorePointer(
      child: Stack(
        children: [
          // 旧截图作为背景
          RawImage(
            image: _snapshot,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          // 半透明蒙层 + 中心 spinner
          Container(
            color: Colors.black.withValues(alpha: 0.15),
            child: Center(
              child: SpinKitRipple(
                color: Colors.white.withValues(alpha: 0.85),
                size: 64,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 用 CustomPainter 绘制涟漪揭示效果。
///
/// 在 Canvas 上直接 drawImage + clipPath，比 widget 层级的 ClipPath
/// 更高效：避免每帧重建 widget tree，直接由 Skia 执行裁剪。
class _CircleRevealPainter extends CustomPainter {
  final ui.Image image;
  final Offset center;
  final double progress; // 0.0 → 1.0
  final double maxRadius;

  _CircleRevealPainter({
    required this.image,
    required this.center,
    required this.progress,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = maxRadius * progress;

    // 保存画布状态
    canvas.save();

    // 创建"全屏矩形 - 圆"的裁剪区域（圆内露出新主题，圆外显示旧截图）
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final clipPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(fullRect),
      circlePath,
    );

    canvas.clipPath(clipPath);

    // 绘制旧截图（可能分辨率低于画布，用 paintImage 拉伸填充）
    paintImage(canvas: canvas, rect: fullRect, image: image, fit: BoxFit.cover);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircleRevealPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

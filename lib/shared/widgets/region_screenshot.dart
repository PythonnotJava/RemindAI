import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 区域截图 Overlay — 全屏覆盖，显示当前窗口截图，用户拖选矩形区域裁剪。
///
/// 调用 [RegionScreenshot.capture] 触发截图流程，返回裁剪后的 ui.Image 或 null（取消）。
class RegionScreenshot extends StatefulWidget {
  final ui.Image screenshot;
  const RegionScreenshot({super.key, required this.screenshot});

  /// 入口：截取 boundaryKey 对应的 widget，弹出选区 overlay，返回裁剪后的图片。
  static Future<ui.Image?> capture(BuildContext context, GlobalKey boundaryKey) async {
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: ui.PlatformDispatcher.instance.views.first.devicePixelRatio);

    if (!context.mounted) return null;

    final result = await Navigator.of(context).push<ui.Image>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, a1, a2) => RegionScreenshot(screenshot: image),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    return result;
  }

  @override
  State<RegionScreenshot> createState() => _RegionScreenshotState();
}

class _RegionScreenshotState extends State<RegionScreenshot> {
  Offset? _startPoint;
  Offset? _endPoint;
  bool _selecting = false;

  Rect get _selectionRect {
    if (_startPoint == null || _endPoint == null) return Rect.zero;
    return Rect.fromPoints(_startPoint!, _endPoint!);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop(null);
        },
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _startPoint = details.localPosition;
              _endPoint = details.localPosition;
              _selecting = true;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _endPoint = details.localPosition;
            });
          },
          onPanEnd: (details) async {
            if (_selectionRect.width < 4 || _selectionRect.height < 4) {
              // 选区太小，视为取消
              Navigator.of(context).pop(null);
              return;
            }
            final cropped = await _cropImage();
            if (!mounted) return;
            // ignore: use_build_context_synchronously
            Navigator.of(context).pop(cropped);
          },
          child: Stack(
            children: [
              // 底层：截图
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScreenshotPainter(
                    image: widget.screenshot,
                    selectionRect: _selecting ? _selectionRect : null,
                  ),
                ),
              ),
              // 顶部提示
              if (!_selecting)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '拖动选择截图区域 · Esc 取消',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              // 选区尺寸标签
              if (_selecting && _selectionRect.width > 20)
                Positioned(
                  left: _selectionRect.left,
                  top: _selectionRect.top - 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_selectionRect.width.round()} × ${_selectionRect.height.round()}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 从截图中裁剪选区
  Future<ui.Image?> _cropImage() async {
    final pixelRatio = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final rect = _selectionRect;

    final srcRect = Rect.fromLTWH(
      rect.left * pixelRatio,
      rect.top * pixelRatio,
      rect.width * pixelRatio,
      rect.height * pixelRatio,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      widget.screenshot,
      srcRect,
      Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(srcRect.width.round(), srcRect.height.round());
    picture.dispose();
    return image;
  }
}

/// 绘制截图 + 半透明遮罩 + 选区高亮
class _ScreenshotPainter extends CustomPainter {
  final ui.Image image;
  final Rect? selectionRect;

  _ScreenshotPainter({required this.image, this.selectionRect});

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制截图铺满
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());

    // 半透明遮罩
    canvas.drawRect(dst, Paint()..color = Colors.black.withValues(alpha: 0.4));

    // 选区高亮（去掉遮罩）
    if (selectionRect != null && selectionRect!.width > 0 && selectionRect!.height > 0) {
      canvas.save();
      canvas.clipRect(selectionRect!);
      canvas.drawImageRect(image, src, dst, Paint());
      canvas.restore();

      // 选区边框
      canvas.drawRect(
        selectionRect!,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_ScreenshotPainter old) => true;
}


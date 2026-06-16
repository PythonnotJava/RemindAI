import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/pet/pet_engine.dart';

/// 精灵渲染画布 — 使用 CustomPainter 高效绘制当前帧
class PetCanvas extends StatelessWidget {
  final PetEngine engine;
  final double displaySize;

  const PetCanvas({
    super.key,
    required this.engine,
    this.displaySize = 128,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        if (engine.loadError != null) {
          return SizedBox.square(
            dimension: displaySize,
            child: Center(
              child: Text(
                engine.loadError!,
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!engine.imageLoaded || engine.spriteImage == null) {
          return SizedBox.square(
            dimension: displaySize,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return CustomPaint(
          size: Size.square(displaySize),
          painter: _SpritePainter(
            image: engine.spriteImage!,
            srcRect: engine.currentFrameRect,
            flipX: engine.flipX,
          ),
        );
      },
    );
  }
}

class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final Rect? srcRect;
  final bool flipX;

  _SpritePainter({
    required this.image,
    required this.srcRect,
    required this.flipX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (srcRect == null) return;

    // 安全检查：image 可能在切换精灵时被 dispose
    final int imageWidth;
    try {
      imageWidth = image.width;
    } catch (_) {
      return; // image 已失效，跳过本帧
    }
    if (imageWidth == 0) return;

    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..filterQuality = FilterQuality.none // 像素风保持锐利
      ..isAntiAlias = false;

    if (flipX) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(image, srcRect!, dst, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(image, srcRect!, dst, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter oldDelegate) {
    return oldDelegate.srcRect != srcRect || oldDelegate.flipX != flipX;
  }
}

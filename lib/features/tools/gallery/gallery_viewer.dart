import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'dart:math' as math;
import '../../../core/l10n/l10n_ext.dart';

class GalleryViewerPage extends StatefulWidget {
  const GalleryViewerPage({super.key});

  @override
  State<GalleryViewerPage> createState() => _GalleryViewerPageState();
}

class _GalleryViewerPageState extends State<GalleryViewerPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showStory = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 星空特效背景
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: StarrySkyPainter(_controller.value),
                  size: Size.infinite,
                );
              },
            ),
          ),

          // 右上角的故事卡片
          Positioned(
            top: 20,
            right: 20,
            child: AnimatedOpacity(
              opacity: _showStory ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 400,
                constraints: const BoxConstraints(maxHeight: 600),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_stories,
                            color: Colors.amber,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.s.galleryStoryTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() => _showStory = false);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Markdown 内容
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: GptMarkdown(
                          context.s.galleryStoryContent,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.8,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 左下角的控制按钮
          Positioned(
            left: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: () {
                setState(() => _showStory = !_showStory);
              },
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              icon: Icon(
                _showStory ? Icons.visibility_off : Icons.auto_stories,
                color: Colors.amber,
              ),
              label: Text(
                _showStory
                    ? context.s.galleryHideStory
                    : context.s.galleryShowStory,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 星星数据
class Star {
  double x;
  final double y;
  final double radius;
  final double speed;
  final Color color;
  double alpha;
  final double twinkleSpeed;
  double twinklePhase;

  Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.color,
    required this.alpha,
    required this.twinkleSpeed,
    required this.twinklePhase,
  });
}

/// 行星数据
class Planet {
  double angle;
  final double orbitRadius;
  final double speed;
  final Color color;
  final double size;
  final List<Offset> trail;
  final int maxTrailLength;
  final Offset center;

  Planet({
    required this.angle,
    required this.orbitRadius,
    required this.speed,
    required this.color,
    required this.size,
    required this.maxTrailLength,
    required this.center,
  }) : trail = [];
}

/// 卫星数据
class Moon {
  double angle;
  final double orbitRadius;
  final double speed;
  final Color color;
  final double size;
  final List<Offset> trail;
  final int maxTrailLength;

  Moon({
    required this.angle,
    required this.orbitRadius,
    required this.speed,
    required this.color,
    required this.size,
    required this.maxTrailLength,
  }) : trail = [];
}

class StarrySkyPainter extends CustomPainter {
  final double animationValue;
  static List<Star>? _stars;
  static Planet? _planet;
  static Moon? _moon;
  static Size? _lastSize;

  StarrySkyPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    if (_stars == null || _lastSize != size) {
      _initializeStars(size);
      _initializePlanet(size);
      _initializeMoon();
      _lastSize = size;
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black,
    );

    _updateAndDrawStars(canvas, size);
    _updateAndDrawPlanet(canvas, size);
  }

  void _initializeStars(Size size) {
    final random = math.Random(42);
    _stars = List.generate(500, (index) {
      double speed;
      final speedRand = random.nextDouble();
      if (speedRand < 0.3) {
        speed = 0.1;
      } else if (speedRand < 0.6) {
        speed = 0.2;
      } else if (speedRand < 0.8) {
        speed = 0.3;
      } else if (speedRand < 0.9) {
        speed = 0.4;
      } else {
        speed = 0.5;
      }

      final radiusRand = random.nextDouble();
      double radius;
      if (radiusRand < 0.3) {
        radius = 1;
      } else if (radiusRand < 0.6) {
        radius = 2;
      } else if (radiusRand < 0.9) {
        radius = 3;
      } else {
        radius = 4;
      }

      return Star(
        x: random.nextDouble() * size.width * 10,
        y: random.nextDouble() * size.height * 0.45,
        radius: radius,
        speed: speed,
        color: Color.fromARGB(
          255,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        ),
        alpha: random.nextDouble() * 0.5 + 0.5,
        twinkleSpeed: random.nextDouble() * 0.02 + 0.01,
        twinklePhase: random.nextDouble() * math.pi * 2,
      );
    });
  }

  void _initializePlanet(Size size) {
    _planet = Planet(
      angle: 0,
      orbitRadius: size.width / 6,
      speed: 0.005,
      color: const Color(0xFF0064FF),
      size: 25,
      maxTrailLength: 150,
      center: Offset(
        size.width / 2 - size.width * 0.26,
        size.height / 2 - size.height * 0.231,
      ),
    );
  }

  void _initializeMoon() {
    _moon = Moon(
      angle: 0,
      orbitRadius: 80,
      speed: 0.05,
      color: const Color(0xFFE6E6E6),
      size: 5,
      maxTrailLength: 90,
    );
  }

  void _updateAndDrawStars(Canvas canvas, Size size) {
    if (_stars == null) return;

    for (var star in _stars!) {
      star.x -= star.speed;
      if (star.x < -10) {
        star.x = size.width + 10;
      }

      star.twinklePhase += star.twinkleSpeed;
      star.alpha = 0.5 + 0.5 * math.sin(star.twinklePhase);

      final paint = Paint()
        ..color = star.color.withValues(alpha: star.alpha)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(star.x, star.y), star.radius, paint);
    }
  }

  void _updateAndDrawPlanet(Canvas canvas, Size size) {
    if (_planet == null || _moon == null) return;

    _planet!.angle += _planet!.speed;
    final planetX =
        _planet!.center.dx + _planet!.orbitRadius * math.sin(_planet!.angle);
    final planetY =
        _planet!.center.dy + _planet!.orbitRadius * math.cos(_planet!.angle);
    final planetPos = Offset(planetX, planetY);

    _planet!.trail.add(planetPos);
    if (_planet!.trail.length > _planet!.maxTrailLength) {
      _planet!.trail.removeAt(0);
    }

    // 绘制行星轨迹 - 渐变圆球
    if (_planet!.trail.length > 1) {
      for (var i = 0; i < _planet!.trail.length; i++) {
        final progress = i / _planet!.trail.length;
        final radius = 0.5 + progress * 2.5;
        final alpha = 0.1 + progress * 0.7;
        final red = (0 + progress * 100).toInt().clamp(0, 255);
        final green = (150 + progress * 105).toInt().clamp(0, 255);

        final trailPaint = Paint()
          ..color = Color.fromRGBO(red, green, 0, alpha)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(_planet!.trail[i], radius, trailPaint);
      }
    }

    // 绘制行星
    final planetPaint = Paint()
      ..color = _planet!.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(planetPos, _planet!.size, planetPaint);

    // 绘制行星光晕
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              _planet!.color.withValues(alpha: 0.6),
              _planet!.color.withValues(alpha: 0.3),
              Colors.transparent,
            ],
            stops: const [0.3, 0.6, 1.0],
          ).createShader(
            Rect.fromCircle(center: planetPos, radius: _planet!.size * 2.5),
          );
    canvas.drawCircle(planetPos, _planet!.size * 2.5, glowPaint);

    // 更新卫星位置
    _moon!.angle += _moon!.speed;
    final moonX = planetX + _moon!.orbitRadius * math.sin(_moon!.angle);
    final moonY = planetY + _moon!.orbitRadius * math.cos(_moon!.angle);
    final moonPos = Offset(moonX, moonY);

    _moon!.trail.add(moonPos);
    if (_moon!.trail.length > _moon!.maxTrailLength) {
      _moon!.trail.removeAt(0);
    }

    // 绘制卫星轨迹 - 渐变圆球
    if (_moon!.trail.length > 1) {
      for (var i = 0; i < _moon!.trail.length; i++) {
        final progress = i / _moon!.trail.length;
        final radius = 0.3 + progress * 1.7;
        final alpha = 0.1 + progress * 0.6;
        final red = (150 + progress * 105).toInt().clamp(0, 255);

        final moonTrailPaint = Paint()
          ..color = Color.fromRGBO(red, 0, 0, alpha)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(_moon!.trail[i], radius, moonTrailPaint);
      }
    }

    // 绘制卫星
    final moonPaint = Paint()
      ..color = _moon!.color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(moonPos, _moon!.size, moonPaint);

    // 绘制卫星微光
    final moonGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _moon!.color.withValues(alpha: 0.8),
          _moon!.color.withValues(alpha: 0.4),
          Colors.transparent,
        ],
        stops: const [0.2, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: moonPos, radius: _moon!.size * 2));
    canvas.drawCircle(moonPos, _moon!.size * 2, moonGlowPaint);
  }

  @override
  bool shouldRepaint(StarrySkyPainter oldDelegate) => true;
}

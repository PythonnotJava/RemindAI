import 'pet_sprite.dart';

/// 内置宠物精灵定义注册表
///
/// 设计目标：
/// - 内置精灵在此静态定义
/// - 用户自定义精灵通过 JSON 加载后追加
/// - 提供统一查找接口
class PetRegistry {
  PetRegistry._();
  static final instance = PetRegistry._();

  final List<PetSpriteSheet> _sprites = [..._builtinSprites];

  List<PetSpriteSheet> get all => List.unmodifiable(_sprites);

  PetSpriteSheet? findById(String id) {
    for (final s in _sprites) {
      if (s.id == id) return s;
    }
    return null;
  }

  void register(PetSpriteSheet sprite) {
    _sprites.removeWhere((s) => s.id == sprite.id);
    _sprites.add(sprite);
  }

  void unregister(String id) {
    _sprites.removeWhere((s) => s.id == id);
  }
}

/// 内置精灵：灰色猫咪 (cat 1.png)
/// 基于 last-tick 32x32 kittens 精灵图布局
/// 352x1696 → 11列 x 53行，每帧 32x32
///
/// 动画行分布（通过像素分析确认）：
/// Row 0 (6帧): idle 站立呼吸
/// Row 1 (8帧): idle 变体 (舔毛/伸懒腰)
/// Row 2 (6帧): idle 变体 (抬头/转头)
/// Row 3 (10帧): idle 变体 (打哈欠)
/// Row 4-5 (4帧): sit 坐下
/// Row 6-7 (8帧): walk 行走
/// Row 8-9 (6帧): run 奔跑
/// Row 10-11 (6帧): run 变体
/// Row 12-19 (2帧): sleep 睡觉
/// Row 20-23 (8帧): jump/play 跳跃
/// Row 24-27 (8帧): play/interact 互动
/// Row 28-31 (3帧): groom 梳理
/// Row 32-35 (8帧): walk 变体
/// Row 36-37 (9帧): climb 攀爬
/// Row 38 (7帧): stretch 伸展
/// Row 39-40 (11帧): long animation
/// Row 44-52: 更多变体动画
const _builtinSprites = <PetSpriteSheet>[
  PetSpriteSheet(
    id: 'builtin_cat_gray',
    name: 'petCatGray',
    assetPath: 'assets/pets/Cat/cat 1.png',
    frameWidth: 32,
    frameHeight: 32,
    columns: 11,
    rows: 53,
    animations: [
      SpriteAnimation(name: 'idle', startRow: 0, frameCount: 6, fps: 4),
      SpriteAnimation(name: 'idle_groom', startRow: 1, frameCount: 8, fps: 6),
      SpriteAnimation(name: 'idle_look', startRow: 2, frameCount: 6, fps: 5),
      SpriteAnimation(
        name: 'yawn',
        startRow: 3,
        frameCount: 10,
        fps: 6,
        loop: false,
      ),
      SpriteAnimation(name: 'sit', startRow: 4, frameCount: 4, fps: 3),
      SpriteAnimation(
        name: 'walk',
        startRow: 6,
        frameCount: 8,
        fps: 8,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(
        name: 'run',
        startRow: 8,
        frameCount: 6,
        fps: 10,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(name: 'sleep', startRow: 12, frameCount: 2, fps: 2),
      SpriteAnimation(
        name: 'jump',
        startRow: 20,
        frameCount: 8,
        fps: 10,
        loop: false,
      ),
      SpriteAnimation(
        name: 'interact',
        startRow: 24,
        frameCount: 8,
        fps: 8,
        loop: false,
      ),
      SpriteAnimation(
        name: 'happy',
        startRow: 28,
        frameCount: 3,
        fps: 5,
        loop: false,
      ),
      SpriteAnimation(name: 'climb', startRow: 36, frameCount: 9, fps: 8),
      SpriteAnimation(
        name: 'stretch',
        startRow: 38,
        frameCount: 7,
        fps: 6,
        loop: false,
      ),
    ],
  ),
  // 橘色猫
  PetSpriteSheet(
    id: 'builtin_cat_orange',
    name: 'petCatOrange',
    assetPath: 'assets/pets/Cat/cat 1.6.png',
    frameWidth: 32,
    frameHeight: 32,
    columns: 11,
    rows: 53,
    animations: [
      SpriteAnimation(name: 'idle', startRow: 0, frameCount: 6, fps: 4),
      SpriteAnimation(name: 'idle_groom', startRow: 1, frameCount: 8, fps: 6),
      SpriteAnimation(name: 'idle_look', startRow: 2, frameCount: 6, fps: 5),
      SpriteAnimation(
        name: 'yawn',
        startRow: 3,
        frameCount: 10,
        fps: 6,
        loop: false,
      ),
      SpriteAnimation(name: 'sit', startRow: 4, frameCount: 4, fps: 3),
      SpriteAnimation(
        name: 'walk',
        startRow: 6,
        frameCount: 8,
        fps: 8,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(
        name: 'run',
        startRow: 8,
        frameCount: 6,
        fps: 10,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(name: 'sleep', startRow: 12, frameCount: 2, fps: 2),
      SpriteAnimation(
        name: 'jump',
        startRow: 20,
        frameCount: 8,
        fps: 10,
        loop: false,
      ),
      SpriteAnimation(
        name: 'interact',
        startRow: 24,
        frameCount: 8,
        fps: 8,
        loop: false,
      ),
      SpriteAnimation(
        name: 'happy',
        startRow: 28,
        frameCount: 3,
        fps: 5,
        loop: false,
      ),
      SpriteAnimation(name: 'climb', startRow: 36, frameCount: 9, fps: 8),
      SpriteAnimation(
        name: 'stretch',
        startRow: 38,
        frameCount: 7,
        fps: 6,
        loop: false,
      ),
    ],
  ),
  // 白色猫
  PetSpriteSheet(
    id: 'builtin_cat_white',
    name: 'petCatWhite',
    assetPath: 'assets/pets/Cat/cat 1.9.png',
    frameWidth: 32,
    frameHeight: 32,
    columns: 11,
    rows: 53,
    animations: [
      SpriteAnimation(name: 'idle', startRow: 0, frameCount: 6, fps: 4),
      SpriteAnimation(name: 'idle_groom', startRow: 1, frameCount: 8, fps: 6),
      SpriteAnimation(name: 'idle_look', startRow: 2, frameCount: 6, fps: 5),
      SpriteAnimation(
        name: 'yawn',
        startRow: 3,
        frameCount: 10,
        fps: 6,
        loop: false,
      ),
      SpriteAnimation(name: 'sit', startRow: 4, frameCount: 4, fps: 3),
      SpriteAnimation(
        name: 'walk',
        startRow: 6,
        frameCount: 8,
        fps: 8,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(
        name: 'run',
        startRow: 8,
        frameCount: 6,
        fps: 10,
        direction: SpriteDirection.right,
      ),
      SpriteAnimation(name: 'sleep', startRow: 12, frameCount: 2, fps: 2),
      SpriteAnimation(
        name: 'jump',
        startRow: 20,
        frameCount: 8,
        fps: 10,
        loop: false,
      ),
      SpriteAnimation(
        name: 'interact',
        startRow: 24,
        frameCount: 8,
        fps: 8,
        loop: false,
      ),
      SpriteAnimation(
        name: 'happy',
        startRow: 28,
        frameCount: 3,
        fps: 5,
        loop: false,
      ),
      SpriteAnimation(name: 'climb', startRow: 36, frameCount: 9, fps: 8),
      SpriteAnimation(
        name: 'stretch',
        startRow: 38,
        frameCount: 7,
        fps: 6,
        loop: false,
      ),
    ],
  ),
];

/// 精灵图定义 — 描述一个精灵图集的元数据
///
/// 设计目标：
/// - 与具体渲染/状态机完全解耦
/// - 支持任意帧尺寸、任意行列布局
/// - 支持从 asset bundle 或文件系统加载
/// - 每个动画(animation)由名称、起始行、帧数、帧率、是否循环定义
class PetSpriteSheet {
  /// 唯一标识，用于持久化引用
  final String id;

  /// 显示名称
  final String name;

  /// 资源路径 (asset path 或 file:// URI)
  final String assetPath;

  /// 单帧宽度 (像素)
  final int frameWidth;

  /// 单帧高度 (像素)
  final int frameHeight;

  /// 图集总列数
  final int columns;

  /// 图集总行数
  final int rows;

  /// 动画定义列表
  final List<SpriteAnimation> animations;

  const PetSpriteSheet({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.rows,
    required this.animations,
  });

  /// 从 JSON 反序列化（用于用户自定义精灵）
  factory PetSpriteSheet.fromJson(Map<String, dynamic> json) {
    return PetSpriteSheet(
      id: json['id'] as String,
      name: json['name'] as String,
      assetPath: json['assetPath'] as String,
      frameWidth: json['frameWidth'] as int? ?? 32,
      frameHeight: json['frameHeight'] as int? ?? 32,
      columns: json['columns'] as int? ?? 11,
      rows: json['rows'] as int? ?? 53,
      animations:
          (json['animations'] as List<dynamic>?)
              ?.map((e) => SpriteAnimation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'assetPath': assetPath,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'columns': columns,
    'rows': rows,
    'animations': animations.map((a) => a.toJson()).toList(),
  };

  /// 通过名称查找动画，找不到返回 null
  SpriteAnimation? findAnimation(String name) {
    for (final anim in animations) {
      if (anim.name == name) return anim;
    }
    return null;
  }
}

/// 单个动画定义
class SpriteAnimation {
  /// 动画名称（如 idle, walk, sleep, jump ...）
  final String name;

  /// 在精灵图中的起始行（0-based）
  final int startRow;

  /// 起始列（默认0，支持同行内多个动画）
  final int startColumn;

  /// 总帧数
  final int frameCount;

  /// 帧率 (fps)
  final double fps;

  /// 是否循环播放
  final bool loop;

  /// 动画方向提示（用于行走等有方向的动画）
  final SpriteDirection direction;

  const SpriteAnimation({
    required this.name,
    required this.startRow,
    this.startColumn = 0,
    required this.frameCount,
    this.fps = 8.0,
    this.loop = true,
    this.direction = SpriteDirection.none,
  });

  factory SpriteAnimation.fromJson(Map<String, dynamic> json) {
    return SpriteAnimation(
      name: json['name'] as String,
      startRow: json['startRow'] as int,
      startColumn: json['startColumn'] as int? ?? 0,
      frameCount: json['frameCount'] as int,
      fps: (json['fps'] as num?)?.toDouble() ?? 8.0,
      loop: json['loop'] as bool? ?? true,
      direction: SpriteDirection.values.firstWhere(
        (d) => d.name == (json['direction'] as String? ?? 'none'),
        orElse: () => SpriteDirection.none,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'startRow': startRow,
    'startColumn': startColumn,
    'frameCount': frameCount,
    'fps': fps,
    'loop': loop,
    'direction': direction.name,
  };
}

/// 精灵方向
enum SpriteDirection { none, left, right, up, down }

/// 技能数据模型
class Skill {
  final String id;
  final String name;
  final String description;
  final String path;
  final int toolCount;
  final bool isActive;
  final bool isBuiltIn;
  final DateTime installedAt;
  final int sortIndex;

  /// 是否为项目级临时技能 (来自工作目录的 .toolshell/skills/)。
  /// 此类技能在所属工作目录下恒定激活，不参与全局启用/停用，
  /// 且生命周期跟随工作目录 (切换目录即消失，不可删除/排序)。
  final bool isProjectLevel;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.path,
    required this.toolCount,
    this.isActive = true,
    this.isBuiltIn = false,
    required this.installedAt,
    this.sortIndex = 0,
    this.isProjectLevel = false,
  });

  Skill copyWith({bool? isActive, int? sortIndex}) {
    return Skill(
      id: id,
      name: name,
      description: description,
      path: path,
      toolCount: toolCount,
      isActive: isActive ?? this.isActive,
      isBuiltIn: isBuiltIn,
      installedAt: installedAt,
      sortIndex: sortIndex ?? this.sortIndex,
      isProjectLevel: isProjectLevel,
    );
  }
}

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
    );
  }
}

import 'package:uuid/uuid.dart';

/// 领域专家配置
class Expert {
  final String id;
  final String name;
  final String icon; // Material Icons 名称
  final String description;
  final String systemPrompt;
  final List<String> boundSkills; // 绑定的技能 ID
  final String category; // 分类: 创意/技术/分析/办公/自定义
  final bool isBuiltin; // 是否为内置专家 (不可删除)
  final DateTime createdAt;

  Expert({
    String? id,
    required this.name,
    this.icon = 'person',
    this.description = '',
    required this.systemPrompt,
    this.boundSkills = const [],
    this.category = '自定义',
    this.isBuiltin = false,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Expert copyWith({
    String? name,
    String? icon,
    String? description,
    String? systemPrompt,
    List<String>? boundSkills,
    String? category,
    bool? isBuiltin,
  }) {
    return Expert(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      boundSkills: boundSkills ?? this.boundSkills,
      category: category ?? this.category,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'description': description,
    'systemPrompt': systemPrompt,
    'boundSkills': boundSkills,
    'category': category,
    'isBuiltin': isBuiltin,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Expert.fromJson(Map<String, dynamic> json) {
    return Expert(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'person',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      boundSkills: (json['boundSkills'] as List?)?.cast<String>() ?? [],
      category: json['category'] as String? ?? '自定义',
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

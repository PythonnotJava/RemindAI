import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';

/// Agent 的运行状态
enum AgentStatus {
  idle, // 空闲
  thinking, // 正在思考/调用LLM
  tooling, // 正在执行工具
  error, // 出错
}

/// Agent 角色类型
enum AgentRole {
  commander, // 总指挥（唯一）
  worker, // 普通工作Agent
  reviewer, // 审查Agent
  researcher, // 研究Agent
  coder, // 编码Agent
  custom, // 自定义
}

extension AgentRoleExt on AgentRole {
  String get label => switch (this) {
    AgentRole.commander => '总指挥',
    AgentRole.worker => '工作者',
    AgentRole.reviewer => '审查员',
    AgentRole.researcher => '研究员',
    AgentRole.coder => '编码员',
    AgentRole.custom => '自定义',
  };

  String localizedLabel(BuildContext context) => switch (this) {
    AgentRole.commander => context.s.agentRoleCommander,
    AgentRole.worker => context.s.agentRoleWorker,
    AgentRole.reviewer => context.s.agentRoleReviewer,
    AgentRole.researcher => context.s.agentRoleResearcher,
    AgentRole.coder => context.s.agentRoleCoder,
    AgentRole.custom => context.s.agentRoleCustom,
  };

  IconData get icon => switch (this) {
    AgentRole.commander => Icons.military_tech,
    AgentRole.worker => Icons.engineering,
    AgentRole.reviewer => Icons.rate_review,
    AgentRole.researcher => Icons.science,
    AgentRole.coder => Icons.code,
    AgentRole.custom => Icons.smart_toy,
  };

  Color get color => switch (this) {
    AgentRole.commander => const Color(0xFFFFD700),
    AgentRole.worker => const Color(0xFF4FC3F7),
    AgentRole.reviewer => const Color(0xFFAB47BC),
    AgentRole.researcher => const Color(0xFF66BB6A),
    AgentRole.coder => const Color(0xFFFF7043),
    AgentRole.custom => const Color(0xFF78909C),
  };
}

/// Agent 权限
enum AgentPermission {
  fileRead, // 读取文件
  fileWrite, // 写入/创建文件
  fileDelete, // 删除文件
  exec, // 执行命令
  network, // 网络访问
}

extension AgentPermissionExt on AgentPermission {
  String get label => switch (this) {
    AgentPermission.fileRead => '读文件',
    AgentPermission.fileWrite => '写文件',
    AgentPermission.fileDelete => '删文件',
    AgentPermission.exec => '执行命令',
    AgentPermission.network => '网络',
  };

  String localizedLabel(BuildContext context) => switch (this) {
    AgentPermission.fileRead => context.s.agentPermRead,
    AgentPermission.fileWrite => context.s.agentPermWrite,
    AgentPermission.fileDelete => context.s.agentPermDelete,
    AgentPermission.exec => context.s.agentPermExec,
    AgentPermission.network => context.s.agentPermNetwork,
  };

  IconData get icon => switch (this) {
    AgentPermission.fileRead => Icons.visibility,
    AgentPermission.fileWrite => Icons.edit_note,
    AgentPermission.fileDelete => Icons.delete_outline,
    AgentPermission.exec => Icons.terminal,
    AgentPermission.network => Icons.wifi,
  };
}

/// 单个 Agent 的配置
class AgentConfig {
  final String id;
  final String name;
  final AgentRole role;
  final String systemPrompt;
  final String modelCardId; // 引用 ModelCard.id
  final List<String> enabledTools; // 允许使用的工具id列表
  final List<String> enabledSkills; // 挂载的技能 (如 'system', 'toolshell')
  final List<String> permissions; // 权限列表
  final bool closable; // 是否可关闭（指挥部不可关闭）

  const AgentConfig({
    required this.id,
    required this.name,
    required this.role,
    required this.systemPrompt,
    required this.modelCardId,
    this.enabledTools = const [],
    this.enabledSkills = const [],
    this.permissions = const [],
    this.closable = true,
  });

  AgentConfig copyWith({
    String? name,
    AgentRole? role,
    String? systemPrompt,
    String? modelCardId,
    List<String>? enabledTools,
    List<String>? enabledSkills,
    List<String>? permissions,
    bool? closable,
  }) {
    return AgentConfig(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelCardId: modelCardId ?? this.modelCardId,
      enabledTools: enabledTools ?? this.enabledTools,
      enabledSkills: enabledSkills ?? this.enabledSkills,
      permissions: permissions ?? this.permissions,
      closable: closable ?? this.closable,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'systemPrompt': systemPrompt,
    'modelCardId': modelCardId,
    'enabledTools': enabledTools,
    'enabledSkills': enabledSkills,
    'permissions': permissions,
    'closable': closable,
  };

  factory AgentConfig.fromJson(Map<String, dynamic> json) => AgentConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    role: AgentRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => AgentRole.custom,
    ),
    systemPrompt: json['systemPrompt'] as String? ?? '',
    modelCardId: json['modelCardId'] as String? ?? '',
    enabledTools: (json['enabledTools'] as List?)?.cast<String>() ?? [],
    enabledSkills: (json['enabledSkills'] as List?)?.cast<String>() ?? [],
    permissions: (json['permissions'] as List?)?.cast<String>() ?? [],
    closable: json['closable'] as bool? ?? true,
  );
}

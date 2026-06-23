import 'dart:io';

/// 用户自定义模型配置 (通过 WebSocket 传入)
class UserModelConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final String provider; // openai / anthropic / gemini

  UserModelConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    required this.provider,
  });

  factory UserModelConfig.fromJson(Map<String, dynamic> json) =>
      UserModelConfig(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        modelId: json['modelId'] as String? ?? '',
        provider: json['provider'] as String? ?? 'openai',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'modelId': modelId,
    'provider': provider,
  };
}

/// 会话中生成的文件产物
class SessionArtifact {
  final String id;
  final String filename;
  final String content;
  final String language;
  final DateTime createdAt;

  SessionArtifact({
    required this.id,
    required this.filename,
    required this.content,
    this.language = '',
  }) : createdAt = DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'filename': filename,
    'language': language,
    'size': content.length,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 在线用户会话 — 每个 WebSocket 连接一个独立实例
class OnlineSession {
  final String id;
  final String clientIp;
  final String nickname;
  final WebSocket ws;
  final DateTime connectedAt;
  final List<String> allowedModelCardIds;
  final bool mcpEnabled;
  final List<String> mcpServerIds;
  final bool skillEnabled;
  final List<String> skillIds;
  final String searchProvider; // "none" | "tavily" | "brave" | "baidu"
  final bool isAdmin; // 127.0.0.1 管理员

  /// 独立的 LLM 消息历史 (OpenAI 格式)
  final List<Map<String, dynamic>> messages = [];

  /// 当前是否正在处理请求
  bool busy = false;

  /// 用户自定义模型列表
  final List<UserModelConfig> userModels = [];

  /// 产物文件列表
  final List<SessionArtifact> artifacts = [];

  /// 管理员运行时 MCP/Skill 开关 (热插拔)
  final Set<String> activeMcpServerIds = {};
  final Set<String> activeSkillIds = {};

  OnlineSession({
    required this.id,
    required this.clientIp,
    required this.nickname,
    required this.ws,
    required this.allowedModelCardIds,
    this.mcpEnabled = false,
    this.mcpServerIds = const [],
    this.skillEnabled = false,
    this.skillIds = const [],
    this.searchProvider = 'none',
    this.isAdmin = false,
  }) : connectedAt = DateTime.now();

  Map<String, dynamic> toInfo() => {
    'id': id,
    'ip': clientIp,
    'nickname': nickname,
    'connectedAt': connectedAt.toIso8601String(),
    'busy': busy,
    'messageCount': messages.length,
    'modelCount': allowedModelCardIds.length,
    'userModelCount': userModels.length,
    'artifactCount': artifacts.length,
    'mcpEnabled': mcpEnabled,
    'skillEnabled': skillEnabled,
    'searchProvider': searchProvider,
    'isAdmin': isAdmin,
  };
}

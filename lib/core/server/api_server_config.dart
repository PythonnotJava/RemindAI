import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 对外服务端的记忆档位。
///
/// - [none]    服务端不挂载任何长期记忆 (最安全, 默认)
/// - [isolated] 服务端使用独立 collection, 与主程序记忆物理隔离, 互不可见
/// - [shared]   服务端与主程序共用 global_memory (会读写用户主记忆, 谨慎使用)
enum ServerMemoryMode {
  none,
  isolated,
  shared;

  String get id => name;

  static ServerMemoryMode fromId(String? id) => ServerMemoryMode.values
      .firstWhere((e) => e.id == id, orElse: () => ServerMemoryMode.none);
}

/// 对外 HTTP API 服务的配置。
///
/// 独立持久化到 `api_server.json`, 与主程序的会话状态完全解耦:
/// 外部客户端拿到的能力由这份固定配置决定, 不随用户在界面上的临时操作而变化。
///
/// 安全默认值: 服务关闭、仅绑定 127.0.0.1、必须配置 token。
class ApiServerConfig {
  /// 服务是否启用 (默认关闭)
  final bool enabled;

  /// 监听端口 (默认 1228, 用户可改)
  final int port;

  /// 是否绑定到所有网卡 (0.0.0.0)。默认 false → 仅 127.0.0.1, 只允许本机访问。
  /// 开启即把已配置的模型/记忆/工具暴露到局域网, 需用户显式确认。
  final bool bindAll;

  /// 访问令牌。请求需在 `Authorization: Bearer <token>` 中携带。
  /// 为空时服务拒绝启动 (强制鉴权)。
  final String token;

  /// 三个对外端点的开关 (可独立启停, 互不影响)。
  ///
  /// - [enableOpenAi]      OpenAI 聚合: `POST /v1/chat/completions`,
  ///   跑 RemindAI 自己的 Agent (技能/MCP/记忆/搜索)。
  /// - [enableClaudeAgent] Claude 聚合: `POST /v1/agent/messages`,
  ///   同样跑聚合 Agent, 但以 Anthropic 协议输出。
  /// - [enableClaudeProxy] Claude 纯代理: `POST /v1/messages`,
  ///   纯协议转换, 透传客户端工具由其自行执行 (供 CherryStudio Agent 接入)。
  ///   令牌同时支持 `x-api-key` 头。
  final bool enableOpenAi;
  final bool enableClaudeAgent;
  final bool enableClaudeProxy;

  /// 服务端使用的模型卡 id (引用 ModelCardsDao 中的卡)。空 → 用第一张可用卡。
  /// 仅作为未指定模型时的回退提示, 实际可用范围由 [allowedModelCardIds] 决定。
  final String modelCardId;

  /// 对外开放的模型卡 id 白名单。
  /// 空列表 = 开放所有模型卡 (客户端可任选)。
  /// 非空 = 仅这些模型卡对外可见且可被请求 (`/v1/models` 仅列出它们)。
  final List<String> allowedModelCardIds;

  /// 服务端启用的用户技能 id 列表。空列表 → 不挂载任何用户技能。
  final List<String> skillIds;

  /// 服务端启用的 MCP server id 列表 (引用已连接的 MCP)。空 → 不挂载 MCP。
  final List<String> mcpServerIds;

  /// 记忆档位。
  final ServerMemoryMode memoryMode;

  /// 独立记忆模式下使用的 collection 名 (memoryMode == isolated 时生效)。
  final String memoryCollection;

  /// 搜索引擎 provider id (none/tavily/brave/baidu)。空或 none → 不挂载搜索。
  final String searchProviderId;

  /// IP 白名单。空列表 = 不限制 (仅本机访问时无需限制)。
  /// 非空 = 仅列表内地址可访问 (本机回环地址始终放行, 避免自锁)。
  /// 支持精确 IP (192.168.1.5) 与 CIDR 网段 (192.168.1.0/24)。
  final List<String> ipWhitelist;

  const ApiServerConfig({
    this.enabled = false,
    this.port = 1228,
    this.bindAll = false,
    this.token = '',
    this.enableOpenAi = true,
    this.enableClaudeAgent = false,
    this.enableClaudeProxy = true,
    this.modelCardId = '',
    this.allowedModelCardIds = const [],
    this.skillIds = const [],
    this.mcpServerIds = const [],
    this.memoryMode = ServerMemoryMode.none,
    this.memoryCollection = 'server_memory',
    this.searchProviderId = 'none',
    this.ipWhitelist = const [],
  });

  /// 配置是否完整到可以启动服务 (启用 + 有 token + 端口合法)。
  bool get canStart =>
      enabled && token.trim().isNotEmpty && port > 0 && port <= 65535;

  ApiServerConfig copyWith({
    bool? enabled,
    int? port,
    bool? bindAll,
    String? token,
    bool? enableOpenAi,
    bool? enableClaudeAgent,
    bool? enableClaudeProxy,
    String? modelCardId,
    List<String>? allowedModelCardIds,
    List<String>? skillIds,
    List<String>? mcpServerIds,
    ServerMemoryMode? memoryMode,
    String? memoryCollection,
    String? searchProviderId,
    List<String>? ipWhitelist,
  }) {
    return ApiServerConfig(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      bindAll: bindAll ?? this.bindAll,
      token: token ?? this.token,
      enableOpenAi: enableOpenAi ?? this.enableOpenAi,
      enableClaudeAgent: enableClaudeAgent ?? this.enableClaudeAgent,
      enableClaudeProxy: enableClaudeProxy ?? this.enableClaudeProxy,
      modelCardId: modelCardId ?? this.modelCardId,
      allowedModelCardIds: allowedModelCardIds ?? this.allowedModelCardIds,
      skillIds: skillIds ?? this.skillIds,
      mcpServerIds: mcpServerIds ?? this.mcpServerIds,
      memoryMode: memoryMode ?? this.memoryMode,
      memoryCollection: memoryCollection ?? this.memoryCollection,
      searchProviderId: searchProviderId ?? this.searchProviderId,
      ipWhitelist: ipWhitelist ?? this.ipWhitelist,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'bindAll': bindAll,
    'token': token,
    'enableOpenAi': enableOpenAi,
    'enableClaudeAgent': enableClaudeAgent,
    'enableClaudeProxy': enableClaudeProxy,
    'modelCardId': modelCardId,
    'allowedModelCardIds': allowedModelCardIds,
    'skillIds': skillIds,
    'mcpServerIds': mcpServerIds,
    'memoryMode': memoryMode.id,
    'memoryCollection': memoryCollection,
    'searchProviderId': searchProviderId,
    'ipWhitelist': ipWhitelist,
  };

  factory ApiServerConfig.fromJson(Map<String, dynamic> json) {
    return ApiServerConfig(
      enabled: json['enabled'] as bool? ?? false,
      port: (json['port'] as num?)?.toInt() ?? 1228,
      bindAll: json['bindAll'] as bool? ?? false,
      token: json['token'] as String? ?? '',
      enableOpenAi: json['enableOpenAi'] as bool? ?? true,
      enableClaudeAgent: json['enableClaudeAgent'] as bool? ?? false,
      enableClaudeProxy:
          json['enableClaudeProxy'] as bool? ??
          (json['enableAnthropic'] as bool? ?? true),
      modelCardId: json['modelCardId'] as String? ?? '',
      allowedModelCardIds:
          (json['allowedModelCardIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      skillIds:
          (json['skillIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      mcpServerIds:
          (json['mcpServerIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      memoryMode: ServerMemoryMode.fromId(json['memoryMode'] as String?),
      memoryCollection: json['memoryCollection'] as String? ?? 'server_memory',
      searchProviderId: json['searchProviderId'] as String? ?? 'none',
      ipWhitelist:
          (json['ipWhitelist'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  static Future<String> get _filePath async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'api_server.json');
  }

  /// 从磁盘加载配置, 不存在则返回默认值。
  static Future<ApiServerConfig> load() async {
    try {
      final file = File(await _filePath);
      if (!await file.exists()) return const ApiServerConfig();
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ApiServerConfig.fromJson(json);
    } catch (_) {
      return const ApiServerConfig();
    }
  }

  /// 持久化到磁盘。
  Future<void> save() async {
    final file = File(await _filePath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }
}

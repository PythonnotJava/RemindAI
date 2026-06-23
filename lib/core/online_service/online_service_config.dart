import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 白名单条目 — 每个 IP/IP段 分配独立的模型和能力
class WhitelistEntry {
  final String ip; // "192.168.1.10" 或 "192.168.1.0/24"
  final String nickname; // 显示名称
  final List<String> allowedModelCardIds; // 允许的模型卡 ID 列表
  final bool mcpEnabled;
  final List<String> mcpServerIds; // 允许的 MCP server ID 列表
  final bool skillEnabled;
  final List<String> skillIds; // 允许的 Skill ID 列表
  final String searchProvider; // 联网搜索: "none" | "tavily" | "brave" | "baidu"

  const WhitelistEntry({
    required this.ip,
    this.nickname = '',
    this.allowedModelCardIds = const [],
    this.mcpEnabled = false,
    this.mcpServerIds = const [],
    this.skillEnabled = false,
    this.skillIds = const [],
    this.searchProvider = 'none',
  });

  WhitelistEntry copyWith({
    String? ip,
    String? nickname,
    List<String>? allowedModelCardIds,
    bool? mcpEnabled,
    List<String>? mcpServerIds,
    bool? skillEnabled,
    List<String>? skillIds,
    String? searchProvider,
  }) => WhitelistEntry(
    ip: ip ?? this.ip,
    nickname: nickname ?? this.nickname,
    allowedModelCardIds: allowedModelCardIds ?? this.allowedModelCardIds,
    mcpEnabled: mcpEnabled ?? this.mcpEnabled,
    mcpServerIds: mcpServerIds ?? this.mcpServerIds,
    skillEnabled: skillEnabled ?? this.skillEnabled,
    skillIds: skillIds ?? this.skillIds,
    searchProvider: searchProvider ?? this.searchProvider,
  );

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'nickname': nickname,
    'allowedModelCardIds': allowedModelCardIds,
    'mcpEnabled': mcpEnabled,
    'mcpServerIds': mcpServerIds,
    'skillEnabled': skillEnabled,
    'skillIds': skillIds,
    'searchProvider': searchProvider,
  };

  factory WhitelistEntry.fromJson(Map<String, dynamic> json) => WhitelistEntry(
    ip: json['ip'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    allowedModelCardIds:
        (json['allowedModelCardIds'] as List?)?.cast<String>() ?? const [],
    mcpEnabled: json['mcpEnabled'] as bool? ?? false,
    mcpServerIds: (json['mcpServerIds'] as List?)?.cast<String>() ?? const [],
    skillEnabled: json['skillEnabled'] as bool? ?? false,
    skillIds: (json['skillIds'] as List?)?.cast<String>() ?? const [],
    searchProvider: json['searchProvider'] as String? ?? 'none',
  );
}

/// 在线服务配置
class OnlineServiceConfig {
  final bool enabled;
  final int port;
  final int maxConnections;
  final bool accepting; // 是否接受新连接 (拉闸开关)
  final List<WhitelistEntry> whitelist;

  const OnlineServiceConfig({
    this.enabled = false,
    this.port = 2002,
    this.maxConnections = 5,
    this.accepting = true,
    this.whitelist = const [],
  });

  bool get canStart => enabled && port > 0 && port < 65536;

  OnlineServiceConfig copyWith({
    bool? enabled,
    int? port,
    int? maxConnections,
    bool? accepting,
    List<WhitelistEntry>? whitelist,
  }) => OnlineServiceConfig(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    maxConnections: maxConnections ?? this.maxConnections,
    accepting: accepting ?? this.accepting,
    whitelist: whitelist ?? this.whitelist,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'maxConnections': maxConnections,
    'accepting': accepting,
    'whitelist': whitelist.map((e) => e.toJson()).toList(),
  };

  factory OnlineServiceConfig.fromJson(Map<String, dynamic> json) =>
      OnlineServiceConfig(
        enabled: json['enabled'] as bool? ?? false,
        port: json['port'] as int? ?? 2002,
        maxConnections: json['maxConnections'] as int? ?? 5,
        accepting: json['accepting'] as bool? ?? true,
        whitelist:
            (json['whitelist'] as List?)
                ?.map((e) => WhitelistEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// 持久化路径
  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/online_service.json');
  }

  /// 从磁盘加载
  static Future<OnlineServiceConfig> load() async {
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        return OnlineServiceConfig.fromJson(json as Map<String, dynamic>);
      }
    } catch (_) {}
    return const OnlineServiceConfig();
  }

  /// 保存到磁盘
  Future<void> save() async {
    final file = await _configFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  /// 检查 IP 是否在白名单中
  WhitelistEntry? matchIp(String clientIp) {
    for (final entry in whitelist) {
      if (_ipMatches(clientIp, entry.ip)) return entry;
    }
    return null;
  }

  static bool _ipMatches(String clientIp, String pattern) {
    if (pattern == clientIp) return true;
    // CIDR 匹配: "192.168.1.0/24"
    if (pattern.contains('/')) {
      final parts = pattern.split('/');
      final subnet = parts[0];
      final mask = int.tryParse(parts[1]) ?? 32;
      return _cidrMatch(clientIp, subnet, mask);
    }
    // 通配符: "192.168.1.*"
    if (pattern.contains('*')) {
      final regex = RegExp(
        '^${pattern.replaceAll('.', r'\.').replaceAll('*', r'\d+')}',
      );
      return regex.hasMatch(clientIp);
    }
    return false;
  }

  static bool _cidrMatch(String ip, String subnet, int mask) {
    try {
      final ipNum = _ipToInt(ip);
      final subnetNum = _ipToInt(subnet);
      final maskBits = (0xFFFFFFFF << (32 - mask)) & 0xFFFFFFFF;
      return (ipNum & maskBits) == (subnetNum & maskBits);
    } catch (_) {
      return false;
    }
  }

  static int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }
}

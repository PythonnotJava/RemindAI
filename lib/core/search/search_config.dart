/// AI 搜索服务配置
library;

/// 搜索服务提供商枚举
enum SearchProvider {
  none,
  tavily,
  brave,
  baidu;

  String get id => name;

  static SearchProvider fromId(String id) {
    return SearchProvider.values.firstWhere(
      (e) => e.id == id,
      orElse: () => SearchProvider.none,
    );
  }
}

/// 单个搜索服务的配置
class SearchServiceConfig {
  final String apiKey;
  final bool enabled;

  const SearchServiceConfig({this.apiKey = '', this.enabled = false});

  bool get isConfigured => apiKey.isNotEmpty;

  SearchServiceConfig copyWith({String? apiKey, bool? enabled}) {
    return SearchServiceConfig(
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {'apiKey': apiKey, 'enabled': enabled};

  factory SearchServiceConfig.fromJson(Map<String, dynamic> json) {
    return SearchServiceConfig(
      apiKey: json['apiKey'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

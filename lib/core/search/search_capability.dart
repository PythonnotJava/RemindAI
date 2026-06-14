import 'dart:convert';

import '../agent/agent_capability.dart';
import '../agent/tool_pipeline.dart';
import 'search_config.dart';
import 'search_service.dart';

/// 搜索能力 — AgentCapability 的第一个标准实现
///
/// 当用户在会话中选择了搜索引擎 (Tavily / Brave / Baidu) 且 API Key 已配置时，
/// 自动向 LLM 注册 `web_search` 工具。LLM 根据用户问题智能判断是否调用。
class SearchCapability extends AgentCapability {
  final SearchProvider provider;
  final String apiKey;

  SearchCapability({required this.provider, required this.apiKey});

  @override
  String get id => 'search_${provider.id}';

  @override
  String get displayName => '搜索:${provider.id}';

  @override
  bool get isActive => provider != SearchProvider.none && apiKey.isNotEmpty;

  @override
  List<Map<String, dynamic>> get toolDefinitions => [
    {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description':
            '搜索互联网获取最新信息。当用户的问题涉及实时新闻、最新数据、'
            '特定网页内容、当前事件、最新技术文档等需要联网才能回答的内容时使用此工具。'
            '对于常识性问题、代码编写、数学计算等不需要联网的任务，不要调用此工具。',
        'parameters': {
          'type': 'object',
          'required': ['query'],
          'properties': {
            'query': {'type': 'string', 'description': '搜索关键词或查询语句，应该简洁精准'},
            'max_results': {
              'type': 'integer',
              'description': '返回结果数量，默认5，范围1-10',
            },
          },
        },
      },
    },
  ];

  @override
  Map<String, CustomToolHandler> get toolHandlers => {'web_search': _execute};

  Future<String> _execute(Map<String, dynamic> args) async {
    final query = args['query'] as String? ?? '';
    if (query.isEmpty) {
      return jsonEncode({'status': 'error', 'message': '搜索查询不能为空'});
    }

    final maxResults = args['max_results'] as int? ?? 5;

    try {
      final result = await SearchService.instance.search(
        provider: provider,
        query: query,
        apiKey: apiKey,
        maxResults: maxResults.clamp(1, 10),
      );
      return jsonEncode({'status': 'success', 'content': result});
    } catch (e) {
      return jsonEncode({'status': 'error', 'message': '搜索失败: $e'});
    }
  }

  /// 测试连接 — 用简单查询验证 API Key 是否有效
  ///
  /// 返回 null 表示成功，返回错误信息表示失败。
  static Future<String?> testConnection({
    required SearchProvider provider,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) return 'API Key 不能为空';
    if (provider == SearchProvider.none) return '未选择搜索服务';

    try {
      final result = await SearchService.instance.search(
        provider: provider,
        query: 'test',
        apiKey: apiKey,
        maxResults: 1,
      );
      // 如果能正常返回内容就算成功
      if (result.isNotEmpty && !result.contains('error')) {
        return null; // 成功
      }
      return '返回内容异常: ${result.substring(0, result.length.clamp(0, 100))}';
    } catch (e) {
      final msg = e.toString();
      // 解析常见错误
      if (msg.contains('401') ||
          msg.contains('403') ||
          msg.contains('Unauthorized')) {
        return 'API Key 无效或已过期';
      }
      if (msg.contains('429')) {
        return '请求频率超限，请稍后再试';
      }
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        return '网络连接失败，请检查网络';
      }
      return '连接失败: $msg';
    }
  }
}

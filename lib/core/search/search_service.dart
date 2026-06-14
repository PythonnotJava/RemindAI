import 'package:dio/dio.dart';
import 'search_config.dart';

/// AI 搜索服务 — 统一调用 Tavily / Brave / 百度智能搜索
class SearchService {
  static final SearchService instance = SearchService._();
  SearchService._();

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// 执行搜索,根据 provider 分发到对应 API
  Future<String> search({
    required SearchProvider provider,
    required String query,
    required String apiKey,
    int maxResults = 5,
  }) async {
    switch (provider) {
      case SearchProvider.tavily:
        return _searchTavily(query, apiKey, maxResults);
      case SearchProvider.brave:
        return _searchBrave(query, apiKey, maxResults);
      case SearchProvider.baidu:
        return _searchBaidu(query, apiKey, maxResults);
      case SearchProvider.none:
        return '搜索未启用';
    }
  }

  /// Tavily Search API
  /// https://docs.tavily.com/documentation/api-reference/endpoint/search
  Future<String> _searchTavily(String query, String apiKey, int max) async {
    final response = await _dio.post(
      'https://api.tavily.com/search',
      data: {
        'query': query,
        'max_results': max,
        'include_answer': true,
        'search_depth': 'basic',
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final results = <String>[];

    // Tavily 自带 AI 生成的回答
    if (data['answer'] != null) {
      results.add('## AI 摘要\n${data['answer']}\n');
    }

    final items = data['results'] as List? ?? [];
    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      results.add(
        '### ${i + 1}. ${item['title'] ?? ''}\n'
        'URL: ${item['url'] ?? ''}\n'
        '${item['content'] ?? ''}\n',
      );
    }

    return results.isEmpty ? '未找到相关结果' : results.join('\n');
  }

  /// Brave Search API
  /// https://api.search.brave.com/app/documentation/web-search/query
  Future<String> _searchBrave(String query, String apiKey, int max) async {
    final response = await _dio.get(
      'https://api.search.brave.com/res/v1/web/search',
      queryParameters: {'q': query, 'count': max},
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'X-Subscription-Token': apiKey,
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final results = <String>[];

    final webResults = data['web']?['results'] as List? ?? [];
    for (int i = 0; i < webResults.length; i++) {
      final item = webResults[i] as Map<String, dynamic>;
      results.add(
        '### ${i + 1}. ${item['title'] ?? ''}\n'
        'URL: ${item['url'] ?? ''}\n'
        '${item['description'] ?? ''}\n',
      );
    }

    return results.isEmpty ? '未找到相关结果' : results.join('\n');
  }

  /// 百度智能搜索 API (千帆 AI Search)
  /// https://cloud.baidu.com/doc/qianfan-api/s/Hmbu8m06u
  ///
  /// 使用方式: 传入 model 获取搜索+AI总结; 不传 model 仅返回搜索结果。
  /// 此处传入轻量模型以获取 AI 摘要 + 结构化 references。
  Future<String> _searchBaidu(String query, String apiKey, int max) async {
    final response = await _dio.post(
      'https://qianfan.baidubce.com/v2/ai_search/chat/completions',
      data: {
        'messages': [
          {'role': 'user', 'content': query},
        ],
        'model': 'ernie-4.5-turbo-32k',
        'stream': false,
        'search_source': 'baidu_search_v2',
        'resource_type_filter': [
          {'type': 'web', 'top_k': max},
        ],
        'enable_deep_search': false,
        'search_mode': 'required',
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'X-Appbuilder-Authorization': 'Bearer $apiKey',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final results = <String>[];

    // 提取 AI 生成的回答
    final choices = data['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content != null && content.isNotEmpty) {
        results.add('## AI 摘要\n$content\n');
      }
    }

    // 提取 references (结构化搜索结果)
    final refs = data['references'] as List? ?? [];
    for (int i = 0; i < refs.length; i++) {
      final ref = refs[i] as Map<String, dynamic>;
      final type = ref['type'] as String? ?? 'web';
      if (type != 'web') continue; // 只取网页结果

      results.add(
        '### ${ref['id'] ?? i + 1}. ${ref['title'] ?? ''}\n'
        'URL: ${ref['url'] ?? ''}\n'
        '来源: ${ref['web_anchor'] ?? ref['website'] ?? ''}\n'
        '${ref['content'] ?? ''}\n',
      );
    }

    return results.isEmpty ? '未找到相关结果' : results.join('\n');
  }
}

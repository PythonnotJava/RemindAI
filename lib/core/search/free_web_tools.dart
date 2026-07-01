import 'dart:convert';

import 'package:dio/dio.dart';

import '../logger/app_logger.dart';

/// 免费网络工具 — 无需 API Key
///
/// 提供两个工具的执行器：
/// - `web_search`: DuckDuckGo Instant Answer API（免费，无限量）
/// - `web_fetch`: HTTP GET 抓取网页内容（自动提取正文）
///
/// 供 SkillInjector 的 handler 绑定机制使用，
/// 当 `web-search` skill 被注入时自动激活。
class FreeWebTools {
  static final FreeWebTools instance = FreeWebTools._();
  FreeWebTools._();

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  );

  /// 工具 handler 映射（供 _bindSkillToolHandlers 注册）
  Map<String, Future<String> Function(Map<String, dynamic>)> get handlers => {
    'web_search': webSearch,
    'web_fetch': webFetch,
  };

  /// DuckDuckGo 搜索
  ///
  /// 使用 DuckDuckGo HTML 搜索页面解析结果（比 Instant Answer API 结果更丰富）。
  /// 完全免费，无需 API Key。
  Future<String> webSearch(Map<String, dynamic> args) async {
    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return jsonEncode({'status': 'error', 'message': '搜索查询不能为空'});
    }

    try {
      // DuckDuckGo HTML 搜索（比 Instant Answer API 结果更完整）
      final resp = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
        options: Options(
          headers: {'Accept': 'text/html'},
          // 跟随重定向
          followRedirects: true,
          maxRedirects: 3,
        ),
      );

      final html = resp.data as String;
      final results = _parseDuckDuckGoHtml(html);

      if (results.isEmpty) {
        // 降级到 Instant Answer API
        return await _duckDuckGoInstant(query);
      }

      return jsonEncode({
        'status': 'success',
        'query': query,
        'results': results,
        'source': 'DuckDuckGo (免费)',
      });
    } catch (e) {
      AppLogger.instance.log('[FreeWebTools] web_search 失败: $e');
      // 降级到 Instant Answer API
      try {
        return await _duckDuckGoInstant(query);
      } catch (e2) {
        return jsonEncode({'status': 'error', 'message': '搜索失败: $e2'});
      }
    }
  }

  /// DuckDuckGo Instant Answer API（备用）
  Future<String> _duckDuckGoInstant(String query) async {
    final resp = await _dio.get(
      'https://api.duckduckgo.com/',
      queryParameters: {
        'q': query,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      },
    );

    final data = resp.data;
    final Map<String, dynamic> json;
    if (data is String) {
      json = jsonDecode(data) as Map<String, dynamic>;
    } else {
      json = data as Map<String, dynamic>;
    }

    final results = <Map<String, String>>[];

    // Abstract (摘要)
    final abstract_ = (json['Abstract'] as String?) ?? '';
    if (abstract_.isNotEmpty) {
      results.add({
        'title': (json['Heading'] as String?) ?? query,
        'snippet': abstract_,
        'url': (json['AbstractURL'] as String?) ?? '',
      });
    }

    // Related Topics
    final topics = json['RelatedTopics'] as List? ?? [];
    for (final topic in topics.take(8)) {
      if (topic is Map && topic['Text'] != null) {
        results.add({
          'title': (topic['Text'] as String).length > 80
              ? '${(topic['Text'] as String).substring(0, 80)}...'
              : topic['Text'] as String,
          'snippet': topic['Text'] as String,
          'url': (topic['FirstURL'] as String?) ?? '',
        });
      }
    }

    // Answer
    final answer = (json['Answer'] as String?) ?? '';
    if (answer.isNotEmpty) {
      results.insert(0, {
        'title': 'Direct Answer',
        'snippet': answer,
        'url': '',
      });
    }

    return jsonEncode({
      'status': results.isEmpty ? 'no_results' : 'success',
      'query': query,
      'results': results,
      'source': 'DuckDuckGo Instant Answer (免费)',
    });
  }

  /// 解析 DuckDuckGo HTML 搜索结果页
  List<Map<String, String>> _parseDuckDuckGoHtml(String html) {
    final results = <Map<String, String>>[];

    // 匹配搜索结果块: class="result__body"
    final resultPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    for (final match in resultPattern.allMatches(html).take(8)) {
      final url = _decodeUrl(match.group(1) ?? '');
      final title = _stripHtml(match.group(2) ?? '');
      final snippet = _stripHtml(match.group(3) ?? '');
      if (title.isNotEmpty || snippet.isNotEmpty) {
        results.add({'title': title, 'snippet': snippet, 'url': url});
      }
    }

    // 备用正则：简化版
    if (results.isEmpty) {
      final simplePattern = RegExp(
        r'class="result__url"[^>]*>([^<]+)</.*?class="result__snippet"[^>]*>(.*?)</a>',
        dotAll: true,
      );
      for (final match in simplePattern.allMatches(html).take(8)) {
        final url = (match.group(1) ?? '').trim();
        final snippet = _stripHtml(match.group(2) ?? '');
        if (snippet.isNotEmpty) {
          results.add({
            'title': url,
            'snippet': snippet,
            'url': 'https://$url',
          });
        }
      }
    }

    return results;
  }

  /// 解码 DuckDuckGo 的重定向 URL
  String _decodeUrl(String url) {
    // DuckDuckGo 会将链接包装为 //duckduckgo.com/l/?uddg=<encoded_url>&...
    if (url.contains('uddg=')) {
      final match = RegExp(r'uddg=([^&]+)').firstMatch(url);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
    }
    return url;
  }

  /// HTTP GET 抓取网页
  Future<String> webFetch(Map<String, dynamic> args) async {
    final url = (args['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) {
      return jsonEncode({'status': 'error', 'message': 'URL 不能为空'});
    }

    // 基本 URL 校验
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return jsonEncode({
        'status': 'error',
        'message': 'URL 必须以 http:// 或 https:// 开头',
      });
    }

    try {
      final resp = await _dio.get(
        url,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final contentType = resp.headers.value('content-type') ?? '';
      final body = resp.data?.toString() ?? '';

      // 如果是 HTML，提取正文
      String content;
      if (contentType.contains('html')) {
        content = _extractReadableText(body);
      } else {
        // JSON / 纯文本等直接返回
        content = body.length > 15000 ? body.substring(0, 15000) : body;
      }

      return jsonEncode({
        'status': 'success',
        'url': url,
        'content_type': contentType,
        'content': content,
        'length': content.length,
      });
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      return jsonEncode({
        'status': 'error',
        'url': url,
        'message': '请求失败: ${status ?? e.type.name} - ${e.message ?? ""}',
      });
    } catch (e) {
      return jsonEncode({'status': 'error', 'url': url, 'message': '抓取失败: $e'});
    }
  }

  /// 从 HTML 中提取可读文本（去标签、去脚本/样式、保留段落结构）
  String _extractReadableText(String html) {
    var text = html;
    // 移除 script/style 块
    text = text.replaceAll(
      RegExp(r'<script[^>]*>.*?</script>', dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<style[^>]*>.*?</style>', dotAll: true),
      '',
    );
    text = text.replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true), '');
    text = text.replaceAll(
      RegExp(r'<header[^>]*>.*?</header>', dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true),
      '',
    );
    // 块级标签换行
    text = text.replaceAll(RegExp(r'<(br|p|div|h[1-6]|li|tr)[^>]*>'), '\n');
    // 去除所有标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    // 解码 HTML entities
    text = _decodeHtmlEntities(text);
    // 合并多空行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 合并多空格
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.trim();
    // 限制长度
    if (text.length > 12000) {
      text = '${text.substring(0, 12000)}\n\n[... 内容过长已截断，共 ${html.length} 字符]';
    }
    return text;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
  }
}

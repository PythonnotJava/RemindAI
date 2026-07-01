import 'dart:async';

import 'isolate_pool.dart';
import 'tasks/json_task.dart';
import 'tasks/markdown_task.dart';
import 'tasks/highlight_task.dart';
import 'tasks/export_task.dart';
import 'tasks/memory_task.dart';
import 'tasks/skill_task.dart';
import 'tasks/context_task.dart';

/// 计算服务 — 提供高层 API，内部自动决策是否走 Isolate。
///
/// 小数据量直接在主 Isolate 执行（避免序列化开销），
/// 大数据量自动分派到 IsolatePool。
///
/// 阈值策略:
/// - JSON: >50KB 走 Isolate
/// - Markdown: >2000 字符走 Isolate
/// - 代码高亮: >200 行走 Isolate
/// - 记忆搜索: >100 条走 Isolate
/// - 导出: >30 条消息走 Isolate
class ComputeService {
  ComputeService._();

  static IsolatePool get _pool => IsolatePool.instance;

  // =========================================================================
  // JSON 序列化/反序列化
  // =========================================================================

  /// JSON 编码，大数据走 Isolate
  static Future<String> jsonEncode(
    dynamic data, {
    int threshold = 50000,
  }) async {
    // 快速路径: 小数据直接执行
    final result = jsonEncodeTask(data);
    if (result.length < threshold || !_pool.isInitialized) {
      return result;
    }
    // 大数据: 因为已经编码了，直接返回
    // 实际场景中应该传原始数据到 Isolate，但 Map 序列化本身有开销
    // 所以只在预知数据大时使用
    return result;
  }

  /// JSON 编码（强制走 Isolate，用于已知的大数据）
  static Future<String> jsonEncodeAsync(dynamic data) async {
    if (!_pool.isInitialized) return jsonEncodeTask(data);
    return _pool.run(jsonEncodeTask, data);
  }

  /// JSON 解码，大字符串走 Isolate
  static Future<dynamic> jsonDecode(String jsonStr) async {
    if (jsonStr.length < 50000 || !_pool.isInitialized) {
      return jsonDecodeTask(jsonStr);
    }
    return _pool.run(jsonDecodeTask, jsonStr);
  }

  /// 对话序列化
  static Future<String> encodeConversation(
    List<Map<String, dynamic>> messages, {
    Map<String, dynamic>? metadata,
  }) async {
    final param = ConversationEncodeParam(
      messages: messages,
      metadata: metadata,
    );
    if (messages.length < 30 || !_pool.isInitialized) {
      return conversationEncodeTask(param);
    }
    return _pool.run(conversationEncodeTask, param);
  }

  // =========================================================================
  // Markdown 预处理
  // =========================================================================

  /// Markdown 预处理（提取代码块、检测特殊内容、计算复杂度）
  static Future<MarkdownPreprocessResult> markdownPreprocess(
    String markdown,
  ) async {
    if (markdown.length < 2000 || !_pool.isInitialized) {
      return markdownPreprocessTask(markdown);
    }
    return _pool.run(markdownPreprocessTask, markdown);
  }

  /// Markdown 分段（超长消息分段渲染）
  static Future<List<String>> markdownSplit(
    String markdown, {
    int maxSegmentLength = 3000,
  }) async {
    final param = MarkdownSplitParam(
      markdown: markdown,
      maxSegmentLength: maxSegmentLength,
    );
    if (markdown.length < maxSegmentLength || !_pool.isInitialized) {
      return markdownSplitTask(param);
    }
    return _pool.run(markdownSplitTask, param);
  }

  /// 批量 Markdown 预处理（加载历史消息）
  static Future<List<MarkdownPreprocessResult>> markdownBatchPreprocess(
    List<String> markdowns,
  ) async {
    if (markdowns.length < 5 || !_pool.isInitialized) {
      return markdownBatchPreprocessTask(markdowns);
    }
    return _pool.run(markdownBatchPreprocessTask, markdowns);
  }

  // =========================================================================
  // 代码高亮
  // =========================================================================

  /// 代码预 token 化
  static Future<HighlightResult> highlightCode(
    String code,
    String language,
  ) async {
    final param = HighlightParam(code: code, language: language);
    final lineCount = code.split('\n').length;
    if (lineCount < 200 || !_pool.isInitialized) {
      return highlightPreTokenizeTask(param);
    }
    return _pool.run(highlightPreTokenizeTask, param);
  }

  /// 批量代码高亮
  static Future<List<HighlightResult>> highlightBatch(
    List<HighlightParam> params,
  ) async {
    if (params.length < 3 || !_pool.isInitialized) {
      return highlightBatchTask(params);
    }
    return _pool.run(highlightBatchTask, params);
  }

  // =========================================================================
  // 导出
  // =========================================================================

  /// 构建对话导出 Markdown
  static Future<String> buildExportMarkdown(
    List<ExportMessage> messages,
    String title, {
    String locale = 'zh',
  }) async {
    final param = ExportBuildParam(
      messages: messages,
      title: title,
      locale: locale,
    );
    if (messages.length < 30 || !_pool.isInitialized) {
      return exportBuildMarkdownTask(param);
    }
    return _pool.run(exportBuildMarkdownTask, param);
  }

  // =========================================================================
  // 记忆搜索
  // =========================================================================

  /// 向量相似度搜索
  static Future<List<MemorySearchHit>> vectorSearch({
    required List<double> queryEmbedding,
    required List<VectorEntry> entries,
    int topK = 5,
    double threshold = 0.7,
  }) async {
    final param = VectorSearchParam(
      queryEmbedding: queryEmbedding,
      entries: entries,
      topK: topK,
      threshold: threshold,
    );
    if (entries.length < 100 || !_pool.isInitialized) {
      return vectorSearchTask(param);
    }
    return _pool.run(vectorSearchTask, param);
  }

  /// 关键词搜索
  static Future<List<MemorySearchHit>> keywordSearch({
    required String query,
    required List<MemoryTextEntry> entries,
    int topK = 10,
  }) async {
    final param = KeywordSearchParam(
      query: query,
      entries: entries,
      topK: topK,
    );
    if (entries.length < 100 || !_pool.isInitialized) {
      return keywordSearchTask(param);
    }
    return _pool.run(keywordSearchTask, param);
  }

  // =========================================================================
  // 技能加载
  // =========================================================================

  /// 批量解析技能
  static Future<List<ParsedSkill>> parseSkills(
    List<SkillFileInfo> infos,
  ) async {
    if (infos.length < 5 || !_pool.isInitialized) {
      return skillBatchParseTask(infos);
    }
    return _pool.run(skillBatchParseTask, infos);
  }

  /// 解析单个技能
  static Future<ParsedSkill> parseSkill(SkillFileInfo info) async {
    if (!_pool.isInitialized) return skillParseTask(info);
    return _pool.run(skillParseTask, info);
  }

  // =========================================================================
  // 上下文压缩
  // =========================================================================

  /// 智能上下文压缩
  static Future<ContextCompressResult> compressContext({
    required List<ContextMessage> messages,
    required int maxTokens,
    int keepRecentCount = 10,
  }) async {
    final param = ContextCompressParam(
      messages: messages,
      maxTokens: maxTokens,
      keepRecentCount: keepRecentCount,
    );
    if (messages.length < 20 || !_pool.isInitialized) {
      return contextCompressTask(param);
    }
    return _pool.run(contextCompressTask, param);
  }

  /// Token 估算（批量）
  static Future<List<int>> estimateTokensBatch(List<String> texts) async {
    if (texts.length < 50 || !_pool.isInitialized) {
      return tokenEstimateBatchTask(texts);
    }
    return _pool.run(tokenEstimateBatchTask, texts);
  }

  /// Token 估算（单条）
  static int estimateTokens(String text) {
    return tokenEstimateTask(text);
  }
}

import 'dart:math';

/// 记忆搜索任务 — 在 Isolate 中执行向量相似度计算和关键词匹配。
///
/// 适用场景:
/// - SQLite fallback 模式下的关键词搜索（大量记忆条目时）
/// - 本地向量相似度计算（如果嵌入向量已缓存在内存中）
/// - 记忆条目的相关性排序

/// 向量相似度搜索参数
class VectorSearchParam {
  final List<double> queryEmbedding;
  final List<VectorEntry> entries;
  final int topK;
  final double threshold;

  VectorSearchParam({
    required this.queryEmbedding,
    required this.entries,
    this.topK = 5,
    this.threshold = 0.7,
  });
}

/// 向量条目
class VectorEntry {
  final int id;
  final String text;
  final List<double> embedding;
  final Map<String, dynamic> metadata;

  VectorEntry({
    required this.id,
    required this.text,
    required this.embedding,
    this.metadata = const {},
  });
}

/// 搜索结果
class MemorySearchHit {
  final int id;
  final String text;
  final double score;
  final Map<String, dynamic> metadata;

  MemorySearchHit({
    required this.id,
    required this.text,
    required this.score,
    this.metadata = const {},
  });
}

/// 顶层函数: 向量余弦相似度搜索（可传入 Isolate）
List<MemorySearchHit> vectorSearchTask(VectorSearchParam param) {
  final results = <MemorySearchHit>[];

  for (final entry in param.entries) {
    if (entry.embedding.length != param.queryEmbedding.length) continue;
    final score = _cosineSimilarity(param.queryEmbedding, entry.embedding);
    if (score >= param.threshold) {
      results.add(
        MemorySearchHit(
          id: entry.id,
          text: entry.text,
          score: score,
          metadata: entry.metadata,
        ),
      );
    }
  }

  // 按分数降序排列，取 topK
  results.sort((a, b) => b.score.compareTo(a.score));
  return results.take(param.topK).toList();
}

/// 关键词搜索参数
class KeywordSearchParam {
  final String query;
  final List<MemoryTextEntry> entries;
  final int topK;

  KeywordSearchParam({
    required this.query,
    required this.entries,
    this.topK = 10,
  });
}

/// 纯文本记忆条目
class MemoryTextEntry {
  final int id;
  final String text;
  final Map<String, dynamic> metadata;

  MemoryTextEntry({
    required this.id,
    required this.text,
    this.metadata = const {},
  });
}

/// 顶层函数: 关键词搜索（可传入 Isolate）
///
/// 使用 CJK 友好的分词 + 命中率评分，与 MemoryDao.search 逻辑一致。
List<MemorySearchHit> keywordSearchTask(KeywordSearchParam param) {
  final queryTokens = _tokenize(param.query);
  if (queryTokens.isEmpty) return [];

  final results = <MemorySearchHit>[];

  for (final entry in param.entries) {
    final entryTokens = _tokenize(entry.text);
    if (entryTokens.isEmpty) continue;

    // 计算命中率: 匹配到的 query token 数 / query token 总数
    int hits = 0;
    for (final qt in queryTokens) {
      if (entryTokens.any((et) => et.contains(qt) || qt.contains(et))) {
        hits++;
      }
    }
    final score = hits / queryTokens.length;
    if (score > 0) {
      results.add(
        MemorySearchHit(
          id: entry.id,
          text: entry.text,
          score: score,
          metadata: entry.metadata,
        ),
      );
    }
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results.take(param.topK).toList();
}

// =============================================================================
// 工具函数
// =============================================================================

/// 余弦相似度
double _cosineSimilarity(List<double> a, List<double> b) {
  double dotProduct = 0;
  double normA = 0;
  double normB = 0;

  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  final denominator = sqrt(normA) * sqrt(normB);
  if (denominator == 0) return 0;
  return dotProduct / denominator;
}

/// CJK 友好的分词（bigram for CJK, word for ASCII）
List<String> _tokenize(String text) {
  final tokens = <String>[];
  final lower = text.toLowerCase();
  final buffer = StringBuffer();

  for (int i = 0; i < lower.length; i++) {
    final c = lower.codeUnitAt(i);
    if (_isCjk(c)) {
      // flush ascii buffer
      if (buffer.isNotEmpty) {
        _addAsciiTokens(buffer.toString(), tokens);
        buffer.clear();
      }
      // CJK bigram
      if (i + 1 < lower.length && _isCjk(lower.codeUnitAt(i + 1))) {
        tokens.add(lower.substring(i, i + 2));
      } else {
        tokens.add(lower[i]);
      }
    } else if (_isAlphaNumeric(c)) {
      buffer.writeCharCode(c);
    } else {
      if (buffer.isNotEmpty) {
        _addAsciiTokens(buffer.toString(), tokens);
        buffer.clear();
      }
    }
  }
  if (buffer.isNotEmpty) {
    _addAsciiTokens(buffer.toString(), tokens);
  }

  return tokens;
}

void _addAsciiTokens(String word, List<String> tokens) {
  if (word.length >= 2) {
    tokens.add(word);
  }
}

bool _isCjk(int c) {
  return (c >= 0x4E00 && c <= 0x9FFF) || // CJK Unified Ideographs
      (c >= 0x3400 && c <= 0x4DBF) || // CJK Extension A
      (c >= 0x3000 && c <= 0x303F); // CJK Symbols
}

bool _isAlphaNumeric(int c) {
  return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

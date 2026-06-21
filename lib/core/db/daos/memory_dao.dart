import 'dart:convert';

import '../database.dart';

/// 记忆持久化 DAO — SQLite 备份层
///
/// 与 Qdrant 向量库形成双写：
/// - Qdrant: 向量检索 (语义搜索)
/// - SQLite: 持久备份 (防 Qdrant 数据丢失时可重建)
class MemoryDao {
  final DatabaseHelper _dbHelper;

  MemoryDao(this._dbHelper);

  /// 存储一条记忆
  Future<void> insert({
    required int id,
    required String collection,
    required String text,
    Map<String, dynamic> metadata = const {},
  }) async {
    final db = await _dbHelper.database;
    db.execute(
      '''INSERT OR REPLACE INTO memory_entries (id, collection, text, metadata, created_at)
         VALUES (?, ?, ?, ?, ?)''',
      [
        id,
        collection,
        text,
        jsonEncode(metadata),
        DateTime.now().toIso8601String(),
      ],
    );
  }

  /// 删除单条记忆
  Future<void> delete(String collection, int id) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM memory_entries WHERE id = ? AND collection = ?', [
      id,
      collection,
    ]);
  }

  /// 清空指定 collection 的所有记忆
  Future<void> deleteAll(String collection) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM memory_entries WHERE collection = ?', [collection]);
  }

  /// 获取指定 collection 的所有记忆（用于重建 Qdrant）
  Future<List<Map<String, dynamic>>> getAll(String collection) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC',
      [collection],
    );
    return result.map((row) {
      Map<String, dynamic> metadata = {};
      try {
        metadata =
            jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
      return {
        'id': row['id'] as int,
        'collection': row['collection'] as String,
        'text': row['text'] as String,
        'metadata': metadata,
        'created_at': row['created_at'] as String,
      };
    }).toList();
  }

  /// 获取指定 collection 的记忆条数
  Future<int> count(String collection) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT COUNT(*) as cnt FROM memory_entries WHERE collection = ?',
      [collection],
    );
    return result.first['cnt'] as int;
  }

  /// 关键词搜索记忆 (SQLite 降级召回，无 Qdrant 时使用)
  ///
  /// 中文友好分词: 对连续 CJK 串生成 bigram (相邻两字)，对 ASCII 串按单词
  /// (长度≥2) 提取。只要 text 命中任一关键词即匹配，命中越多 score 越高。
  /// 返回格式与 Qdrant recall 一致: [{text, score, source, timestamp, ...}]
  Future<List<Map<String, dynamic>>> search(
    String collection,
    String query, {
    int limit = 5,
  }) async {
    final db = await _dbHelper.database;
    final keywords = _tokenize(query);

    if (keywords.isEmpty) {
      // 无有效关键词，返回最近的几条
      final result = db.select(
        'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC LIMIT ?',
        [collection, limit],
      );
      return _rowsToResults(result, const []);
    }

    // 构建 LIKE 条件 (OR 连接)。多取一些候选 (limit*4)，
    // 以便在 Dart 侧按命中数 (score) 重排后再截断，避免高相关的老记忆被丢。
    final conditions = keywords.map((_) => 'text LIKE ?').join(' OR ');
    final params = <dynamic>[collection];
    for (final k in keywords) {
      params.add('%$k%');
    }
    params.add(limit * 4);

    final result = db.select(
      'SELECT * FROM memory_entries WHERE collection = ? AND ($conditions) ORDER BY created_at DESC LIMIT ?',
      params,
    );

    final rows = _rowsToResults(result, keywords);
    // 按 score 降序 (命中关键词比例)，分数相同保持时间倒序
    rows.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return rows.take(limit).toList();
  }

  /// 中文友好分词:
  /// - 连续 CJK 块 → bigram (长度=1 时取单字)
  /// - ASCII 字母数字串 → 整词 (长度≥2)
  List<String> _tokenize(String query) {
    final tokens = <String>{};

    // CJK 块 (中日韩统一表意文字)
    for (final m in RegExp(r'[\u4e00-\u9fff]+').allMatches(query)) {
      final block = m.group(0)!;
      if (block.length == 1) {
        tokens.add(block);
      } else {
        for (var i = 0; i < block.length - 1; i++) {
          tokens.add(block.substring(i, i + 2));
        }
      }
    }

    // ASCII 字母数字词 (长度≥2)
    for (final m in RegExp(r'[A-Za-z0-9]{2,}').allMatches(query)) {
      tokens.add(m.group(0)!.toLowerCase());
    }

    return tokens.toList();
  }

  /// 行 → 结果。当传入 [keywords] 时按命中比例计算 score；否则 score=1.0。
  List<Map<String, dynamic>> _rowsToResults(
    List<dynamic> rows,
    List<String> keywords,
  ) {
    return rows.map((row) {
      Map<String, dynamic> metadata = {};
      try {
        metadata =
            jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}

      final text = row['text'] as String;
      double score = 1.0;
      if (keywords.isNotEmpty) {
        final lower = text.toLowerCase();
        final hits = keywords.where((k) => lower.contains(k)).length;
        // 归一化到 (0,1]，命中越多越高
        score = hits / keywords.length;
      }

      return <String, dynamic>{
        'text': text,
        'score': score,
        'source': 'sqlite', // 标注来源，便于上层区分语义检索/关键词降级
        'timestamp': metadata['timestamp'] ?? row['created_at'] as String,
        ...metadata,
      };
    }).toList();
  }
}

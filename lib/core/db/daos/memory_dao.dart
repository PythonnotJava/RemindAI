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
  /// 对 query 按空格分词，只要 text 包含任一关键词就匹配。
  /// 返回格式与 Qdrant recall 一致: [{text, score, timestamp, ...}]
  Future<List<Map<String, dynamic>>> search(
    String collection,
    String query, {
    int limit = 5,
  }) async {
    final db = await _dbHelper.database;
    // 分词
    final keywords = query
        .split(RegExp(r'\s+'))
        .where((k) => k.length >= 2)
        .toList();
    if (keywords.isEmpty) {
      // 无有效关键词，返回最近的几条
      final result = db.select(
        'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC LIMIT ?',
        [collection, limit],
      );
      return _rowsToResults(result);
    }

    // 构建 LIKE 条件 (OR 连接)
    final conditions = keywords.map((_) => 'text LIKE ?').join(' OR ');
    final params = <dynamic>[collection];
    for (final k in keywords) {
      params.add('%$k%');
    }
    params.add(limit);

    final result = db.select(
      'SELECT * FROM memory_entries WHERE collection = ? AND ($conditions) ORDER BY created_at DESC LIMIT ?',
      params,
    );
    return _rowsToResults(result);
  }

  List<Map<String, dynamic>> _rowsToResults(List<dynamic> rows) {
    return rows.map((row) {
      Map<String, dynamic> metadata = {};
      try {
        metadata =
            jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
      return <String, dynamic>{
        'text': row['text'] as String,
        'score': 1.0, // SQLite 无分数概念，固定为 1.0
        'timestamp': metadata['timestamp'] ?? row['created_at'] as String,
        ...metadata,
      };
    }).toList();
  }
}

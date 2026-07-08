import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/knowledge_base.dart';

/// 知识库 DAO — 管理 knowledge_bases 与 kb_documents 两张表。
class KbDao {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  KbDao(this._dbHelper);

  // ─── 知识库 ────────────────────────────────────────────────

  Future<List<KnowledgeBase>> getAllBases() async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM knowledge_bases ORDER BY created_at DESC',
    );
    return result.map((row) => KnowledgeBase.fromRow(row)).toList();
  }

  Future<KnowledgeBase?> getBase(String id) async {
    final db = await _dbHelper.database;
    final result = db.select('SELECT * FROM knowledge_bases WHERE id = ?', [
      id,
    ]);
    if (result.isEmpty) return null;
    return KnowledgeBase.fromRow(result.first);
  }

  /// 创建一个知识库。[collection] 由调用方生成 (通常 `kb_<id>`)。
  Future<KnowledgeBase> createBase({
    required String name,
    String description = '',
    required String embeddingBaseUrl,
    required String embeddingApiKey,
    required String embeddingModel,
  }) async {
    final db = await _dbHelper.database;
    final id = _uuid.v4().replaceAll('-', '');
    final collection = 'kb_$id';
    final now = DateTime.now().toIso8601String();

    db.execute(
      '''INSERT INTO knowledge_bases
         (id, name, description, collection, embedding_base_url, embedding_api_key, embedding_model, embedding_dimension, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        name,
        description,
        collection,
        embeddingBaseUrl,
        embeddingApiKey,
        embeddingModel,
        0,
        now,
      ],
    );

    return KnowledgeBase(
      id: id,
      name: name,
      description: description,
      collection: collection,
      embeddingBaseUrl: embeddingBaseUrl,
      embeddingApiKey: embeddingApiKey,
      embeddingModel: embeddingModel,
      embeddingDimension: 0,
      createdAt: DateTime.parse(now),
    );
  }

  /// 更新知识库的可编辑字段 (名称/描述)。嵌入配置不可改。
  Future<void> updateBaseMeta({
    required String id,
    required String name,
    required String description,
  }) async {
    final db = await _dbHelper.database;
    db.execute(
      'UPDATE knowledge_bases SET name = ?, description = ? WHERE id = ?',
      [name, description, id],
    );
  }

  /// 回填向量维度 (首次成功嵌入后)。
  Future<void> setBaseDimension(String id, int dimension) async {
    final db = await _dbHelper.database;
    db.execute(
      'UPDATE knowledge_bases SET embedding_dimension = ? WHERE id = ?',
      [dimension, id],
    );
  }

  /// 删除知识库及其所有文档记录 (不含 Qdrant collection，由上层删除)。
  Future<void> deleteBase(String id) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM kb_documents WHERE kb_id = ?', [id]);
    db.execute('DELETE FROM knowledge_bases WHERE id = ?', [id]);
  }

  // ─── 文档 ──────────────────────────────────────────────────

  Future<List<KbDocument>> getDocuments(String kbId) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM kb_documents WHERE kb_id = ? ORDER BY imported_at DESC',
      [kbId],
    );
    return result.map((row) => KbDocument.fromRow(row)).toList();
  }

  /// 检查知识库内是否已存在同名文件 (用于导入去重)
  Future<bool> hasDocument(String kbId, String filename) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT COUNT(*) as cnt FROM kb_documents WHERE kb_id = ? AND filename = ?',
      [kbId, filename],
    );
    return (result.first['cnt'] as int) > 0;
  }

  Future<KbDocument?> getDocument(String docId) async {
    final db = await _dbHelper.database;
    final result = db.select('SELECT * FROM kb_documents WHERE id = ?', [
      docId,
    ]);
    if (result.isEmpty) return null;
    return KbDocument.fromRow(result.first);
  }

  /// 插入一份待解析文档，返回其 id。
  Future<KbDocument> insertDocument({
    required String kbId,
    required String filename,
    String sourcePath = '',
    String sourceGroup = '',
  }) async {
    final db = await _dbHelper.database;
    final id = _uuid.v4().replaceAll('-', '');
    final now = DateTime.now().toIso8601String();

    db.execute(
      '''INSERT INTO kb_documents
         (id, kb_id, filename, source_path, source_group, chunk_count, char_count, status, error, imported_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [id, kbId, filename, sourcePath, sourceGroup, 0, 0, 'pending', '', now],
    );

    return KbDocument(
      id: id,
      kbId: kbId,
      filename: filename,
      sourcePath: sourcePath,
      sourceGroup: sourceGroup,
      status: KbDocStatus.pending,
      importedAt: DateTime.parse(now),
    );
  }

  /// 批量导入文档 (事务内执行，几百份也秒完)。
  ///
  /// 自动跳过 [kbId] 中已有同名文件。返回实际新增的数量。
  Future<int> batchInsertDocuments({
    required String kbId,
    required List<({String filename, String sourcePath})> files,
    String sourceGroup = '',
  }) async {
    if (files.isEmpty) return 0;
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    // 事先一次性取出所有已有文件名，内存去重
    final existing = <String>{};
    final rows = db.select(
      'SELECT filename FROM kb_documents WHERE kb_id = ?',
      [kbId],
    );
    for (final row in rows) {
      existing.add(row['filename'] as String);
    }

    int added = 0;
    db.execute('BEGIN TRANSACTION');
    try {
      final stmt = db.prepare('''INSERT INTO kb_documents
           (id, kb_id, filename, source_path, source_group, chunk_count, char_count, status, error, imported_at)
           VALUES (?, ?, ?, ?, ?, 0, 0, 'pending', '', ?)''');
      for (final f in files) {
        if (existing.contains(f.filename)) continue;
        existing.add(f.filename); // 本批次内也去重
        final id = _uuid.v4().replaceAll('-', '');
        stmt.execute([id, kbId, f.filename, f.sourcePath, sourceGroup, now]);
        added++;
      }
      stmt.dispose();
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return added;
  }

  /// 更新文档解析状态与统计。
  Future<void> updateDocumentStatus({
    required String docId,
    required KbDocStatus status,
    int? chunkCount,
    int? charCount,
    String? error,
  }) async {
    final db = await _dbHelper.database;
    // 动态拼接需要更新的列
    final sets = <String>['status = ?'];
    final params = <dynamic>[status.name];
    if (chunkCount != null) {
      sets.add('chunk_count = ?');
      params.add(chunkCount);
    }
    if (charCount != null) {
      sets.add('char_count = ?');
      params.add(charCount);
    }
    if (error != null) {
      sets.add('error = ?');
      params.add(error);
    }
    params.add(docId);
    db.execute(
      'UPDATE kb_documents SET ${sets.join(', ')} WHERE id = ?',
      params,
    );
  }

  /// 更新文档的 sourcePath (文件副本复制到存储目录后调用)。
  Future<void> updateDocumentSourcePath(String docId, String newPath) async {
    final db = await _dbHelper.database;
    db.execute('UPDATE kb_documents SET source_path = ? WHERE id = ?', [
      newPath,
      docId,
    ]);
  }

  Future<void> deleteDocument(String docId) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM kb_documents WHERE id = ?', [docId]);
  }

  Future<int> documentCount(String kbId) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT COUNT(*) as cnt FROM kb_documents WHERE kb_id = ?',
      [kbId],
    );
    return result.first['cnt'] as int;
  }
}

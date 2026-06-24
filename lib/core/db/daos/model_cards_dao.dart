import 'package:uuid/uuid.dart';
import '../database.dart';
import '../tables/model_cards.dart';

class ModelCardsDao {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  ModelCardsDao(this._dbHelper);

  Future<List<ModelCard>> getAll() async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM model_cards ORDER BY sort_index ASC, created_at DESC',
    );
    return result.map((row) => ModelCard.fromRow(row)).toList();
  }

  /// Returns the default model card. If none is explicitly marked as default,
  /// falls back to the most recently created card.
  Future<ModelCard?> getDefault() async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM model_cards WHERE is_default = 1 LIMIT 1',
    );
    if (result.isNotEmpty) return ModelCard.fromRow(result.first);

    // Fallback: return the most recently created card
    final fallback = db.select(
      'SELECT * FROM model_cards ORDER BY created_at DESC LIMIT 1',
    );
    if (fallback.isEmpty) return null;
    return ModelCard.fromRow(fallback.first);
  }

  Future<ModelCard?> getById(String id) async {
    final db = await _dbHelper.database;
    final result = db.select('SELECT * FROM model_cards WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return ModelCard.fromRow(result.first);
  }

  Future<ModelCard> insert({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    String logoPath = '',
    String provider = 'openai',
    int contextWindow = 0,
  }) async {
    final db = await _dbHelper.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    // If this is the first card, make it default
    final countResult = db.select('SELECT COUNT(*) as cnt FROM model_cards');
    final isFirst = (countResult.first['cnt'] as int) == 0;

    // 新卡片排到末尾
    final maxResult = db.select('SELECT MAX(sort_index) as m FROM model_cards');
    final nextIndex = ((maxResult.first['m'] as int?) ?? -1) + 1;

    db.execute(
      '''INSERT INTO model_cards (id, name, base_url, api_key, model_id, is_default, created_at, sort_index, logo_path, provider, context_window)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        name,
        baseUrl,
        apiKey,
        modelId,
        isFirst ? 1 : 0,
        now,
        nextIndex,
        logoPath,
        provider,
        contextWindow,
      ],
    );

    return ModelCard(
      id: id,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      isDefault: isFirst,
      createdAt: DateTime.parse(now),
      sortIndex: nextIndex,
      logoPath: logoPath,
      provider: provider,
      contextWindow: contextWindow,
    );
  }

  Future<void> update(ModelCard card) async {
    final db = await _dbHelper.database;
    db.execute(
      '''UPDATE model_cards
         SET name = ?, base_url = ?, api_key = ?, model_id = ?, logo_path = ?, provider = ?, context_window = ?
         WHERE id = ?''',
      [
        card.name,
        card.baseUrl,
        card.apiKey,
        card.modelId,
        card.logoPath,
        card.provider,
        card.contextWindow,
        card.id,
      ],
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM model_cards WHERE id = ?', [id]);
  }

  Future<void> setDefault(String id) async {
    final db = await _dbHelper.database;
    db.execute('UPDATE model_cards SET is_default = 0');
    db.execute('UPDATE model_cards SET is_default = 1 WHERE id = ?', [id]);
  }

  /// 按给定 id 顺序重写 sort_index
  Future<void> reorder(List<String> orderedIds) async {
    final db = await _dbHelper.database;
    db.execute('BEGIN TRANSACTION');
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        db.execute('UPDATE model_cards SET sort_index = ? WHERE id = ?', [
          i,
          orderedIds[i],
        ]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

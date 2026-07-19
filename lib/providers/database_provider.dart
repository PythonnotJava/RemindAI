import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/db/database.dart';
import '../core/db/daos/model_cards_dao.dart';
import '../core/db/daos/conversations_dao.dart';
import '../core/db/tables/model_cards.dart';
import '../core/db/tables/conversations.dart';

/// Global database instance provider
final databaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper.instance;
});

/// Model cards DAO provider
final modelCardsDaoProvider = Provider<ModelCardsDao>((ref) {
  final db = ref.watch(databaseProvider);
  return ModelCardsDao(db);
});

/// Conversations DAO provider
final conversationsDaoProvider = Provider<ConversationsDao>((ref) {
  final db = ref.watch(databaseProvider);
  return ConversationsDao(db);
});

/// 会话列表 provider
final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
      ConversationsNotifier.new,
    );

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  ConversationsDao get _dao => ref.read(conversationsDaoProvider);

  @override
  Future<List<Conversation>> build() async {
    return _dao.getAll();
  }

  Future<void> refresh() async {
    state = AsyncData(await _dao.getAll());
  }

  Future<void> deleteConversation(int id) async {
    await _dao.delete(id);
    ref.invalidateSelf();
  }

  Future<void> deleteAll() async {
    await _dao.deleteAll();
    ref.invalidateSelf();
  }
}

/// Model cards list state
final modelCardsProvider =
    AsyncNotifierProvider<ModelCardsNotifier, List<ModelCard>>(
      ModelCardsNotifier.new,
    );

class ModelCardsNotifier extends AsyncNotifier<List<ModelCard>> {
  ModelCardsDao get _dao => ref.read(modelCardsDaoProvider);

  @override
  Future<List<ModelCard>> build() async {
    return _dao.getAll();
  }

  Future<void> addCard({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    String logoPath = '',
    String provider = 'openai',
    int contextWindow = 0,
  }) async {
    await _dao.insert(
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      logoPath: logoPath,
      provider: provider,
      contextWindow: contextWindow,
    );
    ref.invalidateSelf();
  }

  Future<void> updateCard(ModelCard card) async {
    await _dao.update(card);
    ref.invalidateSelf();
  }

  Future<void> deleteCard(String id) async {
    await _dao.delete(id);
    ref.invalidateSelf();
  }

  void setDefault(String id) {
    // 乐观更新：立即修改本地状态让 UI 瞬间响应，不等 DB
    final current = state.valueOrNull;
    if (current != null) {
      final updated = current
          .map((c) => c.copyWith(isDefault: c.id == id))
          .toList();
      state = AsyncData(updated);
    }

    // 后台异步持久化（不阻塞）
    _dao.setDefault(id).catchError((e) {
      // 如果失败，回滚状态
      if (current != null) {
        state = AsyncData(current);
      }
    });
  }

  /// 按新顺序重排卡片 (orderedIds 为重排后的 id 序列)
  void reorder(List<ModelCard> ordered) {
    final previous = state.valueOrNull;
    // 乐观更新本地状态，立即反映拖拽结果
    state = AsyncData(ordered);
    // 后台异步持久化（不阻塞）
    _dao.reorder(ordered.map((c) => c.id).toList()).catchError((e) {
      // 如果失败，回滚状态
      if (previous != null) {
        state = AsyncData(previous);
      }
    });
  }
}

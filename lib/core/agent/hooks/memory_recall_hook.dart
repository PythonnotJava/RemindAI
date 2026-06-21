import '../../logger/app_logger.dart';
import '../../memory/memory_manager.dart';
import '../agent_hook.dart';

/// 记忆召回钩子 — 在用户消息发送前自动召回相关记忆注入 context
class MemoryRecallHook extends AgentHook {
  final MemoryManager manager;
  final String collection;
  final bool useQdrant;
  final int topK;
  final double scoreThreshold;

  MemoryRecallHook({
    required this.manager,
    required this.collection,
    this.useQdrant = false,
    this.topK = 5,
    this.scoreThreshold = 0.5,
  });

  @override
  Future<String?> onBeforeUserMessage(
    String input,
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      AppLogger.instance.log(
        '[Memory] 开始自动召回, collection=$collection, '
        'useQdrant=$useQdrant, '
        'query="${input.length > 50 ? input.substring(0, 50) : input}"',
      );

      final memories = await manager.recall(
        query: input,
        collectionName: collection,
        topK: topK,
        scoreThreshold: scoreThreshold,
        useQdrant: useQdrant,
      );

      AppLogger.instance.log('[Memory] 召回结果: ${memories.length} 条');
      for (final m in memories) {
        final text = m['text'] as String? ?? '';
        AppLogger.instance.log(
          '[Memory]   source=${m['source']}, score=${m['score']}, '
          'text="${text.substring(0, text.length.clamp(0, 80))}"',
        );
      }

      if (memories.isNotEmpty) {
        // 标注来源: qdrant=语义检索(高可信)，sqlite=关键词降级(仅供参考)
        final src = memories.first['source'] as String? ?? 'unknown';
        final isFallback = src == 'sqlite';
        final memoryContext = memories.map((m) => '- ${m['text']}').join('\n');
        final header = isFallback
            ? '[自动召回的相关记忆 — 关键词匹配，相关性仅供参考]'
            : '[自动召回的相关记忆 — 语义检索]';
        messages.add({'role': 'system', 'content': '$header\n$memoryContext'});
        AppLogger.instance.log(
          '[Memory] 已注入 ${memories.length} 条记忆 (source=$src) 到 system message',
        );
      }
    } catch (e) {
      AppLogger.instance.log('[Memory] 自动召回失败: $e');
    }
    return null; // 不修改 input
  }
}

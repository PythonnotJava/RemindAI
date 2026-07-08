import 'package:flutter/foundation.dart';

import '../../db/daos/kb_dao.dart';
import '../../logger/app_logger.dart';
import '../../memory/memory_manager.dart';
import '../agent_hook.dart';

/// 知识库召回钩子 — 在用户消息发送前从选中的知识库中检索相关内容注入 context。
///
/// 与 MemoryRecallHook 的区别:
/// - 支持多个知识库同时检索
/// - 每个知识库使用各自快照的嵌入模型配置
/// - 结果按知识库分组展示，标明来源文件名
class KbRecallHook extends AgentHook {
  final KbDao dao;
  final List<String> kbIds;
  final int topK;
  final double scoreThreshold;

  KbRecallHook({
    required this.dao,
    required this.kbIds,
    this.topK = 5,
    this.scoreThreshold = 0.45,
  });

  @override
  Future<String?> onBeforeUserMessage(
    String input,
    List<Map<String, dynamic>> messages,
  ) async {
    if (kbIds.isEmpty) return null;

    debugPrint(
      '[KB Recall] 开始检索, 知识库数=${kbIds.length}, '
      'query="${input.length > 40 ? input.substring(0, 40) : input}"',
    );

    final allResults = <String>[];

    for (final kbId in kbIds) {
      try {
        final kb = await dao.getBase(kbId);
        if (kb == null || !kb.hasEmbedding) {
          debugPrint('[KB Recall] 跳过 $kbId (不存在或未配置嵌入模型)');
          continue;
        }

        debugPrint('[KB Recall] 检索知识库: ${kb.name} (${kb.collection})');

        final manager = MemoryManager(
          embeddingBaseUrl: kb.embeddingBaseUrl,
          embeddingApiKey: kb.embeddingApiKey,
          embeddingModel: kb.embeddingModel,
          memoryDao: null,
        );

        final results = await manager.recall(
          query: input,
          collectionName: kb.collection,
          topK: topK,
          scoreThreshold: scoreThreshold,
          useQdrant: true,
        );

        debugPrint('[KB Recall] ${kb.name}: 命中 ${results.length} 条');

        if (results.isNotEmpty) {
          allResults.add('── ${kb.name} ──');
          for (final r in results) {
            final text = r['text'] as String? ?? '';
            final filename = r['filename'] as String? ?? '';
            final score = r['score'] as double? ?? 0;
            final prefix = filename.isNotEmpty ? '[$filename] ' : '';
            allResults.add('$prefix$text');
            debugPrint(
              '[KB Recall]   ✓ score=${score.toStringAsFixed(3)}, '
              'file=$filename, len=${text.length}',
            );
          }
        }
      } catch (e) {
        debugPrint('[KB Recall] ✗ 知识库 $kbId 检索失败: $e');
        AppLogger.instance.log('[KB Recall] 知识库 $kbId 检索失败: $e');
      }
    }

    if (allResults.isNotEmpty) {
      final context = allResults.join('\n');
      messages.add({
        'role': 'system',
        'content': '[以下是从知识库中检索到的相关参考内容，请结合这些信息回答用户问题]\n$context',
      });
      debugPrint('[KB Recall] ✓ 已注入 ${allResults.length} 条结果到 context');
    } else {
      debugPrint('[KB Recall] 无相关结果');
    }

    return null;
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/db/daos/kb_dao.dart';
import '../core/db/tables/knowledge_base.dart';
import '../core/knowledge/kb_indexer.dart';
import '../core/memory/qdrant_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

/// 知识库 DAO Provider
final kbDaoProvider = Provider<KbDao>((ref) {
  final db = ref.watch(databaseProvider);
  return KbDao(db);
});

/// 知识库索引器 Provider
final kbIndexerProvider = Provider<KbIndexer>((ref) {
  return KbIndexer(ref.watch(kbDaoProvider));
});

/// 知识库存储根目录 (来自设置，回退到 documents/.RemindAI/knowledge_base)
final kbStorageDirProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.knowledgeBasePath ?? '';
});

/// 解析进度状态 (按 kbId 隔离)
class KbIndexProgress {
  final int total; // 待解析总数
  final int completed; // 已完成数 (成功+失败)
  final bool running; // 是否正在跑

  const KbIndexProgress({
    this.total = 0,
    this.completed = 0,
    this.running = false,
  });

  double get fraction => total > 0 ? completed / total : 0;
  bool get isDone => !running || completed >= total;
}

/// 解析进度 Provider (family, 按 kbId)
final kbIndexProgressProvider = StateProvider.family<KbIndexProgress, String>((
  ref,
  kbId,
) {
  return const KbIndexProgress();
});

/// 全部知识库列表
final knowledgeBasesProvider =
    AsyncNotifierProvider<KnowledgeBasesNotifier, List<KnowledgeBase>>(
      KnowledgeBasesNotifier.new,
    );

class KnowledgeBasesNotifier extends AsyncNotifier<List<KnowledgeBase>> {
  KbDao get _dao => ref.read(kbDaoProvider);

  @override
  Future<List<KnowledgeBase>> build() async {
    return _dao.getAllBases();
  }

  /// 新建知识库 (指定不可修改的嵌入模型快照)
  Future<KnowledgeBase> createBase({
    required String name,
    String description = '',
    required String embeddingBaseUrl,
    required String embeddingApiKey,
    required String embeddingModel,
  }) async {
    final kb = await _dao.createBase(
      name: name,
      description: description,
      embeddingBaseUrl: embeddingBaseUrl,
      embeddingApiKey: embeddingApiKey,
      embeddingModel: embeddingModel,
    );
    ref.invalidateSelf();
    return kb;
  }

  Future<void> updateMeta({
    required String id,
    required String name,
    required String description,
  }) async {
    await _dao.updateBaseMeta(id: id, name: name, description: description);
    ref.invalidateSelf();
  }

  /// 删除知识库: Qdrant collection + 文档副本目录 + DB 记录
  Future<void> deleteBase(KnowledgeBase kb) async {
    final indexer = ref.read(kbIndexerProvider);
    final docsDir = _kbDocsDir(kb.id);
    await indexer.removeBase(kb, docsDir: docsDir);
    ref.invalidateSelf();
  }

  /// 知识库文档副本目录: `<knowledgeBasePath>/<kbId>`
  String _kbDocsDir(String kbId) {
    final root = ref.read(kbStorageDirProvider);
    if (root.isEmpty) return '';
    return p.join(root, kbId);
  }
}

/// 某个知识库的文档列表 (family, 按 kbId 区分)
final kbDocumentsProvider =
    AsyncNotifierProvider.family<KbDocumentsNotifier, List<KbDocument>, String>(
      KbDocumentsNotifier.new,
    );

class KbDocumentsNotifier
    extends FamilyAsyncNotifier<List<KbDocument>, String> {
  KbDao get _dao => ref.read(kbDaoProvider);
  String get _kbId => arg;

  /// 知识库文档副本目录: `<knowledgeBasePath>/<kbId>`
  String _kbDocsDir(String kbId) {
    final root = ref.read(kbStorageDirProvider);
    if (root.isEmpty) return '';
    return p.join(root, kbId);
  }

  @override
  Future<List<KbDocument>> build(String kbId) async {
    return _dao.getDocuments(kbId);
  }

  /// 批量导入文件路径到知识库 (pending 状态)。
  ///
  /// [sourceGroup] 可选，传文件夹名则该批次归为一组 (UI 折叠显示)。
  /// 使用事务批量写 DB，几百份文件也能毫秒级完成。
  /// 同名文件自动跳过，不复制文件 — 副本在"开始解析"时按需复制。
  Future<void> importFiles(
    List<String> filePaths, {
    String sourceGroup = '',
  }) async {
    final files = filePaths
        .map((p_) => (filename: p.basename(p_), sourcePath: p_))
        .toList();

    final added = await _dao.batchInsertDocuments(
      kbId: _kbId,
      files: files,
      sourceGroup: sourceGroup,
    );

    final skipped = filePaths.length - added;
    if (skipped > 0) {
      debugPrint('[KB] 导入: 新增 $added 份, 跳过重复 $skipped 份');
    } else {
      debugPrint('[KB] 导入: 新增 $added 份');
    }

    // 立即刷新列表
    state = AsyncData(await _dao.getDocuments(_kbId));
  }

  /// 目录导入: 接收已计算好的 (相对路径 filename, 绝对路径 sourcePath) 对。
  ///
  /// filename 包含子目录层级 (如 "src/main.py")，避免跨目录同名文件被误判重复。
  Future<void> importDirFiles(
    List<({String filename, String sourcePath})> files, {
    String sourceGroup = '',
  }) async {
    final added = await _dao.batchInsertDocuments(
      kbId: _kbId,
      files: files,
      sourceGroup: sourceGroup,
    );

    final skipped = files.length - added;
    if (skipped > 0) {
      debugPrint('[KB] 目录导入: 新增 $added 份, 跳过重复 $skipped 份');
    } else {
      debugPrint('[KB] 目录导入: 新增 $added 份');
    }

    // 立即刷新列表
    state = AsyncData(await _dao.getDocuments(_kbId));
  }

  /// 一键解析: 将所有 pending/failed 状态的文档逐个解析入库。
  ///
  /// 后台逐个跑: 每完成一份刷新列表 + 更新进度条。不阻塞 UI (调用方用
  /// fire-and-forget 发射即可)，用户可在进度条旁边继续做其他操作。
  Future<void> indexAllPending() async {
    final progressNotifier = ref.read(kbIndexProgressProvider(_kbId).notifier);

    // 立即标记 running，让 UI 瞬间响应
    progressNotifier.state = const KbIndexProgress(
      total: 0,
      completed: 0,
      running: true,
    );
    debugPrint('[KB] 开始解析知识库 $_kbId ...');

    final kb = await _dao.getBase(_kbId);
    if (kb == null) {
      debugPrint('[KB] 错误: 知识库 $_kbId 不存在');
      progressNotifier.state = const KbIndexProgress();
      return;
    }

    // 确保 Qdrant 就绪
    final qdrant = QdrantService.instance;
    if (!await qdrant.probeHealth()) {
      debugPrint('[KB] Qdrant 未运行，尝试启动...');
      try {
        await qdrant.start();
        debugPrint('[KB] Qdrant 已启动');
      } catch (e) {
        debugPrint('[KB] Qdrant 启动失败: $e');
      }
    }

    final docs = await _dao.getDocuments(_kbId);
    final pending = docs
        .where(
          (d) =>
              d.status == KbDocStatus.pending || d.status == KbDocStatus.failed,
        )
        .toList();
    if (pending.isEmpty) {
      debugPrint('[KB] 无待解析文档');
      progressNotifier.state = const KbIndexProgress();
      return;
    }

    debugPrint('[KB] 待解析文档: ${pending.length} 份');
    progressNotifier.state = KbIndexProgress(
      total: pending.length,
      completed: 0,
      running: true,
    );

    final indexer = ref.read(kbIndexerProvider);
    final docsDir = _kbDocsDir(_kbId);
    int completed = 0;

    for (final doc in pending) {
      debugPrint(
        '[KB] 解析: ${doc.filename} (${completed + 1}/${pending.length})',
      );

      // 先将文件复制到 KB 存储目录 (导入阶段只登记了原始路径)
      var workDoc = doc;
      if (docsDir.isNotEmpty) {
        try {
          final destPath = p.join(docsDir, doc.filename);
          // filename 可能含子目录 (如 src/main.py)，需确保父目录存在
          final destDir = Directory(p.dirname(destPath));
          if (!await destDir.exists()) {
            await destDir.create(recursive: true);
          }
          final srcFile = File(doc.sourcePath);
          if (await srcFile.exists()) {
            await srcFile.copy(destPath);
            // 更新 DB 中的 sourcePath 指向副本
            await _dao.updateDocumentSourcePath(doc.id, destPath);
            workDoc = KbDocument(
              id: doc.id,
              kbId: doc.kbId,
              filename: doc.filename,
              sourcePath: destPath,
              sourceGroup: doc.sourceGroup,
              chunkCount: doc.chunkCount,
              charCount: doc.charCount,
              status: doc.status,
              error: doc.error,
              importedAt: doc.importedAt,
            );
          } else {
            debugPrint('[KB] ⚠ 源文件不存在: ${doc.sourcePath}');
          }
        } catch (e) {
          debugPrint('[KB] ⚠ 复制文件失败: ${doc.filename} — $e');
        }
      }

      try {
        final chunks = await indexer.indexDocument(kb: kb, doc: workDoc);
        debugPrint('[KB] ✓ ${doc.filename} → $chunks 块');
      } catch (e) {
        debugPrint('[KB] ✗ ${doc.filename} 失败: $e');
      }
      completed++;
      progressNotifier.state = KbIndexProgress(
        total: pending.length,
        completed: completed,
        running: true,
      );
      // 每份文档处理完刷新列表
      state = AsyncData(await _dao.getDocuments(_kbId));
    }

    // 结束进度
    progressNotifier.state = KbIndexProgress(
      total: pending.length,
      completed: completed,
      running: false,
    );
    debugPrint('[KB] 解析全部完成 ($completed/${pending.length})');

    // 维度可能已回填
    ref.invalidate(knowledgeBasesProvider);
  }

  /// 删除一份文档 (向量块 + 副本 + 记录)
  Future<void> deleteDocument(KbDocument doc) async {
    final kb = await _dao.getBase(_kbId);
    if (kb == null) return;
    final indexer = ref.read(kbIndexerProvider);
    await indexer.removeDocument(kb: kb, doc: doc);
    state = AsyncData(await _dao.getDocuments(_kbId));
  }

  /// 重新索引一份失败的文档
  Future<void> retryDocument(KbDocument doc) async {
    final kb = await _dao.getBase(_kbId);
    if (kb == null) return;
    final indexer = ref.read(kbIndexerProvider);
    try {
      await indexer.indexDocument(kb: kb, doc: doc);
    } catch (_) {}
    state = AsyncData(await _dao.getDocuments(_kbId));
    ref.invalidate(knowledgeBasesProvider);
  }

  Future<void> refresh() async {
    state = AsyncData(await _dao.getDocuments(_kbId));
  }
}

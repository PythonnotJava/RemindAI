import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/daos/kb_dao.dart';
import '../db/tables/knowledge_base.dart';
import '../logger/app_logger.dart';
import '../memory/memory_manager.dart';
import '../utils/document_extractor.dart';

/// 知识库切块策略参数
class ChunkConfig {
  /// 目标块大小 (字符数)
  final int chunkSize;

  /// 相邻块的重叠字符数 (保留上下文连贯)
  final int overlap;

  const ChunkConfig({this.chunkSize = 900, this.overlap = 120});
}

/// 文本纯文本已经支持直接读取的扩展名 (无需外部工具)
const _plainTextExts = {
  'txt',
  'md',
  'markdown',
  'json',
  'csv',
  'log',
  'yaml',
  'yml',
  'xml',
  'html',
  'htm',
};

/// 知识库索引器 — 负责"炼丹": 文档 → 文本 → 切块 → 嵌入 → 写入 Qdrant。
///
/// 不持有状态，所有依赖 (KB 配置、DAO) 通过参数传入。每次导入构建一个
/// 与该知识库固定嵌入模型匹配的 [MemoryManager]，写入其独占 collection。
class KbIndexer {
  final KbDao _dao;

  KbIndexer(this._dao);

  /// 为指定知识库构建 MemoryManager (使用其快照的嵌入配置)。
  MemoryManager _managerFor(KnowledgeBase kb) {
    return MemoryManager(
      embeddingBaseUrl: kb.embeddingBaseUrl,
      embeddingApiKey: kb.embeddingApiKey,
      embeddingModel: kb.embeddingModel,
      // 知识库不走 SQLite 双写，向量元数据由 kb_documents 表管理
      memoryDao: null,
    );
  }

  /// 解析并索引一份已登记的文档 ([doc] 通常处于 pending 状态)。
  ///
  /// 全流程: 提取文本 → 切块 → 逐块嵌入写入 Qdrant → 更新文档状态。
  /// 成功返回切块数；失败抛出异常前会把文档标记为 failed。
  Future<int> indexDocument({
    required KnowledgeBase kb,
    required KbDocument doc,
    ChunkConfig chunkConfig = const ChunkConfig(),
  }) async {
    await _dao.updateDocumentStatus(
      docId: doc.id,
      status: KbDocStatus.indexing,
    );

    try {
      final filePath = doc.sourcePath;
      final ext = p.extension(doc.filename).replaceFirst('.', '').toLowerCase();

      // 1. 提取文本
      final text = await _extractText(filePath, ext);
      if (text.trim().isEmpty) {
        throw Exception('未提取到任何文本内容');
      }

      // 2. 切块
      final chunks = chunkText(text, chunkConfig);
      if (chunks.isEmpty) {
        throw Exception('切块结果为空');
      }

      // 3. 逐块嵌入写入 Qdrant
      final manager = _managerFor(kb);
      final dimension = await manager.addKnowledgeChunks(
        collectionName: kb.collection,
        chunks: chunks,
        payloadBase: {
          'document_id': doc.id,
          'kb_id': kb.id,
          'filename': doc.filename,
        },
      );

      // 4. 回填维度 (首次) + 文档状态
      if (kb.embeddingDimension == 0 && dimension > 0) {
        await _dao.setBaseDimension(kb.id, dimension);
      }
      await _dao.updateDocumentStatus(
        docId: doc.id,
        status: KbDocStatus.done,
        chunkCount: chunks.length,
        charCount: text.length,
        error: '',
      );

      AppLogger.instance.log(
        '[KB] 索引完成: ${doc.filename} → ${chunks.length} 块 '
        '(collection=${kb.collection})',
      );
      return chunks.length;
    } catch (e) {
      final msg = e.toString();
      await _dao.updateDocumentStatus(
        docId: doc.id,
        status: KbDocStatus.failed,
        error: msg.length > 300 ? msg.substring(0, 300) : msg,
      );
      AppLogger.instance.log('[KB] 索引失败: ${doc.filename} — $e');
      rethrow;
    }
  }

  /// 从知识库中删除一份文档: 清除其所有向量块 + 文档记录。
  ///
  /// 当知识库内所有文档都被删除后，会自动删除 Qdrant collection
  /// 以释放磁盘空间 (Qdrant 的 segment 文件在 deletePoints 后不会
  /// 自动回收，需要整个 collection 被删除才能释放)。
  Future<void> removeDocument({
    required KnowledgeBase kb,
    required KbDocument doc,
  }) async {
    final manager = _managerFor(kb);
    // 删除该文档在 Qdrant 中的全部块 (按 document_id 过滤)
    try {
      await manager.deletePointsByField(kb.collection, 'document_id', doc.id);
    } catch (e) {
      AppLogger.instance.log('[KB] 删除文档向量失败 (继续删记录): $e');
    }
    await _dao.deleteDocument(doc.id);

    // 删除导入时保存的文件副本 (尽力而为)
    if (doc.sourcePath.isNotEmpty) {
      try {
        final f = File(doc.sourcePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    // 如果知识库内已无文档，删除整个 collection 回收 Qdrant 磁盘空间
    final remaining = await _dao.documentCount(kb.id);
    if (remaining == 0) {
      try {
        await manager.deleteCollection(kb.collection);
        AppLogger.instance.log('[KB] 知识库 ${kb.name} 所有文档已移除，collection 已回收');
      } catch (e) {
        AppLogger.instance.log('[KB] 回收空 collection 失败: $e');
      }
    }
  }

  /// 删除整个知识库: Qdrant collection + 文档副本目录 + DB 记录。
  Future<void> removeBase(KnowledgeBase kb, {String? docsDir}) async {
    final manager = _managerFor(kb);
    try {
      await manager.deleteCollection(kb.collection);
    } catch (e) {
      AppLogger.instance.log('[KB] 删除 collection 失败 (继续删记录): $e');
    }
    await _dao.deleteBase(kb.id);

    if (docsDir != null && docsDir.isNotEmpty) {
      try {
        final dir = Directory(docsDir);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 提取文本: 纯文本类直接读，办公文档走 DocumentExtractor (pandoc/pdftotext)。
  Future<String> _extractText(String filePath, String ext) async {
    if (filePath.isEmpty || !await File(filePath).exists()) {
      throw Exception('源文件不存在: $filePath');
    }
    if (_plainTextExts.contains(ext)) {
      return await File(filePath).readAsString();
    }
    final result = await DocumentExtractor.extract(filePath, ext);
    if (!result.ok || result.text == null) {
      throw Exception(result.note ?? '文档解析失败');
    }
    return result.text!;
  }

  /// 中文友好切块。
  ///
  /// 策略: 先按段落 (空行) 聚合，累积到接近 [ChunkConfig.chunkSize] 时切分；
  /// 超长段落 (无空行的长文本) 按句末标点/长度硬切；相邻块保留
  /// [ChunkConfig.overlap] 字符重叠以维持上下文连贯。
  static List<String> chunkText(
    String text, [
    ChunkConfig cfg = const ChunkConfig(),
  ]) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return [];
    if (normalized.length <= cfg.chunkSize) return [normalized];

    // 先按段落拆
    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      buffer.clear();
    }

    for (final para in paragraphs) {
      // 单段超长 → 句子级硬切
      if (para.length > cfg.chunkSize) {
        flush();
        chunks.addAll(_splitLongText(para, cfg));
        continue;
      }
      if (buffer.length + para.length + 1 > cfg.chunkSize &&
          buffer.isNotEmpty) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(para);
    }
    flush();

    return _applyOverlap(chunks, cfg.overlap);
  }

  /// 无段落分隔的长文本: 按句末标点聚合，再不行按长度硬切。
  static List<String> _splitLongText(String text, ChunkConfig cfg) {
    final sentences = <String>[];
    final matches = RegExp(r'[^。！？!?\.\n]+[。！？!?\.]?').allMatches(text);
    for (final m in matches) {
      final s = m.group(0)!.trim();
      if (s.isNotEmpty) sentences.add(s);
    }
    if (sentences.isEmpty) {
      // 极端: 无标点，纯长度硬切
      return _hardSplit(text, cfg.chunkSize);
    }

    final out = <String>[];
    final buf = StringBuffer();
    for (final s in sentences) {
      if (s.length > cfg.chunkSize) {
        if (buf.isNotEmpty) {
          out.add(buf.toString().trim());
          buf.clear();
        }
        out.addAll(_hardSplit(s, cfg.chunkSize));
        continue;
      }
      if (buf.length + s.length > cfg.chunkSize && buf.isNotEmpty) {
        out.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(s);
    }
    if (buf.isNotEmpty) out.add(buf.toString().trim());
    return out;
  }

  /// 纯长度硬切
  static List<String> _hardSplit(String text, int size) {
    final out = <String>[];
    for (var i = 0; i < text.length; i += size) {
      final end = (i + size < text.length) ? i + size : text.length;
      out.add(text.substring(i, end));
    }
    return out;
  }

  /// 给相邻块添加前缀重叠 (取上一块末尾 [overlap] 字符)。
  static List<String> _applyOverlap(List<String> chunks, int overlap) {
    if (overlap <= 0 || chunks.length <= 1) return chunks;
    final out = <String>[chunks.first];
    for (var i = 1; i < chunks.length; i++) {
      final prev = chunks[i - 1];
      final tail = prev.length > overlap
          ? prev.substring(prev.length - overlap)
          : prev;
      out.add('$tail\n${chunks[i]}');
    }
    return out;
  }
}

import 'package:sqlite3/sqlite3.dart';

/// 知识库 — 一个按主题/项目组织的文档集合。
///
/// 每个知识库独占一个 Qdrant collection ([collection])，并在创建时
/// 快照当时选中的嵌入模型配置。嵌入模型一旦确定即不可修改
/// (变更维度会导致已有向量失效)，需换模型请新建知识库。
class KnowledgeBase {
  final String id;
  final String name;
  final String description;

  /// 独占的 Qdrant collection 名称 (与记忆共享同一 Qdrant 进程，靠 collection 隔离)。
  final String collection;

  // ─── 嵌入模型快照 (创建时固定，不可修改) ───
  final String embeddingBaseUrl;
  final String embeddingApiKey;
  final String embeddingModel;

  /// 向量维度 (首次成功嵌入后回填，用于校验/展示)，0 表示未知。
  final int embeddingDimension;

  final DateTime createdAt;

  const KnowledgeBase({
    required this.id,
    required this.name,
    this.description = '',
    required this.collection,
    this.embeddingBaseUrl = '',
    this.embeddingApiKey = '',
    this.embeddingModel = '',
    this.embeddingDimension = 0,
    required this.createdAt,
  });

  /// 嵌入模型显示名 (空则占位)
  String get embeddingDisplay =>
      embeddingModel.isNotEmpty ? embeddingModel : '未指定模型';

  bool get hasEmbedding =>
      embeddingBaseUrl.isNotEmpty &&
      embeddingApiKey.isNotEmpty &&
      embeddingModel.isNotEmpty;

  factory KnowledgeBase.fromRow(Row row) {
    return KnowledgeBase(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String? ?? '',
      collection: row['collection'] as String,
      embeddingBaseUrl: row['embedding_base_url'] as String? ?? '',
      embeddingApiKey: row['embedding_api_key'] as String? ?? '',
      embeddingModel: row['embedding_model'] as String? ?? '',
      embeddingDimension: (row['embedding_dimension'] as int?) ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  KnowledgeBase copyWith({
    String? name,
    String? description,
    String? embeddingBaseUrl,
    String? embeddingApiKey,
    String? embeddingModel,
    int? embeddingDimension,
  }) {
    return KnowledgeBase(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      collection: collection,
      embeddingBaseUrl: embeddingBaseUrl ?? this.embeddingBaseUrl,
      embeddingApiKey: embeddingApiKey ?? this.embeddingApiKey,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      embeddingDimension: embeddingDimension ?? this.embeddingDimension,
      createdAt: createdAt,
    );
  }
}

/// 知识库文档的解析状态
enum KbDocStatus {
  pending, // 待解析
  indexing, // 解析中 (炼丹)
  done, // 已入库
  failed; // 解析/入库失败

  static KbDocStatus fromName(String s) {
    return KbDocStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => KbDocStatus.pending,
    );
  }
}

/// 知识库内的一份文档 — 记录来源、切块数与解析状态。
class KbDocument {
  final String id;
  final String kbId;
  final String filename;

  /// 导入时保存到知识库目录的副本路径 (可空)。
  final String sourcePath;

  /// 导入来源分组: 目录导入时为文件夹名 (如 "docs"), 散文件导入为空。
  /// UI 按此字段折叠显示 — 相同 group 的文件归为一组。
  final String sourceGroup;

  /// 切块数量 (入库后回填)。
  final int chunkCount;

  /// 提取到的纯文本字符数。
  final int charCount;

  final KbDocStatus status;

  /// 失败原因 (status=failed 时有效)。
  final String error;

  final DateTime importedAt;

  const KbDocument({
    required this.id,
    required this.kbId,
    required this.filename,
    this.sourcePath = '',
    this.sourceGroup = '',
    this.chunkCount = 0,
    this.charCount = 0,
    this.status = KbDocStatus.pending,
    this.error = '',
    required this.importedAt,
  });

  factory KbDocument.fromRow(Row row) {
    return KbDocument(
      id: row['id'] as String,
      kbId: row['kb_id'] as String,
      filename: row['filename'] as String,
      sourcePath: row['source_path'] as String? ?? '',
      sourceGroup: row['source_group'] as String? ?? '',
      chunkCount: (row['chunk_count'] as int?) ?? 0,
      charCount: (row['char_count'] as int?) ?? 0,
      status: KbDocStatus.fromName(row['status'] as String? ?? 'pending'),
      error: row['error'] as String? ?? '',
      importedAt: DateTime.parse(row['imported_at'] as String),
    );
  }
}

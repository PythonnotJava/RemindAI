import 'package:sqlite3/sqlite3.dart';

class ModelCard {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final bool isDefault;
  final DateTime createdAt;
  final int sortIndex;

  /// 用户导入的 logo 文件路径，空字符串表示未设置 (使用品牌识别或默认图标兜底)。
  final String logoPath;

  /// 协议类型标识 (openai / anthropic / gemini)，默认 openai。
  final String provider;

  const ModelCard({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    this.isDefault = false,
    required this.createdAt,
    this.sortIndex = 0,
    this.logoPath = '',
    this.provider = 'openai',
  });

  factory ModelCard.fromRow(Row row) {
    return ModelCard(
      id: row['id'] as String,
      name: row['name'] as String,
      baseUrl: row['base_url'] as String,
      apiKey: row['api_key'] as String,
      modelId: row['model_id'] as String,
      isDefault: (row['is_default'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      sortIndex: (row['sort_index'] as int?) ?? 0,
      logoPath: row['logo_path'] as String? ?? '',
      provider: row['provider'] as String? ?? 'openai',
    );
  }

  ModelCard copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? modelId,
    bool? isDefault,
    int? sortIndex,
    String? logoPath,
    String? provider,
  }) {
    return ModelCard(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelId: modelId ?? this.modelId,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
      sortIndex: sortIndex ?? this.sortIndex,
      logoPath: logoPath ?? this.logoPath,
      provider: provider ?? this.provider,
    );
  }
}

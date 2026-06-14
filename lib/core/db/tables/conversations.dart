import 'package:sqlite3/sqlite3.dart';

class Conversation {
  final int id;
  final String title;
  final String modelCardId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.title,
    required this.modelCardId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromRow(Row row) {
    return Conversation(
      id: row['id'] as int,
      title: row['title'] as String,
      modelCardId: row['model_card_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Conversation copyWith({
    String? title,
    String? modelCardId,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      modelCardId: modelCardId ?? this.modelCardId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

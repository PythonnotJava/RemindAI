import 'dart:convert';

import '../database.dart';
import '../tables/conversations.dart';
import '../../llm/models.dart';
import '../../models/file_attachment.dart';

/// 数据库消息行（包含 ID）
class DbChatMessage {
  final int id;
  final ChatMessage message;

  DbChatMessage({required this.id, required this.message});
}

class ConversationsDao {
  final DatabaseHelper _dbHelper;

  ConversationsDao(this._dbHelper);

  /// 创建新会话
  Future<Conversation> create({
    required String title,
    required String modelCardId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    db.execute(
      '''INSERT INTO conversations (title, model_card_id, created_at, updated_at)
         VALUES (?, ?, ?, ?)''',
      [title, modelCardId, now, now],
    );
    final id = db.lastInsertRowId;
    return Conversation(
      id: id,
      title: title,
      modelCardId: modelCardId,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
  }

  /// 获取所有会话，按更新时间倒序
  Future<List<Conversation>> getAll() async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM conversations ORDER BY updated_at DESC',
    );
    return result.map((row) => Conversation.fromRow(row)).toList();
  }

  /// 根据 ID 获取会话
  Future<Conversation?> getById(int id) async {
    final db = await _dbHelper.database;
    final result = db.select('SELECT * FROM conversations WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return Conversation.fromRow(result.first);
  }

  /// 更新会话标题
  Future<void> updateTitle(int id, String title) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    db.execute(
      'UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?',
      [title, now, id],
    );
  }

  /// 更新会话的 updated_at
  Future<void> touch(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    db.execute('UPDATE conversations SET updated_at = ? WHERE id = ?', [
      now,
      id,
    ]);
  }

  /// 删除会话及其消息
  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM chat_messages WHERE conversation_id = ?', [id]);
    db.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }

  /// 清空所有会话及消息
  Future<void> deleteAll() async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM chat_messages');
    db.execute('DELETE FROM conversations');
  }

  /// 获取会话的所有消息
  Future<List<ChatMessage>> getMessages(int conversationId) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM chat_messages WHERE conversation_id = ? ORDER BY id ASC',
      [conversationId],
    );
    return _parseMessageRows(result);
  }

  /// 获取会话的消息（分页）
  /// [limit] 返回的消息数量
  /// [beforeMessageId] 如果指定，返回该消息之前的消息（用于向上翻页）
  /// 返回带 ID 的消息列表
  Future<List<DbChatMessage>> getMessagesPage(
    int conversationId, {
    required int limit,
    int? beforeMessageId,
  }) async {
    final db = await _dbHelper.database;

    String query;
    List<Object?> params;

    if (beforeMessageId != null) {
      // 加载更早的消息：id < beforeMessageId，按 id 降序取 limit 条，然后反转
      query = '''
        SELECT * FROM chat_messages
        WHERE conversation_id = ? AND id < ?
        ORDER BY id DESC
        LIMIT ?
      ''';
      params = [conversationId, beforeMessageId, limit];
    } else {
      // 初始加载：取最新的 limit 条消息
      query = '''
        SELECT * FROM chat_messages
        WHERE conversation_id = ?
        ORDER BY id DESC
        LIMIT ?
      ''';
      params = [conversationId, limit];
    }

    final result = db.select(query, params);
    final dbMessages = _parseMessageRowsWithId(result);

    // 因为查询是降序的，需要反转以保持时间顺序
    return dbMessages.reversed.toList();
  }

  /// 获取会话的消息总数
  Future<int> getMessageCount(int conversationId) async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT COUNT(*) as count FROM chat_messages WHERE conversation_id = ?',
      [conversationId],
    );
    return result.first['count'] as int;
  }

  /// 解析消息行数据
  List<ChatMessage> _parseMessageRows(List<dynamic> result) {
    return result.map((row) {
      List<ChatToolCall>? toolCalls;
      final toolCallsJson = row['tool_calls'] as String?;
      if (toolCallsJson != null && toolCallsJson.isNotEmpty) {
        final list = jsonDecode(toolCallsJson) as List;
        toolCalls = list
            .map((tc) => ChatToolCall.fromMap(tc as Map<String, dynamic>))
            .toList();
      }

      final roleStr = row['role'] as String;
      final role = ChatRole.values.firstWhere((r) => r.name == roleStr);

      // 解析附件 (列可能在旧库中不存在)
      List<FileAttachment> attachments = const [];
      final attachmentsJson = _safeColumn(row, 'attachments');
      if (attachmentsJson != null && attachmentsJson.isNotEmpty) {
        try {
          final list = jsonDecode(attachmentsJson) as List;
          attachments = list
              .map((e) => FileAttachment.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      return ChatMessage(
        role: role,
        content: row['content'] as String?,
        toolCalls: toolCalls,
        toolCallId: row['tool_call_id'] as String?,
        timestamp: DateTime.parse(row['created_at'] as String),
        attachments: attachments,
        interrupted: (_safeColumnInt(row, 'interrupted') ?? 0) == 1,
        thinkingContent: _safeColumn(row, 'thinking_content'),
      );
    }).toList();
  }

  /// 解析消息行数据（带 ID）
  List<DbChatMessage> _parseMessageRowsWithId(List<dynamic> result) {
    return result.map((row) {
      final id = row['id'] as int;
      List<ChatToolCall>? toolCalls;
      final toolCallsJson = row['tool_calls'] as String?;
      if (toolCallsJson != null && toolCallsJson.isNotEmpty) {
        final list = jsonDecode(toolCallsJson) as List;
        toolCalls = list
            .map((tc) => ChatToolCall.fromMap(tc as Map<String, dynamic>))
            .toList();
      }

      final roleStr = row['role'] as String;
      final role = ChatRole.values.firstWhere((r) => r.name == roleStr);

      // 解析附件 (列可能在旧库中不存在)
      List<FileAttachment> attachments = const [];
      final attachmentsJson = _safeColumn(row, 'attachments');
      if (attachmentsJson != null && attachmentsJson.isNotEmpty) {
        try {
          final list = jsonDecode(attachmentsJson) as List;
          attachments = list
              .map((e) => FileAttachment.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {}
      }

      final message = ChatMessage(
        role: role,
        content: row['content'] as String?,
        toolCalls: toolCalls,
        toolCallId: row['tool_call_id'] as String?,
        timestamp: DateTime.parse(row['created_at'] as String),
        attachments: attachments,
        interrupted: (_safeColumnInt(row, 'interrupted') ?? 0) == 1,
        thinkingContent: _safeColumn(row, 'thinking_content'),
      );

      return DbChatMessage(id: id, message: message);
    }).toList();
  }

  /// 安全读取列值（列不存在时返回 null，避免旧库报错）。
  String? _safeColumn(dynamic row, String column) {
    try {
      return row[column] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 安全读取 int 列值。
  int? _safeColumnInt(dynamic row, String column) {
    try {
      return row[column] as int?;
    } catch (_) {
      return null;
    }
  }

  /// 删除指定会话中的第 N 条消息 (按数据库行顺序)
  Future<void> deleteMessageAt(int conversationId, int index) async {
    final db = await _dbHelper.database;
    // 获取该会话所有消息的 id
    final result = db.select(
      'SELECT id FROM chat_messages WHERE conversation_id = ? ORDER BY id ASC',
      [conversationId],
    );
    if (index >= 0 && index < result.length) {
      final msgId = result[index]['id'] as int;
      db.execute('DELETE FROM chat_messages WHERE id = ?', [msgId]);
    }
  }

  /// 保存消息到会话
  Future<void> saveMessage(int conversationId, ChatMessage message) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    String? toolCallsJson;
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      toolCallsJson = jsonEncode(
        message.toolCalls!.map((tc) => tc.toMap()).toList(),
      );
    }

    final attachmentsJson = message.attachments.isEmpty
        ? '[]'
        : jsonEncode(message.attachments.map((a) => a.toJson()).toList());

    db.execute(
      '''INSERT INTO chat_messages (conversation_id, role, content, tool_calls, tool_call_id, attachments, interrupted, thinking_content, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        conversationId,
        message.role.name,
        message.content,
        toolCallsJson,
        message.toolCallId,
        attachmentsJson,
        message.interrupted ? 1 : 0,
        message.thinkingContent, // 新增：保存 thinking 内容
        now,
      ],
    );

    // 同时更新会话的 updated_at
    db.execute('UPDATE conversations SET updated_at = ? WHERE id = ?', [
      now,
      conversationId,
    ]);
  }
}

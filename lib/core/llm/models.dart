import 'dart:convert';

import '../models/file_attachment.dart';

/// 聊天消息角色
enum ChatRole { user, assistant, tool, system }

/// 聊天消息数据模型
class ChatMessage {
  final ChatRole role;
  final String? content;
  final List<ChatToolCall>? toolCalls;
  final String? toolCallId;
  final DateTime timestamp;

  /// 该消息是否由用户手动中断生成
  final bool interrupted;

  /// 思考/推理过程内容（extended_thinking / reasoning_content）
  /// 用于展示 AI 的思考过程，不发送给模型
  final String? thinkingContent;

  /// 随消息携带的附件（图片/文档等）。仅用于 UI 展示与持久化，
  /// 不参与发给模型的 content parts 构建。
  final List<FileAttachment> attachments;

  /// 可视化输出文件路径（HTML 交互图表、SVG 矢量图、视频动画等）
  final List<String> htmlFiles;
  final List<String> svgFiles;
  final List<String> videoFiles;

  ChatMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    DateTime? timestamp,
    this.attachments = const [],
    this.interrupted = false,
    this.thinkingContent,
    this.htmlFiles = const [],
    this.svgFiles = const [],
    this.videoFiles = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  /// 创建用户消息
  factory ChatMessage.user(
    String content, {
    List<FileAttachment> attachments = const [],
  }) => ChatMessage(
    role: ChatRole.user,
    content: content,
    attachments: attachments,
  );

  /// 创建助手消息
  factory ChatMessage.assistant(
    String content, {
    List<ChatToolCall>? toolCalls,
    bool interrupted = false,
    String? thinkingContent,
    List<String> htmlFiles = const [],
    List<String> svgFiles = const [],
    List<String> videoFiles = const [],
  }) => ChatMessage(
    role: ChatRole.assistant,
    content: content,
    toolCalls: toolCalls,
    interrupted: interrupted,
    thinkingContent: thinkingContent,
    htmlFiles: htmlFiles,
    svgFiles: svgFiles,
    videoFiles: videoFiles,
  );

  /// 创建工具结果消息
  factory ChatMessage.toolResult({
    required String toolCallId,
    required String result,
  }) =>
      ChatMessage(role: ChatRole.tool, content: result, toolCallId: toolCallId);

  /// 创建系统消息
  factory ChatMessage.system(String content) =>
      ChatMessage(role: ChatRole.system, content: content);

  /// 转换为 AgentLoop 使用的 Map 格式
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'role': role.name};
    if (content != null) map['content'] = content;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((tc) => tc.toMap()).toList();
    }
    if (toolCallId != null) {
      map['tool_call_id'] = toolCallId;
    }
    return map;
  }

  /// 从 AgentLoop 使用的 Map 格式创建
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final roleStr = map['role'] as String;
    final role = ChatRole.values.firstWhere((r) => r.name == roleStr);

    List<ChatToolCall>? toolCalls;
    if (map['tool_calls'] != null) {
      toolCalls = (map['tool_calls'] as List)
          .map((tc) => ChatToolCall.fromMap(tc as Map<String, dynamic>))
          .toList();
    }

    return ChatMessage(
      role: role,
      content: map['content'] as String?,
      toolCalls: toolCalls,
      toolCallId: map['tool_call_id'] as String?,
    );
  }
}

/// 工具调用数据
class ChatToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  ChatToolCall({required this.id, required this.name, required this.arguments});

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };

  factory ChatToolCall.fromMap(Map<String, dynamic> map) {
    final function_ = map['function'] as Map<String, dynamic>;
    final argsRaw = function_['arguments'];
    final args = argsRaw is String
        ? jsonDecode(argsRaw) as Map<String, dynamic>
        : argsRaw as Map<String, dynamic>;
    return ChatToolCall(
      id: map['id'] as String,
      name: function_['name'] as String,
      arguments: args,
    );
  }
}

/// 模型卡片配置
class ModelCard {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 用户导入的 logo 文件路径，空表示无 (UI 用品牌识别兜底)。
  final String logoPath;

  /// 协议类型标识 (openai / anthropic / gemini)。
  final String provider;

  /// 模型上下文窗口大小 (token 数)。
  /// 用于动态计算上下文压缩阈值等场景。
  /// 0 表示未知，会使用保守默认值。
  final int contextWindow;

  const ModelCard({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.logoPath = '',
    this.provider = 'openai',
    this.contextWindow = 0,
  });
}

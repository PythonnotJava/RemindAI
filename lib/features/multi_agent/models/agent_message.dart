/// Agent 间的消息类型
enum AgentMessageType {
  user, // 用户发给Agent的
  assistant, // Agent回复
  broadcast, // 广播给所有Agent（来自指挥部）
  direct, // Agent间点对点通信
  system, // 系统消息（如Agent创建/销毁通知）
  toolResult, // 工具执行结果
}

/// 多Agent协作中的一条消息
class AgentMessage {
  final String id;
  final String fromAgentId; // 发送者Agent id ("user" 表示用户)
  final String? toAgentId; // 接收者Agent id (null = broadcast)
  final AgentMessageType type;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata; // 附加数据（工具调用等）

  const AgentMessage({
    required this.id,
    required this.fromAgentId,
    this.toAgentId,
    required this.type,
    required this.content,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromAgentId': fromAgentId,
    'toAgentId': toAgentId,
    'type': type.name,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    if (metadata != null) 'metadata': metadata,
  };

  factory AgentMessage.fromJson(Map<String, dynamic> json) => AgentMessage(
    id: json['id'] as String,
    fromAgentId: json['fromAgentId'] as String,
    toAgentId: json['toAgentId'] as String?,
    type: AgentMessageType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => AgentMessageType.system,
    ),
    content: json['content'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    metadata: json['metadata'] as Map<String, dynamic>?,
  );
}

/// 任务分配
class AgentTask {
  final String id;
  final String description;
  final String assignedAgentId;
  final String assignedByAgentId; // 通常是 commander
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? result;

  const AgentTask({
    required this.id,
    required this.description,
    required this.assignedAgentId,
    required this.assignedByAgentId,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.result,
  });

  AgentTask copyWith({
    TaskStatus? status,
    DateTime? completedAt,
    String? result,
  }) {
    return AgentTask(
      id: id,
      description: description,
      assignedAgentId: assignedAgentId,
      assignedByAgentId: assignedByAgentId,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      result: result ?? this.result,
    );
  }
}

enum TaskStatus { pending, inProgress, completed, failed }

// 上下文压缩任务 — 在 Isolate 中执行对话历史的智能裁剪。
//
// 适用场景:
// - 对话消息数超过模型上下文窗口时的智能截断
// - 上下文 token 超限时的优先级选择
//
// 策略:
// 1. 系统消息（system prompt）始终保留
// 2. 最近 N 条消息始终保留（保证连贯性）
// 3. 中间消息按优先级评分: 含代码/链接/结论的消息权重高
// 4. 工具调用消息可压缩为摘要

/// 上下文消息的简化表示（可跨 Isolate）
class ContextMessage {
  final int index; // 原始位置
  final String role;
  final String content;
  final int estimatedTokens;
  final bool hasToolCalls;
  final bool isToolResult;

  ContextMessage({
    required this.index,
    required this.role,
    required this.content,
    required this.estimatedTokens,
    this.hasToolCalls = false,
    this.isToolResult = false,
  });
}

/// 压缩参数
class ContextCompressParam {
  final List<ContextMessage> messages;
  final int maxTokens;
  final int keepRecentCount;

  ContextCompressParam({
    required this.messages,
    required this.maxTokens,
    this.keepRecentCount = 10,
  });
}

/// 压缩结果
class ContextCompressResult {
  /// 保留的消息索引（按原始顺序）
  final List<int> retainedIndices;

  /// 被移除的消息数量
  final int removedCount;

  /// 压缩后的总 token 估计
  final int totalTokens;

  /// 压缩比 (0-1, 越小压缩越多)
  final double ratio;

  ContextCompressResult({
    required this.retainedIndices,
    required this.removedCount,
    required this.totalTokens,
    required this.ratio,
  });
}

/// 顶层函数: 智能上下文压缩（可传入 Isolate）
ContextCompressResult contextCompressTask(ContextCompressParam param) {
  final messages = param.messages;
  final maxTokens = param.maxTokens;
  final keepRecent = param.keepRecentCount;

  if (messages.isEmpty) {
    return ContextCompressResult(
      retainedIndices: [],
      removedCount: 0,
      totalTokens: 0,
      ratio: 1.0,
    );
  }

  // 计算总 token
  final totalOriginalTokens = messages.fold<int>(
    0,
    (sum, m) => sum + m.estimatedTokens,
  );

  // 如果不超限，全部保留
  if (totalOriginalTokens <= maxTokens) {
    return ContextCompressResult(
      retainedIndices: List.generate(messages.length, (i) => i),
      removedCount: 0,
      totalTokens: totalOriginalTokens,
      ratio: 1.0,
    );
  }

  // 分类消息
  final systemIndices = <int>[];
  final recentIndices = <int>[];
  final middleIndices = <int>[];

  for (int i = 0; i < messages.length; i++) {
    if (messages[i].role == 'system') {
      systemIndices.add(i);
    } else if (i >= messages.length - keepRecent) {
      recentIndices.add(i);
    } else {
      middleIndices.add(i);
    }
  }

  // 必须保留的消息
  final mustKeep = <int>{...systemIndices, ...recentIndices};
  int currentTokens = mustKeep.fold<int>(
    0,
    (sum, i) => sum + messages[i].estimatedTokens,
  );

  // 对中间消息按优先级评分
  final scored = middleIndices.map((i) {
    final score = _scoreMessage(messages[i]);
    return _ScoredIndex(i, score);
  }).toList();

  // 按分数降序排列
  scored.sort((a, b) => b.score.compareTo(a.score));

  // 贪心选择: 按优先级从高到低加入，直到 token 用完
  final retained = <int>{...mustKeep};
  for (final si in scored) {
    final needed = messages[si.index].estimatedTokens;
    if (currentTokens + needed <= maxTokens) {
      retained.add(si.index);
      currentTokens += needed;
    }
  }

  // 按原始顺序排序
  final retainedList = retained.toList()..sort();

  return ContextCompressResult(
    retainedIndices: retainedList,
    removedCount: messages.length - retainedList.length,
    totalTokens: currentTokens,
    ratio: currentTokens / totalOriginalTokens,
  );
}

/// Token 估算任务（批量）
List<int> tokenEstimateBatchTask(List<String> texts) {
  return texts.map(_estimateTokens).toList();
}

/// 单文本 token 估算
int tokenEstimateTask(String text) {
  return _estimateTokens(text);
}

// =============================================================================
// 内部工具
// =============================================================================

class _ScoredIndex {
  final int index;
  final double score;
  _ScoredIndex(this.index, this.score);
}

/// 消息优先级评分
double _scoreMessage(ContextMessage msg) {
  double score = 0;
  final content = msg.content;

  // 用户消息基础分较高（提供上下文）
  if (msg.role == 'user') score += 2.0;

  // 含代码块 → 高权重（通常含重要决策/实现）
  if (content.contains('```')) score += 3.0;

  // 含链接 → 中等权重
  if (content.contains('http://') || content.contains('https://')) score += 1.0;

  // 长消息 → 通常更重要
  if (content.length > 500) score += 1.5;
  if (content.length > 2000) score += 1.0;

  // 工具调用结果 → 低权重（通常可舍弃，AI 记得结论）
  if (msg.isToolResult) score -= 2.0;

  // 含关键词（结论性内容）
  if (_hasDecisionKeywords(content)) score += 2.0;

  // 位置权重: 越早的消息优先级越低（自然衰减）
  // 这个由调用者通过排序处理，这里不重复

  return score;
}

bool _hasDecisionKeywords(String text) {
  const keywords = [
    '结论',
    '决定',
    '方案',
    '总结',
    '最终',
    '确认',
    'conclusion',
    'decision',
    'summary',
    'final',
    'confirmed',
    '修复',
    '解决',
    'fix',
    'resolved',
    'solution',
  ];
  final lower = text.toLowerCase();
  return keywords.any((k) => lower.contains(k));
}

int _estimateTokens(String text) {
  if (text.isEmpty) return 0;
  // 中文: ~1.5 token/字符, 英文: ~0.25 token/字符 (4字符≈1token)
  int cjkChars = 0;
  int asciiChars = 0;
  for (int i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0x4E00 && c <= 0x9FFF) {
      cjkChars++;
    } else {
      asciiChars++;
    }
  }
  return (cjkChars * 1.5 + asciiChars * 0.25).ceil();
}

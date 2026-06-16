import '../llm/llm_client.dart';

/// Agent 生命周期钩子抽象接口
///
/// 在 AgentLoop 的关键节点插入自定义逻辑,
/// 不修改核心循环代码即可扩展行为。
///
/// 所有方法均有默认空实现 (no-op)，子类只需 override 感兴趣的方法。
abstract class AgentHook {
  // ═══════════════════════════════════════════════════════════════
  // 会话生命周期
  // ═══════════════════════════════════════════════════════════════

  /// 会话开始时 — 用于初始化资源、加载上下文
  ///
  /// [conversationId] 会话 ID (新建时为新 ID，加载历史时为已有 ID)
  /// [messages] 当前消息历史 (可读写)
  Future<void> onSessionStart(
    int conversationId,
    List<Map<String, dynamic>> messages,
  ) async {}

  /// 会话结束时 — 用于清理资源、持久化统计
  ///
  /// [conversationId] 会话 ID
  /// [totalTurns] 本次会话总对话轮数
  Future<void> onSessionEnd(int conversationId, int totalTurns) async {}

  // ═══════════════════════════════════════════════════════════════
  // 用户消息
  // ═══════════════════════════════════════════════════════════════

  /// 用户消息发出前 — 可向 messages 追加 context (如记忆召回)
  ///
  /// [input] 用户输入文本
  /// [messages] 当前消息历史 (可读写)
  /// 返回修改后的 input (返回 null 表示不修改)
  Future<String?> onBeforeUserMessage(
    String input,
    List<Map<String, dynamic>> messages,
  ) async => null;

  // ═══════════════════════════════════════════════════════════════
  // LLM 调用
  // ═══════════════════════════════════════════════════════════════

  /// LLM 请求发送前 — 可用于缓存命中判断、请求审计、token 预估
  ///
  /// [messages] 即将发送给 LLM 的完整消息列表 (只读建议)
  /// [tools] 当前工具定义列表
  Future<void> onBeforeLlmCall(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {}

  /// LLM 响应接收完毕后 — 可用于响应质量评估、费用记账、指标收集
  ///
  /// [content] LLM 回复文本 (可能为空，当有 tool_calls 时)
  /// [toolCalls] 本次响应中的工具调用列表 (可能为空)
  /// [durationMs] 本次 LLM 调用耗时 (毫秒)
  Future<void> onAfterLlmCall(
    String? content,
    List<ToolCall> toolCalls,
    int durationMs,
  ) async {}

  // ═══════════════════════════════════════════════════════════════
  // 工具调用
  // ═══════════════════════════════════════════════════════════════

  /// 工具调用执行前 — 可审查/拦截
  ///
  /// 返回 true 允许执行, false 拦截 (会返回 HOOK_BLOCKED 错误给 LLM)
  Future<bool> onBeforeToolCall(
    String toolName,
    Map<String, dynamic> args,
  ) async => true;

  /// 工具执行完成后 — 可修改/增强结果
  ///
  /// 返回 null 表示不修改原始 result
  Future<String?> onAfterToolResult(String toolName, String result) async =>
      null;

  // ═══════════════════════════════════════════════════════════════
  // 完成与错误
  // ═══════════════════════════════════════════════════════════════

  /// Agent 最终回复完成后 — 可触发后处理
  ///
  /// [content] 最终回复文本
  /// [toolCalls] 本轮使用过的工具列表
  Future<void> onAgentDone(String content, List<ToolCall> toolCalls) async {}

  /// 出错时 — 可自定义恢复策略
  ///
  /// 返回 true = 应该重试, false = 中止
  Future<bool> onError(String error) async => false;
}

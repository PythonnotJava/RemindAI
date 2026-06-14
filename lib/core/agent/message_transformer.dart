/// 消息变换器抽象接口
///
/// 在消息列表发送给 LLM 之前，对其进行可插拔的变换处理。
/// 多个变换器按注册顺序形成管线：
///
/// ```
/// messages → [Transformer1] → [Transformer2] → ... → 发给 LLM
/// ```
///
/// 典型用途：
/// - 滑动窗口：只保留最近 N 轮 + 系统提示
/// - 摘要压缩：超长时调 LLM 压缩历史
/// - 脱敏过滤：发送前替换敏感字段
/// - Token 预算控制：按 token 数裁剪
///
/// 所有变换器接收的是消息列表的副本，不应修改原始列表。
abstract class MessageTransformer {
  /// 变换器名称 (用于日志/调试)
  String get name;

  /// 对消息列表执行变换
  ///
  /// [messages] 当前消息列表的副本（可安全修改）
  /// 返回变换后的消息列表
  ///
  /// 注意：
  /// - 第一条 system 消息通常应保留
  /// - 返回的列表会传给下一个变换器或直接发给 LLM
  Future<List<Map<String, dynamic>>> transform(
    List<Map<String, dynamic>> messages,
  );

  /// 是否应该激活此变换器
  ///
  /// 由 MessagePipeline 在每次调用前检查。
  /// 默认始终激活，子类可按条件跳过（如消息数量不够时跳过压缩）。
  bool shouldActivate(List<Map<String, dynamic>> messages) => true;
}

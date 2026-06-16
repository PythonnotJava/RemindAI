/// 工具执行中间件抽象接口
///
/// 中间件按注册顺序形成链式调用:
/// request → Middleware1 → Middleware2 → ... → 实际执行器 → response
///
/// 每个中间件可以:
/// - 在执行前修改参数
/// - 决定是否调用 next (短路)
/// - 在执行后修改结果
/// - 记录日志/计时/缓存
abstract class ToolMiddleware {
  /// 处理工具调用
  ///
  /// [toolName] 工具名
  /// [args] 调用参数
  /// [next] 调用链的下一层 (最终是实际执行器)
  ///
  /// 必须调用 next 才会继续往下走,不调用即短路。
  Future<String> handle(
    String toolName,
    Map<String, dynamic> args,
    Future<String> Function(String toolName, Map<String, dynamic> args) next,
  );
}

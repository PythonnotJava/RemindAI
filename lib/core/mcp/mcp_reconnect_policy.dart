import 'dart:math' as math;

/// MCP 断线自动重连的策略（纯计算，无 IO/Flutter 依赖，便于单测）。
///
/// 背景：MCP server 大多是**外部进程**（stdio 子进程、本地拉起的 SSE/HTTP 服务、
/// 远程网关）。进程崩溃、网关重启、网络抖动都会让连接静默消失。以前只能靠用户
/// 手动点"重连"，现在按指数退避自动重试有限次数：
///
/// - 次数有限：避免对一个彻底挂掉的服务无限刷连接（既浪费 CPU，
///   也会让日志/UI 一直抖动）；
/// - 间隔指数增长：2s → 4s → 8s → 16s → 32s（上限 [maxDelay]），
///   给对端留出恢复时间，也避免被网关当成攻击；
/// - 到上限后停在 error 态，只需要用户手动点一次重连。
class McpReconnectPolicy {
  /// 最多自动重连几次（不含首次连接）。
  final int maxAttempts;

  /// 第一次重连前的等待时间，之后每次翻倍。
  final Duration baseDelay;

  /// 单次等待时间上限。
  final Duration maxDelay;

  const McpReconnectPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
  });

  /// 第 [attempt] 次重连（1-based）之前应等待多久。
  ///
  /// attempt <= 0 返回 [Duration.zero]（表示不需要等待）。
  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    // 2^(attempt-1) 倍，注意 attempt 很大时 pow 会溢出，先夹指数。
    final exponent = math.min(attempt - 1, 20);
    final raw = baseDelay.inMilliseconds * math.pow(2, exponent);
    final capped = math.min(
      raw.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: capped.toInt());
  }

  /// 是否还应该继续重连（[attempt] 为"将要进行的第几次"，1-based）。
  bool shouldRetry(int attempt) => attempt >= 1 && attempt <= maxAttempts;
}

import '../../logger/app_logger.dart';
import '../tool_middleware.dart';

/// 日志中间件 — 记录每次工具调用的来源和耗时
class LoggingMiddleware extends ToolMiddleware {
  /// toolName → 来源描述 (如 "元技能:ToolShell", "MCP:xxx")
  final Map<String, String> sourceMapping;

  LoggingMiddleware({this.sourceMapping = const {}});

  @override
  Future<String> handle(
    String toolName,
    Map<String, dynamic> args,
    Future<String> Function(String, Map<String, dynamic>) next,
  ) async {
    final source = sourceMapping[toolName] ?? '未知';
    AppLogger.instance.log('[ToolCall] $toolName \u2190 $source');
    // 技能/MCP 来源的调用额外 print 到终端，便于诊断"技能是否真被调用"
    if (source.startsWith('技能:') || source.startsWith('MCP:')) {
      print('[ToolCall] ▶ 调用 $toolName ← $source');
    }

    final stopwatch = Stopwatch()..start();
    final result = await next(toolName, args);
    stopwatch.stop();

    // 简要日志: 工具名 + 耗时 + 成功/失败
    final isError = result.contains('"status":"error"');
    AppLogger.instance.log(
      '[ToolCall] $toolName ${isError ? "✗" : "✓"} (${stopwatch.elapsedMilliseconds}ms)',
    );
    if (source.startsWith('技能:') || source.startsWith('MCP:')) {
      print(
        '[ToolCall] ${isError ? "✗ 失败" : "✓ 完成"} $toolName ($source, ${stopwatch.elapsedMilliseconds}ms)',
      );
    }

    return result;
  }
}

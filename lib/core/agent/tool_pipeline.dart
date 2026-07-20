import 'dart:convert';

import '../mcp/mcp_client.dart';
import '../toolshell/executor.dart';
import 'tool_middleware.dart';

/// 自定义工具处理器类型
typedef CustomToolHandler = Future<String> Function(Map<String, dynamic> args);

/// 工具执行管线 — 替代 CombinedExecutor
///
/// 职责:
/// 1. 维护中间件链
/// 2. 路由工具调用 (Custom → MCP → ToolShell)
/// 3. 提供统一的 run() 入口
class ToolPipeline {
  final Executor _executor;
  final List<ToolMiddleware> _middlewares;

  /// MCP 客户端映射
  final Map<String, McpClient> _mcpClients;

  /// toolName → serverId 映射
  final Map<String, String> _mcpToolMapping;

  /// 自定义工具处理器 (如搜索工具)
  final Map<String, CustomToolHandler> _customHandlers;

  ToolPipeline({
    required this._executor,
    this._middlewares = const [],
    this._mcpClients = const {},
    Map<String, List<Map<String, dynamic>>> mcpToolsCache = const {},
    this._customHandlers = const {},
  }) : _mcpToolMapping = _buildMapping(mcpToolsCache);

  static Map<String, String> _buildMapping(
    Map<String, List<Map<String, dynamic>>> cache,
  ) {
    final mapping = <String, String>{};
    for (final entry in cache.entries) {
      for (final tool in entry.value) {
        final fn = tool['function'] as Map<String, dynamic>?;
        final name = fn?['name'] as String?;
        if (name != null) mapping[name] = entry.key;
      }
    }
    return mapping;
  }

  /// 执行工具调用 — 经过中间件链后路由到实际执行器
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    // 构建中间件调用链 (从后往前包裹)
    Future<String> Function(String, Map<String, dynamic>) chain = _route;
    for (var i = _middlewares.length - 1; i >= 0; i--) {
      final mw = _middlewares[i];
      final nextFn = chain;
      chain = (name, a) => mw.handle(name, a, nextFn);
    }
    return chain(toolName, args);
  }

  /// 最终路由: run_parallel → Custom → MCP → ToolShell
  Future<String> _route(String toolName, Map<String, dynamic> args) async {
    // 层1「代码执行并行」元工具: 单次决策内并行跑多个互不依赖的子调用。
    // 特判放在 _route 而非 run()，使其自身仍经过外层中间件(日志)一次;
    // 内部每个子调用再各自递归调用 run()，从而重新走满整条中间件链
    // (日志逐条记录、权限判断逐条生效)。
    if (toolName == 'toolshell_run_parallel') {
      return _runParallel(args);
    }

    // 自定义工具 (搜索等)
    final customHandler = _customHandlers[toolName];
    if (customHandler != null) {
      return customHandler(args);
    }

    // MCP 工具
    final serverId = _mcpToolMapping[toolName];
    if (serverId != null) {
      final client = _mcpClients[serverId];
      if (client != null && client.isConnected) {
        try {
          // 参数名自动修正：修复 Agent 常见的参数名混淆问题
          final correctedArgs = _correctMcpArgs(toolName, args);
          final result = await client.callTool(toolName, correctedArgs);
          return jsonEncode({'status': 'ok', 'content': result});
        } catch (e) {
          return jsonEncode({
            'status': 'error',
            'code': 'MCP_ERROR',
            'detail': e.toString(),
          });
        }
      }
      return jsonEncode({
        'status': 'error',
        'code': 'MCP_DISCONNECTED',
        'detail': 'MCP 服务器未连接: $serverId',
      });
    }

    // ToolShell 内置工具
    return _executor.run(toolName, args);
  }

  /// 单次决策内的多个子调用一起并行发起，互不依赖时用它换掉逐个串行等待。
  ///
  /// 入参: `{"calls": [{"tool": "toolshell_read", "args": {...}}, ...]}`
  ///
  /// 安全设计(经讨论确定的兜底规则):
  /// - 是否"可并行"由 LLM 自行判断依赖关系，框架不猜测调用意图。
  /// - 框架只做资源冲突的安全兜底: 任意子调用命中
  ///   [kApprovalRequiredTools](写/删/执行/跑代码)或再次嵌套
  ///   `toolshell_run_parallel`，直接拒绝整批，要求改为逐个串行调用。
  ///   这不仅是权限确认弹窗的 UX 问题——并发写同一文件、并发在同一
  ///   cwd 跑命令本身就有资源竞态风险，所以在 normal/auto 模式下
  ///   都一律拒绝，而不仅是 normal 模式才拦。
  /// - 每个子调用通过 `run()` 递归发起，因此仍会完整走一遍中间件链
  ///   (日志逐条记录)，只是本层已提前排除了需要权限确认的工具。
  Future<String> _runParallel(Map<String, dynamic> args) async {
    const maxCalls = 8;

    final rawCalls = args['calls'];
    if (rawCalls is! List || rawCalls.isEmpty) {
      return jsonEncode({
        'status': 'error',
        'code': 'INVALID_ARGS',
        'detail': 'calls 必须是非空数组，形如 [{"tool":"toolshell_read","args":{...}}]',
      });
    }
    if (rawCalls.length > maxCalls) {
      return jsonEncode({
        'status': 'error',
        'code': 'TOO_MANY_CALLS',
        'detail': '并行调用数(${rawCalls.length})超过上限 $maxCalls，请分批调用',
      });
    }

    final calls = <_ParallelCall>[];
    for (var i = 0; i < rawCalls.length; i++) {
      final item = rawCalls[i];
      if (item is! Map) {
        return jsonEncode({
          'status': 'error',
          'code': 'INVALID_ARGS',
          'detail': 'calls[$i] 必须是对象，但收到: ${item.runtimeType}',
        });
      }
      final tool = item['tool'];
      if (tool is! String || tool.isEmpty) {
        return jsonEncode({
          'status': 'error',
          'code': 'INVALID_ARGS',
          'detail': 'calls[$i] 缺少非空的 tool 字段。收到的 item: $item',
        });
      }
      final rawArgs = item['args'];
      final callArgs = rawArgs is Map
          ? rawArgs.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      // 警告：如果 args 字段缺失或不是 Map，会使用空对象，可能导致子工具缺少必需参数
      if (rawArgs == null) {
        print('[并行调用警告] calls[$i].tool=$tool: args 字段缺失，将使用空对象 {}');
      } else if (rawArgs is! Map) {
        print(
          '[并行调用警告] calls[$i].tool=$tool: args 不是对象类型(${rawArgs.runtimeType})，将使用空对象 {}',
        );
      }

      calls.add(_ParallelCall(tool: tool, args: callArgs));
    }

    // 资源冲突安全兜底：写/删/执行/跑代码/嵌套并行 一律拒绝批量并行
    final blocked = <String>{
      for (final c in calls)
        if (c.tool == 'toolshell_run_parallel' ||
            kApprovalRequiredTools.contains(c.tool))
          c.tool,
    };
    if (blocked.isNotEmpty) {
      return jsonEncode({
        'status': 'error',
        'code': 'PARALLEL_NOT_ALLOWED',
        'detail':
            '以下工具不允许出现在 toolshell_run_parallel 的批次中（涉及写/删/执行'
            '或嵌套并行，存在资源竞态/需人工确认风险): ${blocked.join(", ")}。'
            '请改为逐个串行调用这些工具。',
      });
    }

    final results = await Future.wait(
      calls.map((c) async {
        try {
          final raw = await run(c.tool, c.args); // 递归走完整中间件链
          return {
            'tool': c.tool,
            'args': c.args,
            'result': _tryDecodeJson(raw),
          };
        } catch (e) {
          return {'tool': c.tool, 'args': c.args, 'error': e.toString()};
        }
      }),
    );

    return jsonEncode({
      'status': 'ok',
      'count': results.length,
      'results': results,
    });
  }

  /// 子调用返回的是 JSON 字符串，尝试解成结构化对象方便汇总展示；
  /// 解析失败(非 JSON 的自定义/MCP 结果)则原样作为字符串保留。
  dynamic _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// MCP 工具参数名自动修正
  ///
  /// Agent 经常混淆不同工具的参数名。此方法检测并修正常见的参数名错误，
  /// 避免工具调用失败并返回难以理解的错误信息。
  Map<String, dynamic> _correctMcpArgs(
    String toolName,
    Map<String, dynamic> args,
  ) {
    // mcp__agent-memory__memory: append action 需要 "text" 参数，不是 "content"
    if (toolName == 'mcp__agent-memory__memory') {
      final action = args['action'];
      if (action == 'append' && args.containsKey('content') && !args.containsKey('text')) {
        final corrected = Map<String, dynamic>.from(args);
        corrected['text'] = corrected.remove('content');
        print('[MCP] 自动修正参数: $toolName.content → text');
        return corrected;
      }
    }

    // 可以在此添加更多工具的参数修正规则

    return args;
  }
}

/// [ToolPipeline._runParallel] 内部使用的单个子调用描述
class _ParallelCall {
  final String tool;
  final Map<String, dynamic> args;
  const _ParallelCall({required this.tool, required this.args});
}

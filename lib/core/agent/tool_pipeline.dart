import 'dart:convert';

import '../mcp/mcp_client.dart';
import '../mcp/mcp_tool_names.dart';
import '../memory/project_config.dart';
import '../toolshell/budget.dart';
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

  /// 暴露名 → MCP 调用目标（serverId + 原始工具名）
  ///
  /// 由 [McpToolRoute] 承载：暴露名可能被命名空间改写（`mcp__<serverId>__<name>`），
  /// 调用 MCP 服务器时必须还原成原始工具名，否则同名工具会打错服务器。
  final Map<String, McpToolRoute> _mcpRoutes;

  /// 自定义工具处理器 (如搜索工具)
  final Map<String, CustomToolHandler> _customHandlers;

  /// 工具级进展追踪器（可选）
  ///
  /// 记录每次真实执行的 (工具名, 参数, 结果哈希)，用于判定"空转/无进展"。
  /// 放在管线的唯一出口上，因此 MCP、自定义工具、内置工具、以及
  /// toolshell_run_parallel 的每个子调用都会被记到同一份证据里。
  final ToolProgressTracker? progressTracker;

  ToolPipeline({
    required this._executor,
    this._middlewares = const [],
    this._mcpClients = const {},
    Map<String, List<Map<String, dynamic>>> mcpToolsCache = const {},
    List<McpToolRoute> mcpToolRoutes = const [],
    this._customHandlers = const {},
    this.progressTracker,
  }) : _mcpRoutes = _buildRoutes(mcpToolsCache, mcpToolRoutes);

  /// 组装 MCP 路由表。
  ///
  /// 优先使用调用方传入的 [routes]（来自 McpConnectionsNotifier，已按命名空间
  /// 规则算好暴露名）；只传了 [cache] 的老调用点，则退化为"原始名 → 所属服务器"，
  /// 保持既有行为（同名歧义只能靠后来的覆盖，属于兼容路径）。
  static Map<String, McpToolRoute> _buildRoutes(
    Map<String, List<Map<String, dynamic>>> cache,
    List<McpToolRoute> routes,
  ) {
    if (routes.isNotEmpty) {
      return {for (final r in routes) r.exposedName: r};
    }
    final mapping = <String, McpToolRoute>{};
    for (final entry in cache.entries) {
      for (final tool in entry.value) {
        final name = mcpToolDefName(tool);
        if (name == null) continue;
        mapping[name] = McpToolRoute(
          exposedName: name,
          serverId: entry.key,
          toolName: name,
        );
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
    final result = await chain(toolName, args);
    // 进展追踪的唯一落点：只看最终结果，不看中间件细节。
    progressTracker?.record(toolName, args, result);
    return result;
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
    final mcpRoute = _mcpRoutes[toolName];
    if (mcpRoute != null) {
      final client = _mcpClients[mcpRoute.serverId];
      if (client != null && client.isConnected) {
        try {
          // 参数名自动修正：修复 Agent 常见的参数名混淆问题
          // （按原始工具名判断，暴露名可能被加了命名空间前缀）
          final correctedArgs = _correctMcpArgs(mcpRoute.toolName, args);
          // 关键：调用时用原始工具名，不能用暴露名
          final result = await client.callTool(
            mcpRoute.toolName,
            correctedArgs,
          );
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
        'detail': 'MCP 服务器未连接: ${mcpRoute.serverId}',
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
  /// - 框架只做资源冲突的安全兜底，且**不再整批拒绝**（旧实现只要批次里出现
  ///   写/删/执行就全拒，太粗：3 个读 + 1 个 `adb devices` 明明可以一起跑）：
  ///   1. normal 模式下需要用户确认的工具 → 串行（一次一个弹窗）；
  ///   2. 目标重叠的子调用（同路径的读/写/删、同一条命令、同一段代码）→ 串行，
  ///      并保持它们在批次里的原始顺序（避免"读到的还是写之前的内容"）；
  ///   3. 其余全部并发。
  /// - 只有嵌套 `toolshell_run_parallel` 仍然直接拒绝（会放大并发数、失去预算约束）。
  /// - 每个子调用通过 `run()` 递归发起，因此仍会完整走一遍中间件链（日志逐条记录）。
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

    // ─── 资源冲突检测：只允许操作不同目标的并行 ───
    // 策略：
    // 1. 仍然禁止嵌套并行（toolshell_run_parallel）
    // 2. 检测写/删/执行操作的目标冲突：
    //    - 写/删：检查文件路径是否重复
    //    - 执行：检查命令是否相同
    // 3. 如果操作不同目标 → 允许并行 ✅
    // 4. 如果操作相同目标 → 拒绝并行 ❌

    // 禁止嵌套并行
    if (calls.any((c) => c.tool == 'toolshell_run_parallel')) {
      return jsonEncode({
        'status': 'error',
        'code': 'PARALLEL_NOT_ALLOWED',
        'detail': '不允许嵌套调用 toolshell_run_parallel',
      });
    }

    // ─── 执行编排：能并发的并发，有冲突/需确认的自动串行 ───
    //
    // 旧实现是"批次里只要出现写/删/执行就整批拒绝"，太粗：
    // 3 个读 + 1 个 `adb devices` 明明可以一起跑。现在改成自动分流，
    // 不再整批失败：
    // 1. normal 模式下需要确认的调用串行（一次一个弹窗，避免并发弹窗）；
    // 2. 目标重叠的调用串行（同路径的读/写/删、同一条命令、同一段代码），
    //    并保持原始顺序，避免"读到的还是写之前的内容"；
    // 3. 其余全部并发。
    final autoMode = _executor.permissionMode == PermissionMode.auto;
    final serialIndexes = <int>{};

    if (!autoMode) {
      for (var i = 0; i < calls.length; i++) {
        if (kApprovalRequiredTools.contains(calls[i].tool)) {
          serialIndexes.add(i);
        }
      }
    }

    final byTarget = <String, List<int>>{};
    for (var i = 0; i < calls.length; i++) {
      final key = _targetKey(calls[i]);
      if (key == null) continue;
      byTarget.putIfAbsent(key, () => <int>[]).add(i);
    }
    for (final group in byTarget.values) {
      if (group.length > 1) serialIndexes.addAll(group);
    }

    final results = List<Map<String, dynamic>?>.filled(calls.length, null);

    Future<Map<String, dynamic>> execute(int index) async {
      final c = calls[index];
      try {
        final raw = await run(c.tool, c.args); // 递归走完整中间件链
        return {'tool': c.tool, 'args': c.args, 'result': _tryDecodeJson(raw)};
      } catch (e) {
        return {'tool': c.tool, 'args': c.args, 'error': e.toString()};
      }
    }

    final parallelIndexes = <int>[
      for (var i = 0; i < calls.length; i++)
        if (!serialIndexes.contains(i)) i,
    ];
    final serializedIndexes = <int>[
      for (var i = 0; i < calls.length; i++)
        if (serialIndexes.contains(i)) i,
    ];

    if (parallelIndexes.isNotEmpty) {
      final done = await Future.wait(parallelIndexes.map(execute));
      for (var k = 0; k < parallelIndexes.length; k++) {
        results[parallelIndexes[k]] = done[k];
      }
    }
    for (final index in serializedIndexes) {
      results[index] = await execute(index);
    }

    return jsonEncode({
      'status': 'ok',
      'count': calls.length,
      'parallel_count': parallelIndexes.length,
      'serial_count': serializedIndexes.length,
      if (serializedIndexes.isNotEmpty)
        'serialized': serializedIndexes.map((i) => calls[i].tool).toList(),
      'results': results,
    });
  }

  /// 资源键：同一键的子调用会被串行执行。
  ///
  /// 覆盖"会互相影响"的目标：同一文件的读/写/删、同一条命令、同一段代码。
  /// 只读且目标不同的调用（读 A、读 B、搜 C）键不同，仍然并发。
  String? _targetKey(_ParallelCall call) {
    final path = call.args['path'];
    final command = call.args['command'];
    final code = call.args['code'];

    switch (call.tool) {
      case 'toolshell_read':
      case 'toolshell_write':
      case 'toolshell_delete':
      case 'office_word_read':
      case 'office_excel_read':
      case 'office_word_file':
      case 'office_excel_file':
        if (path is String && path.isNotEmpty) return 'path:$path';
        return null;
      case 'toolshell_exec':
      case 'toolshell_exec_background':
        if (command is String && command.isNotEmpty) return 'exec:$command';
        return null;
      case 'toolshell_run_python':
        if (code is String && code.isNotEmpty) return 'py:$code';
        return null;
      case 'toolshell_run_js':
        if (code is String && code.isNotEmpty) return 'js:$code';
        return null;
      default:
        return null;
    }
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
      if (action == 'append' &&
          args.containsKey('content') &&
          !args.containsKey('text')) {
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

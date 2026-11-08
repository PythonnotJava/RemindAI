import '../tools/builtin_tool_names.dart';

/// 一个 MCP 工具的「对外暴露名 → 真实调用目标」映射。
///
/// MCP 服务器各自命名工具，两台服务器完全可能都提供 `search`；
/// 内置工具里也有 `toolshell_search` 这类名字。以前的做法是"名字直接拼进
/// 工具列表、调用时再按名字反查服务器"，同名就会静默互相覆盖（后连上的赢），
/// 模型调用时到底打到哪台服务器完全取决于连接顺序。
///
/// 现在统一由 [buildMcpToolRoutes] 计算暴露名：
/// - 没有冲突 → 沿用原名（保持与历史对话/用户习惯兼容）；
/// - 有冲突（与内置工具同名，或多台服务器同名）→ 改用
///   `mcp__<serverId>__<toolName>` 形式做命名空间隔离。
class McpToolRoute {
  /// 暴露给 LLM 的工具名（写进 tools 列表、模型回来的 tool_calls 用它）。
  final String exposedName;

  /// 真实所属的 MCP 服务器 id。
  final String serverId;

  /// 调用 MCP 服务器时使用的原始工具名（`tools/call` 的 name 字段）。
  final String toolName;

  /// 是否做了命名空间改写。
  final bool namespaced;

  const McpToolRoute({
    required this.exposedName,
    required this.serverId,
    required this.toolName,
    this.namespaced = false,
  });

  @override
  String toString() =>
      'McpToolRoute($exposedName -> $serverId/$toolName'
      '${namespaced ? ', namespaced' : ''})';
}

/// 命名空间前缀：`mcp__<serverId>__<toolName>`。
const String kMcpToolNamespacePrefix = 'mcp__';

/// 取工具定义里的函数名（兼容 OpenAI 嵌套格式）。
///
/// 与 [toolDefName] 同源，保留该具名函数是为了让 MCP 侧的调用点读起来更明确。
String? mcpToolDefName(Map<String, dynamic> def) => toolDefName(def);

/// 复制一份工具定义并把函数名改成 [newName]（不修改原对象，缓存可复用）。
Map<String, dynamic> renameMcpToolDef(
  Map<String, dynamic> def,
  String newName,
) {
  final fn = def['function'];
  if (fn is! Map) return def;
  return <String, dynamic>{
    ...def,
    'function': <String, dynamic>{...fn.cast<String, dynamic>(), 'name': newName},
  };
}

/// 计算一批 MCP 工具的暴露名。
///
/// [cache] 是 serverId → 工具定义列表。调用方应只传入"当前已连接"的服务器
/// （见 McpConnectionsNotifier.getConnectedToolRoutes），否则会给未连接的
/// 服务器也占掉名字。
///
/// 冲突判定分两轮：
/// 1. 先统计每个原始名出现的次数（跨服务器），以及是否与内置工具同名；
/// 2. 再逐条决定：次数为 1 且不与内置冲突 → 原名；否则 → 命名空间形式。
///
/// 顺序稳定：按 [cache] 的迭代顺序输出，保证同一份状态每次算出的结果一致
/// （否则工具列表在每轮构建 AgentContext 时都可能变，破坏 prompt cache）。
List<McpToolRoute> buildMcpToolRoutes(
  Map<String, List<Map<String, dynamic>>> cache, {
  Set<String> reserved = const <String>{},
}) {
  final counts = <String, int>{};
  for (final tools in cache.values) {
    for (final def in tools) {
      final name = mcpToolDefName(def);
      if (name == null) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }

  final routes = <McpToolRoute>[];
  final used = <String>{};
  for (final entry in cache.entries) {
    final serverId = entry.key;
    for (final def in entry.value) {
      final name = mcpToolDefName(def);
      if (name == null) continue;

      final collides =
          (counts[name] ?? 0) > 1 ||
          reserved.contains(name) ||
          isKnownBuiltinTool(name);

      var exposed = name;
      var namespaced = false;
      if (collides) {
        exposed = _namespacedName(serverId, name);
        namespaced = true;
      }
      // 极端情况：两个 serverId 归一化后相同，或原本就有工具叫这个名字。
      if (used.contains(exposed)) {
        exposed = '${_namespacedName(serverId, name)}__${used.length}';
        namespaced = true;
      }
      used.add(exposed);

      routes.add(
        McpToolRoute(
          exposedName: exposed,
          serverId: serverId,
          toolName: name,
          namespaced: namespaced,
        ),
      );
    }
  }
  return routes;
}

/// serverId 里可能有 uuid 之外的字符，做一次轻量归一化，保留可读性。
String _namespacedName(String serverId, String toolName) {
  final safeServer = serverId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return '$kMcpToolNamespacePrefix${safeServer}__$toolName';
}

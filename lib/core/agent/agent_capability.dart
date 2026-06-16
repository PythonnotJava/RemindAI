import 'agent_hook.dart';
import 'tool_pipeline.dart';

/// 可插拔能力接口 — 统一 Search / RAG / Sandbox 等扩展能力的注册协议
///
/// 每个 Capability 实现声明自己提供的：
/// - 工具定义 (让 LLM 可以调用)
/// - 工具执行器 (实际处理调用)
/// - 生命周期 Hook (如 Memory 的召回/存储)
/// - 系统提示词扩展 (可选的额外指令)
///
/// AgentContextBuilder 在构建时统一收集所有活跃 Capability，
/// 一次性注入到 AgentContext 中，无需为每种新能力修改 builder 代码。
abstract class AgentCapability {
  /// 唯一标识符 (用于日志、source mapping 等)
  String get id;

  /// 显示名称 (用于 UI 和 source mapping)
  String get displayName;

  /// 当前是否激活 (UI 已开启 + 配置完备)
  ///
  /// 返回 false 时，AgentContextBuilder 会跳过该 Capability 的所有注册。
  bool get isActive;

  /// 返回要注册给 LLM 的工具定义列表
  ///
  /// 格式: OpenAI function tool JSON
  /// 返回空列表表示不注册任何工具 (纯 Hook 型能力如 Memory)。
  List<Map<String, dynamic>> get toolDefinitions;

  /// 返回工具执行器映射
  ///
  /// key = toolName (必须与 toolDefinitions 中的 function.name 一致)
  /// value = 异步执行函数
  /// 返回空 map 表示不提供自定义执行器。
  Map<String, CustomToolHandler> get toolHandlers;

  /// 返回生命周期 Hook 列表 (可选)
  ///
  /// 用于需要拦截 Agent 生命周期的能力 (如 Memory 的召回/存储)。
  /// 返回空列表表示不需要 Hook。
  List<AgentHook> get hooks => const [];

  /// 系统提示词扩展 (可选)
  ///
  /// 非空时会被追加到系统提示词末尾，用于给 LLM 额外指令。
  /// 例如搜索能力可以加: "当需要最新信息时使用 web_search 工具"
  String? get systemPromptExtension => null;

  /// source mapping (用于日志/UI 标记工具来源)
  ///
  /// 默认实现: 为每个 toolDefinition 生成 "能力:displayName" 的映射。
  /// 子类可 override 自定义。
  Map<String, String> get sourceMapping {
    final map = <String, String>{};
    for (final tool in toolDefinitions) {
      final fn = tool['function'] as Map<String, dynamic>?;
      final name = fn?['name'] as String?;
      if (name != null) {
        map[name] = displayName;
      }
    }
    return map;
  }
}

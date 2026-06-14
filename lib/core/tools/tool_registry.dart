import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tool_plugin.dart';
import 'tool_config.dart';

/// 工具注册表 — 管理所有已注册的工具实例和配置
class ToolRegistry {
  final List<ToolPlugin> _tools = [];
  final Map<String, ToolConfig> _configs = {};

  List<ToolPlugin> get tools => List.unmodifiable(_tools);

  /// 注册一个工具
  void register(ToolPlugin tool) {
    if (_tools.any((t) => t.id == tool.id)) return;
    _tools.add(tool);
  }

  /// 获取工具
  ToolPlugin? getById(String id) {
    try {
      return _tools.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 按分类分组
  Map<String, List<ToolPlugin>> get grouped {
    final map = <String, List<ToolPlugin>>{};
    for (final tool in _tools) {
      map.putIfAbsent(tool.category, () => []).add(tool);
    }
    return map;
  }

  /// 按国际化分类分组（需要 BuildContext）
  Map<String, List<ToolPlugin>> groupedLocalized(BuildContext context) {
    final map = <String, List<ToolPlugin>>{};
    for (final tool in _tools) {
      map.putIfAbsent(tool.localizedCategory(context), () => []).add(tool);
    }
    return map;
  }

  /// 获取配置（内存缓存）
  ToolConfig getConfig(String toolId) =>
      _configs[toolId] ?? ToolConfig(toolId: toolId);

  /// 加载工具配置
  Future<ToolConfig> loadConfig(String toolId) async {
    if (_configs.containsKey(toolId)) return _configs[toolId]!;
    final config = await ToolConfig.load(toolId);
    _configs[toolId] = config;
    return config;
  }

  /// 更新并保存永久配置
  Future<void> saveConfig(ToolConfig config) async {
    _configs[config.toolId] = config;
    await config.save();
  }

  /// 设置临时配置（不持久化）
  void setTempConfig(String toolId, String key, dynamic value) {
    final existing = _configs[toolId] ?? ToolConfig(toolId: toolId);
    _configs[toolId] = existing.setTemporary(key, value);
  }

  /// 清除临时配置
  void clearTempConfig(String toolId) {
    final existing = _configs[toolId];
    if (existing != null) {
      _configs[toolId] = existing.clearTemporary();
    }
  }

  /// 初始化所有已注册工具
  Future<void> initAll() async {
    for (final tool in _tools) {
      final config = await loadConfig(tool.id);
      await tool.onInit(config);
    }
  }

  /// 销毁所有工具
  Future<void> disposeAll() async {
    for (final tool in _tools) {
      await tool.onDispose();
    }
  }
}

/// 全局 ToolRegistry provider
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  throw UnimplementedError(
    'toolRegistryProvider must be overridden at app startup',
  );
});

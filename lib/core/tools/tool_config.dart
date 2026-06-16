import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 工具配置 — 分永久和临时两层
class ToolConfig {
  final String toolId;
  final Map<String, dynamic> permanent; // 持久化的配置
  final Map<String, dynamic> temporary; // 会话内临时覆盖

  ToolConfig({
    required this.toolId,
    this.permanent = const {},
    this.temporary = const {},
  });

  /// 获取配置值（临时优先于永久）
  T? get<T>(String key) {
    if (temporary.containsKey(key)) return temporary[key] as T?;
    if (permanent.containsKey(key)) return permanent[key] as T?;
    return null;
  }

  /// 获取配置值，带默认值
  T getOr<T>(String key, T defaultValue) => get<T>(key) ?? defaultValue;

  /// 更新永久配置
  ToolConfig setPermanent(String key, dynamic value) {
    final newPerm = Map<String, dynamic>.from(permanent);
    newPerm[key] = value;
    return ToolConfig(toolId: toolId, permanent: newPerm, temporary: temporary);
  }

  /// 更新临时配置
  ToolConfig setTemporary(String key, dynamic value) {
    final newTemp = Map<String, dynamic>.from(temporary);
    newTemp[key] = value;
    return ToolConfig(toolId: toolId, permanent: permanent, temporary: newTemp);
  }

  /// 清除所有临时配置
  ToolConfig clearTemporary() =>
      ToolConfig(toolId: toolId, permanent: permanent, temporary: const {});

  Map<String, dynamic> toJson() => {'toolId': toolId, 'permanent': permanent};

  factory ToolConfig.fromJson(Map<String, dynamic> json) => ToolConfig(
    toolId: json['toolId'] as String,
    permanent: (json['permanent'] as Map<String, dynamic>?) ?? {},
  );

  /// 配置存储目录
  static Future<Directory> _configDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'tool_configs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 加载某个工具的永久配置
  static Future<ToolConfig> load(String toolId) async {
    try {
      final dir = await _configDir();
      final file = File(p.join(dir.path, '$toolId.json'));
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return ToolConfig.fromJson(json);
      }
    } catch (_) {}
    return ToolConfig(toolId: toolId);
  }

  /// 保存永久配置到磁盘
  Future<void> save() async {
    final dir = await _configDir();
    final file = File(p.join(dir.path, '$toolId.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }
}

/// 配置字段 schema 定义
class ConfigField {
  final String key;
  final String label;
  final ConfigFieldType type;
  final bool required;
  final dynamic defaultValue;
  final List<String>? options; // 用于 select 类型
  final String? hint;

  const ConfigField({
    required this.key,
    required this.label,
    this.type = ConfigFieldType.text,
    this.required = false,
    this.defaultValue,
    this.options,
    this.hint,
  });
}

enum ConfigFieldType {
  text,
  secret, // 密码/key，不明文显示
  url,
  number,
  select,
  toggle,
}

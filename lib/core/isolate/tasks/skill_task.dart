import 'dart:convert';
import 'dart:io';

/// 技能加载任务 — 在 Isolate 中批量解析 SKILL.md 和 tools.json。
///
/// 适用场景:
/// - 应用启动时批量加载 L1/L2/L3 技能
/// - 技能 ZIP 导入时的解析与校验

/// 技能文件信息（可跨 Isolate 传递）
class SkillFileInfo {
  final String dirPath;
  final String? skillMdContent;
  final String? toolsJsonContent;
  final String? metaJsonContent;

  SkillFileInfo({
    required this.dirPath,
    this.skillMdContent,
    this.toolsJsonContent,
    this.metaJsonContent,
  });
}

/// 解析后的技能数据
class ParsedSkill {
  final String dirPath;
  final String name;
  final String description;
  final int toolCount;
  final List<ParsedTool> tools;
  final String? systemPrompt; // SKILL.md 内容
  final Map<String, dynamic>? meta;
  final String? error; // 解析失败时的错误信息

  ParsedSkill({
    required this.dirPath,
    required this.name,
    this.description = '',
    this.toolCount = 0,
    this.tools = const [],
    this.systemPrompt,
    this.meta,
    this.error,
  });
}

/// 解析后的工具定义
class ParsedTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  ParsedTool({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

/// 顶层函数: 解析单个技能目录（可传入 Isolate）
ParsedSkill skillParseTask(SkillFileInfo info) {
  try {
    // 解析 tools.json
    final tools = <ParsedTool>[];
    if (info.toolsJsonContent != null && info.toolsJsonContent!.isNotEmpty) {
      final parsed = _parseToolsJson(info.toolsJsonContent!);
      tools.addAll(parsed);
    }

    // 解析 meta
    Map<String, dynamic>? meta;
    String name = _dirName(info.dirPath);
    String description = '';

    if (info.metaJsonContent != null && info.metaJsonContent!.isNotEmpty) {
      try {
        meta = jsonDecode(info.metaJsonContent!) as Map<String, dynamic>;
        name = meta['name'] as String? ?? name;
        description = meta['description'] as String? ?? '';
      } catch (_) {}
    }

    return ParsedSkill(
      dirPath: info.dirPath,
      name: name,
      description: description,
      toolCount: tools.length,
      tools: tools,
      systemPrompt: info.skillMdContent,
      meta: meta,
    );
  } catch (e) {
    return ParsedSkill(
      dirPath: info.dirPath,
      name: _dirName(info.dirPath),
      error: e.toString(),
    );
  }
}

/// 顶层函数: 批量解析技能（可传入 Isolate）
List<ParsedSkill> skillBatchParseTask(List<SkillFileInfo> infos) {
  return infos.map(skillParseTask).toList();
}

/// 顶层函数: 从文件系统读取并解析技能（用于主 Isolate 预处理）
///
/// 注意: 此函数涉及文件 I/O，不能直接在 worker isolate 中使用。
/// 正确用法是在主 isolate 中读取文件内容，构造 SkillFileInfo，
/// 然后将 SkillFileInfo 传入 worker 做纯计算解析。
Future<SkillFileInfo> readSkillFiles(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    return SkillFileInfo(dirPath: dirPath);
  }

  String? skillMd;
  String? toolsJson;
  String? metaJson;

  final skillMdFile = File('$dirPath/SKILL.md');
  if (await skillMdFile.exists()) {
    skillMd = await skillMdFile.readAsString();
  }

  final toolsJsonFile = File('$dirPath/tools.json');
  if (await toolsJsonFile.exists()) {
    toolsJson = await toolsJsonFile.readAsString();
  }

  final metaFile = File('$dirPath/.skill_meta.json');
  if (await metaFile.exists()) {
    metaJson = await metaFile.readAsString();
  }

  return SkillFileInfo(
    dirPath: dirPath,
    skillMdContent: skillMd,
    toolsJsonContent: toolsJson,
    metaJsonContent: metaJson,
  );
}

// =============================================================================
// 工具 JSON 解析（支持多种格式）
// =============================================================================

List<ParsedTool> _parseToolsJson(String content) {
  final decoded = jsonDecode(content);
  final tools = <ParsedTool>[];

  if (decoded is List) {
    // 格式1: 直接数组 [{name, description, parameters}, ...]
    // 格式2: OpenAI 格式 [{type: "function", function: {name, ...}}, ...]
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final tool = _parseSingleTool(item);
        if (tool != null) tools.add(tool);
      }
    }
  } else if (decoded is Map<String, dynamic>) {
    // 格式3: 包裹对象 {tools: [...]}
    if (decoded.containsKey('tools')) {
      final toolsList = decoded['tools'] as List?;
      if (toolsList != null) {
        for (final item in toolsList) {
          if (item is Map<String, dynamic>) {
            final tool = _parseSingleTool(item);
            if (tool != null) tools.add(tool);
          }
        }
      }
    } else {
      // 格式4: 单个工具对象
      final tool = _parseSingleTool(decoded);
      if (tool != null) tools.add(tool);
    }
  }

  return tools;
}

ParsedTool? _parseSingleTool(Map<String, dynamic> json) {
  // OpenAI function calling 格式
  if (json['type'] == 'function' && json['function'] is Map) {
    final fn = json['function'] as Map<String, dynamic>;
    return ParsedTool(
      name: fn['name'] as String? ?? '',
      description: fn['description'] as String? ?? '',
      parameters: fn['parameters'] as Map<String, dynamic>? ?? {},
    );
  }
  // 扁平格式
  if (json.containsKey('name')) {
    return ParsedTool(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      parameters:
          json['parameters'] as Map<String, dynamic>? ??
          json['input_schema'] as Map<String, dynamic>? ??
          {},
    );
  }
  return null;
}

String _dirName(String path) {
  final sep = path.contains('\\') ? '\\' : '/';
  final parts = path.split(sep);
  return parts.lastWhere((p) => p.isNotEmpty, orElse: () => 'unknown');
}

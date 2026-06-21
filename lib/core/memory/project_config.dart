import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// 项目级配置 — 解析工作目录下的 memory.json
///
/// 决定:
/// - 是否启动嵌入模型 + Qdrant 向量存储
/// - 是否存入/召回长期记忆
/// - 操作权限模式 (normal 需确认 / auto 自动执行)
class ProjectConfig {
  /// 是否启用嵌入模型 + Qdrant
  final bool embeddings;

  /// 是否将重要信息存入长期记忆
  final bool longTermStore;

  /// 对话时是否语义召回长期记忆
  final bool longTermRecall;

  /// 权限模式: normal=写/删/执行操作需确认, auto=自动执行
  final PermissionMode mode;

  const ProjectConfig({
    this.embeddings = false,
    this.longTermStore = false,
    this.longTermRecall = false,
    this.mode = PermissionMode.normal,
  });

  /// 从工作目录加载 memory.json，不存在则返回默认配置
  static Future<ProjectConfig> load(String workspacePath) async {
    final file = File(p.join(workspacePath, 'memory.json'));
    if (!await file.exists()) return const ProjectConfig();

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ProjectConfig(
        embeddings: json['embeddings'] == true,
        longTermStore: json['long_term_store'] == true,
        longTermRecall: json['long_term_recall'] == true,
        mode: json['mode'] == 'auto'
            ? PermissionMode.auto
            : PermissionMode.normal,
      );
    } catch (_) {
      // JSON 解析失败时用默认值
      return const ProjectConfig();
    }
  }

  /// 是否需要 Qdrant (嵌入模型启用时需要)
  bool get needsQdrant => embeddings;
}

/// 权限模式
enum PermissionMode {
  /// 写入/删除/执行操作需要用户确认
  normal,

  /// 所有操作自动执行
  auto,
}

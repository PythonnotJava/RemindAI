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

  ProjectConfig copyWith({
    bool? embeddings,
    bool? longTermStore,
    bool? longTermRecall,
    PermissionMode? mode,
  }) {
    return ProjectConfig(
      embeddings: embeddings ?? this.embeddings,
      longTermStore: longTermStore ?? this.longTermStore,
      longTermRecall: longTermRecall ?? this.longTermRecall,
      mode: mode ?? this.mode,
    );
  }

  Map<String, dynamic> toJson() => {
    'embeddings': embeddings,
    'long_term_store': longTermStore,
    'long_term_recall': longTermRecall,
    'mode': mode == PermissionMode.auto ? 'auto' : 'normal',
  };

  /// 把当前配置写回工作目录下的 memory.json。
  ///
  /// 若文件已存在，会先读出原始内容并只覆盖本类识别的 4 个已知字段，
  /// 尽量保留文件中可能存在的其它自定义字段，不做破坏性覆盖。
  /// 工作目录不存在时会自动创建，保证"纯对话"场景 (默认落在
  /// `.RemindAI/workspace`) 也能持久化开关状态。
  Future<void> save(String workspacePath) async {
    final dir = Directory(workspacePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(workspacePath, 'memory.json'));
    Map<String, dynamic> merged = {};
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final existing = jsonDecode(content);
        if (existing is Map<String, dynamic>) {
          merged = existing;
        }
      } catch (_) {
        // 原文件损坏/非法 JSON，直接用新内容覆盖，不阻塞保存操作
      }
    }

    merged.addAll(toJson());
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(merged),
    );
  }
}

/// 权限模式
enum PermissionMode {
  /// 写入/删除/执行操作需要用户确认
  normal,

  /// 所有操作自动执行
  auto,
}

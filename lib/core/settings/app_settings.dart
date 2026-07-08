import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 嵌入式模型配置 (替代 memory.json)
class EmbeddingConfig {
  final String id; // 唯一标识 (用于多配置区分/选中)
  final String name; // 显示名称
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool useQdrant; // 是否启用 Qdrant 向量检索
  final bool persistToSqlite; // 是否存入 SQLite 作为长期记忆

  const EmbeddingConfig({
    this.id = '',
    this.name = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.useQdrant = false,
    this.persistToSqlite = true,
  });

  bool get isConfigured =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;

  /// 卡片标题: 优先用 name，其次 model，最后占位
  String get displayName {
    if (name.isNotEmpty) return name;
    if (model.isNotEmpty) return model;
    return '未命名模型';
  }

  EmbeddingConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? useQdrant,
    bool? persistToSqlite,
  }) {
    return EmbeddingConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      useQdrant: useQdrant ?? this.useQdrant,
      persistToSqlite: persistToSqlite ?? this.persistToSqlite,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'useQdrant': useQdrant,
    'persistToSqlite': persistToSqlite,
  };

  factory EmbeddingConfig.fromJson(Map<String, dynamic> json) {
    return EmbeddingConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? '',
      useQdrant: json['useQdrant'] as bool? ?? false,
      persistToSqlite: json['persistToSqlite'] as bool? ?? true,
    );
  }
}

class AppSettings {
  /// 当前 .RemindAI 根目录 (main 启动时设置一次，全局可读)。
  /// 所有需要根目录的代码从这里取，不再各自硬编码默认路径。
  static String? _rootDir;

  /// 获取当前根目录。若未初始化则回退到默认路径。
  static Future<String> getRootDir() async {
    if (_rootDir != null && _rootDir!.isNotEmpty) return _rootDir!;
    return await defaultRootDir;
  }

  /// main 启动时从已加载的 settings 中设置根目录 (从 databasePath 推算)。
  static void initRootDir(AppSettings settings) {
    if (settings.databasePath.isNotEmpty) {
      // databasePath = <root>/sqlite/remind_ai.db → root = 上两级
      _rootDir = p.dirname(p.dirname(settings.databasePath));
    }
  }

  final String databasePath;
  final String historyPath;
  final String skillsPath; // 技能存放目录
  final String knowledgeBasePath; // 知识库存放目录 (导入文档副本)
  final String logsPath; // 日志存放目录
  final String pandocPath;
  final String workingDirectory; // 工作目录
  final String themeMode; // 主题模式: system / light / dark
  final String accentColor; // 主题色: 'purple' / 'green' / 'blue' / 'cyan'
  final List<EmbeddingConfig> embeddings; // 多个嵌入式模型配置
  final String selectedEmbeddingId; // 当前选中(默认)的嵌入模型 id
  final String qdrantPath; // 手动指定的 Qdrant 可执行文件路径 (空=自动检测)
  final bool notifyOnBlur; // 失焦时是否发送系统通知 (默认开启)
  final String locale; // 语言: 'system' / 'zh' / 'en'
  final String uiFont; // 界面字体
  final double uiFontSize; // 界面字体大小
  final String chatFont; // 交互字体（对话+多Agent）
  final double chatFontSize; // 交互字体大小
  final String enterAction; // 回车行为: 'send' / 'newline'

  const AppSettings({
    required this.databasePath,
    required this.historyPath,
    required this.skillsPath,
    this.knowledgeBasePath = '',
    required this.logsPath,
    required this.pandocPath,
    this.workingDirectory = '',
    this.themeMode = 'dark',
    this.accentColor = 'purple',
    this.embeddings = const [],
    this.selectedEmbeddingId = '',
    this.qdrantPath = '',
    this.notifyOnBlur = true,
    this.locale = 'system',
    this.uiFont = 'Noto Sans SC',
    this.uiFontSize = 14.0,
    this.chatFont = 'Noto Sans SC',
    this.chatFontSize = 14.0,
    this.enterAction = 'send',
  });

  /// 向后兼容: 返回当前选中的嵌入模型配置。
  /// 无选中或列表为空时返回空配置 (isConfigured == false)。
  EmbeddingConfig get embedding {
    if (embeddings.isEmpty) return const EmbeddingConfig();
    for (final e in embeddings) {
      if (e.id == selectedEmbeddingId) return e;
    }
    // 选中 id 失效则回退到第一个
    return embeddings.first;
  }

  AppSettings copyWith({
    String? databasePath,
    String? historyPath,
    String? skillsPath,
    String? knowledgeBasePath,
    String? logsPath,
    String? pandocPath,
    String? workingDirectory,
    String? themeMode,
    String? accentColor,
    List<EmbeddingConfig>? embeddings,
    String? selectedEmbeddingId,
    String? qdrantPath,
    bool? notifyOnBlur,
    String? locale,
    String? uiFont,
    double? uiFontSize,
    String? chatFont,
    double? chatFontSize,
    String? enterAction,
  }) {
    return AppSettings(
      databasePath: databasePath ?? this.databasePath,
      historyPath: historyPath ?? this.historyPath,
      skillsPath: skillsPath ?? this.skillsPath,
      knowledgeBasePath: knowledgeBasePath ?? this.knowledgeBasePath,
      logsPath: logsPath ?? this.logsPath,
      pandocPath: pandocPath ?? this.pandocPath,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      embeddings: embeddings ?? this.embeddings,
      selectedEmbeddingId: selectedEmbeddingId ?? this.selectedEmbeddingId,
      qdrantPath: qdrantPath ?? this.qdrantPath,
      notifyOnBlur: notifyOnBlur ?? this.notifyOnBlur,
      locale: locale ?? this.locale,
      uiFont: uiFont ?? this.uiFont,
      uiFontSize: uiFontSize ?? this.uiFontSize,
      chatFont: chatFont ?? this.chatFont,
      chatFontSize: chatFontSize ?? this.chatFontSize,
      enterAction: enterAction ?? this.enterAction,
    );
  }

  Map<String, dynamic> toJson() => {
    'databasePath': databasePath,
    'historyPath': historyPath,
    'skillsPath': skillsPath,
    'knowledgeBasePath': knowledgeBasePath,
    'logsPath': logsPath,
    'pandocPath': pandocPath,
    'workingDirectory': workingDirectory,
    'themeMode': themeMode,
    'accentColor': accentColor,
    'embeddings': embeddings.map((e) => e.toJson()).toList(),
    'selectedEmbeddingId': selectedEmbeddingId,
    'qdrantPath': qdrantPath,
    'notifyOnBlur': notifyOnBlur,
    'locale': locale,
    'uiFont': uiFont,
    'uiFontSize': uiFontSize,
    'chatFont': chatFont,
    'chatFontSize': chatFontSize,
    'enterAction': enterAction,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 解析嵌入模型列表，兼容旧版单个 'embedding' 字段
    final List<EmbeddingConfig> embeddings;
    String selectedId = json['selectedEmbeddingId'] as String? ?? '';

    if (json['embeddings'] is List) {
      embeddings = (json['embeddings'] as List)
          .map((e) => EmbeddingConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (json['embedding'] != null) {
      // 旧版迁移: 把单个配置包装成列表，并分配 id
      final legacy = EmbeddingConfig.fromJson(
        json['embedding'] as Map<String, dynamic>,
      );
      if (legacy.isConfigured || legacy.baseUrl.isNotEmpty) {
        final migrated = legacy.copyWith(
          id: 'embedding_legacy',
          name: legacy.name.isEmpty ? legacy.displayName : legacy.name,
        );
        embeddings = [migrated];
        selectedId = migrated.id;
      } else {
        embeddings = const [];
      }
    } else {
      embeddings = const [];
    }

    return AppSettings(
      databasePath: json['databasePath'] as String? ?? '',
      historyPath: json['historyPath'] as String? ?? '',
      skillsPath: json['skillsPath'] as String? ?? '',
      knowledgeBasePath: json['knowledgeBasePath'] as String? ?? '',
      logsPath: json['logsPath'] as String? ?? '',
      pandocPath: json['pandocPath'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String? ?? '',
      themeMode: json['themeMode'] as String? ?? 'dark',
      accentColor: json['accentColor'] as String? ?? 'purple',
      embeddings: embeddings,
      selectedEmbeddingId: selectedId,
      qdrantPath: json['qdrantPath'] as String? ?? '',
      notifyOnBlur: json['notifyOnBlur'] as bool? ?? true,
      locale: json['locale'] as String? ?? 'system',
      uiFont: json['uiFont'] as String? ?? 'Noto Sans SC',
      uiFontSize: (json['uiFontSize'] as num?)?.toDouble() ?? 14.0,
      chatFont: json['chatFont'] as String? ?? 'Noto Sans SC',
      chatFontSize: (json['chatFontSize'] as num?)?.toDouble() ?? 14.0,
      enterAction: json['enterAction'] as String? ?? 'send',
    );
  }

  static Future<String> get settingsFilePath async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'settings.json');
  }

  static Future<AppSettings> load() async {
    final filePath = await settingsFilePath;
    final file = File(filePath);

    final defaults = await _defaults();

    if (!await file.exists()) {
      return defaults;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(json);
      // 用默认值填充空字段
      return AppSettings(
        databasePath: settings.databasePath.isEmpty
            ? defaults.databasePath
            : settings.databasePath,
        historyPath: settings.historyPath.isEmpty
            ? defaults.historyPath
            : settings.historyPath,
        skillsPath: settings.skillsPath.isEmpty
            ? defaults.skillsPath
            : settings.skillsPath,
        knowledgeBasePath: settings.knowledgeBasePath.isEmpty
            ? defaults.knowledgeBasePath
            : settings.knowledgeBasePath,
        logsPath: settings.logsPath.isEmpty
            ? defaults.logsPath
            : settings.logsPath,
        pandocPath: settings.pandocPath.isEmpty
            ? defaults.pandocPath
            : settings.pandocPath,
        workingDirectory: settings.workingDirectory,
        themeMode: settings.themeMode,
        accentColor: settings.accentColor,
        embeddings: settings.embeddings,
        selectedEmbeddingId: settings.selectedEmbeddingId,
        qdrantPath: settings.qdrantPath,
        notifyOnBlur: settings.notifyOnBlur,
        locale: settings.locale,
        uiFont: settings.uiFont,
        uiFontSize: settings.uiFontSize,
        chatFont: settings.chatFont,
        chatFontSize: settings.chatFontSize,
        enterAction: settings.enterAction,
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() async {
    final filePath = await settingsFilePath;
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  /// 默认存储根目录: 用户文档目录下的 .RemindAI
  static Future<String> get defaultRootDir async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, '.RemindAI');
  }

  static Future<AppSettings> _defaults() async {
    final root = await defaultRootDir;
    // DB 放 .RemindAI/sqlite/，历史放 .RemindAI/history/，技能放 .RemindAI/skills/，日志放 .RemindAI/logs/
    final defaultDbPath = p.join(root, 'sqlite', 'remind_ai.db');
    final defaultHistoryPath = p.join(root, 'history');
    final defaultSkillsPath = p.join(root, 'skills');
    final defaultKnowledgeBasePath = p.join(root, 'knowledge_base');
    final defaultLogsPath = p.join(root, 'logs');
    final pandocPath = await _detectPandoc();

    return AppSettings(
      databasePath: defaultDbPath,
      historyPath: defaultHistoryPath,
      skillsPath: defaultSkillsPath,
      knowledgeBasePath: defaultKnowledgeBasePath,
      logsPath: defaultLogsPath,
      pandocPath: pandocPath,
    );
  }

  static Future<String> _detectPandoc() async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'pandoc',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        return output.split('\n').first.trim();
      }
    } catch (_) {}
    return '';
  }
}

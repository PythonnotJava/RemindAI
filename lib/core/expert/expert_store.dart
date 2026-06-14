import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'expert.dart';

/// 专家存储服务 — 管理专家配置的持久化
class ExpertStore {
  ExpertStore._();
  static final ExpertStore instance = ExpertStore._();

  late String _storePath;
  List<Expert> _experts = [];
  bool _initialized = false;

  List<Expert> get experts => List.unmodifiable(_experts);

  Future<void> init() async {
    if (_initialized) return;
    final documentsDir = await getApplicationDocumentsDirectory();
    _storePath = p.join(documentsDir.path, '.RemindAI', 'experts.json');
    await _load();
    _initialized = true;
  }

  /// 按分类分组
  Map<String, List<Expert>> get grouped {
    final map = <String, List<Expert>>{};
    for (final e in _experts) {
      map.putIfAbsent(e.category, () => []).add(e);
    }
    return map;
  }

  /// 获取单个专家
  Expert? getById(String id) {
    try {
      return _experts.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 添加专家
  Future<void> add(Expert expert) async {
    _experts.add(expert);
    await _save();
  }

  /// 更新专家
  Future<void> update(Expert expert) async {
    final idx = _experts.indexWhere((e) => e.id == expert.id);
    if (idx >= 0) {
      _experts[idx] = expert;
      await _save();
    }
  }

  /// 删除专家 (内置专家不可删)
  Future<bool> delete(String id) async {
    final idx = _experts.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    if (_experts[idx].isBuiltin) return false;
    _experts.removeAt(idx);
    await _save();
    return true;
  }

  /// 导出单个专家为 JSON 字符串
  String exportOne(String id) {
    final expert = getById(id);
    if (expert == null) return '';
    return const JsonEncoder.withIndent('  ').convert(expert.toJson());
  }

  /// 从 JSON 字符串导入专家
  Future<Expert?> importOne(String jsonStr) async {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      // 重新生成 ID 避免冲突
      json.remove('id');
      json['isBuiltin'] = false;
      final expert = Expert.fromJson(json);
      await add(expert);
      return expert;
    } catch (_) {
      return null;
    }
  }

  // ─── 内部方法 ─────────────────────────────────────────────

  Future<void> _load() async {
    final file = File(_storePath);
    if (!await file.exists()) {
      // 首次启动: 写入内置专家
      _experts = _builtinExperts();
      await _save();
      return;
    }
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      _experts = list
          .map((e) => Expert.fromJson(e as Map<String, dynamic>))
          .toList();
      // 确保内置专家始终存在
      _ensureBuiltins();
    } catch (_) {
      _experts = _builtinExperts();
      await _save();
    }
  }

  Future<void> _save() async {
    final file = File(_storePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final json = _experts.map((e) => e.toJson()).toList();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  void _ensureBuiltins() {
    final builtins = _builtinExperts();
    for (final builtin in builtins) {
      if (!_experts.any((e) => e.id == builtin.id)) {
        _experts.insert(0, builtin);
      }
    }
  }

  /// 内置专家列表
  static List<Expert> _builtinExperts() => [
    Expert(
      id: 'builtin_ppt',
      name: 'PPT 设计师',
      icon: 'slideshow',
      description: '专业演示文稿的结构规划、内容撰写与视觉设计建议',
      category: '办公',
      isBuiltin: true,
      systemPrompt: '''你是一位资深的演示文稿设计顾问，擅长：
- 根据用户主题进行内容规划和结构设计
- 提供每页幻灯片的标题、要点、视觉布局建议
- 把控整体叙事逻辑和节奏感
- 建议配色方案、字体搭配、图表类型

工作方式：
1. 先了解演示场景（汇报/路演/教学/分享）、受众、时长
2. 输出大纲结构（含每页核心信息）
3. 逐页细化内容和设计建议
4. 如需要，直接生成 Markdown 大纲供导入 PPT 工具

保持简洁有力，避免文字堆砌。每页 PPT 核心观点不超过 3 条。''',
      boundSkills: ['toolshell'],
    ),
    Expert(
      id: 'builtin_data_analyst',
      name: '数据分析师',
      icon: 'analytics',
      description: '数据清洗、统计分析、可视化方案与洞察报告',
      category: '分析',
      isBuiltin: true,
      systemPrompt: '''你是一位专业的数据分析师，擅长：
- 数据清洗与预处理策略
- 统计分析方法选择（描述性/推断性/预测性）
- 可视化方案设计（图表类型选择、维度映射）
- 从数据中提取商业洞察，撰写分析报告

工作方式：
1. 先了解数据来源、格式、分析目标
2. 建议分析路径和所需工具（Python/R/SQL/Excel）
3. 如果有 ToolShell，可直接编写并执行分析代码
4. 输出结论时区分"数据表明"和"推测/建议"

遇到数据质量问题时主动指出，不在脏数据上做结论。''',
      boundSkills: ['toolshell'],
    ),
    Expert(
      id: 'builtin_code_reviewer',
      name: '代码审查员',
      icon: 'code',
      description: '代码质量审查、架构评估、性能与安全分析',
      category: '技术',
      isBuiltin: true,
      systemPrompt: '''你是一位严谨的高级代码审查员，擅长：
- 代码风格与可读性评估
- 架构设计合理性分析
- 潜在 Bug 和边界条件检查
- 性能瓶颈识别
- 安全漏洞发现

工作方式：
1. 逐文件/逐函数审查，按严重程度分级 (Critical/Major/Minor/Suggestion)
2. 每个问题给出：位置、问题描述、修复建议
3. 最后给出总体评价和优先修复建议
4. 对好的设计也给予肯定

语气专业但友善，目标是帮助代码变得更好，不是挑刺。''',
      boundSkills: ['toolshell'],
    ),
    Expert(
      id: 'builtin_pyside6_designer',
      name: 'PySide6 设计师',
      icon: 'desktop_windows',
      description: '基于 PySide6/Qt 设计开箱即用的桌面端工具应用',
      category: '技术',
      isBuiltin: true,
      systemPrompt: '''你是一位精通 PySide6 (Qt for Python) 的桌面应用设计师，擅长：
- 设计开箱即用的小工具应用（文件处理、批量操作、数据转换、系统工具等）
- PySide6 布局系统（QVBoxLayout/QHBoxLayout/QGridLayout/QSplitter）
- 常用组件运用（QTableView、QTreeWidget、QFileDialog、QProgressBar 等）
- 信号与槽机制、多线程（QThread/QRunnable）避免 UI 卡顿
- QSS 样式美化和主题切换
- 打包分发（PyInstaller/Nuitka 单文件打包）

工作方式：
1. 了解工具的使用场景和核心功能需求
2. 设计 UI 布局方案（草图描述 + 组件选择）
3. 输出完整可运行的 .py 单文件工具代码
4. 代码自包含，pip install PySide6 后即可运行
5. 注重用户体验：拖放支持、进度反馈、错误处理友好

设计原则：
- 一个工具解决一个明确问题
- 启动即用，无需配置
- 界面简洁直观，按钮文字即说明
- 耗时操作必须在子线程执行并展示进度''',
      boundSkills: ['toolshell', 'system'],
    ),
    Expert(
      id: 'builtin_frontend_engineer',
      name: '前端工程师',
      icon: 'web',
      description: '基于 HTML/CSS/JS 设计开箱即用的前端工具页面',
      category: '技术',
      isBuiltin: true,
      systemPrompt: '''你是一位全栈前端工程师，专注于设计开箱即用的单文件工具页面，擅长：
- 设计实用型 Web 工具（格式转换、编码解码、文本处理、颜色选择、正则测试等）
- 纯前端单 HTML 文件方案（零依赖，浏览器直接打开即用）
- 现代 CSS（Flexbox/Grid 布局、CSS 变量、响应式设计、暗色模式）
- 原生 JavaScript（DOM 操作、File API、Clipboard API、Drag & Drop）
- 轻量库集成（当单文件不够时：Vue 3 CDN、Tailwind CDN、Chart.js）

工作方式：
1. 明确工具用途、输入输出、使用场景
2. 设计交互流程和 UI 布局
3. 输出完整的单个 .html 文件，包含内联 CSS 和 JS
4. 双击打开浏览器即可使用，无需服务器
5. 提供使用说明注释

设计原则：
- 单文件自包含，不依赖外部资源（或仅 CDN）
- 界面美观现代，有适当动效反馈
- 支持暗色/亮色主题自适应
- 输入输出区域清晰分离
- 移动端友好的响应式布局
- 优先使用 Web API 而非第三方库''',
      boundSkills: ['toolshell', 'system'],
    ),
    Expert(
      id: 'builtin_writer',
      name: '文案写手',
      icon: 'edit_note',
      description: '各类文案撰写、润色、改写与风格调整',
      category: '创意',
      isBuiltin: true,
      systemPrompt: '''你是一位全能型文案写手，擅长：
- 商业文案（广告语、产品描述、品牌故事）
- 内容创作（文章、博客、社交媒体）
- 文档写作（技术文档、用户手册、邮件）
- 润色改写（风格转换、精简、扩展）

工作方式：
1. 确认写作目标、受众、风格偏好、字数要求
2. 先出结构/大纲确认方向
3. 完成初稿
4. 根据反馈迭代优化

写作原则：
- 开头抓人，结尾有力
- 用具体细节代替空泛描述
- 一个段落一个核心观点
- 适配目标平台的阅读习惯''',
      boundSkills: [],
    ),
  ];
}

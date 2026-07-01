import '../logger/app_logger.dart';
import '../memory/memory_manager.dart';
import '../skill/skill_model.dart';
import '../skill/skill_registry.dart';
import '../skill/skill_router.dart';

/// 技能注入结果 — 统一返回结构
///
/// 包含技能匹配后的产出：system prompt、tools 定义、来源映射。
/// 工具执行由 skill 自身的脚本/运行时负责，框架不介入。
class SkillInjection {
  /// 匹配到的技能列表（含分数）
  final List<ScoredSkill> matched;

  /// 拼装好的 system prompt 片段（直接追加到 system message）
  final String systemPrompt;

  /// 所有匹配技能的工具定义（直接合并到 tools 列表）
  final List<Map<String, dynamic>> tools;

  /// 工具来源映射 (toolName → "技能:xxx")
  final Map<String, String> sourceMapping;

  const SkillInjection({
    required this.matched,
    required this.systemPrompt,
    required this.tools,
    required this.sourceMapping,
  });

  /// 空注入（无匹配技能时）
  static const empty = SkillInjection(
    matched: [],
    systemPrompt: '',
    tools: [],
    sourceMapping: {},
  );

  bool get isEmpty => matched.isEmpty;
  bool get isNotEmpty => matched.isNotEmpty;
  int get skillCount => matched.length;
}

/// 统一技能注入器 — 三端共享的 Skill 按需加载 API
///
/// 封装了完整的"skill 池 + 用户输入 → 匹配 → 加载 prompt/tools → 打印日志"流程。
/// 对话页、ApiServer、OnlineServer 只需调用 [inject] 即可。
///
/// 用法:
/// ```dart
/// final injector = SkillInjector(registry: registry);
/// final result = await injector.inject(
///   userInput: '帮我写个 API 接口',
///   skillPool: allActiveSkills,
///   context: recentMessages,
/// );
/// systemPrompt += result.systemPrompt;
/// tools.addAll(result.tools);
/// ```
class SkillInjector {
  /// 技能注册表（用于加载 SKILL.md 和 tools.json）
  final SkillRegistry registry;

  /// 可选的 embedding 管理器（启用语义匹配）
  final MemoryManager? memoryManager;

  /// 内部路由器实例（跨轮次复用以维护 pin 状态）
  late final SkillRouter _router;

  /// 已加载的 skill prompt 缓存（避免重复磁盘 IO）
  final Map<String, String> _promptCache = {};

  /// 调用来源标识（用于日志区分）
  final String source;

  SkillInjector({
    required this.registry,
    this.memoryManager,
    this.source = 'SkillInjector',
  }) {
    _router = SkillRouter(memoryManager: memoryManager);
  }

  /// 核心 API — 根据用户输入，从 skill 池中按相关性注入
  ///
  /// [userInput] 当前用户输入文本
  /// [skillPool] 可选的技能池（所有可能被注入的技能）
  /// [context] 最近对话上下文（辅助匹配）
  /// [forceAll] 强制全量注入（忽略相关性，用于无法判断时的 fallback）
  ///
  /// 返回 [SkillInjection]，包含拼装好的 prompt、tools、来源映射。
  Future<SkillInjection> inject({
    required String userInput,
    required List<Skill> skillPool,
    List<String> context = const [],
    bool forceAll = false,
  }) async {
    if (skillPool.isEmpty) return SkillInjection.empty;

    // 预加载所有 skill 的 prompt（带缓存）
    final skillPrompts = await _loadPrompts(skillPool);

    // 决定注入哪些 skill
    List<ScoredSkill> matched;
    if (forceAll || userInput.isEmpty) {
      // 无输入 或 强制模式：全量注入
      matched = skillPool
          .map(
            (s) => ScoredSkill(
              skill: s,
              score: 1.0,
              matchReason: forceAll ? '强制全量' : '无输入(全量)',
            ),
          )
          .toList();
      _logInjection(matched, fullMode: true);
    } else {
      // 相关性路由
      matched = await _router.resolve(
        userInput: userInput,
        recentContext: context,
        allSkills: skillPool,
        skillPrompts: skillPrompts,
      );

      // 无命中 → 不注入任何 skill（不相关就不用）
      if (matched.isEmpty) {
        print('[$source] 本轮未命中任何技能，跳过注入');
        AppLogger.instance.log('[$source] 本轮未命中任何技能，跳过注入');
        return SkillInjection.empty;
      }
    }

    // 加载匹配 skill 的 tools 和 prompt
    final tools = <Map<String, dynamic>>[];
    final sourceMapping = <String, String>{};
    final promptParts = <String>[];

    for (final scored in matched) {
      final skill = scored.skill;

      // 加载 tools.json
      final skillTools = await registry.loadSkillTools(skill);
      for (final t in skillTools) {
        final name = (t['function'] as Map)['name'] as String;
        sourceMapping[name] = '技能:${skill.name}';
      }
      tools.addAll(skillTools);

      // 加载 SKILL.md prompt
      final prompt = skillPrompts[skill.id] ?? '';
      if (prompt.isNotEmpty) {
        promptParts.add(
          '\n\n---\n# 技能: ${skill.name}\n'
          '${skill.path.isNotEmpty ? '> 技能目录: ${skill.path}\n' : ''}\n'
          '$prompt',
        );
      }
    }

    return SkillInjection(
      matched: matched,
      systemPrompt: promptParts.join(),
      tools: tools,
      sourceMapping: sourceMapping,
    );
  }

  /// 将某个 skill pin 住（对话中被实际使用后，后续轮次始终注入）
  void pinSkill(String skillId) => _router.pinSkill(skillId);

  /// 清除所有 pin（新会话时调用）
  void clearPins() => _router.clearPins();

  /// 清除 prompt 缓存（技能文件变更后调用）
  void clearCache() => _promptCache.clear();

  // ─── 内部方法 ─────────────────────────────────────────────

  /// 批量加载 skill prompt（带内存缓存）
  Future<Map<String, String>> _loadPrompts(List<Skill> skills) async {
    final result = <String, String>{};
    for (final skill in skills) {
      if (_promptCache.containsKey(skill.id)) {
        result[skill.id] = _promptCache[skill.id]!;
      } else {
        try {
          final prompt = await registry.loadSkillPrompt(skill);
          _promptCache[skill.id] = prompt;
          result[skill.id] = prompt;
        } catch (e) {
          AppLogger.instance.log('[$source] 加载 ${skill.name} prompt 失败: $e');
          result[skill.id] = '';
        }
      }
    }
    return result;
  }

  /// 打印注入日志
  void _logInjection(List<ScoredSkill> skills, {bool fullMode = false}) {
    if (fullMode) {
      final names = skills.map((s) => s.skill.name).join(', ');
      print('[$source] 全量注入 ${skills.length} 个技能: $names');
      AppLogger.instance.log('[$source] 全量注入 ${skills.length} 个技能: $names');
    }
    // 相关性模式的日志由 SkillRouter._logLoadedSkills 负责
  }
}

import 'dart:math' as math;

import '../logger/app_logger.dart';
import '../memory/memory_manager.dart';
import 'skill_model.dart';

/// 技能相关性匹配结果
class ScoredSkill {
  final Skill skill;
  final double score;
  final String matchReason;

  const ScoredSkill({
    required this.skill,
    required this.score,
    required this.matchReason,
  });
}

/// 技能路由器 — 基于用户输入的相关性匹配，按需注入 skill
///
/// 三层策略：
/// 1. 关键词触发（快速，0ms）
/// 2. 语义相似度（embedding，需要配置）
/// 3. Agent 运行时自主拉取（load_skill 工具）
///
/// 每轮对话匹配一次，最多注入 [maxActiveSkills] 个 skill。
class SkillRouter {
  /// 单轮最多注入的 skill 数量
  static const int maxActiveSkills = 10;

  /// 相关性分数阈值（低于此值不注入）
  static const double relevanceThreshold = 0.2;

  /// 可选的 embedding 管理器（有则启用语义匹配）
  final MemoryManager? memoryManager;

  /// 已被 pin 住的 skill（对话中被实际使用过，不再移除）
  final Set<String> _pinnedSkillIds = {};

  SkillRouter({this.memoryManager});

  /// 将 skill pin 住（对话中被触发后调用）
  void pinSkill(String skillId) {
    _pinnedSkillIds.add(skillId);
  }

  /// 清除所有 pin（新对话开始时调用）
  void clearPins() {
    _pinnedSkillIds.clear();
  }

  /// 对技能池进行相关性匹配，返回本轮应注入的 skill 列表。
  ///
  /// [userInput] 当前用户输入
  /// [recentContext] 最近 2 轮对话内容（辅助匹配）
  /// [allSkills] 全部激活状态的技能列表
  /// [skillPrompts] 技能 id → SKILL.md 内容的映射（用于关键词匹配）
  ///
  /// 返回按相关性排序的 skill 列表（最多 [maxActiveSkills] 个）。
  Future<List<ScoredSkill>> resolve({
    required String userInput,
    required List<String> recentContext,
    required List<Skill> allSkills,
    required Map<String, String> skillPrompts,
  }) async {
    if (allSkills.isEmpty) return [];

    final results = <ScoredSkill>[];
    final contextText = [userInput, ...recentContext].join(' ');

    // ─── 1. Pinned skills 直接注入（满分）───
    for (final skill in allSkills) {
      if (_pinnedSkillIds.contains(skill.id)) {
        results.add(
          ScoredSkill(skill: skill, score: 1.0, matchReason: 'pinned（会话中已使用）'),
        );
      }
    }

    // ─── 2. 关键词匹配 ───
    final unpinned = allSkills
        .where((s) => !_pinnedSkillIds.contains(s.id))
        .toList();

    for (final skill in unpinned) {
      final score = _keywordScore(
        skill,
        skillPrompts[skill.id] ?? '',
        contextText,
      );
      if (score >= relevanceThreshold) {
        results.add(
          ScoredSkill(skill: skill, score: score, matchReason: '关键词匹配'),
        );
      }
    }

    // ─── 3. 语义匹配（如果配置了 embedding 且关键词匹配不足）───
    if (results.length < maxActiveSkills && memoryManager != null) {
      final unmatched = unpinned
          .where((s) => !results.any((r) => r.skill.id == s.id))
          .toList();
      if (unmatched.isNotEmpty) {
        final semanticResults = await _semanticMatch(
          contextText,
          unmatched,
          skillPrompts,
        );
        results.addAll(semanticResults);
      }
    }

    // ─── 4. 排序 + 截断 ───
    results.sort((a, b) => b.score.compareTo(a.score));
    final selected = results.take(maxActiveSkills).toList();

    // ─── 5. 打印载入日志 ───
    _logLoadedSkills(selected);

    return selected;
  }

  // ─── 内部实现 ─────────────────────────────────────────────

  /// 关键词匹配评分
  ///
  /// 双向匹配 + 固定增量：
  /// - 技能名在输入中出现：+0.5（强信号）
  /// - 反向匹配（技能侧关键词出现在输入中）：每命中一个 +0.08（上限 0.5）
  /// - 正向匹配（输入关键词出现在技能侧）：每命中一个 +0.06（上限 0.4）
  ///
  /// 固定增量而非比例，确保多话题输入不会互相摊薄。
  double _keywordScore(Skill skill, String prompt, String contextText) {
    final inputLower = contextText.toLowerCase();
    final nameLower = skill.name.toLowerCase();
    final descLower = skill.description.toLowerCase();
    final promptLower = prompt.toLowerCase();

    double score = 0.0;

    // ── 技能名直接出现在用户输入中（强信号）──
    if (inputLower.contains(nameLower)) {
      score += 0.5;
    }

    // ── 反向匹配：技能侧关键词在用户输入中出现 ──
    // 技能侧包含 name + desc + prompt 的关键词
    final skillKeywords = _extractKeywords(
      '$nameLower $descLower ${promptLower.length > 300 ? promptLower.substring(0, 300) : promptLower}',
    );
    double reverseScore = 0.0;
    for (final kw in skillKeywords) {
      if (inputLower.contains(kw)) {
        reverseScore += 0.08;
      }
    }
    score += reverseScore.clamp(0.0, 0.5);

    // ── 正向匹配：用户输入关键词在技能侧出现 ──
    final inputKeywords = _extractKeywords(inputLower);
    double forwardScore = 0.0;
    for (final kw in inputKeywords) {
      if (nameLower.contains(kw) ||
          descLower.contains(kw) ||
          promptLower.contains(kw)) {
        forwardScore += 0.06;
      }
    }
    score += forwardScore.clamp(0.0, 0.4);

    return score.clamp(0.0, 1.0);
  }

  /// 分词：按空格/标点分割 + 中文 bigram 拆分
  ///
  /// 策略：
  /// - 英文/数字按空格分割，保留 >= 2 字符的 token
  /// - 连续中文字符额外做 bigram（2 字一组滑动窗口），
  ///   解决中文无空格导致的长 token 匹配问题
  /// - 过滤停用词
  List<String> _extractKeywords(String text) {
    // 先按非词字符分割
    final rawTokens = text
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    final result = <String>{};

    for (final token in rawTokens) {
      if (token.length < 2) continue;
      if (_stopWords.contains(token)) continue;

      // 英文/数字 token 直接加入
      if (RegExp(r'^[a-z0-9_]+$').hasMatch(token)) {
        result.add(token);
        continue;
      }

      // 纯中文 token：保留原始 + bigram 拆分
      final zhChars = RegExp(r'[\u4e00-\u9fff]+').allMatches(token);
      final enParts = RegExp(r'[a-z0-9_]+').allMatches(token);

      // 加入英文部分
      for (final m in enParts) {
        if (m.group(0)!.length >= 2) result.add(m.group(0)!);
      }

      // 加入中文 bigram
      for (final m in zhChars) {
        final chars = m.group(0)!;
        if (chars.length >= 2) {
          result.add(chars); // 原始中文串
          // bigram 滑动窗口
          for (var i = 0; i < chars.length - 1; i++) {
            final bigram = chars.substring(i, i + 2);
            if (!_stopWords.contains(bigram)) {
              result.add(bigram);
            }
          }
        }
      }
    }

    return result.toList();
  }

  /// 中英文停用词
  static const _stopWords = {
    '的',
    '了',
    '是',
    '在',
    '我',
    '有',
    '和',
    '就',
    '不',
    '人',
    '都',
    '一',
    '一个',
    '上',
    '也',
    '很',
    '到',
    '说',
    '要',
    '去',
    '你',
    '会',
    '着',
    '没有',
    '看',
    '好',
    '自己',
    '这',
    '他',
    '她',
    '它',
    '们',
    '那',
    '些',
    'the',
    'is',
    'at',
    'which',
    'on',
    'a',
    'an',
    'and',
    'or',
    'but',
    'in',
    'with',
    'to',
    'for',
    'of',
    'not',
    'no',
    'can',
    'do',
    'be',
    'this',
    'that',
    'it',
    'you',
    'we',
    'they',
    'he',
    'she',
    'my',
    'your',
    'have',
    'has',
    'had',
    'will',
    'would',
    'could',
    'should',
    'may',
    '帮我',
    '请',
    '怎么',
    '如何',
    '什么',
    '哪个',
    '能不能',
    '可以',
  };

  /// 语义匹配（基于 embedding 相似度）
  ///
  /// 将用户输入 embed，与各技能描述的 embedding 比较余弦相似度。
  /// 注意：这里不做 Qdrant 查询（skill 不在 Qdrant 中），
  /// 而是实时计算 embedding 对比。
  Future<List<ScoredSkill>> _semanticMatch(
    String contextText,
    List<Skill> candidates,
    Map<String, String> skillPrompts,
  ) async {
    try {
      final inputEmbedding = await memoryManager!.embed(contextText);
      if (inputEmbedding.isEmpty) return [];

      final results = <ScoredSkill>[];
      for (final skill in candidates) {
        // 用技能名 + 描述做 embedding（不用完整 SKILL.md，太长）
        final skillText = '${skill.name}: ${skill.description}';
        final skillEmbedding = await memoryManager!.embed(skillText);
        if (skillEmbedding.isEmpty) continue;

        final similarity = _cosineSimilarity(inputEmbedding, skillEmbedding);
        if (similarity >= relevanceThreshold) {
          results.add(
            ScoredSkill(
              skill: skill,
              score: similarity,
              matchReason: '语义匹配(${(similarity * 100).toStringAsFixed(0)}%)',
            ),
          );
        }
      }
      return results;
    } catch (e) {
      AppLogger.instance.log('[SkillRouter] 语义匹配失败(降级到关键词): $e');
      return [];
    }
  }

  /// 余弦相似度
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// 打印载入的 skill 日志到终端
  void _logLoadedSkills(List<ScoredSkill> skills) {
    if (skills.isEmpty) return; // 无命中由调用方统一打印

    print('[SkillRouter] ╭─ 本轮载入 ${skills.length} 个技能 ─────────');
    AppLogger.instance.log('[SkillRouter] 本轮载入 ${skills.length} 个技能');
    for (final scored in skills) {
      final pct = (scored.score * 100).toStringAsFixed(0);
      final line =
          '[SkillRouter] │ 载入 ${scored.skill.name} '
          '(相关度:$pct%, ${scored.matchReason})';
      print(line);
      AppLogger.instance.log(line);
    }
    print('[SkillRouter] ╰────────────────────────────────────────');
  }
}

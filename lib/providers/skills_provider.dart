import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/skill/skill_model.dart';
import '../core/skill/skill_registry.dart';
import '../features/chat/chat_provider.dart';
import 'settings_provider.dart';

/// 技能注册表 Provider
final skillRegistryProvider = Provider<SkillRegistry>((ref) {
  // 跟随设置中的技能目录；设置未就绪时回退到旧默认位置
  final skillsPath = ref.watch(settingsProvider).valueOrNull?.skillsPath ?? '';
  return SkillRegistry(skillsPath: skillsPath);
});

/// 全局技能列表 Provider
///
/// 仅包含用户安装的全局技能 (应用支持目录/Skills)。
/// 不含项目级临时技能 —— 后者由 [projectSkillsProvider] 单独管理，
/// 避免污染全局技能管理 UI (技能页、对话框技能栏、在线服务技能选择)。
final skillsProvider = AsyncNotifierProvider<SkillsNotifier, List<Skill>>(
  SkillsNotifier.new,
);

class SkillsNotifier extends AsyncNotifier<List<Skill>> {
  SkillRegistry get _registry => ref.read(skillRegistryProvider);

  @override
  Future<List<Skill>> build() async {
    // 用 watch 订阅 skillRegistryProvider，确保 settings 加载完成后
    // registry 路径更新时技能列表会自动重建
    final registry = ref.watch(skillRegistryProvider);
    return registry.listInstalled();
  }

  /// 从 ZIP 导入技能
  Future<Skill> importFromZip(String zipPath) async {
    final skill = await _registry.importFromZip(zipPath);
    ref.invalidateSelf();
    return skill;
  }

  /// 删除技能
  Future<void> remove(String skillId) async {
    await _registry.remove(skillId);
    ref.invalidateSelf();
  }

  /// 切换技能激活状态
  Future<void> toggleActive(String skillId) async {
    final skills = state.valueOrNull ?? [];
    final skill = skills.firstWhere((s) => s.id == skillId);
    await _registry.setActive(skillId, !skill.isActive);
    ref.invalidateSelf();
  }

  /// 更新技能描述 (用户手动编辑)
  Future<void> updateDescription(String skillId, String description) async {
    await _registry.setDescription(skillId, description);
    ref.invalidateSelf();
  }

  /// 读取技能的 SKILL.md 原文 (用于查看渲染)
  Future<String> loadSkillMd(Skill skill) async {
    return _registry.loadSkillPrompt(skill);
  }

  /// 按新顺序重排卡片 (拖拽排序)
  Future<void> reorder(List<Skill> ordered) async {
    // 乐观更新本地状态，立即反映拖拽结果
    state = AsyncData(ordered);
    await _registry.reorder(ordered.map((s) => s.id).toList());
  }
}

/// 项目级临时技能 Provider
///
/// 扫描当前工作目录的 `.toolshell/skills/`，与全局技能完全隔离。
/// 这类技能恒定激活、生命周期跟随工作目录，仅供 Agent 运行时挂载，
/// 不出现在任何全局技能管理 UI 中。
///
/// 切换工作目录时自动重建。中途新增技能可由消费方 invalidate 触发重扫。
final projectSkillsProvider =
    AsyncNotifierProvider<ProjectSkillsNotifier, List<Skill>>(
      ProjectSkillsNotifier.new,
    );

class ProjectSkillsNotifier extends AsyncNotifier<List<Skill>> {
  @override
  Future<List<Skill>> build() async {
    final registry = ref.watch(skillRegistryProvider);
    // 订阅工作目录：切换目录时项目级技能列表自动重建
    final workDir = ref.watch(workingDirectoryProvider);
    return registry.listProjectSkills(workDir);
  }
}

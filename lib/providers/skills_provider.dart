import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/skill/skill_model.dart';
import '../core/skill/skill_registry.dart';
import 'settings_provider.dart';

/// 技能注册表 Provider
final skillRegistryProvider = Provider<SkillRegistry>((ref) {
  // 跟随设置中的技能目录；设置未就绪时回退到旧默认位置
  final skillsPath = ref.watch(settingsProvider).valueOrNull?.skillsPath ?? '';
  return SkillRegistry(skillsPath: skillsPath);
});

/// 技能列表 Provider
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

  /// 按新顺序重排卡片 (拖拽排序)
  Future<void> reorder(List<Skill> ordered) async {
    // 乐观更新本地状态，立即反映拖拽结果
    state = AsyncData(ordered);
    await _registry.reorder(ordered.map((s) => s.id).toList());
  }
}

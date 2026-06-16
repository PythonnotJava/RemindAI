import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/expert/expert.dart';
import '../core/expert/expert_store.dart';

/// 当前激活的专家 (从专家页点击后设置，对话页读取并应用)
/// null 表示无专家模式（普通对话）
final activeExpertProvider = StateProvider<Expert?>((ref) => null);

/// 专家列表 Provider
final expertsProvider = AsyncNotifierProvider<ExpertsNotifier, List<Expert>>(
  ExpertsNotifier.new,
);

class ExpertsNotifier extends AsyncNotifier<List<Expert>> {
  @override
  Future<List<Expert>> build() async {
    await ExpertStore.instance.init();
    return ExpertStore.instance.experts;
  }

  Future<void> addExpert(Expert expert) async {
    await ExpertStore.instance.add(expert);
    state = AsyncData(ExpertStore.instance.experts);
  }

  Future<void> updateExpert(Expert expert) async {
    await ExpertStore.instance.update(expert);
    state = AsyncData(ExpertStore.instance.experts);
  }

  Future<bool> deleteExpert(String id) async {
    final ok = await ExpertStore.instance.delete(id);
    if (ok) state = AsyncData(ExpertStore.instance.experts);
    return ok;
  }

  Future<Expert?> importFromJson(String jsonStr) async {
    final expert = await ExpertStore.instance.importOne(jsonStr);
    if (expert != null) state = AsyncData(ExpertStore.instance.experts);
    return expert;
  }
}

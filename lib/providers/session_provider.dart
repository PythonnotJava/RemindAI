import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/search/search_config.dart';

/// Session 级记忆开关 — 独立于 memory.json，由 UI 记忆按钮控制
/// null = 跟随 memory.json 配置; true/false = 强制覆盖
final sessionMemoryRecallProvider = StateProvider<bool?>((ref) => null);
final sessionMemoryStoreProvider = StateProvider<bool?>((ref) => null);

/// 本次对话指定的 Python 解释器路径 (可执行文件路径)。空表示用系统默认。
final sessionPythonProvider = StateProvider<String>((ref) => '');

/// 本次对话指定的 Node/npm 路径 (可执行文件路径)。空表示用系统默认。
final sessionNpmProvider = StateProvider<String>((ref) => '');

/// 本次对话选中的搜索 provider (none = 关闭搜索)
final sessionSearchProvider = StateProvider<SearchProvider>((ref) {
  return SearchProvider.none;
});

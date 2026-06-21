import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/settings/app_settings.dart';
import '../core/db/database.dart';
import '../core/logger/app_logger.dart';
import '../core/skill/skill_registry.dart';
import '../core/memory/qdrant_service.dart';

/// 主题模式 Provider — 由 settingsProvider 初始化，UI 可直接 watch
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return _parseThemeMode(settings?.themeMode ?? 'dark');
});

ThemeMode _parseThemeMode(String mode) => switch (mode) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// 主题色 Provider — 'purple' / 'green' / 'blue' / 'cyan'
final accentColorProvider = StateProvider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.accentColor ?? 'purple';
});

/// 主题色 seed 映射
const _accentColorSeeds = {
  'purple': 0xFF6750A4,
  'green': 0xFF00897B, // Teal 600 - 护眼
  'blue': 0xFF1976D2,
  'cyan': 0xFF00ACC1,
};

Color getAccentColor(String accentColor) =>
    Color(_accentColorSeeds[accentColor] ?? 0xFF6750A4);

/// 语言 Locale Provider — 由 settingsProvider 初始化，MaterialApp 可直接 watch
final localeProvider = StateProvider<Locale?>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return _parseLocale(settings?.locale ?? 'system');
});

Locale? _parseLocale(String locale) => switch (locale) {
  'zh' => const Locale('zh'),
  'en' => const Locale('en'),
  _ => null, // null = 跟随系统
};

/// 界面字体 Provider
final uiFontProvider = StateProvider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.uiFont ?? 'Noto Sans SC';
});

/// 界面字体大小 Provider
final uiFontSizeProvider = StateProvider<double>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.uiFontSize ?? 14.0;
});

/// 交互字体 Provider
final chatFontProvider = StateProvider<String>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.chatFont ?? 'Noto Sans SC';
});

/// 交互字体大小 Provider
final chatFontSizeProvider = StateProvider<double>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return settings?.chatFontSize ?? 14.0;
});

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  /// 写入序列化锁 — 所有 update* 方法经此串行化，
  /// 防止并发 read-modify-save 导致文件写冲突或状态覆盖。
  Future<void> _writeLock = Future.value();

  /// 将 [action] 追加到写入队列末尾，保证串行执行。
  Future<void> _serialized(Future<void> Function() action) {
    final prev = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    () async {
      // 等待上一个操作完成（即使它失败了也继续）
      await prev.catchError((_) {});
      try {
        await action();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }();
    return completer.future;
  }

  @override
  Future<AppSettings> build() async {
    final settings = await AppSettings.load();
    // 一次性迁移: 把旧版默认位置 (应用支持目录/Skills) 的技能搬到新目录
    await _migrateLegacySkills(settings.skillsPath);
    return settings;
  }

  /// 旧版技能目录一次性迁移。
  /// 若新技能目录尚不存在或为空，而旧位置有内容，则整体搬迁过去。
  Future<void> _migrateLegacySkills(String newSkillsPath) async {
    if (newSkillsPath.isEmpty) return;
    try {
      final legacyPath = await SkillRegistry.legacySkillsDir();
      if (p.equals(legacyPath, newSkillsPath)) return;

      final legacyDir = Directory(legacyPath);
      if (!await legacyDir.exists()) return;

      // 旧目录是否有内容
      final hasLegacyContent = await legacyDir.list().isEmpty == false;
      if (!hasLegacyContent) return;

      // 新目录已有内容则不覆盖，避免重复迁移
      final newDir = Directory(newSkillsPath);
      if (await newDir.exists()) {
        final newHasContent = await newDir.list().isEmpty == false;
        if (newHasContent) return;
      }

      await _migrateDirectory(legacyPath, newSkillsPath);
    } catch (_) {
      // 迁移失败不阻塞启动
    }
  }

  Future<void> updateDatabasePath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final oldPath = current.databasePath;
    if (oldPath == newPath) return;

    // 迁移: 复制旧 db 文件到新路径
    await _migrateFile(oldPath, newPath);

    // 重新配置数据库路径并重连
    DatabaseHelper.instance.close();
    DatabaseHelper.configurePath(newPath);

    final updated = current.copyWith(databasePath: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  Future<void> updateHistoryPath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final oldPath = current.historyPath;
    if (oldPath == newPath) return;

    // 迁移: 复制旧历史目录到新路径
    await _migrateDirectory(oldPath, newPath);

    final updated = current.copyWith(historyPath: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  Future<void> updatePandocPath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(pandocPath: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 更新技能存放目录 (迁移已安装技能到新路径)
  Future<void> updateSkillsPath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final oldPath = current.skillsPath;
    if (oldPath == newPath) return;

    // 迁移: 复制旧技能目录到新路径
    await _migrateDirectory(oldPath, newPath);

    final updated = current.copyWith(skillsPath: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 更新工作目录
  Future<void> updateWorkingDirectory(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(workingDirectory: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 更新 Qdrant 可执行文件路径 (空字符串表示恢复自动检测)
  Future<void> updateQdrantPath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(qdrantPath: newPath);
    await updated.save();
    state = AsyncData(updated);
    // 通知 QdrantService 使用新路径 (下次启动生效)
    QdrantService.instance.setManualPath(newPath);
  });

  /// 更新日志存放目录 (迁移已有日志文件到新路径)
  Future<void> updateLogsPath(String newPath) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final oldPath = current.logsPath;
    if (oldPath == newPath) return;

    // 迁移旧日志文件到新目录
    await _migrateDirectory(oldPath, newPath);

    // 通知 Logger 切换到新目录
    await AppLogger.instance.updateLogDir(newPath);

    final updated = current.copyWith(logsPath: newPath);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 更新主题模式 ('system' / 'light' / 'dark')
  Future<void> updateThemeMode(String mode) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(themeMode: mode);
    await updated.save();
    state = AsyncData(updated);
    // 同步更新 themeModeProvider
    ref.read(themeModeProvider.notifier).state = _parseThemeMode(mode);
  });

  /// 更新主题色 ('purple' / 'green' / 'blue' / 'cyan')
  Future<void> updateAccentColor(String color) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(accentColor: color);
    await updated.save();
    state = AsyncData(updated);
    // 同步更新 accentColorProvider
    ref.read(accentColorProvider.notifier).state = color;
  });

  /// 更新失焦通知开关
  Future<void> updateNotifyOnBlur(bool enabled) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(notifyOnBlur: enabled);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 更新语言设置 ('system' / 'zh' / 'en')
  Future<void> updateLocale(String locale) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.copyWith(locale: locale);
    await updated.save();
    state = AsyncData(updated);
    // 同步更新 localeProvider
    ref.read(localeProvider.notifier).state = _parseLocale(locale);
  });

  /// 更新界面字体
  Future<void> updateUiFont(String font) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(uiFont: font);
    await updated.save();
    state = AsyncData(updated);
    ref.read(uiFontProvider.notifier).state = font;
  });

  /// 更新界面字体大小
  Future<void> updateUiFontSize(double size) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(uiFontSize: size);
    await updated.save();
    state = AsyncData(updated);
    ref.read(uiFontSizeProvider.notifier).state = size;
  });

  /// 更新交互字体
  Future<void> updateChatFont(String font) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(chatFont: font);
    await updated.save();
    state = AsyncData(updated);
    ref.read(chatFontProvider.notifier).state = font;
  });

  /// 更新交互字体大小
  Future<void> updateChatFontSize(double size) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(chatFontSize: size);
    await updated.save();
    state = AsyncData(updated);
    ref.read(chatFontSizeProvider.notifier).state = size;
  });

  /// 更新回车行为 ('send' / 'newline')
  Future<void> updateEnterAction(String action) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = current.copyWith(enterAction: action);
    await updated.save();
    state = AsyncData(updated);
  });

  /// 新增或更新一个嵌入式模型配置。
  /// 若 [config].id 已存在则更新，否则追加。
  /// 列表中首个加入的配置会自动设为选中。
  Future<void> upsertEmbedding(EmbeddingConfig config) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final list = [...current.embeddings];
    final idx = list.indexWhere((e) => e.id == config.id);
    if (idx >= 0) {
      list[idx] = config;
    } else {
      list.add(config);
    }

    // 若当前无选中或选中已失效，自动选中本次的配置
    String selectedId = current.selectedEmbeddingId;
    final selectedValid = list.any((e) => e.id == selectedId);
    if (!selectedValid) selectedId = config.id;

    final updated = current.copyWith(
      embeddings: list,
      selectedEmbeddingId: selectedId,
    );
    await updated.save();
    state = AsyncData(updated);
  });

  /// 删除指定 id 的嵌入式模型配置。
  Future<void> deleteEmbedding(String id) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final list = current.embeddings.where((e) => e.id != id).toList();

    // 若删掉的是选中项，重新选中第一个 (若有)
    String selectedId = current.selectedEmbeddingId;
    if (selectedId == id) {
      selectedId = list.isNotEmpty ? list.first.id : '';
    }

    final updated = current.copyWith(
      embeddings: list,
      selectedEmbeddingId: selectedId,
    );
    await updated.save();
    state = AsyncData(updated);
  });

  /// 设置当前选中(默认)的嵌入式模型。
  Future<void> selectEmbedding(String id) => _serialized(() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.embeddings.any((e) => e.id == id)) return;

    final updated = current.copyWith(selectedEmbeddingId: id);
    await updated.save();
    state = AsyncData(updated);
  });

  Future<void> _migrateFile(String oldPath, String newPath) async {
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return;

    final newDir = Directory(p.dirname(newPath));
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    await oldFile.copy(newPath);
    await oldFile.delete();
  }

  Future<void> _migrateDirectory(String oldPath, String newPath) async {
    final oldDir = Directory(oldPath);
    if (!await oldDir.exists()) return;

    final newDir = Directory(newPath);
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    await for (final entity in oldDir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: oldPath);
      final newEntityPath = p.join(newPath, relativePath);

      if (entity is File) {
        final destDir = Directory(p.dirname(newEntityPath));
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        await entity.copy(newEntityPath);
      } else if (entity is Directory) {
        final destDir = Directory(newEntityPath);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
      }
    }

    // Remove old directory after successful copy
    await oldDir.delete(recursive: true);
  }
}

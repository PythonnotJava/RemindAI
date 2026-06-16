import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/daos/memory_dao.dart';
import '../core/memory/memory_manager.dart';
import '../core/memory/qdrant_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

/// 记忆 DAO Provider
final memoryDaoProvider = Provider<MemoryDao>((ref) {
  final db = ref.watch(databaseProvider);
  return MemoryDao(db);
});

/// 记忆视图数据 — 供记忆管理页面展示
class MemoryView {
  final bool enabled; // 是否已配置嵌入模型
  final bool qdrantRunning; // Qdrant 是否在运行
  final String collection; // 当前项目的 collection 名
  final int pointCount; // 记忆条数
  final List<Map<String, dynamic>> items; // 记忆条目列表
  final int sqliteBytes; // SQLite 数据库文件占用 (字节)
  final int qdrantBytes; // Qdrant 存储目录占用 (字节)

  const MemoryView({
    this.enabled = false,
    this.qdrantRunning = false,
    this.collection = '',
    this.pointCount = 0,
    this.items = const [],
    this.sqliteBytes = 0,
    this.qdrantBytes = 0,
  });
}

/// 构建当前的 MemoryManager (基于全局 embedding 配置)。
/// 未配置则返回 null。
final memoryManagerProvider = Provider<MemoryManager?>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  final embCfg = settings?.embedding;
  if (embCfg == null || !embCfg.isConfigured) return null;

  final dao = embCfg.persistToSqlite ? ref.watch(memoryDaoProvider) : null;

  return MemoryManager(
    embeddingBaseUrl: embCfg.baseUrl,
    embeddingApiKey: embCfg.apiKey,
    embeddingModel: embCfg.model,
    memoryDao: dao,
  );
});

/// 当前记忆 collection 名称 (全局长期记忆，跨项目)
final currentCollectionProvider = Provider<String>((ref) {
  return MemoryManager.globalCollection;
});

/// 记忆视图 — 加载当前 collection 的统计和条目
final memoryViewProvider = FutureProvider<MemoryView>((ref) async {
  final manager = ref.watch(memoryManagerProvider);
  final collection = ref.watch(currentCollectionProvider);
  final settings = ref.watch(settingsProvider).valueOrNull;

  // SQLite 文件占用 (无论是否启用 Qdrant 都应展示)
  int sqliteBytes = 0;
  final dbPath = settings?.databasePath ?? '';
  if (dbPath.isNotEmpty) {
    try {
      final f = File(dbPath);
      if (await f.exists()) sqliteBytes = await f.length();
    } catch (_) {}
  }

  final qdrant = QdrantService.instance;
  final qdrantBytes = await qdrant.storageSize();

  // 未配置嵌入模型 — 仍返回 SQLite 占用
  if (manager == null) {
    return MemoryView(
      enabled: false,
      sqliteBytes: sqliteBytes,
      qdrantBytes: qdrantBytes,
    );
  }

  // 真实探活 (兼容外部/遗留 Qdrant 进程)
  bool running = await qdrant.probeHealth();
  if (!running) {
    try {
      await qdrant.start();
      running = qdrant.isRunning;
    } catch (_) {
      running = false;
    }
  }

  if (!running) {
    return MemoryView(
      enabled: true,
      qdrantRunning: false,
      collection: collection,
      sqliteBytes: sqliteBytes,
      qdrantBytes: qdrantBytes,
    );
  }

  final items = await manager.listPoints(collection);
  return MemoryView(
    enabled: true,
    qdrantRunning: true,
    collection: collection,
    pointCount: items.length,
    items: items,
    sqliteBytes: sqliteBytes,
    qdrantBytes: qdrantBytes,
  );
});

/// 字节数格式化为可读字符串
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final str = unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
  return '$str ${units[unit]}';
}

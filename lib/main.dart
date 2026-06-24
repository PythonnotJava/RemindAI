import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/db/database.dart';
import 'core/font/custom_font_loader.dart';
import 'core/logger/app_logger.dart';
import 'core/settings/app_settings.dart';
import 'core/shortcuts/shortcut_config.dart';
import 'core/memory/qdrant_service.dart';
import 'core/notification/notification_service.dart';
import 'core/pet/pet_economy.dart';
import 'core/tools/tool_bootstrap.dart';
import 'core/tools/tool_registry.dart';

Future<void> main() async {
  await runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 先加载设置，以便获取自定义路径
      AppSettings? settings;
      try {
        settings = await AppSettings.load();
      } catch (_) {}

      // 初始化日志系统 (使用设置中的路径，若为空则用默认)
      await AppLogger.instance.init(settings?.logsPath);

      // 窗口管理初始化
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1200, 800),
        center: true,
        title: 'RemindAI',
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      // 配置数据库和 Qdrant 路径
      if (settings != null) {
        if (settings.databasePath.isNotEmpty) {
          DatabaseHelper.configurePath(settings.databasePath);
        }
        if (settings.qdrantPath.isNotEmpty) {
          QdrantService.instance.setManualPath(settings.qdrantPath);
        }
      }

      // 过滤 flutter_math_fork 已知的亚像素溢出和 FormatException
      // 这些不影响功能和视觉，只是浮点精度问题
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        // 忽略 RenderLine 微量溢出 (< 1px)
        if (msg.contains('RenderLine') && msg.contains('overflowed by')) {
          final match = RegExp(r'overflowed by ([\d.]+)').firstMatch(msg);
          if (match != null) {
            final px = double.tryParse(match[1] ?? '') ?? 0;
            if (px < 1.0) return; // 亚像素溢出，忽略
          }
        }
        // 忽略 flutter_math_fork 内部的 FormatException (布局阶段)
        if (details.exception is FormatException) {
          final stack = details.stack?.toString() ?? '';
          if (stack.contains('flutter_math_fork')) return;
        }
        // 其他错误：终端 + 日志双写
        final errorMsg = '[FlutterError] ${details.exceptionAsString()}';
        final stackStr = details.stack?.toString() ?? '';
        print(errorMsg);
        if (stackStr.isNotEmpty) {
          print(stackStr.split('\n').take(8).join('\n'));
        }
        FlutterError.presentError(details);
      };

      // 初始化工具注册表 + 通知服务 + 字体 + 快捷键 + 宠物经济（互相独立，并行执行）
      final results = await Future.wait([
        createToolRegistry(),
        NotificationService.instance.init(),
        CustomFontLoader.instance.loadAll(),
        ShortcutConfig.instance.load(),
        PetEconomy.instance.load(),
      ]);
      final toolRegistry = results[0] as ToolRegistry;

      runApp(
        ProviderScope(
          overrides: [toolRegistryProvider.overrideWithValue(toolRegistry)],
          child: const RemindAIApp(),
        ),
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // 写入日志文件
        AppLogger.instance.log(line);
        // 同时保留终端输出 (开发时可见)
        parent.print(zone, line);
      },
    ),
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:dock_panel/dock_panel.dart';
import 'package:path/path.dart' as p;

import '../../core/logger/app_logger.dart';
import '../../core/settings/app_settings.dart';

/// 把多 Agent 工作台的 dock 布局落到 `<rootDir>/multi_agent_dock.json`。
///
/// 为什么需要它：`packages/dock_panel` 只自带 `MemoryDockStorage`（测试用），
/// 而 `DockManager.setStorage` 在全仓库都没有调用点——于是
/// `DockLayout`/分栏宽度/面板所在分组每次重启都丢，用户得重新拖一遍。
/// 这里补上真实的文件存储，并在 [AgentWorkspace] 初始化时接线。
///
/// 只保存布局结构（节点类型、方向、flex、面板 id 列表、activeIndex），
/// 不保存 `WidgetBuilder`——恢复时用注册过的面板 id 重新绑定。
class FileDockStorage implements DockStorage {
  FileDockStorage(this.file);

  final File file;

  /// 打开应用数据根目录下的默认布局文件（目录不存在时由 write 创建）。
  static Future<FileDockStorage> open() async {
    final root = await AppSettings.getRootDir();
    return FileDockStorage(File(p.join(root, 'multi_agent_dock.json')));
  }

  @override
  Map<String, dynamic>? read() {
    try {
      if (!file.existsSync()) return null;
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) return null;
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      // 布局文件损坏不该挡住工作台启动：当作"没有已存布局"即可。
      AppLogger.instance.log('[Dock] 读取布局失败(已忽略): $e');
      return null;
    }
  }

  @override
  void write(Map<String, dynamic> data) {
    try {
      if (data.isEmpty) {
        // DockManager 在根节点为空时写 `{}`，当作"没有布局"直接删文件。
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      AppLogger.instance.log('[Dock] 保存布局失败(已忽略): $e');
    }
  }

  @override
  void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      AppLogger.instance.log('[Dock] 清除布局失败(已忽略): $e');
    }
  }
}

import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// 系统通知服务 — 窗口失焦时对话完成发送 Toast 通知
class NotificationService with WindowListener {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  bool _focused = true;
  bool _initialized = false;

  /// 窗口是否处于焦点状态
  bool get isFocused => _focused;

  /// 初始化: 注册窗口焦点监听
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await localNotifier.setup(appName: 'RemindAI');
    windowManager.addListener(this);

    // 初始状态假定有焦点 (刚启动的窗口通常有焦点)
    _focused = await windowManager.isFocused();
  }

  /// 发送系统通知 (仅在失焦时才真正弹出)
  ///
  /// [title] 通知标题
  /// [body] 通知正文
  /// [forceShow] 为 true 时无论焦点状态都发送
  Future<void> notify({
    required String title,
    required String body,
    bool forceShow = false,
  }) async {
    if (!forceShow && _focused) return;

    final notification = LocalNotification(
      title: title,
      body: body.length > 200 ? '${body.substring(0, 200)}...' : body,
    );
    await notification.show();
  }

  // ─── WindowListener ───

  @override
  void onWindowFocus() {
    _focused = true;
  }

  @override
  void onWindowBlur() {
    _focused = false;
  }

  void dispose() {
    windowManager.removeListener(this);
    _instance = null;
  }
}

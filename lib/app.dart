import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/app_localizations.dart';
import 'core/l10n/l10n_ext.dart';
import 'providers/settings_provider.dart';
import 'shared/layout/app_scaffold.dart';
import 'shared/widgets/theme_transition.dart';

class RemindAIApp extends ConsumerWidget {
  const RemindAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'RemindAI',
      debugShowCheckedModeBanner: false,
      // ─── 国际化 ───
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const ThemeTransition(child: _WindowWrapper()),
    );
  }
}

/// 包装层：监听窗口关闭事件 + 系统托盘管理
class _WindowWrapper extends StatefulWidget {
  const _WindowWrapper();

  @override
  State<_WindowWrapper> createState() => _WindowWrapperState();
}

class _WindowWrapperState extends State<_WindowWrapper>
    with WindowListener, TrayListener {
  /// 启动阶段: splash → ready (主界面可见)
  bool _ready = false;
  /// 控制淡入动画
  bool _fadeIn = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    trayManager.addListener(this);
    _initTray();
    _waitForWindowReady();
  }

  /// 等待窗口布局完全稳定后再切换到主界面
  ///
  /// 策略：
  /// 1. 先让 splash 立即渲染（简单居中布局，不依赖复杂约束）
  /// 2. 等待 5 帧确保 window metrics / MediaQuery 完全传播
  /// 3. 额外延迟 100ms 等 GPU 光栅化跟上
  /// 4. 创建 AppScaffold 并用交叉淡入替换 splash
  Future<void> _waitForWindowReady() async {
    // 等待 5 帧: 窗口尺寸传播 + Flutter layout 管线稳定
    for (int i = 0; i < 5; i++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    // 额外等 100ms 让系统 compositor/GPU 完成光栅化
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // 先把 AppScaffold 挂上（还不可见，opacity=0）
    setState(() => _ready = true);

    // 再等 2 帧让 AppScaffold 完成首次 layout + paint
    for (int i = 0; i < 2; i++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    // 开始淡入
    setState(() => _fadeIn = true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    await trayManager.setIcon('assets/icons/logo.ico');
    await trayManager.setToolTip('RemindAI');
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口 (Show)'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出 (Exit)'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  // ─── TrayListener ───

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'exit':
        windowManager.setPreventClose(false);
        windowManager.close();
        break;
    }
  }

  // ─── WindowListener ───

  @override
  void onWindowClose() async {
    final shouldMinimize = await _showCloseDialog();
    if (shouldMinimize) {
      await windowManager.hide();
    } else {
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  Future<bool> _showCloseDialog() async {
    final s = context.s;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.dialogCloseTitle),
        content: Text(s.dialogCloseContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.dialogCloseExit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.dialogCloseMinimize),
          ),
        ],
      ),
    );
    return result ?? true; // 默认最小化
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // 底层: 主界面 (ready 后创建，fadeIn 后可见)
        if (_ready)
          AnimatedOpacity(
            opacity: _fadeIn ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: const AppScaffold(),
          ),
        // 顶层: Splash 闪屏 (fadeIn 后淡出消失)
        IgnorePointer(
          ignoring: _fadeIn,
          child: AnimatedOpacity(
            opacity: _fadeIn ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: Container(
              color: colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/icons/logo.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Loading 指示器
                    SpinKitFadingCircle(
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      size: 32,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'RemindAI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

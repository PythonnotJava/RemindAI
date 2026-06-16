import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'core/font/custom_font_loader.dart';
import 'core/shortcuts/shortcut_config.dart';
import 'l10n/app_localizations.dart';
import 'core/l10n/l10n_ext.dart';
import 'providers/settings_provider.dart';
import 'shared/layout/app_scaffold.dart';
import 'shared/widgets/region_screenshot.dart';
import 'shared/widgets/screenshot_editor.dart';
import 'shared/widgets/theme_transition.dart';
import 'features/pet/widgets/floating_pet.dart';
import 'features/pet/widgets/pet_bubble.dart';
import 'core/pet/pet_observer.dart';
import 'core/tts/tts_service.dart';

class RemindAIApp extends ConsumerWidget {
  const RemindAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final uiFont = ref.watch(uiFontProvider);

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
      theme: _buildTheme(Brightness.light, uiFont),
      darkTheme: _buildTheme(Brightness.dark, uiFont),
      themeMode: themeMode,
      home: const ThemeTransition(child: _WindowWrapper()),
    );
  }

  ThemeData _buildTheme(Brightness brightness, String fontFamily) {
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      ),
      useMaterial3: true,
    );

    // 应用字体族：自定义字体直接用 fontFamily，Google Fonts 用 getTextTheme
    TextTheme textTheme;
    final isCustom = CustomFontLoader.instance.loadedFonts.contains(fontFamily);
    if (isCustom) {
      // 自定义字体通过 FontLoader 注册，直接用 fontFamily 名
      textTheme = baseTheme.textTheme.apply(fontFamily: fontFamily);
    } else {
      try {
        textTheme = GoogleFonts.getTextTheme(fontFamily, baseTheme.textTheme);
      } catch (_) {
        textTheme = baseTheme.textTheme;
      }
    }

    return baseTheme.copyWith(textTheme: textTheme);
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
  /// Splash 动画结束后从 tree 移除
  bool _splashRemoved = false;
  /// 截图用的 RepaintBoundary key
  final _screenshotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    PetObserver.instance.initialize();
    _loadTtsConfig();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    trayManager.addListener(this);
    _initTray();
    _waitForWindowReady();
  }

  /// 等待窗口布局完全稳定后再切换到主界面
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

    // 等待淡出动画完成 (300ms) 后彻底移除 Splash
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _splashRemoved = true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  /// 从本地文件加载 TTS 配置（用户自行填写密钥）
  Future<void> _loadTtsConfig() async {
    await TtsService.instance.loadPersistedConfig();
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
    final screenshotBinding = ShortcutConfig.instance.bindings['screenshot'];

    return CallbackShortcuts(
      bindings: {
        if (screenshotBinding != null)
          screenshotBinding.activator: _triggerScreenshot,
      },
      child: Focus(
        autofocus: true,
        child: RepaintBoundary(
          key: _screenshotKey,
          child: Stack(
            children: [
              // 底层: 主界面 (ready 后创建，fadeIn 后可见)
              if (_ready)
                AnimatedOpacity(
                  opacity: _fadeIn ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: const AppScaffold(),
                ),
              // 全局浮动宠物 (主界面可见后显示)
              if (_ready && _fadeIn)
                const FloatingPet(),
              if (_ready && _fadeIn)
                const PetBubble(),
              // 顶层: Splash 闪屏 (淡出动画完成后从树中彻底移除)
              if (!_splashRemoved)
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/icons/logo_egg.png',
                              width: 72,
                              height: 72,
                            ),
                          ),
                          const SizedBox(height: 24),
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
          ),
        ),
      ),
    );
  }

  /// 触发区域截图
  void _triggerScreenshot() async {
    final image = await RegionScreenshot.capture(context, _screenshotKey);
    if (image == null || !mounted) return;

    // 打开截图编辑器对话框
    await ScreenshotEditor.show(context, image);
  }
}

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
import 'core/logger/app_logger.dart';
import 'core/shortcuts/shortcut_config.dart';
import 'core/theme/independent_themes/independent_theme_registry.dart';
import 'l10n/app_localizations.dart';
import 'core/l10n/l10n_ext.dart';
import 'providers/mcp_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/api_server_provider.dart';
import 'features/online_service/online_service_provider.dart';
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
    final accentColor = ref.watch(accentColorProvider);

    // 首帧后按需拉起对外 API 服务 (进程级一次性, 不阻塞 UI)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bootstrapApiServer(ref);
      bootstrapOnlineService(ref);
    });

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
      theme: _buildTheme(Brightness.light, uiFont, accentColor),
      darkTheme: _buildTheme(Brightness.dark, uiFont, accentColor),
      themeMode: themeMode,
      home: const ThemeTransition(child: _WindowWrapper()),
    );
  }

  ThemeData _buildTheme(
    Brightness brightness,
    String fontFamily,
    String accentColor,
  ) {
    // 检查是否为独立主题
    if (IndependentThemeRegistry.isIndependentTheme(accentColor)) {
      final theme = IndependentThemeRegistry.buildTheme(
        accentColor,
        brightness,
      );
      if (theme != null) {
        // 独立主题已经包含完整的字体配置，直接返回
        return _applyFont(theme, fontFamily);
      }
    }

    // 标准主题：使用配色方案 + Material 3
    final baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: getAccentColor(accentColor),
        brightness: brightness,
      ),
      useMaterial3: true,
    );

    return _applyFont(baseTheme, fontFamily);
  }

  /// 应用字体到主题
  ThemeData _applyFont(ThemeData theme, String fontFamily) {
    // 应用字体族：
    // 1. 自定义字体（通过 FontLoader 注册）直接用 fontFamily
    // 2. 系统字体直接用 fontFamily
    // 3. Google Fonts 用 getTextTheme
    TextTheme textTheme;
    final isCustom = CustomFontLoader.instance.loadedFonts.contains(fontFamily);

    if (isCustom) {
      // 自定义字体通过 FontLoader 注册，直接用 fontFamily 名
      textTheme = theme.textTheme.apply(fontFamily: fontFamily);
    } else {
      // 尝试 Google Fonts，如果失败则当作系统字体处理
      try {
        textTheme = GoogleFonts.getTextTheme(fontFamily, theme.textTheme);
      } catch (_) {
        // Google Fonts 不存在该字体，当作系统字体直接应用
        textTheme = theme.textTheme.apply(fontFamily: fontFamily);
      }
    }

    return theme.copyWith(textTheme: textTheme);
  }
}

/// 包装层：监听窗口关闭事件 + 系统托盘管理
class _WindowWrapper extends ConsumerStatefulWidget {
  const _WindowWrapper();

  @override
  ConsumerState<_WindowWrapper> createState() => _WindowWrapperState();
}

class _WindowWrapperState extends ConsumerState<_WindowWrapper>
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
    // 首帧后再构建菜单, 确保 S.of(context) 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshTrayMenu();
    });
  }

  /// 根据当前服务器运行状态重建托盘菜单 (右键弹出前 / 切换后调用)
  Future<void> _refreshTrayMenu() async {
    if (!mounted) return;
    final s = context.s;
    final server = ref.read(apiServerProvider);
    final config = ref.read(apiServerConfigProvider).valueOrNull;
    final running = server.isRunning;
    final hasToken = (config?.token.trim().isNotEmpty) ?? false;

    final String serverLabel;
    if (running) {
      serverLabel = s.trayServerOn(server.boundPort ?? config?.port ?? 0);
    } else if (hasToken) {
      serverLabel = s.trayServerOff;
    } else {
      serverLabel = s.trayServerNeedConfig;
    }

    // 在线服务状态
    final olsServer = ref.read(onlineServerProvider);
    final olsRunning = olsServer.isRunning;
    final olsLabel = olsRunning
        ? s.trayOnlineOn(olsServer.boundPort ?? 2002)
        : s.trayOnlineOff;

    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: s.trayShow),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'toggle_server',
          label: serverLabel,
          checked: running,
          // 未配置令牌时禁用勾选 (点击会引导用户打开窗口配置)
          disabled: !running && !hasToken,
        ),
        MenuItem.checkbox(
          key: 'toggle_online',
          label: olsLabel,
          checked: olsRunning,
        ),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: s.trayExit),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// 切换对外 API 服务器的启停
  Future<void> _toggleServer() async {
    final server = ref.read(apiServerProvider);
    final notifier = ref.read(apiServerConfigProvider.notifier);
    final config = ref.read(apiServerConfigProvider).valueOrNull;
    if (config == null) return;

    if (server.isRunning) {
      // 运行中 → 停止
      await notifier.save(config.copyWith(enabled: false));
    } else {
      // 已停止 → 启动; 若缺少令牌则无法启动, 引导用户打开窗口配置
      if (config.token.trim().isEmpty) {
        await windowManager.show();
        await windowManager.focus();
      } else {
        await notifier.save(config.copyWith(enabled: true));
      }
    }
    await _refreshTrayMenu();
  }

  /// 切换在线服务的启停
  Future<void> _toggleOnlineService() async {
    final server = ref.read(onlineServerProvider);
    final notifier = ref.read(onlineServiceConfigProvider.notifier);
    final config = ref.read(onlineServiceConfigProvider).valueOrNull;
    if (config == null) return;

    if (server.isRunning) {
      await notifier.save(config.copyWith(enabled: false));
    } else {
      await notifier.save(config.copyWith(enabled: true));
    }
    await _refreshTrayMenu();
  }

  // ─── TrayListener ───

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    // 弹出前刷新, 确保勾选状态与端口号实时反映当前运行状态
    await _refreshTrayMenu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'toggle_server':
        _toggleServer();
        break;
      case 'toggle_online':
        _toggleOnlineService();
        break;
      case 'exit':
        // 这里先关闭 preventClose 再 close()，走的是"直接原生关闭"路径，
        // 不保证 onWindowClose 监听器一定会被触发去做清理，所以清理动作
        // 显式放在这里做一遍 (与 onWindowClose 里的清理逻辑重复调用是安全的，
        // disconnectAll 对已清空的状态是幂等操作)。
        _cleanupBeforeExit().whenComplete(() {
          windowManager.setPreventClose(false);
          windowManager.close();
        });
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
      await _cleanupBeforeExit();
      await trayManager.destroy();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  /// 真正退出前的收尾清理——目前主要是 MCP 连接：stdio 模式的子进程、
  /// SSE/HTTP 模式下应用代为拉起的本地进程，若不在这里显式断开，
  /// 单靠 Riverpod 容器 dispose 并不保证会在窗口关闭流程里被同步触发，
  /// 遗留下来会变成占着端口/常驻后台的僵尸进程。加超时兜底，避免某个
  /// 进程杀不掉时把整个退出流程卡住。
  Future<void> _cleanupBeforeExit() async {
    try {
      await ref
          .read(mcpConnectionsProvider.notifier)
          .disconnectAll()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.instance.log('[App] 退出前清理 MCP 连接异常(已忽略，继续退出): $e');
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
              if (_ready && _fadeIn) const FloatingPet(),
              if (_ready && _fadeIn) const PetBubble(),
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
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
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

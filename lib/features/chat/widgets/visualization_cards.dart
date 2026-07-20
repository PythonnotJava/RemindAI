import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

// 平台隔离导入：Windows 使用 webview_windows，macOS/Linux 使用 webview_flutter API
import 'package:webview_windows/webview_windows.dart' as wv;
import 'package:webview_flutter/webview_flutter.dart' as wf;

/// HTML 交互式可视化卡片（Plotly/Bokeh/ECharts 等）
/// Windows 使用 webview_windows (WebView2)
/// macOS 使用 webview_flutter (WKWebView)
/// Linux 使用 webview_all_linux (WebKitGTK)
class HtmlVisualizationCard extends StatefulWidget {
  final String htmlPath;
  final ColorScheme colorScheme;

  const HtmlVisualizationCard({
    required this.htmlPath,
    required this.colorScheme,
    super.key,
  });

  @override
  // ignore: no_logic_in_create_state
  State<HtmlVisualizationCard> createState() {
    if (Platform.isWindows) {
      return _HtmlVisualizationCardWindowsState();
    } else if (Platform.isMacOS || Platform.isLinux) {
      // macOS 和 Linux 都使用 webview_flutter API（实现不同但接口相同）
      return _HtmlVisualizationCardUnixState();
    } else {
      return _HtmlVisualizationCardUnsupportedState();
    }
  }
}

// ==================== Windows 实现（webview_windows）====================
class _HtmlVisualizationCardWindowsState extends State<HtmlVisualizationCard> {
  late final wv.WebviewController _controller;
  bool _ready = false;
  bool _failed = false;
  String? _error;
  double _height = 450;

  @override
  void initState() {
    super.initState();
    _controller = wv.WebviewController();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();
      _controller.setPopupWindowPolicy(wv.WebviewPopupWindowPolicy.deny);

      // 检查文件是否存在
      final file = File(widget.htmlPath);
      if (await file.exists()) {
        // 使用 file:// 协议加载本地文件
        final fileUrl = Uri.file(widget.htmlPath).toString();
        await _controller.loadUrl(fileUrl);

        // 等待页面加载完成后调整高度
        Future.delayed(const Duration(milliseconds: 800), _adjustHeight);
        if (mounted) setState(() => _ready = true);
      } else {
        throw Exception('HTML 文件不存在: ${widget.htmlPath}');
      }
    } catch (e) {
      print('[HtmlVisualizationCard] Windows WebView2 初始化失败: $e');
      if (mounted) {
        setState(() {
          _failed = true;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _adjustHeight() async {
    if (!_ready || !mounted) return;
    try {
      final result = await _controller.executeScript(
        'Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)',
      );
      final h = double.tryParse(result?.toString() ?? '');
      if (h != null && h > 0 && mounted) {
        setState(() => _height = h.clamp(300, 800).toDouble());
      }
    } catch (_) {}
  }

  void _openInBrowser() {
    Process.run('cmd', ['/c', 'start', '', widget.htmlPath]);
  }

  void _openInExplorer() {
    Process.run('explorer', ['/select,', widget.htmlPath]);
  }

  void _copyPath(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.htmlPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路径已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              border: Border(
                bottom: BorderSide(
                  color: widget.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  size: 20,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '交互式图表 - ${p.basename(widget.htmlPath)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 在浏览器中打开
                Tooltip(
                  message: '在浏览器中打开',
                  child: IconButton(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    onPressed: _openInBrowser,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 在文件管理器中显示
                Tooltip(
                  message: '在文件管理器中显示',
                  child: IconButton(
                    icon: const Icon(Icons.folder_open, size: 18),
                    onPressed: _openInExplorer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 复制路径
                Tooltip(
                  message: '复制路径',
                  child: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () => _copyPath(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          // WebView 内容
          if (_failed)
            Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: widget.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'WebView2 不可用，请安装 Microsoft Edge WebView2 Runtime',
                    style: TextStyle(
                      color: widget.colorScheme.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: widget.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            )
          else if (!_ready)
            Container(
              height: 450,
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                color: widget.colorScheme.primary,
              ),
            )
          else
            SizedBox(height: _height, child: wv.Webview(_controller)),
        ],
      ),
    );
  }
}

// ==================== macOS/Linux 实现（webview_flutter API）====================
// macOS 使用 webview_flutter (WKWebView)
// Linux 使用 webview_all_linux (WebKitGTK)
// 两者都实现 webview_flutter 接口，API 相同
class _HtmlVisualizationCardUnixState extends State<HtmlVisualizationCard> {
  late final wf.WebViewController _controller;
  bool _failed = false;
  String? _error;
  double _height = 450;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    try {
      _controller = wf.WebViewController()
        ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          wf.NavigationDelegate(
            onPageFinished: (url) async {
              // 获取页面高度
              final result = await _controller.runJavaScriptReturningResult(
                'Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)',
              );
              final h = double.tryParse(result.toString());
              if (h != null && h > 0 && mounted) {
                setState(() => _height = h.clamp(300, 800).toDouble());
              }
            },
            onWebResourceError: (error) {
              print(
                '[HtmlVisualizationCard] macOS WKWebView 加载失败: ${error.description}',
              );
              if (mounted) {
                setState(() {
                  _failed = true;
                  _error = error.description;
                });
              }
            },
          ),
        );

      // 加载本地文件
      final fileUrl = Uri.file(widget.htmlPath).toString();
      _controller.loadRequest(Uri.parse(fileUrl));
    } catch (e) {
      print('[HtmlVisualizationCard] macOS WebView 初始化失败: $e');
      if (mounted) {
        setState(() {
          _failed = true;
          _error = e.toString();
        });
      }
    }
  }

  void _openInBrowser() {
    if (Platform.isMacOS) {
      Process.run('open', [widget.htmlPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [widget.htmlPath]);
    }
  }

  void _openInExplorer() {
    if (Platform.isMacOS) {
      Process.run('open', ['-R', widget.htmlPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [p.dirname(widget.htmlPath)]);
    }
  }

  void _copyPath(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.htmlPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路径已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              border: Border(
                bottom: BorderSide(
                  color: widget.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  size: 20,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '交互式图表 - ${p.basename(widget.htmlPath)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 在浏览器中打开
                Tooltip(
                  message: '在浏览器中打开',
                  child: IconButton(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    onPressed: _openInBrowser,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 在文件管理器中显示
                Tooltip(
                  message: '在文件管理器中显示',
                  child: IconButton(
                    icon: const Icon(Icons.folder_open, size: 18),
                    onPressed: _openInExplorer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 复制路径
                Tooltip(
                  message: '复制路径',
                  child: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () => _copyPath(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          // WebView 内容
          if (_failed)
            Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: widget.colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'WebView 不可用',
                    style: TextStyle(
                      color: widget.colorScheme.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: widget.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            )
          else
            SizedBox(
              height: _height,
              child: wf.WebViewWidget(controller: _controller),
            ),
        ],
      ),
    );
  }
}

// ==================== Linux / 不支持平台 ====================
class _HtmlVisualizationCardUnsupportedState
    extends State<HtmlVisualizationCard> {
  void _openInBrowser() {
    if (Platform.isLinux) {
      Process.run('xdg-open', [widget.htmlPath]);
    }
  }

  void _openInExplorer() {
    if (Platform.isLinux) {
      Process.run('xdg-open', [p.dirname(widget.htmlPath)]);
    }
  }

  void _copyPath(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.htmlPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路径已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              border: Border(
                bottom: BorderSide(
                  color: widget.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bar_chart_rounded,
                  size: 20,
                  color: widget.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '交互式图表 - ${p.basename(widget.htmlPath)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: widget.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 在浏览器中打开
                Tooltip(
                  message: '在浏览器中打开',
                  child: IconButton(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    onPressed: _openInBrowser,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 在文件管理器中显示
                Tooltip(
                  message: '在文件管理器中显示',
                  child: IconButton(
                    icon: const Icon(Icons.folder_open, size: 18),
                    onPressed: _openInExplorer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 复制路径
                Tooltip(
                  message: '复制路径',
                  child: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () => _copyPath(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          // 内容
          Container(
            height: 120,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  color: widget.colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Linux 平台 WebView 支持开发中',
                  style: TextStyle(
                    color: widget.colorScheme.onSurface,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '请使用上方按钮在浏览器中打开',
                  style: TextStyle(
                    color: widget.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// SVG 矢量图可视化卡片（支持缩放）
class SvgVisualizationCard extends StatelessWidget {
  final String svgPath;
  final ColorScheme colorScheme;

  const SvgVisualizationCard({
    required this.svgPath,
    required this.colorScheme,
    super.key,
  });

  void _openInExplorer() {
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', svgPath]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', svgPath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [p.dirname(svgPath)]);
    }
  }

  void _copyPath(BuildContext context) {
    Clipboard.setData(ClipboardData(text: svgPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路径已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(p.basename(svgPath)),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.1,
            maxScale: 10.0,
            child: Center(
              child: SvgPicture.file(File(svgPath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '矢量图 - ${p.basename(svgPath)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 全屏查看
                Tooltip(
                  message: '全屏查看',
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen, size: 18),
                    onPressed: () => _showFullscreen(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 在文件管理器中显示
                Tooltip(
                  message: '在文件管理器中显示',
                  child: IconButton(
                    icon: const Icon(Icons.folder_open, size: 18),
                    onPressed: _openInExplorer,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // 复制路径
                Tooltip(
                  message: '复制路径',
                  child: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () => _copyPath(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          // SVG 内容（支持缩放）
          Container(
            height: 400,
            color: colorScheme.surfaceContainer.withValues(alpha: 0.3),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: SvgPicture.file(
                  File(svgPath),
                  fit: BoxFit.contain,
                  placeholderBuilder: (context) => Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

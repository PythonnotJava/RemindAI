import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

import '../../features/chat/widgets/message_bubble.dart';
import '../l10n/l10n_ext.dart';
import '../llm/models.dart';
import '../logger/app_logger.dart';

/// 把整段对话渲染成"长截图"（一张或按高度拆成多张 PNG）。
///
/// 和 [ConversationExporter] 的 md / pdf / docx / html 四条路互不影响：那四条
/// 走 Markdown + pandoc，这里直接用 Flutter 自己的渲染管线出图。
///
/// 三个关键设计：
/// 1. **不复用聊天页的 ListView**。`ListView.builder` 只构建可见项，屏幕外的
///    消息根本不在 widget 树里，套 `RepaintBoundary` 也只能截一屏。这里用
///    `Column` 把全部消息铺开，放进一个 0×0 的离屏容器里排版并绘制。
/// 2. **按块栅格化**。整页可能高达成万逻辑像素，一次性 `toImage` 会撞 GPU
///    纹理上限（常见 16384）。这里每个"块"（页眉/每条消息/页脚）各自是一个
///    `RepaintBoundary`，单独 `toImage`；再按 [maxPageHeight] 把块拼成"页"，
///    逐页落盘并立刻释放，内存峰值只有一页。
/// 3. **平台视图要绕开**。HTML 可视化卡是 WebView2 原生控件，不经过 Flutter
///    光栅管线，截出来必然是空白。所以给气泡喂一份去掉了 `htmlFiles` 的消息
///    副本，再自己画一张占位卡，不去改 `visualization_cards.dart`。
class ConversationImageExporter {
  ConversationImageExporter._();

  /// 导出画布的逻辑宽度。固定宽度保证不同窗口尺寸下产出稳定。
  static const double canvasWidth = 1000;

  /// 单张图片的最大逻辑高度，超过就自动拆成多张。
  static const double maxPageHeight = 5000;

  /// 单个块允许占用的最大像素高度（留出纹理上限余量）。
  static const double _maxBlockPixels = 14000;

  /// 输出像素倍率（画布逻辑尺寸 × 该倍率 = 图片像素尺寸）。
  static const double _pixelRatio = 2.0;

  /// 显示进度对话框并导出。
  ///
  /// 返回保存的文件路径列表（多张时按顺序），用户取消或失败返回 null。
  static Future<List<String>?> export({
    required BuildContext context,
    required List<ChatMessage> messages,
    required String title,
  }) async {
    // 先抓住 context 的派生对象，后面跨 await 就不再碰 context。
    final s = context.s;
    final messenger = ScaffoldMessenger.of(context);

    if (messages.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.exportLongImageEmpty)));
      return null;
    }

    // 先让用户选保存位置：取消时不必经历"进度条闪一下再消失"。
    final basePath = await FilePicker.platform.saveFile(
      dialogTitle: s.exportSaveTitle,
      fileName: '${_safeFileName(title)}.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (basePath == null) return null; // 用户取消
    // 原生保存对话框是异步的：之后还要用 context（Overlay / 进度框 / 预加载）。
    if (!context.mounted) return null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final headerKey = GlobalKey();
    final footerKey = GlobalKey();
    final bubbleKeys = List<GlobalKey>.generate(
      messages.length,
      (_) => GlobalKey(),
    );
    final progress = ValueNotifier<String>(s.exportLongImagePreparing);

    BuildContext? dialogCtx;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          return _ProgressDialog(message: progress);
        },
      ),
    );

    OverlayEntry? entry;
    try {
      // 附件图片先解码进 image cache，否则首帧截到的是空白框。
      await _precacheImages(context, messages);

      entry = _buildOverlayEntry(
        headerKey: headerKey,
        footerKey: footerKey,
        bubbleKeys: bubbleKeys,
        messages: messages,
        title: title,
      );
      overlay.insert(entry);

      // 等布局 + 绘制稳定（列排版、Markdown、代码高亮、图片上屏）。
      await _settle();

      // 块顺序必须与视觉顺序一致：页眉 → 各条消息 → 页脚。
      final blocks = <GlobalKey>[headerKey, ...bubbleKeys, footerKey];
      final heights = <double>[];
      final renderers = <RenderRepaintBoundary>[];
      for (final key in blocks) {
        final render =
            key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (render == null) {
          throw StateError('长截图离屏渲染未就绪（块渲染对象为空）');
        }
        // 空消息块高度为 0：`toImage` 不接受 0 尺寸，直接跳过（也不占页高）。
        if (render.size.height < 1) continue;
        renderers.add(render);
        heights.add(render.size.height);
      }
      if (renderers.isEmpty) {
        throw StateError('长截图没有可渲染的内容');
      }

      final pageIndexes = splitImagePages(heights);

      final saved = <String>[];
      for (var page = 0; page < pageIndexes.length; page++) {
        progress.value = s.exportLongImageProgress(page + 1, pageIndexes.length);
        // 同一页内所有块用同一个倍率，否则拼图时宽度会对不齐。
        final pageRatio = _ratioFor(
          pageIndexes[page].map((i) => heights[i]).reduce(math.max),
        );
        final bytes = await _renderPage(
          renderers: renderers,
          indexes: pageIndexes[page],
          pixelRatio: pageRatio,
        );
        final path = pageIndexes.length == 1
            ? basePath
            : _partPath(basePath, page + 1);
        await File(path).writeAsBytes(bytes, flush: true);
        saved.add(path);
        AppLogger.instance.log(
          '[LongImage] 已写出第 ${page + 1}/${pageIndexes.length} 张: $path '
          '(${(bytes.length / 1024).toStringAsFixed(0)} KB)',
        );
      }
      return saved;
    } catch (e) {
      AppLogger.instance.log('[LongImage] 导出失败: $e');
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${s.exportFailed(s.exportLongImageFormat)}: $e'),
          ),
        );
      }
      return null;
    } finally {
      entry?.remove();
      entry?.dispose();
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.of(dialogCtx!).pop();
      }
      // 不 dispose progress：对话框可能还要在下一帧走一次移除流程，
      // 提前释放会撞 "used after being disposed"。它是纯本地小对象，交给 GC。
    }
  }

  // ─── 离屏挂载 ────────────────────────────────────────────────

  /// 把导出内容挂到一个 0×0、被裁剪掉、不接收手势的离屏位置。
  ///
  /// 为什么不是 `Offstage`：`Offstage` 不参与绘制，内部 `RepaintBoundary`
  /// 的图层会是空的。这里用 `ClipRect + OverflowBox` —— 子节点照常完成布局
  /// 和绘制（图层内容完整），只是被父级裁成不可见。
  static OverlayEntry _buildOverlayEntry({
    required GlobalKey headerKey,
    required GlobalKey footerKey,
    required List<GlobalKey> bubbleKeys,
    required List<ChatMessage> messages,
    required String title,
  }) {
    return OverlayEntry(
      builder: (context) {
        // 让气泡按导出画布而不是真实窗口宽度计算最大宽度
        // （`MessageBubble` 用的是 `MediaQuery.size.width * 0.72`）。
        final media = MediaQuery.of(context);
        return Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: ClipRect(
              child: SizedBox(
                width: 0,
                height: 0,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: MediaQuery(
                    data: media.copyWith(
                      size: const Size(canvasWidth, 1200),
                    ),
                    child: ConversationImagePage(
                      headerKey: headerKey,
                      footerKey: footerKey,
                      bubbleKeys: bubbleKeys,
                      messages: messages,
                      title: title,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 拍照前等几帧，让排版尺寸稳定。
  static Future<void> _settle() async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;
  }

  static Future<void> _precacheImages(
    BuildContext context,
    List<ChatMessage> messages,
  ) async {
    for (final message in messages) {
      for (final attachment in message.attachments) {
        if (!attachment.isImage) continue;
        try {
          await precacheImage(FileImage(File(attachment.path)), context);
        } catch (e) {
          // 附件丢了/坏了不该让整次导出失败，气泡里会显示它自己的错误态。
          AppLogger.instance.log('[LongImage] 附件预加载失败(忽略): $e');
        }
      }
    }
  }

  // ─── 分页 ────────────────────────────────────────────────────

  /// 把连续块按高度装进若干页，切点永远落在块之间（不会把一条消息劈开）。
  ///
  /// 单块自身超过 [maxHeight] 时独占一页，靠 [_ratioFor] 降低倍率来兼容。
  ///
  /// 公开是为了单测能直接验证分页边界（不涉及渲染）。
  static List<List<int>> splitImagePages(
    List<double> heights, {
    double maxHeight = maxPageHeight,
  }) {
    final pages = <List<int>>[];
    var current = <int>[];
    var accumulated = 0.0;
    for (var i = 0; i < heights.length; i++) {
      final h = heights[i];
      if (current.isNotEmpty && accumulated + h > maxHeight) {
        pages.add(current);
        current = <int>[];
        accumulated = 0;
      }
      current.add(i);
      accumulated += h;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  /// 为某个块挑一个像素倍率：保证单块不超过纹理上限。
  static double _ratioFor(double logicalHeight) {
    if (logicalHeight <= 0) return _pixelRatio;
    final fit = _maxBlockPixels / logicalHeight;
    return math.min(_pixelRatio, math.max(0.5, fit));
  }

  // ─── 栅格化与合成 ────────────────────────────────────────────

  /// 把一页里的块逐块栅格化后纵向拼接成 PNG 字节。
  ///
  /// 这一页画完立刻释放所有块图像，内存不随对话长度线性增长。
  static Future<Uint8List> _renderPage({
    required List<RenderRepaintBoundary> renderers,
    required List<int> indexes,
    required double pixelRatio,
  }) async {
    final images = <ui.Image>[];
    try {
      for (final index in indexes) {
        images.add(
          await renderers[index].toImage(pixelRatio: pixelRatio),
        );
      }
      if (images.isEmpty) throw StateError('长截图分页为空');

      var widthPx = 0;
      var heightPx = 0;
      for (final image in images) {
        widthPx = math.max(widthPx, image.width);
        heightPx += image.height;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      var dy = 0.0;
      for (final image in images) {
        canvas.drawImage(image, Offset(0, dy), Paint());
        dy += image.height.toDouble();
      }
      final picture = recorder.endRecording();
      final composed = await picture.toImage(widthPx, heightPx);
      picture.dispose();
      try {
        final data = await composed.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('PNG 编码失败');
        return data.buffer.asUint8List();
      } finally {
        composed.dispose();
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }

  // ─── 杂项 ────────────────────────────────────────────────────

  static String _safeFileName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
    final trimmed = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
    return trimmed.isEmpty ? 'conversation' : trimmed;
  }

  static String _partPath(String base, int index) {
    final ext = p.extension(base);
    if (ext.isEmpty) return '${base}_$index.png';
    final stem = base.substring(0, base.length - ext.length);
    return '${stem}_$index$ext';
  }
}

// ─── 导出内容（离屏渲染的真实树）────────────────────────────────

/// 长截图的"整页内容"：页眉 + 每条消息 + 页脚。
///
/// 只应由 [ConversationImageExporter] 在离屏 Overlay 里使用；对外可见是为了
/// 让 widget 测试能直接验证"气泡隐藏操作按钮 / HTML 占位卡"这些渲染行为。
class ConversationImagePage extends StatelessWidget {
  const ConversationImagePage({
    super.key,
    required this.headerKey,
    required this.footerKey,
    required this.bubbleKeys,
    required this.messages,
    required this.title,
  });

  final GlobalKey headerKey;
  final GlobalKey footerKey;
  final List<GlobalKey> bubbleKeys;
  final List<ChatMessage> messages;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final exportedAt = DateTime.now();

    return Material(
      color: colorScheme.surface,
      child: SizedBox(
        width: ConversationImageExporter.canvasWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(
              key: headerKey,
              child: _header(colorScheme, exportedAt),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            for (var i = 0; i < messages.length; i++)
              RepaintBoundary(
                key: bubbleKeys[i],
                child: _messageBlock(messages[i]),
              ),
            RepaintBoundary(
              key: footerKey,
              child: _footer(colorScheme, exportedAt),
            ),
          ],
        ),
      ),
    );
  }

  /// 单条消息：气泡（去掉平台视图、隐藏操作按钮）+ 自己画的 HTML 占位卡。
  Widget _messageBlock(ChatMessage message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBubble(
          message: _stripPlatformViews(message),
          showActions: false,
        ),
        for (final htmlPath in message.htmlFiles)
          _HtmlCardPlaceholder(path: htmlPath),
      ],
    );
  }

  Widget _header(ColorScheme colorScheme, DateTime exportedAt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Remind AI',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                _timestamp(exportedAt),
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme colorScheme, DateTime exportedAt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Row(
        children: [
          Text(
            'Remind AI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _timestamp(exportedAt),
            style: TextStyle(fontSize: 11, color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

/// 去掉会挡住截图的平台视图（HTML 卡是 WebView2 原生控件）。
///
/// 不动 `visualization_cards.dart`：这里复制一份消息，把 `htmlFiles` 清空，
/// 由 [_HtmlCardPlaceholder] 画一张说明卡。SVG（`SvgPicture`）和视频占位
/// 都是纯 Flutter 绘制，可以正常进图，原样保留。
ChatMessage _stripPlatformViews(ChatMessage message) {
  if (message.htmlFiles.isEmpty) return message;
  return ChatMessage(
    role: message.role,
    content: message.content,
    toolCalls: message.toolCalls,
    toolCallId: message.toolCallId,
    timestamp: message.timestamp,
    attachments: message.attachments,
    interrupted: message.interrupted,
    thinkingContent: message.thinkingContent,
    htmlFiles: const [],
    svgFiles: message.svgFiles,
    videoFiles: message.videoFiles,
  );
}

class _HtmlCardPlaceholder extends StatelessWidget {
  const _HtmlCardPlaceholder({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = p.basename(path);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.s.exportLongImageHtmlCard,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final ValueListenable<String> message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: message,
              builder: (context, value, child) => Text(value),
            ),
          ),
        ],
      ),
    );
  }
}

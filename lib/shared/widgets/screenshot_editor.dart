import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 截图标注工具类型
enum AnnotationTool { pen, rect, circle, arrow, text }

/// 单个标注动作
class DrawAction {
  final AnnotationTool tool;
  final Color color;
  final double strokeWidth;
  // Pen: 点列表
  final List<Offset> points;
  // Rect/Circle/Arrow: 起止点
  final Offset? start;
  final Offset? end;
  // Text: 位置 + 内容
  final Offset? textPosition;
  final String? textContent;

  DrawAction({
    required this.tool,
    required this.color,
    required this.strokeWidth,
    this.points = const [],
    this.start,
    this.end,
    this.textPosition,
    this.textContent,
  });

  DrawAction copyWith({
    List<Offset>? points,
    Offset? start,
    Offset? end,
    Offset? textPosition,
    String? textContent,
  }) {
    return DrawAction(
      tool: tool,
      color: color,
      strokeWidth: strokeWidth,
      points: points ?? this.points,
      start: start ?? this.start,
      end: end ?? this.end,
      textPosition: textPosition ?? this.textPosition,
      textContent: textContent ?? this.textContent,
    );
  }
}

/// 截图编辑器对话框
class ScreenshotEditor extends StatefulWidget {
  final ui.Image image;
  const ScreenshotEditor({super.key, required this.image});

  /// 显示编辑器对话框，返回 true 表示已保存/复制
  static Future<bool> show(BuildContext context, ui.Image image) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScreenshotEditor(image: image),
    );
    return result ?? false;
  }

  @override
  State<ScreenshotEditor> createState() => _ScreenshotEditorState();
}

class _ScreenshotEditorState extends State<ScreenshotEditor> {
  AnnotationTool _currentTool = AnnotationTool.pen;
  Color _currentColor = Colors.red;
  double _currentStrokeWidth = 3.0;

  final List<DrawAction> _actions = [];
  final List<DrawAction> _redoStack = [];

  // 当前正在绘制的动作
  DrawAction? _currentAction;

  // 文本输入相关
  final _textController = TextEditingController();
  Offset? _pendingTextPosition;

  static const _colorPresets = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.white,
    Colors.black,
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
// CONTINUE_2

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.82;
    final dialogHeight = screenSize.height * 0.85;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // 工具栏
            _buildToolbar(context),
            const Divider(height: 1),
            // 画布区域
            Expanded(child: _buildCanvas()),
            const Divider(height: 1),
            // 底部按钮
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 工具按钮
          _toolBtn(AnnotationTool.pen, Icons.edit, '画笔'),
          _toolBtn(AnnotationTool.rect, Icons.crop_square, '矩形'),
          _toolBtn(AnnotationTool.circle, Icons.circle_outlined, '椭圆'),
          _toolBtn(AnnotationTool.arrow, Icons.arrow_forward, '箭头'),
          _toolBtn(AnnotationTool.text, Icons.text_fields, '文本'),
          const SizedBox(width: 12),
          // 分隔
          Container(width: 1, height: 24, color: colorScheme.outlineVariant),
          const SizedBox(width: 12),
          // 颜色选择
          ..._colorPresets.map((c) => _colorBtn(c)),
          const SizedBox(width: 12),
          Container(width: 1, height: 24, color: colorScheme.outlineVariant),
          const SizedBox(width: 12),
// CONTINUE_3
          // 线宽
          const Text('粗细', style: TextStyle(fontSize: 12)),
          SizedBox(
            width: 100,
            child: Slider(
              value: _currentStrokeWidth,
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) => setState(() => _currentStrokeWidth = v),
            ),
          ),
          const Spacer(),
          // 撤销/重做
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            tooltip: '撤销 (Ctrl+Z)',
            onPressed: _actions.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            tooltip: '重做 (Ctrl+Y)',
            onPressed: _redoStack.isEmpty ? null : _redo,
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(AnnotationTool tool, IconData icon, String tooltip) {
    final selected = _currentTool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _currentTool = tool),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 20,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : null),
          ),
        ),
      ),
    );
  }
// CONTINUE_4

  Widget _colorBtn(Color color) {
    final selected = _currentColor == color;
    return GestureDetector(
      onTap: () => setState(() => _currentColor = color),
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
      },
      child: Focus(
        autofocus: true,
        child: ClipRect(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onTapUp: _onTapUp,
            child: CustomPaint(
              painter: _EditorPainter(
                image: widget.image,
                actions: _actions,
                currentAction: _currentAction,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
// CONTINUE_5
          FilledButton.icon(
            onPressed: _saveAs,
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('另存为'),
          ),
        ],
      ),
    );
  }

  // ─── 绘图交互 ───

  void _onPanStart(DragStartDetails details) {
    if (_currentTool == AnnotationTool.text) return;

    final action = DrawAction(
      tool: _currentTool,
      color: _currentColor,
      strokeWidth: _currentStrokeWidth,
      points: _currentTool == AnnotationTool.pen
          ? [details.localPosition]
          : [],
      start: details.localPosition,
      end: details.localPosition,
    );
    setState(() {
      _currentAction = action;
      _redoStack.clear();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentAction == null) return;

    setState(() {
      if (_currentTool == AnnotationTool.pen) {
        _currentAction = _currentAction!.copyWith(
          points: [..._currentAction!.points, details.localPosition],
        );
      } else {
        _currentAction = _currentAction!.copyWith(end: details.localPosition);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentAction == null) return;
    setState(() {
      _actions.add(_currentAction!);
      _currentAction = null;
    });
  }
// CONTINUE_6

  void _onTapUp(TapUpDetails details) {
    if (_currentTool != AnnotationTool.text) return;

    setState(() => _pendingTextPosition = details.localPosition);
    _textController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入文本'),
        content: TextField(
          controller: _textController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入标注文本...'),
          onSubmitted: (_) => _confirmText(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _confirmText(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmText(BuildContext ctx) {
    final text = _textController.text.trim();
    if (text.isNotEmpty && _pendingTextPosition != null) {
      setState(() {
        _actions.add(DrawAction(
          tool: AnnotationTool.text,
          color: _currentColor,
          strokeWidth: _currentStrokeWidth,
          textPosition: _pendingTextPosition,
          textContent: text,
        ));
        _redoStack.clear();
      });
    }
    Navigator.of(ctx).pop();
  }

  void _undo() {
    if (_actions.isEmpty) return;
    setState(() {
      _redoStack.add(_actions.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _actions.add(_redoStack.removeLast());
    });
  }
// CONTINUE_7

  // ─── 导出 ───

  Future<ui.Image> _renderFinalImage() async {
    final w = widget.image.width.toDouble();
    final h = widget.image.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 画底图
    canvas.drawImage(widget.image, Offset.zero, Paint());

    // 计算画布到原图的缩放比
    final renderBox = context.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? Size(w, h);
    final scaleX = w / canvasSize.width;
    final scaleY = h / canvasSize.height;

    // 画标注
    for (final action in _actions) {
      _drawAction(canvas, action, scaleX, scaleY);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.round(), h.round());
    picture.dispose();
    return image;
  }

  void _drawAction(Canvas canvas, DrawAction action, double sx, double sy) {
    final paint = Paint()
      ..color = action.color
      ..strokeWidth = action.strokeWidth * sx
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (action.tool) {
      case AnnotationTool.pen:
        if (action.points.length < 2) break;
        final path = Path();
        path.moveTo(action.points[0].dx * sx, action.points[0].dy * sy);
        for (int i = 1; i < action.points.length; i++) {
          path.lineTo(action.points[i].dx * sx, action.points[i].dy * sy);
        }
        canvas.drawPath(path, paint);
        break;
      case AnnotationTool.rect:
        if (action.start == null || action.end == null) break;
        canvas.drawRect(
          Rect.fromPoints(
            Offset(action.start!.dx * sx, action.start!.dy * sy),
            Offset(action.end!.dx * sx, action.end!.dy * sy),
          ),
          paint,
        );
        break;
// CONTINUE_8
      case AnnotationTool.circle:
        if (action.start == null || action.end == null) break;
        canvas.drawOval(
          Rect.fromPoints(
            Offset(action.start!.dx * sx, action.start!.dy * sy),
            Offset(action.end!.dx * sx, action.end!.dy * sy),
          ),
          paint,
        );
        break;
      case AnnotationTool.arrow:
        if (action.start == null || action.end == null) break;
        final s = Offset(action.start!.dx * sx, action.start!.dy * sy);
        final e = Offset(action.end!.dx * sx, action.end!.dy * sy);
        canvas.drawLine(s, e, paint);
        // 箭头头部
        final angle = (e - s).direction;
        const headLen = 16.0;
        final p1 = e - Offset.fromDirection(angle - 0.5, headLen * sx);
        final p2 = e - Offset.fromDirection(angle + 0.5, headLen * sx);
        canvas.drawLine(e, p1, paint);
        canvas.drawLine(e, p2, paint);
        break;
      case AnnotationTool.text:
        if (action.textPosition == null || action.textContent == null) break;
        final tp = TextPainter(
          text: TextSpan(
            text: action.textContent,
            style: TextStyle(
              color: action.color,
              fontSize: 16 * sx,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(
          action.textPosition!.dx * sx,
          action.textPosition!.dy * sy,
        ));
        break;
    }
  }

  Future<void> _saveAs() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存截图',
      fileName: 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    if (result == null) return;

    final image = await _renderFinalImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
// CONTINUE_9

    final file = File(result.endsWith('.png') ? result : '$result.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

/// 标注画布 Painter
class _EditorPainter extends CustomPainter {
  final ui.Image image;
  final List<DrawAction> actions;
  final DrawAction? currentAction;

  _EditorPainter({
    required this.image,
    required this.actions,
    this.currentAction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制底图（适配画布大小）
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, Paint());

    // 绘制所有标注
    for (final action in actions) {
      _paintAction(canvas, action, size);
    }
    // 绘制正在进行的标注
    if (currentAction != null) {
      _paintAction(canvas, currentAction!, size);
    }
  }
// CONTINUE_10

  void _paintAction(Canvas canvas, DrawAction action, Size size) {
    final paint = Paint()
      ..color = action.color
      ..strokeWidth = action.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (action.tool) {
      case AnnotationTool.pen:
        if (action.points.length < 2) break;
        final path = Path();
        path.moveTo(action.points[0].dx, action.points[0].dy);
        for (int i = 1; i < action.points.length; i++) {
          path.lineTo(action.points[i].dx, action.points[i].dy);
        }
        canvas.drawPath(path, paint);
        break;
      case AnnotationTool.rect:
        if (action.start == null || action.end == null) break;
        canvas.drawRect(Rect.fromPoints(action.start!, action.end!), paint);
        break;
      case AnnotationTool.circle:
        if (action.start == null || action.end == null) break;
        canvas.drawOval(Rect.fromPoints(action.start!, action.end!), paint);
        break;
      case AnnotationTool.arrow:
        if (action.start == null || action.end == null) break;
        canvas.drawLine(action.start!, action.end!, paint);
        final angle = (action.end! - action.start!).direction;
        const headLen = 14.0;
        final p1 = action.end! - Offset.fromDirection(angle - 0.5, headLen);
        final p2 = action.end! - Offset.fromDirection(angle + 0.5, headLen);
        canvas.drawLine(action.end!, p1, paint);
        canvas.drawLine(action.end!, p2, paint);
        break;
      case AnnotationTool.text:
        if (action.textPosition == null || action.textContent == null) break;
        final tp = TextPainter(
          text: TextSpan(
            text: action.textContent,
            style: TextStyle(
              color: action.color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, action.textPosition!);
        break;
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) => true;
}


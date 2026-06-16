import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../core/l10n/l10n_ext.dart';
import 'flowchart_models.dart';

const _uuid = Uuid();

/// 预设配色方案
const _presetColors = [
  Color(0xFF42A5F5), // 蓝
  Color(0xFF66BB6A), // 绿
  Color(0xFFFF7043), // 橙
  Color(0xFFAB47BC), // 紫
  Color(0xFFEF5350), // 红
  Color(0xFF26C6DA), // 青
  Color(0xFFFFA726), // 黄
  Color(0xFF78909C), // 灰蓝
  Color(0xFFEC407A), // 粉
  Color(0xFF8D6E63), // 棕
];

class FlowchartEditorPage extends StatefulWidget {
  const FlowchartEditorPage({super.key});

  @override
  State<FlowchartEditorPage> createState() => _FlowchartEditorPageState();
}

class _FlowchartEditorPageState extends State<FlowchartEditorPage> {
  late final NodeFlowController<FcNodeData, dynamic> _controller;
  final GlobalKey _repaintKey = GlobalKey();
  String _currentFile = '';
  bool _dirty = false;
  String _status = '';
  FcNodeShape _selectedShape = FcNodeShape.rect;
  Color _selectedColor = _presetColors[0];
  bool _showGrid = true;

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<FcNodeData, dynamic>(
      config: NodeFlowConfig(showAttribution: false),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  // ─── 节点操作 ───

  /// 每个节点端口 ID 必须全局唯一，且避免 PortType.both（会重复渲染）
  /// 每个方向放一个 input + 一个 output 端口
  List<Port> _makePorts(String nodeId) => [
    Port(
      id: '${nodeId}_top_in',
      name: '',
      position: PortPosition.top,
      type: PortType.input,
    ),
    Port(
      id: '${nodeId}_top_out',
      name: '',
      position: PortPosition.top,
      type: PortType.output,
    ),
    Port(
      id: '${nodeId}_bottom_in',
      name: '',
      position: PortPosition.bottom,
      type: PortType.input,
    ),
    Port(
      id: '${nodeId}_bottom_out',
      name: '',
      position: PortPosition.bottom,
      type: PortType.output,
    ),
    Port(
      id: '${nodeId}_left_in',
      name: '',
      position: PortPosition.left,
      type: PortType.input,
    ),
    Port(
      id: '${nodeId}_left_out',
      name: '',
      position: PortPosition.left,
      type: PortType.output,
    ),
    Port(
      id: '${nodeId}_right_in',
      name: '',
      position: PortPosition.right,
      type: PortType.input,
    ),
    Port(
      id: '${nodeId}_right_out',
      name: '',
      position: PortPosition.right,
      type: PortType.output,
    ),
  ];

  void _addNode([Offset? position]) {
    final id = _uuid.v4();
    final node = Node<FcNodeData>(
      id: id,
      type: _selectedShape.name,
      position: position ?? Offset(150 + (_controller.nodeCount * 30.0), 200),
      data: FcNodeData(
        shape: _selectedShape,
        text: _selectedShape.label,
        color: _selectedColor,
      ),
      ports: _makePorts(id),
    );
    _controller.addNode(node);
    setState(() => _dirty = true);
  }

  void _editNode(Node<FcNodeData> node) {
    showDialog(
      context: context,
      builder: (ctx) => _NodeEditDialog(
        data: node.data,
        currentSize: node.size.value,
        onSave: (newData, newSize) {
          _controller.removeNode(node.id);
          _controller.addNode(
            Node<FcNodeData>(
              id: node.id,
              type: newData.shape.name,
              position: node.position.value,
              data: newData,
              ports: node.ports,
              size: newSize,
            ),
          );
          setState(() => _dirty = true);
        },
      ),
    );
  }

  // ─── 文件操作 ───

  /// 如果有未保存的修改，提示用户是否保存。返回 true 表示可以继续操作。
  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.fcUnsavedTitle),
        content: Text(context.s.fcUnsavedContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(1),
            child: Text(context.s.fcDontSave),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(2),
            child: Text(context.s.commonSave),
          ),
        ],
      ),
    );
    if (result == null || result == 0) return false;
    if (result == 2) await _save();
    return true;
  }

  Future<void> _save() async {
    if (_currentFile.isNotEmpty) {
      await _saveToFile(_currentFile);
      return;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.s.fcSaveTitle,
      fileName: context.s.fcDefaultFilename,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    final path = result.endsWith('.fc.json') ? result : '$result.fc.json';
    await _saveToFile(path);
  }

  Future<void> _saveToFile(String path) async {
    try {
      final graph = _controller.exportGraph();
      final nodes = <Map<String, dynamic>>[];
      for (final id in _controller.nodeIds) {
        final node = _controller.getNode(id);
        if (node == null) continue;
        nodes.add({
          'id': node.id,
          'type': node.type,
          'x': node.position.value.dx,
          'y': node.position.value.dy,
          'data': node.data.toJson(),
        });
      }
      final connections = <Map<String, dynamic>>[];
      for (final conn in graph.connections) {
        connections.add({
          'id': conn.id,
          'sourceNodeId': conn.sourceNodeId,
          'sourcePortId': conn.sourcePortId,
          'targetNodeId': conn.targetNodeId,
          'targetPortId': conn.targetPortId,
        });
      }
      final json = const JsonEncoder.withIndent(
        '  ',
      ).convert({'version': 1, 'nodes': nodes, 'connections': connections});
      await File(path).writeAsString(json);
      if (!mounted) return;
      setState(() {
        _currentFile = path;
        _dirty = false;
        _status = context.s.fcSaved(p.basename(path));
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context.s.fcSaveFailed(e.toString()));
    }
  }

  Future<void> _load() async {
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.fcOpenTitle,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _loadFromJson(data);
      if (!mounted) return;
      setState(() {
        _currentFile = path;
        _dirty = false;
        _status = context.s.fcOpened(p.basename(path));
      });
    } catch (e) {
      if (!mounted) return;
      _snack(context.s.fcOpenFailed(e.toString()));
    }
  }

  void _loadFromJson(Map<String, dynamic> data) {
    _controller.clearGraph();
    final nodes = (data['nodes'] as List?) ?? [];
    final connections = (data['connections'] as List?) ?? [];

    final nodeList = <Node<FcNodeData>>[];
    for (final n in nodes) {
      final nodeId = n['id'] as String;
      nodeList.add(
        Node<FcNodeData>(
          id: nodeId,
          type: n['type'] as String,
          position: Offset(
            (n['x'] as num).toDouble(),
            (n['y'] as num).toDouble(),
          ),
          data: FcNodeData.fromJson(n['data'] as Map<String, dynamic>),
          ports: _makePorts(nodeId),
        ),
      );
    }

    final connList = <Connection<dynamic>>[];
    for (final c in connections) {
      connList.add(
        Connection<dynamic>(
          id: c['id'] as String,
          sourceNodeId: c['sourceNodeId'] as String,
          sourcePortId: c['sourcePortId'] as String,
          targetNodeId: c['targetNodeId'] as String,
          targetPortId: c['targetPortId'] as String,
        ),
      );
    }

    _controller.loadGraph(
      NodeGraph<FcNodeData, dynamic>(nodes: nodeList, connections: connList),
    );
  }

  Future<void> _newChart() async {
    if (!await _confirmDiscardIfDirty()) return;
    _controller.clearGraph();
    setState(() {
      _currentFile = '';
      _dirty = false;
      _status = context.s.fcNewChart;
    });
  }

  // ─── 导出图片 ───

  Future<void> _exportImage() async {
    if (!mounted) return;

    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack(context.s.fcCanvasNotReady);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (byteData == null) {
        _snack(context.s.fcImageFailed);
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();

      final result = await FilePicker.platform.saveFile(
        dialogTitle: context.s.fcExportPng,
        fileName: 'flowchart.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      if (result == null) return;
      final outPath = result.endsWith('.png') ? result : '$result.png';
      await File(outPath).writeAsBytes(pngBytes);
      if (!mounted) return;
      _snack(context.s.fcExported(p.basename(outPath)));
    } catch (e) {
      if (!mounted) return;
      _snack(context.s.fcExportFailed(e.toString()));
    }
  }

  // ─── UI 辅助 ───

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // 左侧工具面板
          _buildToolPanel(colorScheme),
          const VerticalDivider(width: 1),
          // 主画布
          Expanded(
            child: Column(
              children: [
                _buildTopBar(colorScheme),
                const Divider(height: 1),
                Expanded(
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: NodeFlowEditor<FcNodeData, dynamic>(
                      controller: _controller,
                      theme: _buildTheme(isDark),
                      nodeBuilder: _buildNode,
                      nodeShapeBuilder: _buildNodeShape,
                      events: NodeFlowEvents(
                        node: NodeEvents(
                          onDoubleTap: (node) => _editNode(node),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildBottomBar(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ColorScheme cs) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.surface,
      child: Row(
        children: [
          _btn(Icons.add, context.s.fcBtnNew, _newChart),
          _btn(Icons.folder_open, context.s.fcBtnOpen, _load),
          _btn(Icons.save, context.s.fcBtnSave, _save),
          const VerticalDivider(indent: 8, endIndent: 8),
          _btn(Icons.image_outlined, context.s.fcBtnExportImage, _exportImage),
          const Spacer(),
          _btn(
            _showGrid ? Icons.grid_on : Icons.grid_off,
            _showGrid ? context.s.fcBtnHideGrid : context.s.fcBtnShowGrid,
            () => setState(() => _showGrid = !_showGrid),
          ),
          _btn(
            Icons.center_focus_strong,
            context.s.fcBtnFitCanvas,
            () => _controller.fitToView(),
          ),
          _btn(
            Icons.select_all,
            context.s.fcBtnSelectAll,
            () => _controller.selectAllNodes(),
          ),
          _btn(Icons.delete_outline, context.s.fcBtnDeleteSelected, () {
            final ids = _controller.selectedNodeIds.toList();
            if (ids.isNotEmpty) {
              _controller.deleteNodes(ids);
              setState(() => _dirty = true);
            }
          }),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          if (_dirty) const Icon(Icons.circle, size: 8, color: Colors.orange),
          if (_dirty) const SizedBox(width: 6),
          Text(
            _status.isNotEmpty ? _status : context.s.fcStatusReady,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          Text(
            context.s.fcStatusNodes(_controller.nodeCount, 0),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 左侧工具面板 ───

  void _pickCustomColor() async {
    final hexCtrl = TextEditingController(
      text:
          '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
    );
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.fcCustomColor),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hexCtrl,
              decoration: const InputDecoration(
                labelText: 'HEX 颜色码',
                hintText: '#FF5722',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // 快速预览
            StatefulBuilder(
              builder: (ctx2, setInner) {
                Color preview = _selectedColor;
                try {
                  final hex = hexCtrl.text.replaceFirst('#', '');
                  if (hex.length == 6) {
                    preview = Color(int.parse('FF$hex', radix: 16));
                  }
                } catch (_) {}
                hexCtrl.addListener(() => setInner(() {}));
                return Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              try {
                final hex = hexCtrl.text.replaceFirst('#', '');
                if (hex.length == 6) {
                  Navigator.of(ctx).pop(Color(int.parse('FF$hex', radix: 16)));
                }
              } catch (_) {
                Navigator.of(ctx).pop(null);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _selectedColor = result);
    }
  }

  Widget _buildToolPanel(ColorScheme cs) {
    return SizedBox(
      width: 170,
      child: Material(
        color: cs.surface,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              context.s.fcClickToAdd,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: FcNodeShape.values.map((shape) {
                return Tooltip(
                  message: shape.localizedLabel(context),
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedShape = shape);
                      _addNode(); // 点击直接添加
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        shape.icon,
                        size: 20,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              context.s.fcNodeColor,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ..._presetColors.map((color) {
                  final selected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: cs.onSurface, width: 2.5)
                            : null,
                      ),
                    ),
                  );
                }),
                // 自定义颜色按钮
                GestureDetector(
                  onTap: _pickCustomColor,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      Icons.colorize,
                      size: 14,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 当前颜色预览
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: _selectedColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.s.fcHelpText,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Theme ───

  NodeFlowTheme _buildTheme(bool isDark) {
    final base = isDark ? NodeFlowTheme.dark : NodeFlowTheme.light;
    if (_showGrid) return base;
    // 无网格背景
    return base.copyWith(
      gridTheme: base.gridTheme.copyWith(style: GridStyles.none),
    );
  }

  // ─── 节点渲染 ───

  Widget _buildNode(BuildContext context, Node<FcNodeData> node) {
    final data = node.data;
    final theme = Theme.of(context);

    return GestureDetector(
      onDoubleTap: () => _editNode(node),
      child: Container(
        constraints: const BoxConstraints(minWidth: 80, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.15),
          border: Border.all(color: data.color, width: 1.5),
          borderRadius: _borderRadiusFor(data.shape),
        ),
        child: Text(
          data.text.isNotEmpty ? data.text : data.shape.localizedLabel(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: data.fontSize,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  BorderRadius? _borderRadiusFor(FcNodeShape shape) {
    switch (shape) {
      case FcNodeShape.rect:
        return BorderRadius.circular(4);
      case FcNodeShape.roundedRect:
      case FcNodeShape.stadium:
        return BorderRadius.circular(20);
      case FcNodeShape.cylinder:
        return BorderRadius.circular(8);
      default:
        return BorderRadius.circular(4);
    }
  }

  NodeShape? _buildNodeShape(BuildContext context, Node<FcNodeData> node) {
    switch (node.data.shape) {
      case FcNodeShape.diamond:
        return DiamondShape(
          fillColor: node.data.color.withValues(alpha: 0.15),
          strokeColor: node.data.color,
        );
      case FcNodeShape.circle:
        return CircleShape(
          fillColor: node.data.color.withValues(alpha: 0.15),
          strokeColor: node.data.color,
        );
      case FcNodeShape.hexagon:
        return HexagonShape(
          fillColor: node.data.color.withValues(alpha: 0.15),
          strokeColor: node.data.color,
        );
      default:
        return null; // 使用默认矩形
    }
  }
}

// ─── 节点编辑对话框 ───

class _NodeEditDialog extends StatefulWidget {
  const _NodeEditDialog({
    required this.data,
    required this.currentSize,
    required this.onSave,
  });
  final FcNodeData data;
  final Size currentSize;
  final void Function(FcNodeData, Size) onSave;

  @override
  State<_NodeEditDialog> createState() => _NodeEditDialogState();
}

class _NodeEditDialogState extends State<_NodeEditDialog> {
  late TextEditingController _textCtrl;
  late FcNodeShape _shape;
  late Color _color;
  late double _fontSize;
  late double _width;
  late double _height;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.data.text);
    _shape = widget.data.shape;
    _color = widget.data.color;
    _fontSize = widget.data.fontSize;
    _width = widget.currentSize.width;
    _height = widget.currentSize.height;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.s.fcEditNode),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _textCtrl,
                decoration: InputDecoration(
                  labelText: context.s.fcTextContent,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('形状:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: FcNodeShape.values.map((s) {
                  final sel = s == _shape;
                  return ChoiceChip(
                    label: Text(
                      s.localizedLabel(context),
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: sel,
                    onSelected: (_) => setState(() => _shape = s),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('颜色:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _presetColors.map((c) {
                  final sel = c == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: sel ? Border.all(width: 2.5) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('字号:', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 10,
                      max: 24,
                      divisions: 14,
                      label: _fontSize.round().toString(),
                      onChanged: (v) => setState(() => _fontSize = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('尺寸:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('宽', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _width.clamp(60, 400),
                      min: 60,
                      max: 400,
                      divisions: 34,
                      label: '${_width.round()}',
                      onChanged: (v) => setState(() => _width = v),
                    ),
                  ),
                  Text(
                    '${_width.round()}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('高', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _height.clamp(30, 300),
                      min: 30,
                      max: 300,
                      divisions: 27,
                      label: '${_height.round()}',
                      onChanged: (v) => setState(() => _height = v),
                    ),
                  ),
                  Text(
                    '${_height.round()}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(
              FcNodeData(
                shape: _shape,
                text: _textCtrl.text,
                color: _color,
                fontSize: _fontSize,
              ),
              Size(_width, _height),
            );
            Navigator.of(context).pop();
          },
          child: Text(context.s.commonSave),
        ),
      ],
    );
  }
}

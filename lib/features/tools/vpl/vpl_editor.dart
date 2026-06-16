import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../../../core/l10n/l10n_ext.dart';
import 'vpl_code_gen.dart';
import 'vpl_nodes.dart';

const _uuid = Uuid();

class VplEditorPage extends StatefulWidget {
  const VplEditorPage({super.key});

  @override
  State<VplEditorPage> createState() => _VplEditorPageState();
}

class _VplEditorPageState extends State<VplEditorPage> {
  late final NodeFlowController<VplNodeData, dynamic> _controller;
  String _currentFile = '';
  bool _dirty = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<VplNodeData, dynamic>(
      config: NodeFlowConfig.defaultConfig,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ─── 节点创建 ───

  void _addNode(VplNodeType type, [Offset? position]) {
    final ports = VplPortPresets.portsFor(type);
    final nodePorts = ports
        .map(
          (pd) => Port(
            id: pd.id,
            name: pd.name == '▶'
                ? '▶'
                : VplPortPresets.localizedPortName(context, pd.id),
            position: pd.side == VplPortSide.left
                ? PortPosition.left
                : PortPosition.right,
            type: pd.type == VplPortType.input
                ? PortType.input
                : PortType.output,
          ),
        )
        .toList();

    final node = Node<VplNodeData>(
      id: _uuid.v4(),
      type: type.name,
      position: position ?? const Offset(200, 200),
      data: VplNodeData(
        nodeType: type,
        properties: _defaultProps(type, context),
      ),
      ports: nodePorts,
    );

    _controller.addNode(node);
    setState(() => _dirty = true);
  }

  Map<String, dynamic> _defaultProps(VplNodeType type, BuildContext context) {
    switch (type) {
      case VplNodeType.variable:
        return {'name': 'x', 'value': '0'};
      case VplNodeType.constant:
        return {'name': 'PI', 'value': '3.14159'};
      case VplNodeType.math:
        return {'op': '+', 'resultVar': 'result'};
      case VplNodeType.compare:
        return {'op': '==', 'resultVar': 'cmp_result'};
      case VplNodeType.logic:
        return {'op': 'and', 'resultVar': 'logic_result'};
      case VplNodeType.string:
        return {'op': 'concat', 'resultVar': 'str_result'};
      case VplNodeType.forLoop:
        return {'indexVar': 'i'};
      case VplNodeType.print:
        return {'value': '"Hello, World!"'};
      case VplNodeType.input:
        return {'prompt': context.s.vplDefaultPrompt, 'varName': 'user_input'};
      case VplNodeType.functionDef:
        return {'name': 'my_func', 'params': ''};
      case VplNodeType.functionCall:
        return {'name': 'my_func', 'args': '', 'resultVar': 'ret'};
      case VplNodeType.readFile:
        return {'varName': 'content'};
      case VplNodeType.writeFile:
        return {};
      case VplNodeType.comment:
        return {'text': context.s.vplNodeComment};
      default:
        return {};
    }
  }

  // ─── 文件操作 ───

  Future<void> _save() async {
    if (_currentFile.isNotEmpty) {
      await _saveToFile(_currentFile);
      return;
    }
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.s.vplSave,
      fileName: context.s.vplDefaultFilename,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    final path = result.endsWith('.vpl.json') ? result : '$result.vpl.json';
    await _saveToFile(path);
  }

  Future<void> _saveToFile(String path) async {
    try {
      final gen = VplCodeGenerator(_controller);
      final json = gen.exportJson();
      await File(path).writeAsString(json);
      if (!mounted) return;
      setState(() {
        _currentFile = path;
        _dirty = false;
        _statusMessage = context.s.vplSaved(p.basename(path));
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(context.s.vplSaveFailed(e.toString()));
    }
  }

  Future<void> _load() async {
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.vplOpen,
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
        _statusMessage = context.s.vplOpened(p.basename(path));
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(context.s.vplOpenFailed(e.toString()));
    }
  }

  void _loadFromJson(Map<String, dynamic> data) {
    _controller.clearGraph();
    final nodes = (data['nodes'] as List?) ?? [];
    final connections = (data['connections'] as List?) ?? [];

    final nodeList = <Node<VplNodeData>>[];
    for (final n in nodes) {
      final nodeData = VplNodeData.fromJson(n['data'] as Map<String, dynamic>);
      final portsList =
          (n['ports'] as List?)?.map((pd) {
            return Port(
              id: pd['id'] as String,
              name: pd['name'] as String,
              position: PortPosition.values.firstWhere(
                (e) => e.name == pd['position'],
                orElse: () => PortPosition.left,
              ),
              type: PortType.values.firstWhere(
                (e) => e.name == pd['type'],
                orElse: () => PortType.input,
              ),
            );
          }).toList() ??
          [];

      nodeList.add(
        Node<VplNodeData>(
          id: n['id'] as String,
          type: n['type'] as String,
          position: Offset(
            (n['x'] as num).toDouble(),
            (n['y'] as num).toDouble(),
          ),
          data: nodeData,
          ports: portsList,
        ),
      );
    }

    final connList = <Connection<dynamic>>[];
    for (final c in connections) {
      connList.add(
        Connection(
          id: c['id'] as String,
          sourceNodeId: c['sourceNodeId'] as String,
          sourcePortId: c['sourcePortId'] as String,
          targetNodeId: c['targetNodeId'] as String,
          targetPortId: c['targetPortId'] as String,
        ),
      );
    }

    final graph = NodeGraph<VplNodeData, dynamic>(
      nodes: nodeList,
      connections: connList,
    );
    _controller.loadGraph(graph);
  }

  // ─── 导出 ───

  Future<void> _export() async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.s.vplExportCode),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('python'),
            child: const ListTile(
              leading: Icon(Icons.code),
              title: Text('Python (.py)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('dart'),
            child: const ListTile(
              leading: Icon(Icons.flutter_dash),
              title: Text('Dart (.dart)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('json'),
            child: ListTile(
              leading: const Icon(Icons.data_object),
              title: Text(context.s.vplExportJson),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('clipboard'),
            child: ListTile(
              leading: const Icon(Icons.copy),
              title: Text(context.s.vplCopyPython),
            ),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final gen = VplCodeGenerator(_controller);
    String code;
    String defaultName;
    String ext;

    switch (choice) {
      case 'python':
        code = gen.exportPython();
        defaultName = 'vpl_export.py';
        ext = 'py';
        break;
      case 'dart':
        code = gen.exportDart();
        defaultName = 'vpl_export.dart';
        ext = 'dart';
        break;
      case 'json':
        code = gen.exportJson();
        defaultName = 'vpl_export.json';
        ext = 'json';
        break;
      case 'clipboard':
        code = gen.exportPython();
        await Clipboard.setData(ClipboardData(text: code));
        if (!mounted) return;
        _showSnackBar(context.s.vplCopied);
        return;
      default:
        return;
    }

    if (!mounted) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: context.s.vplExportCode,
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (result == null) return;
    await File(result).writeAsString(code);
    if (!mounted) return;
    _showSnackBar(context.s.vplExported(p.basename(result)));

    if (mounted) {
      _showCodePreview(
        code,
        choice == 'json' ? 'JSON' : (choice == 'dart' ? 'Dart' : 'Python'),
      );
    }
  }

  void _showCodePreview(String code, String lang) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 600,
          height: 500,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      context.s.vplCodePreview(lang),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        Navigator.of(ctx).pop();
                        _showSnackBar(context.s.vplCopied);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontFamily: 'Consolas, monospace',
                      fontSize: 13,
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

  // ─── UI 辅助 ───

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ─── 节点属性编辑 ───

  void _editNodeProperties(Node<VplNodeData> node) {
    final data = node.data;
    final props = Map<String, dynamic>.from(data.properties);

    showDialog(
      context: context,
      builder: (ctx) => _NodePropertiesDialog(
        nodeType: data.nodeType,
        properties: props,
        onSave: (newProps) {
          // 更新节点数据
          final newData = data.copyWith(properties: newProps);
          _controller.removeNode(node.id);
          final newNode = Node<VplNodeData>(
            id: node.id,
            type: node.type,
            position: node.position.value,
            data: newData,
            ports: node.ports,
          );
          _controller.addNode(newNode);
          setState(() => _dirty = true);
        },
      ),
    );
  }

  // ─── 新建 ───

  /// 如果有未保存的修改，提示用户是否保存。返回 true 表示可以继续操作。
  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.vplUnsavedTitle),
        content: Text(context.s.vplUnsavedContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(0), // 取消
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(1), // 不保存
            child: Text(context.s.vplDontSave),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(2), // 保存
            child: Text(context.s.commonSave),
          ),
        ],
      ),
    );
    if (result == null || result == 0) return false; // 取消
    if (result == 2) await _save(); // 保存
    return true;
  }

  Future<void> _newProject() async {
    if (!await _confirmDiscardIfDirty()) return;
    _controller.clearGraph();
    setState(() {
      _currentFile = '';
      _dirty = false;
      _statusMessage = context.s.vplNewProject;
    });
    // 默认添加一个 Start 节点
    _addNode(VplNodeType.start, const Offset(100, 300));
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
          // 左侧节点面板
          _buildNodePalette(colorScheme),
          const VerticalDivider(width: 1),
          // 主编辑区域
          Expanded(
            child: Column(
              children: [
                _buildToolbar(colorScheme),
                const Divider(height: 1),
                Expanded(
                  child: NodeFlowEditor<VplNodeData, dynamic>(
                    controller: _controller,
                    theme: isDark ? NodeFlowTheme.dark : NodeFlowTheme.light,
                    nodeBuilder: _buildNodeWidget,
                    events: NodeFlowEvents(
                      node: NodeEvents(
                        onDoubleTap: (node) => _editNodeProperties(node),
                      ),
                    ),
                  ),
                ),
                // 底部状态栏
                _buildStatusBar(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.surface,
      child: Row(
        children: [
          _toolBtn(Icons.add, context.s.vplBtnNew, _newProject),
          _toolBtn(Icons.folder_open, context.s.vplBtnOpen, _load),
          _toolBtn(Icons.save, context.s.vplBtnSave, _save),
          const VerticalDivider(indent: 8, endIndent: 8),
          _toolBtn(Icons.upload, context.s.vplBtnExport, _export),
          const Spacer(),
          _toolBtn(
            Icons.center_focus_strong,
            context.s.vplBtnFitCanvas,
            () => _controller.fitToView(),
          ),
          _toolBtn(
            Icons.select_all,
            context.s.vplBtnSelectAll,
            () => _controller.selectAllNodes(),
          ),
          _toolBtn(Icons.delete_outline, context.s.vplBtnDeleteSelected, () {
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

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
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

  Widget _buildStatusBar(ColorScheme colorScheme) {
    final textStyle = TextStyle(
      fontSize: 11,
      color: colorScheme.onSurface.withValues(alpha: 0.7),
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          if (_dirty) const Icon(Icons.circle, size: 8, color: Colors.orange),
          if (_dirty) const SizedBox(width: 6),
          Text(
            _statusMessage.isNotEmpty
                ? _statusMessage
                : context.s.vplStatusReady,
            style: textStyle,
          ),
          const Spacer(),
          Text(
            context.s.vplStatusNodes(
              _controller.nodeCount,
              _controller.exportGraph().connections.length,
            ),
            style: textStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildNodePalette(ColorScheme colorScheme) {
    final categories = <String, List<VplNodeType>>{
      context.s.vplCatFlow: [
        VplNodeType.start,
        VplNodeType.end,
        VplNodeType.ifCondition,
        VplNodeType.forLoop,
        VplNodeType.whileLoop,
      ],
      context.s.vplCatData: [
        VplNodeType.variable,
        VplNodeType.constant,
        VplNodeType.list,
        VplNodeType.map,
      ],
      context.s.vplCatMath: [
        VplNodeType.math,
        VplNodeType.compare,
        VplNodeType.logic,
        VplNodeType.string,
      ],
      context.s.vplCatIO: [
        VplNodeType.print,
        VplNodeType.input,
        VplNodeType.readFile,
        VplNodeType.writeFile,
      ],
      context.s.vplCatFunc: [
        VplNodeType.functionDef,
        VplNodeType.functionCall,
        VplNodeType.returnNode,
      ],
      context.s.vplCatOther: [VplNodeType.comment],
    };

    return SizedBox(
      width: 180,
      child: Material(
        color: colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: categories.entries.map((entry) {
            return ExpansionTile(
              title: Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              initiallyExpanded: true,
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.only(bottom: 4),
              children: entry.value.map((type) {
                return _PaletteItem(type: type, onTap: () => _addNode(type));
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── 节点渲染 ───

  Widget _buildNodeWidget(BuildContext context, Node<VplNodeData> node) {
    final data = node.data;
    final type = data.nodeType;
    final theme = Theme.of(context);

    return GestureDetector(
      onDoubleTap: () => _editNodeProperties(node),
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.1),
          border: Border.all(color: type.color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 16, color: type.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _nodeTitle(context, node),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: type.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_nodeSubtitle(node) != null) ...[
              const SizedBox(height: 4),
              Text(
                _nodeSubtitle(node)!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _nodeTitle(BuildContext context, Node<VplNodeData> node) {
    final data = node.data;
    final props = data.properties;
    switch (data.nodeType) {
      case VplNodeType.variable:
        return '${context.s.vplNodeVariable}: ${props['name'] ?? 'x'}';
      case VplNodeType.constant:
        return '${context.s.vplNodeConstant}: ${props['name'] ?? 'C'}';
      case VplNodeType.functionDef:
        return 'def ${props['name'] ?? 'func'}()';
      case VplNodeType.functionCall:
        return '${props['name'] ?? 'func'}()';
      case VplNodeType.math:
        return '${context.s.vplNodeMath} [${props['op'] ?? '+'}]';
      case VplNodeType.compare:
        return '${context.s.vplNodeCompare} [${props['op'] ?? '=='}]';
      case VplNodeType.logic:
        return '${context.s.vplNodeLogic} [${props['op'] ?? 'and'}]';
      case VplNodeType.string:
        return '${context.s.vplNodeString} [${props['op'] ?? 'concat'}]';
      default:
        return data.nodeType.localizedLabel(context);
    }
  }

  String? _nodeSubtitle(Node<VplNodeData> node) {
    final props = node.data.properties;
    switch (node.data.nodeType) {
      case VplNodeType.variable:
        return '= ${props['value'] ?? '0'}';
      case VplNodeType.constant:
        return '= ${props['value'] ?? ''}';
      case VplNodeType.print:
        return props['value']?.toString();
      case VplNodeType.comment:
        return props['text']?.toString();
      default:
        return null;
    }
  }
}

// ─── 节点面板拖拽项 ───

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.type, required this.onTap});

  final VplNodeType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(type.icon, size: 16, color: type.color),
            const SizedBox(width: 8),
            Text(
              type.localizedLabel(context),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 节点属性编辑对话框 ───

class _NodePropertiesDialog extends StatefulWidget {
  const _NodePropertiesDialog({
    required this.nodeType,
    required this.properties,
    required this.onSave,
  });

  final VplNodeType nodeType;
  final Map<String, dynamic> properties;
  final void Function(Map<String, dynamic>) onSave;

  @override
  State<_NodePropertiesDialog> createState() => _NodePropertiesDialogState();
}

class _NodePropertiesDialogState extends State<_NodePropertiesDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    for (final entry in widget.properties.entries) {
      _controllers[entry.key] = TextEditingController(
        text: entry.value?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.nodeType.icon, color: widget.nodeType.color),
          const SizedBox(width: 8),
          Text(context.s.vplPropTitle(widget.nodeType.localizedLabel(context))),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _controllers.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: _fieldLabel(entry.key),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final result = <String, dynamic>{};
            for (final entry in _controllers.entries) {
              result[entry.key] = entry.value.text;
            }
            widget.onSave(result);
            Navigator.of(context).pop();
          },
          child: Text(context.s.commonSave),
        ),
      ],
    );
  }

  String _fieldLabel(String key) {
    final labels = {
      'name': context.s.vplPropName,
      'value': context.s.vplPropValue,
      'op': context.s.vplPropOperator,
      'resultVar': context.s.vplPropResultVar,
      'indexVar': context.s.vplPropIndexVar,
      'prompt': context.s.vplPropPromptText,
      'varName': context.s.vplPropVarName,
      'params': context.s.vplPropParamList,
      'args': context.s.vplPropCallArgs,
      'text': context.s.vplPropContent,
      'path': context.s.vplPropFilePath,
      'content': context.s.vplPropContent,
    };
    return labels[key] ?? key;
  }
}

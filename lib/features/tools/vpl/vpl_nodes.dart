import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';

/// VPL 节点数据类型枚举
enum VplNodeType {
  // 流程控制
  start('开始', Icons.play_circle_outline, Color(0xFF4CAF50)),
  end('结束', Icons.stop_circle_outlined, Color(0xFFF44336)),
  ifCondition('条件', Icons.call_split, Color(0xFFFF9800)),
  forLoop('循环', Icons.loop, Color(0xFF9C27B0)),
  whileLoop('While', Icons.repeat, Color(0xFF9C27B0)),

  // 数据
  variable('变量', Icons.data_object, Color(0xFF2196F3)),
  constant('常量', Icons.pin, Color(0xFF607D8B)),
  list('列表', Icons.view_list, Color(0xFF00BCD4)),
  map('字典', Icons.map_outlined, Color(0xFF009688)),

  // 运算
  math('数学运算', Icons.calculate, Color(0xFF3F51B5)),
  compare('比较运算', Icons.compare_arrows, Color(0xFFFF5722)),
  logic('逻辑运算', Icons.rule, Color(0xFF795548)),
  string('字符串', Icons.text_fields, Color(0xFF8BC34A)),

  // IO
  print('输出', Icons.print_outlined, Color(0xFF673AB7)),
  input('输入', Icons.input, Color(0xFFE91E63)),
  readFile('读文件', Icons.file_open_outlined, Color(0xFF455A64)),
  writeFile('写文件', Icons.save_outlined, Color(0xFF455A64)),

  // 函数
  functionDef('函数定义', Icons.functions, Color(0xFFFF6F00)),
  functionCall('函数调用', Icons.call_made, Color(0xFFFF6F00)),
  returnNode('返回', Icons.keyboard_return, Color(0xFFFF6F00)),

  // 注释
  comment('注释', Icons.comment_outlined, Color(0xFF9E9E9E));

  const VplNodeType(this.label, this.icon, this.color);

  /// Original Chinese label, kept for serialization/persistence compatibility.
  final String label;
  final IconData icon;
  final Color color;

  /// Returns the localized display label for this node type.
  String localizedLabel(BuildContext context) {
    switch (this) {
      case VplNodeType.start:
        return context.s.vplNodeStart;
      case VplNodeType.end:
        return context.s.vplNodeEnd;
      case VplNodeType.ifCondition:
        return context.s.vplNodeCondition;
      case VplNodeType.forLoop:
        return context.s.vplNodeLoop;
      case VplNodeType.whileLoop:
        return context.s.vplNodeLoop;
      case VplNodeType.variable:
        return context.s.vplNodeVariable;
      case VplNodeType.constant:
        return context.s.vplNodeConstant;
      case VplNodeType.list:
        return context.s.vplNodeList;
      case VplNodeType.map:
        return context.s.vplNodeDict;
      case VplNodeType.math:
        return context.s.vplNodeMath;
      case VplNodeType.compare:
        return context.s.vplNodeCompare;
      case VplNodeType.logic:
        return context.s.vplNodeLogic;
      case VplNodeType.string:
        return context.s.vplNodeString;
      case VplNodeType.print:
        return context.s.vplNodeOutput;
      case VplNodeType.input:
        return context.s.vplNodeInput;
      case VplNodeType.readFile:
        return context.s.vplNodeReadFile;
      case VplNodeType.writeFile:
        return context.s.vplNodeWriteFile;
      case VplNodeType.functionDef:
        return context.s.vplNodeFuncDef;
      case VplNodeType.functionCall:
        return context.s.vplNodeFuncCall;
      case VplNodeType.returnNode:
        return context.s.vplNodeReturn;
      case VplNodeType.comment:
        return context.s.vplNodeComment;
    }
  }
}

/// VPL 节点携带的数据
class VplNodeData {
  final VplNodeType nodeType;
  final Map<String, dynamic> properties;

  const VplNodeData({required this.nodeType, this.properties = const {}});

  VplNodeData copyWith({
    VplNodeType? nodeType,
    Map<String, dynamic>? properties,
  }) {
    return VplNodeData(
      nodeType: nodeType ?? this.nodeType,
      properties: properties ?? this.properties,
    );
  }

  Map<String, dynamic> toJson() => {
    'nodeType': nodeType.name,
    'properties': properties,
  };

  factory VplNodeData.fromJson(Map<String, dynamic> json) {
    return VplNodeData(
      nodeType: VplNodeType.values.firstWhere(
        (e) => e.name == json['nodeType'],
        orElse: () => VplNodeType.variable,
      ),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
    );
  }
}

/// 节点端口预设模板
class VplPortPresets {
  /// 根据节点类型返回预设的端口列表描述
  static List<PortDef> portsFor(VplNodeType type) {
    switch (type) {
      case VplNodeType.start:
        return [
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.end:
        return [PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input)];
      case VplNodeType.ifCondition:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('cond', '条件', VplPortSide.left, VplPortType.input),
          PortDef('true_out', 'True', VplPortSide.right, VplPortType.output),
          PortDef('false_out', 'False', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.forLoop:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('count', '次数', VplPortSide.left, VplPortType.input),
          PortDef('body', '循环体', VplPortSide.right, VplPortType.output),
          PortDef('index', '索引', VplPortSide.right, VplPortType.output),
          PortDef('done', '完成', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.whileLoop:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('cond', '条件', VplPortSide.left, VplPortType.input),
          PortDef('body', '循环体', VplPortSide.right, VplPortType.output),
          PortDef('done', '完成', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.variable:
        return [
          PortDef('value_in', '赋值', VplPortSide.left, VplPortType.input),
          PortDef('value_out', '值', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.constant:
        return [
          PortDef('value_out', '值', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.list:
        return [
          PortDef('items_in', '元素', VplPortSide.left, VplPortType.input),
          PortDef('list_out', '列表', VplPortSide.right, VplPortType.output),
          PortDef('length_out', '长度', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.map:
        return [
          PortDef('key_in', '键', VplPortSide.left, VplPortType.input),
          PortDef('value_in', '值', VplPortSide.left, VplPortType.input),
          PortDef('map_out', '字典', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.math:
        return [
          PortDef('a', 'A', VplPortSide.left, VplPortType.input),
          PortDef('b', 'B', VplPortSide.left, VplPortType.input),
          PortDef('result', '结果', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.compare:
        return [
          PortDef('a', 'A', VplPortSide.left, VplPortType.input),
          PortDef('b', 'B', VplPortSide.left, VplPortType.input),
          PortDef('result', '结果', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.logic:
        return [
          PortDef('a', 'A', VplPortSide.left, VplPortType.input),
          PortDef('b', 'B', VplPortSide.left, VplPortType.input),
          PortDef('result', '结果', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.string:
        return [
          PortDef('input', '输入', VplPortSide.left, VplPortType.input),
          PortDef('arg', '参数', VplPortSide.left, VplPortType.input),
          PortDef('result', '结果', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.print:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('value', '值', VplPortSide.left, VplPortType.input),
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.input:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('prompt', '提示', VplPortSide.left, VplPortType.input),
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
          PortDef('value_out', '值', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.readFile:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('path', '路径', VplPortSide.left, VplPortType.input),
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
          PortDef('content', '内容', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.writeFile:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('path', '路径', VplPortSide.left, VplPortType.input),
          PortDef('content', '内容', VplPortSide.left, VplPortType.input),
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.functionDef:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('params', '参数', VplPortSide.left, VplPortType.input),
          PortDef('body', '函数体', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.functionCall:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('args', '参数', VplPortSide.left, VplPortType.input),
          PortDef('exec_out', '▶', VplPortSide.right, VplPortType.output),
          PortDef('return_val', '返回', VplPortSide.right, VplPortType.output),
        ];
      case VplNodeType.returnNode:
        return [
          PortDef('exec_in', '▶', VplPortSide.left, VplPortType.input),
          PortDef('value', '值', VplPortSide.left, VplPortType.input),
        ];
      case VplNodeType.comment:
        return [];
    }
  }

  /// Returns localized port name for a given port ID.
  /// Used for UI display; the port ID remains stable for serialization.
  static String localizedPortName(BuildContext context, String portId) {
    switch (portId) {
      case 'cond':
        return context.s.vplPortCondition;
      case 'count':
        return context.s.vplPortCount;
      case 'body':
        return context.s.vplPortBody;
      case 'index':
        return context.s.vplPortIndex;
      case 'done':
        return context.s.vplPortDone;
      case 'value_in':
        return context.s.vplPortAssign;
      case 'value_out':
      case 'value':
        return context.s.vplPortValue;
      case 'items_in':
        return context.s.vplPortElement;
      case 'list_out':
        return context.s.vplPortList;
      case 'length_out':
        return context.s.vplPortLength;
      case 'key_in':
        return context.s.vplPortKey;
      case 'map_out':
        return context.s.vplPortDict;
      case 'result':
        return context.s.vplPortResult;
      case 'input':
        return context.s.vplPortInput;
      case 'arg':
      case 'args':
      case 'params':
        return context.s.vplPortParam;
      case 'prompt':
        return context.s.vplPortPrompt;
      case 'path':
        return context.s.vplPortPath;
      case 'content':
        return context.s.vplPortContent;
      case 'return_val':
        return context.s.vplPortReturn;
      default:
        return portId;
    }
  }
}

enum VplPortSide { left, right }

enum VplPortType { input, output }

class PortDef {
  final String id;
  final String name;
  final VplPortSide side;
  final VplPortType type;
  const PortDef(this.id, this.name, this.side, this.type);
}

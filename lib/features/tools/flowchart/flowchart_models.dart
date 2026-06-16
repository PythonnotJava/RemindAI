import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_ext.dart';

/// 流程图节点形状
enum FcNodeShape {
  rect('矩形', Icons.rectangle_outlined),
  roundedRect('圆角矩形', Icons.rounded_corner),
  diamond('菱形', Icons.diamond_outlined),
  circle('圆形', Icons.circle_outlined),
  parallelogram('平行四边形', Icons.input),
  hexagon('六边形', Icons.hexagon_outlined),
  cylinder('数据库', Icons.storage_outlined),
  stadium('胶囊形', Icons.label_outlined);

  const FcNodeShape(this.label, this.icon);
  final String label;
  final IconData icon;

  String localizedLabel(BuildContext context) {
    switch (this) {
      case FcNodeShape.rect:
        return context.s.fcShapeRect;
      case FcNodeShape.roundedRect:
        return context.s.fcShapeRoundRect;
      case FcNodeShape.diamond:
        return context.s.fcShapeDiamond;
      case FcNodeShape.circle:
        return context.s.fcShapeCircle;
      case FcNodeShape.parallelogram:
        return context.s.fcShapeParallelogram;
      case FcNodeShape.hexagon:
        return context.s.fcShapeHexagon;
      case FcNodeShape.cylinder:
        return context.s.fcShapeDatabase;
      case FcNodeShape.stadium:
        return context.s.fcShapeCapsule;
    }
  }
}

/// 连线箭头
enum FcArrowType {
  arrow('单向箭头'),
  biArrow('双向箭头'),
  none('无箭头');

  const FcArrowType(this.label);
  final String label;

  String localizedLabel(BuildContext context) {
    switch (this) {
      case FcArrowType.arrow:
        return context.s.fcArrowSingle;
      case FcArrowType.biArrow:
        return context.s.fcArrowDouble;
      case FcArrowType.none:
        return context.s.fcArrowNone;
    }
  }
}

/// 连线线型
enum FcLineStyle {
  solid('实线'),
  dashed('虚线'),
  dotted('点线');

  const FcLineStyle(this.label);
  final String label;

  String localizedLabel(BuildContext context) {
    switch (this) {
      case FcLineStyle.solid:
        return context.s.fcLineSolid;
      case FcLineStyle.dashed:
        return context.s.fcLineDashed;
      case FcLineStyle.dotted:
        return context.s.fcLineDotted;
    }
  }
}

/// 流程图节点数据
class FcNodeData {
  final FcNodeShape shape;
  final String text;
  final Color color;
  final double fontSize;

  const FcNodeData({
    this.shape = FcNodeShape.rect,
    this.text = '',
    this.color = const Color(0xFF42A5F5),
    this.fontSize = 13,
  });

  FcNodeData copyWith({
    FcNodeShape? shape,
    String? text,
    Color? color,
    double? fontSize,
  }) {
    return FcNodeData(
      shape: shape ?? this.shape,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  Map<String, dynamic> toJson() => {
    'shape': shape.name,
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
  };

  factory FcNodeData.fromJson(Map<String, dynamic> json) {
    return FcNodeData(
      shape: FcNodeShape.values.firstWhere(
        (e) => e.name == json['shape'],
        orElse: () => FcNodeShape.rect,
      ),
      text: json['text'] as String? ?? '',
      color: Color(json['color'] as int? ?? 0xFF42A5F5),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13,
    );
  }
}

/// 连线附加数据
class FcEdgeData {
  final String label;
  final FcLineStyle lineStyle;
  final FcArrowType arrow;
  final Color color;

  const FcEdgeData({
    this.label = '',
    this.lineStyle = FcLineStyle.solid,
    this.arrow = FcArrowType.arrow,
    this.color = const Color(0xFF757575),
  });

  FcEdgeData copyWith({
    String? label,
    FcLineStyle? lineStyle,
    FcArrowType? arrow,
    Color? color,
  }) {
    return FcEdgeData(
      label: label ?? this.label,
      lineStyle: lineStyle ?? this.lineStyle,
      arrow: arrow ?? this.arrow,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'lineStyle': lineStyle.name,
    'arrow': arrow.name,
    'color': color.toARGB32(),
  };

  factory FcEdgeData.fromJson(Map<String, dynamic> json) {
    return FcEdgeData(
      label: json['label'] as String? ?? '',
      lineStyle: FcLineStyle.values.firstWhere(
        (e) => e.name == json['lineStyle'],
        orElse: () => FcLineStyle.solid,
      ),
      arrow: FcArrowType.values.firstWhere(
        (e) => e.name == json['arrow'],
        orElse: () => FcArrowType.arrow,
      ),
      color: Color(json['color'] as int? ?? 0xFF757575),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 获取交互字体的 TextStyle（用于对话和多Agent区域）
TextStyle chatTextStyle({
  required String fontFamily,
  required double fontSize,
  Color? color,
  FontWeight? fontWeight,
  double? height,
}) {
  return GoogleFonts.getFont(
    fontFamily,
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    height: height,
  );
}

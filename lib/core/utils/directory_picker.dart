import 'dart:async';

import 'package:file_selector/file_selector.dart' as fs;

/// 统一的目录选择封装。
///
/// 历史问题：`file_picker` 的目录选择（底层 comdlg32）在 Windows 上会**原生崩溃**，
/// 且无 Dart 异常（try/catch 接不住、日志里看不到任何痕迹）。改用 `file_selector`
/// （底层 IFileDialog）稳定。全应用所有"选目录"入口都应走此函数，便于统一维护。
///
/// [dialogTitle] 仅用于语义保留；`file_selector` 用 [confirmButtonText] 作为确认按钮文案，
/// 不支持设置标题栏文字，这里把标题忽略（或作为确认按钮文案的回退）。
/// [initialDirectory] 打开对话框时的初始目录。
/// [timeout] 防止原生对话框卡死的兜底超时（默认 60s）。
///
/// 用户取消、超时或任何异常都返回 `null`，绝不抛出——调用方据此静默处理。
Future<String?> pickDirectory({
  String? dialogTitle,
  String? initialDirectory,
  Duration timeout = const Duration(seconds: 60),
}) async {
  try {
    final path = await fs
        .getDirectoryPath(initialDirectory: initialDirectory)
        .timeout(timeout);
    return path;
  } on TimeoutException {
    // 原生对话框卡死的兜底，静默忽略
    return null;
  } catch (_) {
    // 其他平台异常，静默忽略
    return null;
  }
}

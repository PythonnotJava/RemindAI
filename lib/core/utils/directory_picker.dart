import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;

import '../logger/app_logger.dart';

/// 异步检查目录是否存在，并限制等待时间。
///
/// 不使用 [Directory.existsSync]，避免离线网络盘、云盘占位目录或失效
/// Junction 在 Flutter UI isolate 上同步阻塞。
Future<bool> directoryExistsSafely(
  String path, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (path.trim().isEmpty) return false;
  final stopwatch = Stopwatch()..start();
  try {
    final exists = await Directory(path).exists().timeout(timeout);
    stopwatch.stop();
    AppLogger.instance.log(
      '[DirectoryPicker] 路径检查完成: exists=$exists, '
      'elapsed=${stopwatch.elapsedMilliseconds}ms, path=$path',
    );
    return exists;
  } on TimeoutException {
    stopwatch.stop();
    AppLogger.instance.log(
      '[DirectoryPicker] 路径检查超时: '
      'elapsed=${stopwatch.elapsedMilliseconds}ms, path=$path',
    );
    return false;
  } catch (e) {
    stopwatch.stop();
    AppLogger.instance.log(
      '[DirectoryPicker] 路径检查异常: $e, '
      'elapsed=${stopwatch.elapsedMilliseconds}ms, path=$path',
    );
    return false;
  }
}

/// 返回可安全传给原生选择器的初始目录。
/// 无效或慢路径返回 null，避免 Windows 恢复到失效网络位置。
Future<String?> validInitialDirectory(String? candidate) async {
  if (candidate == null || candidate.trim().isEmpty) return null;
  return await directoryExistsSafely(candidate) ? candidate : null;
}

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
  final stopwatch = Stopwatch()..start();
  AppLogger.instance.log(
    '[DirectoryPicker] 开始调用原生选择器: '
    'initial=${initialDirectory ?? "(系统默认)"}, timeout=${timeout.inSeconds}s',
  );
  try {
    final path = await fs
        .getDirectoryPath(initialDirectory: initialDirectory)
        .timeout(timeout);
    stopwatch.stop();
    if (path == null) {
      AppLogger.instance.log(
        '[DirectoryPicker] 用户取消选择: elapsed=${stopwatch.elapsedMilliseconds}ms',
      );
    } else {
      AppLogger.instance.log(
        '[DirectoryPicker] 原生选择器返回: '
        'elapsed=${stopwatch.elapsedMilliseconds}ms, path=$path',
      );
    }
    return path;
  } on TimeoutException {
    stopwatch.stop();
    // 注意：Dart Future 超时无法强制关闭已卡住的 Windows IFileDialog。
    AppLogger.instance.log(
      '[DirectoryPicker] Dart 等待超时: '
      'elapsed=${stopwatch.elapsedMilliseconds}ms。'
      '原生 IFileDialog 可能仍在阻塞平台线程。',
    );
    return null;
  } catch (e, stackTrace) {
    stopwatch.stop();
    AppLogger.instance.log(
      '[DirectoryPicker] 原生选择器异常: $e, '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    AppLogger.instance.log('[DirectoryPicker] StackTrace: $stackTrace');
    return null;
  }
}

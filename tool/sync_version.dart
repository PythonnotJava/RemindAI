// 版本号同步器 —— 把 pubspec.yaml 作为版本号的**唯一来源**。
//
// 背景：版本号曾经手写在三处（pubspec.yaml、lib/features/settings/version.dart、
// windows/runner/Runner.rc 的 FLUTTER_VERSION 回退值）。漏改任何一处都会导致
// "更新检查永远认为已是最新"这类静默故障。
//
// 现在：
//   * Windows 资源版本由 flutter 构建时从 pubspec 注入 FLUTTER_VERSION* 宏；
//   * Dart 侧读本脚本生成的 lib/features/settings/version.dart；
//   * test/settings/version_sync_test.dart 在两者不一致时让测试失败。
//
// 用法：
//   dart run tool/sync_version.dart          # 写回 version.dart
//   dart run tool/sync_version.dart --check  # 只校验，不一致时退出码 1
import 'dart:io';

const _generatedPath = 'lib/features/settings/version.dart';
const _fallbackRepo = 'https://github.com/PythonnotJava/RemindAI';

void main(List<String> args) {
  final checkOnly = args.contains('--check');

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('找不到 pubspec.yaml，请在项目根目录执行本脚本。');
    exit(2);
  }

  final pubspec = pubspecFile.readAsStringSync();
  final fullVersion = _readField(pubspec, 'version');
  if (fullVersion == null || fullVersion.isEmpty) {
    stderr.writeln('pubspec.yaml 里没有 version 字段。');
    exit(2);
  }

  final repo = _readField(pubspec, 'homepage') ?? _fallbackRepo;
  final semver = fullVersion.split('+').first;

  final content = '''
// GENERATED FILE — DO NOT EDIT BY HAND.
//
// 由 `dart run tool/sync_version.dart` 从 pubspec.yaml 生成。
// test/settings/version_sync_test.dart 会在两者不一致时失败，
// 所以忘记跑脚本不会静默漂移（历史上这里手写过 1.0.5，而 pubspec 是 1.0.5+2，
// 结果更新检查永远认为"已是最新"）。

/// 语义版本号（不含 `+build`），用于展示与版本比较。
const String version = '$semver';

/// 完整版本号（含构建号），与 pubspec 完全一致。
const String versionFull = '$fullVersion';

/// 项目主页 / 发布页。
const String repo = '$repo';
''';

  final target = File(_generatedPath);
  final existing = target.existsSync() ? target.readAsStringSync() : null;

  if (existing == content) {
    stdout.writeln('版本号已同步：$fullVersion');
    return;
  }

  if (checkOnly) {
    stderr.writeln(
      '版本号不一致：pubspec=$fullVersion，'
      '但 $_generatedPath 未同步。请执行 dart run tool/sync_version.dart',
    );
    exit(1);
  }

  target.parent.createSync(recursive: true);
  target.writeAsStringSync(content);
  stdout.writeln('已写入 $_generatedPath：$fullVersion');
}

/// 读取顶层 `key: value`（忽略缩进字段与注释）。
String? _readField(String yaml, String key) {
  final match = RegExp(
    '^${RegExp.escape(key)}:\\s*(.+?)\\s*\$',
    multiLine: true,
  ).firstMatch(yaml);
  final raw = match?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  // 去掉可能的引号
  if ((raw.startsWith('"') && raw.endsWith('"')) ||
      (raw.startsWith("'") && raw.endsWith("'"))) {
    return raw.substring(1, raw.length - 1);
  }
  return raw;
}

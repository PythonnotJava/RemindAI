import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/features/settings/version.dart' as v;

/// 版本号单一来源守卫。
///
/// 版本号历史上手写在三处（pubspec.yaml、version.dart、Runner.rc 回退值），
/// 漏改就会让"检查更新"永远认为已是最新。现在 pubspec.yaml 是唯一来源，
/// `version.dart` 由 `dart run tool/sync_version.dart` 生成，本用例负责
/// 在两者漂移时立刻失败。
void main() {
  test('version.dart 与 pubspec.yaml 保持一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version 字段');
    final full = match!.group(1)!;
    final semver = full.split('+').first;

    expect(
      v.versionFull,
      full,
      reason: 'version.dart 已过期：pubspec 是 $full。'
          '请执行 `dart run tool/sync_version.dart`（不要手改 version.dart）',
    );
    expect(
      v.version,
      semver,
      reason: 'version 应为去掉 +build 的语义版本（$semver）',
    );
  });
}

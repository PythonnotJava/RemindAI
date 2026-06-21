import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 单个快捷键绑定
class ShortcutBinding {
  final String id;
  final String label;
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;

  const ShortcutBinding({
    required this.id,
    required this.label,
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  SingleActivator get activator =>
      SingleActivator(key, control: control, shift: shift, alt: alt);

  /// 人类可读的快捷键描述
  String get displayString {
    final parts = <String>[];
    if (control) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    parts.add(key.keyLabel.isNotEmpty ? key.keyLabel : key.debugName ?? '?');
    return parts.join(' + ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'keyId': key.keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
  };

  factory ShortcutBinding.fromJson(
    Map<String, dynamic> json,
    String id,
    String label,
    ShortcutBinding fallback,
  ) {
    final keyId = json['keyId'] as int?;
    return ShortcutBinding(
      id: id,
      label: label,
      key: keyId != null ? LogicalKeyboardKey(keyId) : fallback.key,
      control: json['control'] as bool? ?? fallback.control,
      shift: json['shift'] as bool? ?? fallback.shift,
      alt: json['alt'] as bool? ?? fallback.alt,
    );
  }
}

/// 全局快捷键配置管理
class ShortcutConfig {
  ShortcutConfig._();
  static final instance = ShortcutConfig._();

  /// 所有快捷键的默认值
  static const _defaults = <String, ShortcutBinding>{
    'screenshot': ShortcutBinding(
      id: 'screenshot',
      label: '区域截图',
      key: LogicalKeyboardKey.keyS,
      control: true,
      shift: true,
    ),
  };

  /// 当前生效的绑定
  final Map<String, ShortcutBinding> bindings = {};

  /// 加载配置
  Future<void> load() async {
    // 先填入默认值
    bindings.addAll(_defaults);

    try {
      final file = await _configFile();
      if (file.existsSync()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final entry in json.entries) {
          final defaultBinding = _defaults[entry.key];
          if (defaultBinding != null && entry.value is Map<String, dynamic>) {
            bindings[entry.key] = ShortcutBinding.fromJson(
              entry.value as Map<String, dynamic>,
              entry.key,
              defaultBinding.label,
              defaultBinding,
            );
          }
        }
      }
    } catch (_) {}
  }

  /// 更新一个快捷键
  Future<void> update(String id, ShortcutBinding binding) async {
    bindings[id] = binding;
    await _save();
  }

  /// 重置为默认
  Future<void> resetToDefaults() async {
    bindings.clear();
    bindings.addAll(_defaults);
    await _save();
  }

  /// 获取默认值
  ShortcutBinding getDefault(String id) => _defaults[id]!;

  Future<void> _save() async {
    final file = await _configFile();
    final json = <String, dynamic>{};
    for (final entry in bindings.entries) {
      json[entry.key] = entry.value.toJson();
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'shortcuts.json'));
  }
}

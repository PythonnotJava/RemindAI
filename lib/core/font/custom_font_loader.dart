import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自定义字体加载器 — 扫描 .RemindAI/fonts/ 目录，注册本地字体文件。
class CustomFontLoader {
  CustomFontLoader._();
  static final instance = CustomFontLoader._();

  /// 已加载的自定义字体族名列表
  final List<String> loadedFonts = [];

  /// fonts 目录路径
  String? _fontsDir;

  /// 获取 fonts 目录路径
  Future<String> get fontsDir async {
    if (_fontsDir != null) return _fontsDir!;
    final docs = await getApplicationDocumentsDirectory();
    _fontsDir = p.join(docs.path, '.RemindAI', 'fonts');
    return _fontsDir!;
  }

  /// 确保 fonts 目录存在
  Future<Directory> ensureFontsDir() async {
    final dir = Directory(await fontsDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 扫描并注册所有自定义字体。应在 app 启动时调用一次。
  Future<void> loadAll() async {
    loadedFonts.clear();
    final dir = await ensureFontsDir();

    final fontFiles = dir.listSync().whereType<File>().where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return ext == '.ttf' || ext == '.otf';
    }).toList();

    for (final file in fontFiles) {
      final familyName = _fileToFamilyName(file.path);
      try {
        await _registerFont(file, familyName);
        loadedFonts.add(familyName);
      } catch (_) {
        // 跳过无法加载的字体文件
      }
    }
  }

  /// 导入一个字体文件到 fonts 目录并注册
  Future<String?> importFont(String sourcePath) async {
    final file = File(sourcePath);
    if (!file.existsSync()) return null;

    final dir = await ensureFontsDir();
    final fileName = p.basename(sourcePath);
    final destPath = p.join(dir.path, fileName);

    // 如果已存在同名文件则覆盖
    await file.copy(destPath);

    final familyName = _fileToFamilyName(destPath);
    try {
      await _registerFont(File(destPath), familyName);
      if (!loadedFonts.contains(familyName)) {
        loadedFonts.add(familyName);
      }
      return familyName;
    } catch (_) {
      return null;
    }
  }

  /// 删除一个自定义字体文件
  Future<bool> removeFont(String familyName) async {
    final dir = await ensureFontsDir();
    final files = dir.listSync().whereType<File>().where((f) {
      return _fileToFamilyName(f.path) == familyName;
    });

    for (final file in files) {
      await file.delete();
    }
    loadedFonts.remove(familyName);
    return true;
  }

  /// 从文件名推导字体族名：去扩展名，将连字符/下划线替换为空格
  String _fileToFamilyName(String filePath) {
    final baseName = p.basenameWithoutExtension(filePath);
    // 保留原始文件名作为族名（去掉常见的 -Regular, -Bold 等后缀）
    final cleaned = baseName.replaceAll(
      RegExp(
        r'[-_](Regular|Bold|Italic|Light|Medium|Thin|SemiBold|ExtraBold|Black|ExtraLight)$',
        caseSensitive: false,
      ),
      '',
    );
    return cleaned.replaceAll('_', ' ').replaceAll('-', ' ');
  }

  /// 注册单个字体文件到 Flutter 引擎
  Future<void> _registerFont(File file, String familyName) async {
    final bytes = await file.readAsBytes();
    final fontLoader = FontLoader(familyName);
    fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await fontLoader.load();
  }
}

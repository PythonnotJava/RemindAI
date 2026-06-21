import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/font/custom_font_loader.dart';

/// 已加载的自定义字体列表 provider
final customFontsProvider =
    StateNotifierProvider<CustomFontsNotifier, List<String>>(
      (ref) => CustomFontsNotifier(),
    );

class CustomFontsNotifier extends StateNotifier<List<String>> {
  CustomFontsNotifier() : super(List.of(CustomFontLoader.instance.loadedFonts));

  /// 导入一个新字体文件
  Future<String?> importFont(String path) async {
    final familyName = await CustomFontLoader.instance.importFont(path);
    if (familyName != null) {
      state = List.of(CustomFontLoader.instance.loadedFonts);
    }
    return familyName;
  }

  /// 删除一个自定义字体
  Future<void> removeFont(String familyName) async {
    await CustomFontLoader.instance.removeFont(familyName);
    state = List.of(CustomFontLoader.instance.loadedFonts);
  }
}

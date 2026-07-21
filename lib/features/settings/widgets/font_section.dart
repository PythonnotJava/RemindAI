import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:system_fonts/system_fonts.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../providers/custom_fonts_provider.dart';
import '../../../providers/settings_provider.dart';

/// Google Fonts 预置字体列表
const _googleFontOptions = [
  'Noto Sans SC',
  'Noto Serif SC',
  'LXGW WenKai TC',
  'Ma Shan Zheng',
  'Roboto',
  'Inter',
  'Lato',
  'Open Sans',
  'Source Sans 3',
  'Poppins',
  'Nunito',
  'JetBrains Mono',
  'Fira Code',
];

/// 系统字体 Provider（异步加载）
final systemFontsProvider = FutureProvider<List<String>>((ref) async {
  try {
    final fontList = SystemFonts().getFontList();
    // 过滤并排序系统字体
    final filtered = fontList
        .where((font) => font.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return filtered;
  } catch (e) {
    return [];
  }
});

/// 字体设置区域 — 界面字体 + 交互字体 + 自定义字体管理
class FontSection extends ConsumerWidget {
  const FontSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiFont = ref.watch(uiFontProvider);
    final chatFont = ref.watch(chatFontProvider);
    final chatFontSize = ref.watch(chatFontSizeProvider);
    final customFonts = ref.watch(customFontsProvider);
    final systemFontsAsync = ref.watch(systemFontsProvider);
    final s = context.s;

    return systemFontsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, stack) {
        // 系统字体加载失败时，只使用自定义字体 + Google Fonts
        final allFonts = [...customFonts, ..._googleFontOptions];
        return _buildFontContent(
          context,
          ref,
          uiFont,
          chatFont,
          chatFontSize,
          customFonts,
          allFonts,
          [],
          s,
        );
      },
      data: (systemFonts) {
        // 合并列表：自定义字体 → 系统字体 → Google Fonts
        final allFonts = [
          ...customFonts,
          ...systemFonts,
          ..._googleFontOptions,
        ];
        return _buildFontContent(
          context,
          ref,
          uiFont,
          chatFont,
          chatFontSize,
          customFonts,
          allFonts,
          systemFonts,
          s,
        );
      },
    );
  }

  Widget _buildFontContent(
      BuildContext context,
      WidgetRef ref,
      String uiFont,
      String chatFont,
      double chatFontSize,
      List<String> customFonts,
      List<String> allFonts,
      List<String> systemFonts,
      dynamic s,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 自定义字体管理
        _CustomFontsCard(customFonts: customFonts),
        const SizedBox(height: 12),
        // 界面字体（仅选择字体，不提供字号调节）
        _FontOnlyCard(
          title: s.settingsUiFont,
          subtitle: s.settingsUiFontDesc,
          currentFont: uiFont,
          allFonts: allFonts,
          customFonts: customFonts,
          systemFonts: systemFonts,
          onFontChanged: (font) =>
              ref.read(settingsProvider.notifier).updateUiFont(font),
        ),
        const SizedBox(height: 12),
        // 交互字体
        _FontCard(
          title: s.settingsChatFont,
          subtitle: s.settingsChatFontDesc,
          currentFont: chatFont,
          currentSize: chatFontSize,
          sizeLabel: s.settingsChatFontSize,
          allFonts: allFonts,
          customFonts: customFonts,
          systemFonts: systemFonts,
          onFontChanged: (font) =>
              ref.read(settingsProvider.notifier).updateChatFont(font),
          onSizeChanged: (size) =>
              ref.read(settingsProvider.notifier).updateChatFontSize(size),
        ),
      ],
    );
  }
}

/// 自定义字体管理卡片 — 导入/删除
class _CustomFontsCard extends ConsumerWidget {
  final List<String> customFonts;
  const _CustomFontsCard({required this.customFonts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.settingsCustomFont,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _importFont(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.settingsCustomFontImport),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.settingsCustomFontDesc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (customFonts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: customFonts.map((font) {
                  return Chip(
                    label: Text(font, style: TextStyle(fontFamily: font)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeFont(context, ref, font),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importFont(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.settingsCustomFontPick,
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
      allowMultiple: true,
    );
    if (result == null) return;

    for (final file in result.files) {
      if (file.path == null) continue;
      await ref.read(customFontsProvider.notifier).importFont(file.path!);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.settingsCustomFontImported),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removeFont(
      BuildContext context,
      WidgetRef ref,
      String font,
      ) async {
    await ref.read(customFontsProvider.notifier).removeFont(font);
  }
}

/// 仅字体选择的卡片（无字号调节）
class _FontOnlyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String currentFont;
  final List<String> allFonts;
  final List<String> customFonts;
  final List<String> systemFonts;
  final ValueChanged<String> onFontChanged;

  const _FontOnlyCard({
    required this.title,
    required this.subtitle,
    required this.currentFont,
    required this.allFonts,
    required this.customFonts,
    required this.systemFonts,
    required this.onFontChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _buildFontDropdown(
              currentFont,
              allFonts,
              customFonts,
              systemFonts,
              onFontChanged,
            ),
            const SizedBox(height: 12),
            // 预览
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s.settingsFontPreview,
                style: _getPreviewStyle(currentFont, customFonts, systemFonts, 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String currentFont;
  final double currentSize;
  final String sizeLabel;
  final List<String> allFonts;
  final List<String> customFonts;
  final List<String> systemFonts;
  final ValueChanged<String> onFontChanged;
  final ValueChanged<double> onSizeChanged;

  const _FontCard({
    required this.title,
    required this.subtitle,
    required this.currentFont,
    required this.currentSize,
    required this.sizeLabel,
    required this.allFonts,
    required this.customFonts,
    required this.systemFonts,
    required this.onFontChanged,
    required this.onSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 + 描述
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // 字体选择下拉
            _buildFontDropdown(
              currentFont,
              allFonts,
              customFonts,
              systemFonts,
              onFontChanged,
            ),
            const SizedBox(height: 12),
            // 字号滑块
            Row(
              children: [
                Text(sizeLabel, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 8),
                Text(
                  '${currentSize.round()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: currentSize,
                    min: 10,
                    max: 22,
                    divisions: 12,
                    onChanged: onSizeChanged,
                  ),
                ),
              ],
            ),
            // 预览
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s.settingsFontPreview,
                style: _getPreviewStyle(currentFont, customFonts, systemFonts, currentSize),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 构建通用的字体下拉选择器
Widget _buildFontDropdown(
    String currentFont,
    List<String> allFonts,
    List<String> customFonts,
    List<String> systemFonts,
    ValueChanged<String> onChanged,
    ) {
  final effectiveFont = allFonts.contains(currentFont)
      ? currentFont
      : allFonts.first;

  return Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          value: effectiveFont,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
          items: allFonts.map((font) {
            final isCustom = customFonts.contains(font);
            final isSystem = systemFonts.contains(font);

            // 图标：自定义字体用文件夹图标，系统字体用电脑图标，Google Fonts 无图标
            final icon = isCustom
                ? const Icon(Icons.folder_outlined, size: 14)
                : isSystem
                    ? const Icon(Icons.computer, size: 14)
                    : null;

            final style = (isCustom || isSystem)
                ? TextStyle(fontFamily: font, fontSize: 14)
                : _safeGoogleFont(font, 14);

            return DropdownMenuItem(
              value: font,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    icon,
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      font,
                      style: style,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    ],
  );
}

/// 获取预览 style：自定义字体和系统字体用 fontFamily，Google Fonts 用 getFont
TextStyle _getPreviewStyle(
    String font,
    List<String> customFonts,
    List<String> systemFonts,
    double size,
    ) {
  if (customFonts.contains(font) || systemFonts.contains(font)) {
    return TextStyle(fontFamily: font, fontSize: size);
  }
  return _safeGoogleFont(font, size);
}

/// 安全获取 Google Font，未找到时回退到默认 TextStyle
TextStyle _safeGoogleFont(String fontFamily, double fontSize) {
  try {
    return GoogleFonts.getFont(fontFamily, fontSize: fontSize);
  } catch (_) {
    return TextStyle(fontSize: fontSize);
  }
}

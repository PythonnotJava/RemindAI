import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
import '../../shared/widgets/theme_transition.dart';
import 'widgets/custom_license_page.dart';
import 'widgets/embedding_section.dart';
import 'widgets/qdrant_path_tile.dart';
import 'version.dart' show version, repo;

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.s.settingsTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('加载设置失败: $err')),
        data: (settings) {
          final s = context.s;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _SectionHeader(title: s.settingsAppearance),
              const SizedBox(height: 12),
              _ThemeSwitcher(currentMode: settings.themeMode),
              const SizedBox(height: 12),
              _NotifyOnBlurTile(enabled: settings.notifyOnBlur),
              const SizedBox(height: 12),
              _LocaleSwitcher(currentLocale: settings.locale),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsStorage),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsDatabasePath,
                currentPath: settings.databasePath,
                onChangePressed: () => _pickDatabasePath(context, ref),
              ),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsHistoryPath,
                currentPath: settings.historyPath,
                onChangePressed: () => _pickHistoryPath(context, ref),
              ),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsSkillsPath,
                currentPath: settings.skillsPath,
                onChangePressed: () => _pickSkillsPath(context, ref),
              ),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsLogsPath,
                currentPath: settings.logsPath,
                onChangePressed: () => _pickLogsPath(context, ref),
              ),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsToolPaths),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsPandocPath,
                currentPath: settings.pandocPath.isEmpty
                    ? s.settingsPandocNotDetected
                    : settings.pandocPath,
                onChangePressed: () => _pickPandocPath(context, ref),
              ),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsQdrant),
              const SizedBox(height: 12),
              QdrantPathTile(manualPath: settings.qdrantPath),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsEmbedding),
              const SizedBox(height: 12),
              EmbeddingSection(
                embeddings: settings.embeddings,
                selectedId: settings.selectedEmbeddingId,
              ),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsAbout),
              const SizedBox(height: 12),
              const _AboutCard(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickDatabasePath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '选择数据库保存位置',
      fileName: 'remind_ai.db',
      type: FileType.any,
    );
    if (result == null) return;
    if (!context.mounted) return;

    _showMigrationDialog(context);
    try {
      await ref.read(settingsProvider.notifier).updateDatabasePath(result);
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickHistoryPath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择历史记录保存目录',
    );
    if (result == null) return;
    if (!context.mounted) return;

    _showMigrationDialog(context);
    try {
      await ref.read(settingsProvider.notifier).updateHistoryPath(result);
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickSkillsPath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择技能存放目录',
    );
    if (result == null) return;
    if (!context.mounted) return;

    _showMigrationDialog(context);
    try {
      await ref.read(settingsProvider.notifier).updateSkillsPath(result);
      // 迁移后刷新技能列表
      ref.invalidate(skillsProvider);
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickLogsPath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择日志存放目录',
    );
    if (result == null) return;
    if (!context.mounted) return;

    _showMigrationDialog(context);
    try {
      await ref.read(settingsProvider.notifier).updateLogsPath(result);
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickPandocPath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 Pandoc 可执行文件',
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;
    if (!context.mounted) return;

    await ref
        .read(settingsProvider.notifier)
        .updatePandocPath(result.files.single.path!);
  }

  void _showMigrationDialog(BuildContext context) {
    final s = context.s;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  s.settingsMigrating,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  s.settingsMigratingHint,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Private widgets ---

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PathSettingTile extends StatelessWidget {
  final String label;
  final String currentPath;
  final VoidCallback onChangePressed;

  const _PathSettingTile({
    required this.label,
    required this.currentPath,
    required this.onChangePressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentPath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: onChangePressed,
                  child: Text(
                    // ignore: use_build_context_synchronously
                    S.of(context).settingsChange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwitcher extends ConsumerWidget {
  final String currentMode;
  const _ThemeSwitcher({required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.palette_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              context.s.settingsTheme,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'light',
                  icon: Icon(Icons.light_mode, size: 18),
                ),
                ButtonSegment(
                  value: 'system',
                  icon: Icon(Icons.brightness_auto, size: 18),
                ),
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(Icons.dark_mode, size: 18),
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (set) async {
                final newMode = set.first;
                if (newMode == currentMode) return;

                // 获取 SegmentedButton 的中心位置作为圆形扩散的圆心
                final renderBox = context.findRenderObject() as RenderBox?;
                if (renderBox != null) {
                  final position = renderBox.localToGlobal(Offset.zero);
                  final center =
                      position +
                      Offset(
                        renderBox.size.width * 0.75, // 偏向右侧按钮区域
                        renderBox.size.height / 2,
                      );
                  await ThemeTransitionController.instance.startTransition(
                    center,
                  );
                }

                // 延后一帧再改主题，让动画先启动、截图覆盖旧画面
                // 这样 widget tree 的全量 rebuild 发生在截图之下，用户看不到卡顿
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(settingsProvider.notifier).updateThemeMode(newMode);
                });
              },
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SettingsGlassLogo(size: 40),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RemindAI',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'v$version',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              context.s.aboutDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(repo)),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('GitHub'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomLicensePage(),
                    ),
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: Text(context.s.aboutLicense),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifyOnBlurTile extends ConsumerWidget {
  final bool enabled;
  const _NotifyOnBlurTile({required this.enabled});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        secondary: Icon(
          Icons.notifications_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          S.of(context).settingsNotifyOnBlur,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          S.of(context).settingsNotifyOnBlurDesc,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        value: enabled,
        onChanged: (value) {
          ref.read(settingsProvider.notifier).updateNotifyOnBlur(value);
        },
      ),
    );
  }
}

class _LocaleSwitcher extends ConsumerWidget {
  final String currentLocale;
  const _LocaleSwitcher({required this.currentLocale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.language,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              '语言 / Language',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh', label: Text('中文')),
                ButtonSegment(value: 'system', label: Text('Auto')),
                ButtonSegment(value: 'en', label: Text('EN')),
              ],
              selected: {currentLocale},
              onSelectionChanged: (set) {
                final newLocale = set.first;
                if (newLocale == currentLocale) return;
                ref.read(settingsProvider.notifier).updateLocale(newLocale);
              },
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置页关于卡片的水润拟态 Logo
class _SettingsGlassLogo extends StatelessWidget {
  final double size;
  const _SettingsGlassLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.7),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25 - 0.8),
        child: Image.asset('assets/icons/logo.png', fit: BoxFit.contain),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/utils/directory_picker.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skills_provider.dart';
import '../../shared/widgets/theme_transition.dart';
import 'widgets/custom_license_page.dart';
import 'widgets/embedding_section.dart';
import 'widgets/font_section.dart';
import 'widgets/qdrant_path_tile.dart';
import 'widgets/update_dialog.dart';
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
              _EnterActionSwitcher(currentAction: settings.enterAction),
              const SizedBox(height: 12),
              _LocaleSwitcher(currentLocale: settings.locale),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsFont),
              const SizedBox(height: 12),
              const FontSection(),
              const SizedBox(height: 32),
              _SectionHeader(title: s.settingsStorage),
              const SizedBox(height: 12),
              _PathSettingTile(
                label: s.settingsRootPath,
                currentPath: settings.databasePath.isNotEmpty
                    ? _extractRootDir(settings.databasePath)
                    : '',
                onChangePressed: () => _pickRootDir(context, ref),
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

  /// 从数据库路径中解析 .RemindAI 的父目录
  /// (数据库路径形如 `<parent>/.RemindAI/sqlite/remind_ai.db`)
  static String _extractRootDir(String dbPath) {
    // 向上三级: sqlite/remind_ai.db → .RemindAI → parent
    return p.dirname(p.dirname(p.dirname(dbPath)));
  }

  Future<void> _pickRootDir(BuildContext context, WidgetRef ref) async {
    final result = await pickDirectory(dialogTitle: '选择 .RemindAI 数据根目录');
    if (result == null) return;
    if (!context.mounted) return;

    _showMigrationDialog(context);
    try {
      await ref.read(settingsProvider.notifier).updateRootDir(result);
      ref.invalidate(skillsProvider);
    } on MigrationException catch (e) {
      // 迁移失败已回退，提示用户
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('迁移失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          PopScope(canPop: false, child: const _MigrationProgressDialog()),
    );
  }
}

// --- Private widgets ---

/// 迁移进度对话框 — 实时显示文件复制进度
class _MigrationProgressDialog extends ConsumerWidget {
  const _MigrationProgressDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(migrationProgressProvider);
    final s = context.s;
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.settingsMigrating,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.total > 0 ? progress.fraction : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            if (progress.total > 0)
              Text(
                '${progress.completed} / ${progress.total}',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (progress.currentFile.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                progress.currentFile,
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              s.settingsMigratingHint,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final s = context.s;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final currentAccent = settings?.accentColor ?? 'purple';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：主题模式
            Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  s.settingsTheme,
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
                            renderBox.size.width * 0.75,
                            renderBox.size.height / 2,
                          );
                      await ThemeTransitionController.instance.startTransition(
                        center,
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateThemeMode(newMode);
                    });
                  },
                  showSelectedIcon: false,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 第二行：主题色
            Row(
              children: [
                const SizedBox(width: 32),
                Text(
                  s.settingsAccentColorTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'purple',
                      label: Text(s.settingsAccentColorPurple),
                    ),
                    ButtonSegment(
                      value: 'green',
                      label: Text(s.settingsAccentColorGreen),
                    ),
                    ButtonSegment(
                      value: 'blue',
                      label: Text(s.settingsAccentColorBlue),
                    ),
                    ButtonSegment(
                      value: 'cyan',
                      label: Text(s.settingsAccentColorCyan),
                    ),
                    // 独立主题：最后的黄昏
                    ButtonSegment(
                      value: 'last_twilight',
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wb_twilight, size: 16),
                          const SizedBox(width: 4),
                          Text(s.settingsAccentColorTwilight),
                        ],
                      ),
                    ),
                  ],
                  selected: {currentAccent},
                  onSelectionChanged: (set) async {
                    final newAccent = set.first;
                    if (newAccent == currentAccent) return;

                    // 获取圆心位置
                    final renderBox = context.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      final position = renderBox.localToGlobal(Offset.zero);
                      final center =
                          position +
                          Offset(
                            renderBox.size.width * 0.75,
                            renderBox.size.height * 1.5,
                          );
                      await ThemeTransitionController.instance.startTransition(
                        center,
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateAccentColor(newAccent);
                    });
                  },
                ),
              ],
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(repo)),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('GitHub'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomLicensePage(),
                    ),
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: Text(context.s.aboutLicense),
                ),
                OutlinedButton.icon(
                  onPressed: () => showUpdateDialog(context),
                  icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                  label: Text(context.s.aboutCheckUpdate),
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

class _EnterActionSwitcher extends ConsumerWidget {
  final String currentAction;
  const _EnterActionSwitcher({required this.currentAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.keyboard,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              context.s.settingsEnterAction,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'send',
                  icon: const Icon(Icons.send, size: 16),
                  label: Text(context.s.settingsEnterSend),
                ),
                ButtonSegment(
                  value: 'newline',
                  icon: const Icon(Icons.keyboard_return, size: 16),
                  label: Text(context.s.settingsEnterNewline),
                ),
              ],
              selected: {currentAction},
              onSelectionChanged: (set) {
                final newAction = set.first;
                if (newAction == currentAction) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateEnterAction(newAction);
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

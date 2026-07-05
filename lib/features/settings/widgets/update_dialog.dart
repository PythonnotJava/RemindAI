import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/update/update_checker.dart';
import '../../chat/widgets/markdown_view.dart';
import '../version.dart' show version;

/// 弹出"检查更新"弹窗 —— 立即以 loading 态展示，请求完成后原地切换为
/// 对应终态 (已最新/发现新版本/出错)，不需要调用方等待请求结果再开弹窗。
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _UpdateDialog(),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  UpdateCheckResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    final result = await const UpdateChecker().check(version);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _loading
                ? _LoadingBody(message: s.aboutCheckingUpdate)
                : _buildResultBody(context, colorScheme, _result!),
          ),
        ),
      ),
    );
  }

  Widget _buildResultBody(
    BuildContext context,
    ColorScheme colorScheme,
    UpdateCheckResult result,
  ) {
    switch (result.status) {
      case UpdateCheckStatus.upToDate:
        return _UpToDateBody(
          currentVersion: result.latestVersion ?? version,
          onClose: () => Navigator.of(context).pop(),
        );
      case UpdateCheckStatus.updateAvailable:
        return _UpdateAvailableBody(
          currentVersion: version,
          latestVersion: result.latestVersion!,
          changelog: result.changelog!,
          releaseUrl: result.releaseUrl!,
          onClose: () => Navigator.of(context).pop(),
        );
      case UpdateCheckStatus.error:
        return _ErrorBody(
          message: result.errorMessage ?? '',
          onRetry: _run,
          onClose: () => Navigator.of(context).pop(),
        );
    }
  }
}

/// 加载态：居中的转圈 + 提示文案，尺寸小巧不撑满弹窗，避免出现后又要
/// 变大导致的跳动感（用 AnimatedSize 让切换更平滑）。
class _LoadingBody extends StatelessWidget {
  final String message;
  const _LoadingBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 已是最新版本：用一个柔和的对勾图标做正向反馈，而不是干巴巴一行文字。
class _UpToDateBody extends StatelessWidget {
  final String currentVersion;
  final VoidCallback onClose;

  const _UpToDateBody({required this.currentVersion, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 32,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          s.updateDialogUpToDateTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          s.updateDialogUpToDateBody(currentVersion),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onClose,
            child: Text(s.updateDialogClose),
          ),
        ),
      ],
    );
  }
}

/// 发现新版本：版本号对比小标签 + changelog (markdown 渲染，可滚动) +
/// "前往下载"跳转 GitHub Release 页面。不提供任何应用内下载/安装按钮——
/// 下载安装完全交给用户自己在浏览器里完成。
class _UpdateAvailableBody extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String changelog;
  final String releaseUrl;
  final VoidCallback onClose;

  const _UpdateAvailableBody({
    required this.currentVersion,
    required this.latestVersion,
    required this.changelog,
    required this.releaseUrl,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.tertiaryContainer,
              ),
              child: Icon(
                Icons.rocket_launch_rounded,
                size: 22,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.updateDialogAvailableTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.updateDialogAvailableSubtitle(
                      currentVersion,
                      latestVersion,
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          s.updateDialogChangelogTitle,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: SingleChildScrollView(
            child: MarkdownView(
              data: changelog,
              textColor: colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onClose,
                child: Text(s.updateDialogClose),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(releaseUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(s.updateDialogGoDownload),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 出错：不用红色刺眼报错样式压过去，用 error 容器色柔和提示 + 重试按钮。
class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ErrorBody({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = context.s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.errorContainer,
          ),
          child: Icon(
            Icons.wifi_off_rounded,
            size: 28,
            color: colorScheme.onErrorContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          s.updateDialogErrorTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onClose,
                child: Text(s.updateDialogClose),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onRetry,
                child: Text(s.updateDialogRetry),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

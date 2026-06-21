import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_ext.dart';

/// 工具链检测页 — 嵌入在服务 Tab 中
///
/// 列出推荐的外部命令行工具 (pandoc/bun/node/git 等)，
/// 以系统环境变量 PATH 可寻为准。默认不检测，
/// 点击按钮后才批量探测，避免无意义的性能开销。
class ToolchainPageBody extends ConsumerStatefulWidget {
  const ToolchainPageBody({super.key});

  @override
  ConsumerState<ToolchainPageBody> createState() => _ToolchainPageBodyState();
}

/// 单个工具的探测结果
class _ProbeResult {
  final bool found;
  final String? path;
  final String? version;

  const _ProbeResult({required this.found, this.path, this.version});
}

/// 推荐工具的元信息
class _ToolSpec {
  final String command; // 实际探测的命令名
  final String label; // 展示名
  final String descKey; // i18n 描述 key
  final String homepage; // 官网，用于安装引导

  const _ToolSpec(this.command, this.label, this.descKey, this.homepage);
}

/// 工具分类
class _ToolGroup {
  final String titleKey;
  final IconData icon;
  final List<_ToolSpec> tools;

  const _ToolGroup(this.titleKey, this.icon, this.tools);
}

class _ToolchainPageBodyState extends ConsumerState<ToolchainPageBody> {
  /// 探测结果缓存 (command -> 结果)，null 表示尚未检测
  final Map<String, _ProbeResult> _results = {};
  bool _probing = false;
  int _probedCount = 0;
  int _totalCount = 0;

  /// 推荐工具清单 (按用途分组)
  static const List<_ToolGroup> _groups = [
    _ToolGroup('toolchainGroupRuntime', Icons.terminal, [
      _ToolSpec('node', 'Node.js', 'toolchainDescNode', 'https://nodejs.org'),
      _ToolSpec('bun', 'Bun', 'toolchainDescBun', 'https://bun.sh'),
      _ToolSpec(
        'python',
        'Python',
        'toolchainDescPython',
        'https://www.python.org',
      ),
      _ToolSpec('deno', 'Deno', 'toolchainDescDeno', 'https://deno.com'),
    ]),
    _ToolGroup('toolchainGroupPkg', Icons.inventory_2_outlined, [
      _ToolSpec('npm', 'npm', 'toolchainDescNpm', 'https://www.npmjs.com'),
      _ToolSpec('pnpm', 'pnpm', 'toolchainDescPnpm', 'https://pnpm.io'),
      _ToolSpec('yarn', 'Yarn', 'toolchainDescYarn', 'https://yarnpkg.com'),
      _ToolSpec('pip', 'pip', 'toolchainDescPip', 'https://pip.pypa.io'),
      _ToolSpec('uv', 'uv', 'toolchainDescUv', 'https://docs.astral.sh/uv'),
    ]),
    _ToolGroup('toolchainGroupVcs', Icons.account_tree_outlined, [
      _ToolSpec('git', 'Git', 'toolchainDescGit', 'https://git-scm.com'),
    ]),
    _ToolGroup('toolchainGroupDoc', Icons.description_outlined, [
      _ToolSpec(
        'pandoc',
        'Pandoc',
        'toolchainDescPandoc',
        'https://pandoc.org',
      ),
      _ToolSpec(
        'pdftotext',
        'Poppler',
        'toolchainDescPdftotext',
        'https://poppler.freedesktop.org',
      ),
      _ToolSpec(
        'xelatex',
        'XeLaTeX',
        'toolchainDescXelatex',
        'https://www.latex-project.org',
      ),
      _ToolSpec('typst', 'Typst', 'toolchainDescTypst', 'https://typst.app'),
    ]),
    _ToolGroup('toolchainGroupMedia', Icons.image_outlined, [
      _ToolSpec(
        'ffmpeg',
        'FFmpeg',
        'toolchainDescFfmpeg',
        'https://ffmpeg.org',
      ),
      _ToolSpec(
        'magick',
        'ImageMagick',
        'toolchainDescMagick',
        'https://imagemagick.org',
      ),
    ]),
    _ToolGroup('toolchainGroupNet', Icons.cloud_outlined, [
      _ToolSpec('curl', 'cURL', 'toolchainDescCurl', 'https://curl.se'),
      _ToolSpec(
        'wget',
        'Wget',
        'toolchainDescWget',
        'https://www.gnu.org/software/wget',
      ),
    ]),
  ];

  /// 部分工具的版本参数不是 --version
  static const Map<String, String> _versionFlags = {
    'xelatex': '--version',
    'magick': '--version',
  };

  /// 全部工具的扁平列表
  List<_ToolSpec> get _allTools =>
      _groups.expand((g) => g.tools).toList(growable: false);

  /// 批量检测所有工具
  Future<void> _probeAll() async {
    if (_probing) return;
    final tools = _allTools;
    setState(() {
      _probing = true;
      _probedCount = 0;
      _totalCount = tools.length;
      _results.clear();
    });

    for (final tool in tools) {
      final result = await _probeSingle(tool.command);
      if (!mounted) return;
      setState(() {
        _results[tool.command] = result;
        _probedCount++;
      });
    }

    if (!mounted) return;
    setState(() => _probing = false);
  }

  /// 探测单个工具：where/which 查路径 + --version 取版本
  Future<_ProbeResult> _probeSingle(String command) async {
    final locateCmd = Platform.isWindows ? 'where' : 'which';
    try {
      final locate = await Process.run(locateCmd, [
        command,
      ], runInShell: true).timeout(const Duration(seconds: 4));

      if (locate.exitCode != 0) {
        return const _ProbeResult(found: false);
      }

      final path = (locate.stdout as String? ?? '')
          .trim()
          .split('\n')
          .first
          .trim();
      if (path.isEmpty) return const _ProbeResult(found: false);

      final version = await _getVersion(command);
      return _ProbeResult(found: true, path: path, version: version);
    } on TimeoutException {
      return const _ProbeResult(found: false);
    } catch (_) {
      return const _ProbeResult(found: false);
    }
  }

  Future<String?> _getVersion(String command) async {
    final flag = _versionFlags[command] ?? '--version';
    try {
      final result = await Process.run(command, [
        flag,
      ], runInShell: true).timeout(const Duration(seconds: 4));

      final raw = (result.stdout as String? ?? '').trim();
      final out = raw.isNotEmpty
          ? raw
          : (result.stderr as String? ?? '').trim();
      if (out.isEmpty) return null;

      final firstLine = out.split('\n').first.trim();
      return firstLine.length > 100 ? firstLine.substring(0, 100) : firstLine;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final foundCount = _results.values.where((r) => r.found).length;
    final hasProbed = _results.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 说明卡片 ──
        Card(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.s.toolchainDescription,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 检测按钮 + 统计 ──
        Row(
          children: [
            FilledButton.icon(
              onPressed: _probing ? null : _probeAll,
              icon: _probing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(
                _probing
                    ? '${context.s.toolchainDetecting} ($_probedCount/$_totalCount)'
                    : context.s.toolchainDetect,
              ),
            ),
            const SizedBox(width: 12),
            if (hasProbed && !_probing)
              Text(
                context.s.toolchainSummary(foundCount, _results.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 分组工具列表 ──
        for (final group in _groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(group.icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  toolchainL10n(context.s, group.titleKey),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.tools.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ToolTile(
                    spec: group.tools[i],
                    result: _results[group.tools[i].command],
                    probing: _probing,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// 单个工具行
class _ToolTile extends StatelessWidget {
  final _ToolSpec spec;
  final _ProbeResult? result;
  final bool probing;

  const _ToolTile({
    required this.spec,
    required this.result,
    required this.probing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 状态指示
    Widget statusIcon;
    if (result == null) {
      statusIcon = Icon(
        Icons.remove_circle_outline,
        size: 20,
        color: colorScheme.outline,
      );
    } else if (result!.found) {
      statusIcon = Icon(
        Icons.check_circle,
        size: 20,
        color: Colors.green.shade600,
      );
    } else {
      statusIcon = Icon(
        Icons.cancel_outlined,
        size: 20,
        color: colorScheme.error,
      );
    }

    // 副标题：描述 + (检测后) 路径/版本
    final subtitleLines = <Widget>[
      Text(
        toolchainL10n(context.s, spec.descKey),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    ];

    if (result != null && result!.found) {
      if (result!.version != null) {
        subtitleLines.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              result!.version!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green.shade700,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (result!.path != null) {
        subtitleLines.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              result!.path!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    return ListTile(
      leading: statusIcon,
      title: Row(
        children: [
          Text(spec.label, style: theme.textTheme.bodyLarge),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              spec.command,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subtitleLines,
      ),
      trailing: result != null && !result!.found && !probing
          ? TextButton.icon(
              onPressed: () => _openHomepage(context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(context.s.toolchainInstall),
            )
          : null,
      isThreeLine: result != null && result!.found,
    );
  }

  Future<void> _openHomepage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failMsg = context.s.toolchainOpenFailed(spec.homepage);
    try {
      final ok = await launchUrl(
        Uri.parse(spec.homepage),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(failMsg),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(failMsg), duration: const Duration(seconds: 3)),
      );
    }
  }
}

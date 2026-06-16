import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../version.dart' show version;

/// 自定义许可证页面，替换 Flutter 内置的 showLicensePage。
/// 底部显示 "Powered by Flutter & PythonnotJava"。
class CustomLicensePage extends StatefulWidget {
  const CustomLicensePage({super.key});

  @override
  State<CustomLicensePage> createState() => _CustomLicensePageState();
}

class _CustomLicensePageState extends State<CustomLicensePage> {
  final List<_PackageLicenses> _packages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    // 收集所有许可证并按包名分组
    final Map<String, List<LicenseEntry>> grouped = {};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        grouped.putIfAbsent(package, () => []).add(entry);
      }
    }

    final sorted = grouped.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _packages.addAll(
        sorted.map((e) => _PackageLicenses(name: e.key, entries: e.value)),
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.s.aboutLicense)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(colorScheme),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _packages.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(colorScheme);
        if (index == _packages.length + 1) return _buildFooter(colorScheme);
        final pkg = _packages[index - 1];
        return _buildPackageTile(pkg, colorScheme);
      },
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showLogoDialog(context),
            child: _GlassLogoBox(asset: 'assets/icons/logo.png', size: 48),
          ),
          const SizedBox(height: 12),
          Text(
            'RemindAI',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'v$version',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
          const SizedBox(height: 16),
          Divider(color: colorScheme.outlineVariant),
        ],
      ),
    );
  }

  Widget _buildPackageTile(_PackageLicenses pkg, ColorScheme colorScheme) {
    return ListTile(
      title: Text(pkg.name),
      trailing: Text(
        '${pkg.entries.length} 条',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
      ),
      onTap: () => _showPackageDetail(pkg),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 24),
      child: Column(
        children: [
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 20),
          Text(
            'Powered by',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flutter logo
              FlutterLogo(size: 28),
              const SizedBox(width: 6),
              Text(
                'Flutter',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '&',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              // RemindAI logo (点击放大)
              GestureDetector(
                onTap: () => _showLogoDialog(context),
                child: _GlassLogoBox(asset: 'assets/icons/logo.png', size: 28),
              ),
              const SizedBox(width: 6),
              Text(
                'PythonnotJava',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogoDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(40),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.6),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(
                'assets/icons/logo_egg.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPackageDetail(_PackageLicenses pkg) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _PackageDetailPage(package: pkg)));
  }
}

class _PackageLicenses {
  final String name;
  final List<LicenseEntry> entries;
  const _PackageLicenses({required this.name, required this.entries});
}

class _PackageDetailPage extends StatelessWidget {
  final _PackageLicenses package;
  const _PackageDetailPage({required this.package});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(package.name)),
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: package.entries.length,
        separatorBuilder: (_, _) => const Divider(height: 32),
        itemBuilder: (context, index) {
          final paragraphs = package.entries[index].paragraphs.toList();
          return SelectableText.rich(
            TextSpan(
              children: paragraphs.map((p) {
                final indent = p.indent > 0 ? '    ' * p.indent : '';
                return TextSpan(text: '$indent${p.text}\n\n');
              }).toList(),
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'Consolas',
              height: 1.5,
            ),
          );
        },
      ),
    );
  }
}

/// 水润拟态 Logo 方块 — 透明背景 + 光晕 + 柔和边框
class _GlassLogoBox extends StatelessWidget {
  final String asset;
  final double size;
  const _GlassLogoBox({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
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
        borderRadius: BorderRadius.circular(size * 0.22 - 0.8),
        child: Image.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}

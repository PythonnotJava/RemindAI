import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../core/search/search_capability.dart';
import '../../providers/search_provider.dart';

/// 搜索服务配置页 — 嵌入在服务 Tab 中
class SearchPageBody extends ConsumerWidget {
  const SearchPageBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(searchSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (settings) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 说明卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.s.searchDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Tavily
            _SearchProviderCard(
              provider: SearchProvider.tavily,
              config: settings.getConfig(SearchProvider.tavily),
              icon: Icons.travel_explore,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            // Brave
            _SearchProviderCard(
              provider: SearchProvider.brave,
              config: settings.getConfig(SearchProvider.brave),
              icon: Icons.shield_outlined,
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            // Baidu
            _SearchProviderCard(
              provider: SearchProvider.baidu,
              config: settings.getConfig(SearchProvider.baidu),
              icon: Icons.search,
              color: Colors.red,
            ),
          ],
        );
      },
    );
  }
}

/// 单个搜索服务商配置卡片
class _SearchProviderCard extends ConsumerStatefulWidget {
  final SearchProvider provider;
  final SearchServiceConfig config;
  final IconData icon;
  final Color color;

  const _SearchProviderCard({
    required this.provider,
    required this.config,
    required this.icon,
    required this.color,
  });

  @override
  ConsumerState<_SearchProviderCard> createState() =>
      _SearchProviderCardState();
}

class _SearchProviderCardState extends ConsumerState<_SearchProviderCard> {
  late TextEditingController _apiKeyCtrl;
  bool _obscureKey = true;
  bool _editing = false;
  bool _testing = false;
  _TestResult? _testResult;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(text: widget.config.apiKey);
  }

  @override
  void didUpdateWidget(covariant _SearchProviderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.apiKey != widget.config.apiKey && !_editing) {
      _apiKeyCtrl.text = widget.config.apiKey;
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  String get _providerName => switch (widget.provider) {
    SearchProvider.tavily => 'Tavily',
    SearchProvider.brave => 'Brave Search',
    SearchProvider.baidu => context.s.searchBaidu,
    SearchProvider.none => '',
  };

  String get _providerHint => switch (widget.provider) {
    SearchProvider.tavily => context.s.searchTavilyHint,
    SearchProvider.brave => context.s.searchBraveHint,
    SearchProvider.baidu => context.s.searchBaiduHint,
    SearchProvider.none => '',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.08)),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _providerName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _providerHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 配置状态指示
                if (widget.config.isConfigured)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      context.s.searchConfigured,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // API Key 输入
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _apiKeyCtrl,
                        obscureText: _obscureKey,
                        onChanged: (_) {
                          _editing = true;
                          // 清除旧的测试结果
                          if (_testResult != null) {
                            setState(() => _testResult = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: context.s.searchApiKeyHint,
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        _editing = false;
                        ref
                            .read(searchSettingsProvider.notifier)
                            .updateApiKey(
                              widget.provider,
                              _apiKeyCtrl.text.trim(),
                            );
                      },
                      child: Text(context.s.searchSave),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 测试连接按钮 + 结果
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check, size: 16),
                      label: Text(
                        _testing
                            ? context.s.searchTesting
                            : context.s.searchTestConnection,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_testResult != null)
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              _testResult!.success
                                  ? Icons.check_circle
                                  : Icons.error,
                              size: 16,
                              color: _testResult!.success
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _testResult!.message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _testResult!.success
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      setState(
        () => _testResult = _TestResult(
          success: false,
          message: context.s.searchApiKeyHint,
        ),
      );
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final error = await SearchCapability.testConnection(
      provider: widget.provider,
      apiKey: key,
    );

    if (!mounted) return;

    setState(() {
      _testing = false;
      _testResult = _TestResult(
        success: error == null,
        message: error ?? context.s.searchTestSuccess,
      );
    });

    // 测试成功时自动保存
    if (error == null) {
      ref
          .read(searchSettingsProvider.notifier)
          .updateApiKey(widget.provider, key);
    }
  }
}

/// 测试连接结果
class _TestResult {
  final bool success;
  final String message;
  _TestResult({required this.success, required this.message});
}

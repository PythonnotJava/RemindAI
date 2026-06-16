import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/search/search_config.dart';
export '../core/search/search_config.dart';

/// 搜索服务配置状态 (持久化到 search_settings.json)
class SearchSettings {
  final Map<SearchProvider, SearchServiceConfig> configs;

  const SearchSettings({this.configs = const {}});

  SearchServiceConfig getConfig(SearchProvider provider) {
    return configs[provider] ?? const SearchServiceConfig();
  }

  SearchSettings updateConfig(
    SearchProvider provider,
    SearchServiceConfig config,
  ) {
    return SearchSettings(configs: {...configs, provider: config});
  }

  Map<String, dynamic> toJson() => {
    'configs': configs.map((k, v) => MapEntry(k.id, v.toJson())),
  };

  factory SearchSettings.fromJson(Map<String, dynamic> json) {
    final configsRaw = json['configs'] as Map<String, dynamic>? ?? {};
    final configs = <SearchProvider, SearchServiceConfig>{};
    for (final entry in configsRaw.entries) {
      final provider = SearchProvider.fromId(entry.key);
      if (provider != SearchProvider.none) {
        configs[provider] = SearchServiceConfig.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }
    return SearchSettings(configs: configs);
  }
}

/// 搜索设置 Provider
final searchSettingsProvider =
    AsyncNotifierProvider<SearchSettingsNotifier, SearchSettings>(
      SearchSettingsNotifier.new,
    );

class SearchSettingsNotifier extends AsyncNotifier<SearchSettings> {
  @override
  Future<SearchSettings> build() async {
    return _load();
  }

  Future<String> get _filePath async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'search_settings.json');
  }

  Future<SearchSettings> _load() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return const SearchSettings();
      final content = await file.readAsString();
      return SearchSettings.fromJson(jsonDecode(content));
    } catch (_) {
      return const SearchSettings();
    }
  }

  Future<void> _save(SearchSettings settings) async {
    final path = await _filePath;
    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) await dir.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  /// 更新指定 provider 的 API Key
  Future<void> updateApiKey(SearchProvider provider, String apiKey) async {
    final current = state.valueOrNull ?? const SearchSettings();
    final config = current.getConfig(provider).copyWith(apiKey: apiKey);
    final updated = current.updateConfig(provider, config);
    await _save(updated);
    state = AsyncData(updated);
  }

  /// 更新指定 provider 的启用状态
  Future<void> toggleEnabled(SearchProvider provider, bool enabled) async {
    final current = state.valueOrNull ?? const SearchSettings();
    final config = current.getConfig(provider).copyWith(enabled: enabled);
    final updated = current.updateConfig(provider, config);
    await _save(updated);
    state = AsyncData(updated);
  }
}

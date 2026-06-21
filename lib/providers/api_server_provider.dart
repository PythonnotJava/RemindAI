import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger/app_logger.dart';
import '../core/server/api_server.dart';
import '../core/server/api_server_config.dart';

/// 对外 API 服务配置 Provider。
final apiServerConfigProvider =
    AsyncNotifierProvider<ApiServerConfigNotifier, ApiServerConfig>(
      ApiServerConfigNotifier.new,
    );

class ApiServerConfigNotifier extends AsyncNotifier<ApiServerConfig> {
  @override
  Future<ApiServerConfig> build() async {
    return ApiServerConfig.load();
  }

  /// 保存配置并按需重启服务。
  Future<void> save(ApiServerConfig config) async {
    await config.save();
    state = AsyncData(config);
    // 应用到运行中的服务
    await ref.read(apiServerProvider).applyConfig(config);
  }
}

/// 单例 ApiServer。Provider 持有, 由配置驱动启停。
final apiServerProvider = Provider<ApiServer>((ref) {
  final config =
      ref.read(apiServerConfigProvider).valueOrNull ?? const ApiServerConfig();
  final server = ApiServer(ref, config);
  ref.onDispose(() => server.stop());
  return server;
});

/// 启动时调用: 若配置为启用则拉起服务。进程级一次性, 重复调用安全。
bool _bootstrapped = false;
Future<void> bootstrapApiServer(WidgetRef ref) async {
  if (_bootstrapped) return;
  _bootstrapped = true;
  try {
    final config = await ref.read(apiServerConfigProvider.future);
    if (config.canStart) {
      // applyConfig 会把已加载的配置注入 server 并按需启动,
      // 避免使用 Provider 构造时可能为 null 的默认配置。
      await ref.read(apiServerProvider).applyConfig(config);
    }
  } catch (e) {
    AppLogger.instance.log('[ApiServer] 启动失败: $e');
  }
}

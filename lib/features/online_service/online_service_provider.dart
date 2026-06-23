import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/online_service/online_server.dart';
import '../../core/online_service/online_service_config.dart';
import '../../core/online_service/online_session.dart';

/// 在线服务器实例 Provider (独立，不依赖 config provider)
final onlineServerProvider = Provider<OnlineServer>((ref) {
  final server = OnlineServer(ref, const OnlineServiceConfig());
  ref.onDispose(() => server.dispose());
  return server;
});

/// 在线服务配置 Provider
class OnlineServiceConfigNotifier extends AsyncNotifier<OnlineServiceConfig> {
  @override
  Future<OnlineServiceConfig> build() async {
    final config = await OnlineServiceConfig.load();
    // 初始化时把配置同步到 server (不启动，只设置)
    final server = ref.read(onlineServerProvider);
    server.updateConfig(config);
    return config;
  }

  Future<void> save(OnlineServiceConfig config) async {
    state = AsyncData(config);
    final server = ref.read(onlineServerProvider);
    await server.applyConfig(config);
  }
}

final onlineServiceConfigProvider =
    AsyncNotifierProvider<OnlineServiceConfigNotifier, OnlineServiceConfig>(
      OnlineServiceConfigNotifier.new,
    );

/// 活跃连接列表 (定期刷新)
class OnlineUsersNotifier extends StateNotifier<List<OnlineSession>> {
  final OnlineServer _server;
  StreamSubscription? _sub;
  Timer? _refreshTimer;

  OnlineUsersNotifier(this._server) : super(_server.activeSessions) {
    _sub = _server.events.listen((_) {
      state = _server.activeSessions;
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => state = _server.activeSessions,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final onlineUsersProvider =
    StateNotifierProvider<OnlineUsersNotifier, List<OnlineSession>>((ref) {
      final server = ref.watch(onlineServerProvider);
      return OnlineUsersNotifier(server);
    });

/// 启动在线服务 (app 启动时调用, 同 bootstrapApiServer 模式)
bool _bootstrapped = false;
Future<void> bootstrapOnlineService(WidgetRef ref) async {
  if (_bootstrapped) return;
  _bootstrapped = true;
  try {
    final config = await ref.read(onlineServiceConfigProvider.future);
    if (config.canStart) {
      final server = ref.read(onlineServerProvider);
      await server.applyConfig(config);
    }
  } catch (_) {}
}

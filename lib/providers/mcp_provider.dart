import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logger/app_logger.dart';
import '../core/mcp/local_process_launcher.dart';
import '../core/mcp/mcp_client.dart';
import '../core/mcp/mcp_registry.dart';
import '../core/mcp/mcp_reconnect_policy.dart';
import '../core/mcp/mcp_tool_names.dart';
import '../core/mcp/transports/mcp_transport.dart';
import 'database_provider.dart';

/// MCP 注册表 Provider
final mcpRegistryProvider = Provider<McpRegistry>((ref) {
  final db = ref.watch(databaseProvider);
  return McpRegistry(db);
});

/// MCP 服务器列表 Provider
final mcpServersProvider =
    AsyncNotifierProvider<McpServersNotifier, List<McpServerConfig>>(
      McpServersNotifier.new,
    );

class McpServersNotifier extends AsyncNotifier<List<McpServerConfig>> {
  McpRegistry get _registry => ref.read(mcpRegistryProvider);

  @override
  Future<List<McpServerConfig>> build() async {
    return _registry.getAll();
  }

  Future<McpServerConfig> add({
    required String name,
    McpTransportType transportType = McpTransportType.stdio,
    String command = '',
    List<String> args = const [],
    Map<String, String> env = const {},
    String cwd = '',
    String url = '',
    Map<String, String> httpHeaders = const {},
  }) async {
    final config = await _registry.add(
      name: name,
      transportType: transportType,
      command: command,
      args: args,
      env: env,
      cwd: cwd,
      url: url,
      httpHeaders: httpHeaders,
    );
    ref.invalidateSelf();
    return config;
  }

  Future<void> updateServer(McpServerConfig config) async {
    await _registry.update(config);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    // 断开连接
    ref.read(mcpConnectionsProvider.notifier).disconnect(id);
    await _registry.remove(id);
    ref.invalidateSelf();
  }

  Future<void> toggleEnabled(String id) async {
    final servers = state.valueOrNull ?? [];
    final server = servers.firstWhere((s) => s.id == id);
    await _registry.setEnabled(id, !server.enabled);
    if (server.enabled) {
      // 禁用时断开连接
      ref.read(mcpConnectionsProvider.notifier).disconnect(id);
    }
    ref.invalidateSelf();
  }

  /// 按新顺序重排卡片 (拖拽排序)
  Future<void> reorder(List<McpServerConfig> ordered) async {
    // 乐观更新本地状态，立即反映拖拽结果
    state = AsyncData(ordered);
    await _registry.reorder(ordered.map((c) => c.id).toList());
  }
}

/// MCP 活跃连接状态
class McpConnectionState {
  final Map<String, McpClient> clients;
  final Map<String, McpConnectionStatus> statuses;
  final Map<String, List<Map<String, dynamic>>> toolsCache;

  /// SSE/HTTP 模式下，若配置了 command 而由应用代为拉起的本地进程。
  /// 只有这类连接才会有条目；纯远程连接 (未配置 command) 或 stdio 模式
  /// (子进程生命周期已经在 StdioTransport 内部管理) 都不会出现在这里。
  final Map<String, LocalProcessLauncher> localProcesses;

  /// 各服务器最近一次异常断开的原因（用于 UI 提示/排查）。
  /// 主动 disconnect 不会写入这里。
  final Map<String, String> lastErrors;

  /// 各服务器当前进行到第几次自动重连（1-based；0/缺省 = 未在重连）。
  final Map<String, int> reconnectAttempts;

  const McpConnectionState({
    this.clients = const {},
    this.statuses = const {},
    this.toolsCache = const {},
    this.localProcesses = const {},
    this.lastErrors = const {},
    this.reconnectAttempts = const {},
  });

  McpConnectionState copyWith({
    Map<String, McpClient>? clients,
    Map<String, McpConnectionStatus>? statuses,
    Map<String, List<Map<String, dynamic>>>? toolsCache,
    Map<String, LocalProcessLauncher>? localProcesses,
    Map<String, String>? lastErrors,
    Map<String, int>? reconnectAttempts,
  }) {
    return McpConnectionState(
      clients: clients ?? this.clients,
      statuses: statuses ?? this.statuses,
      toolsCache: toolsCache ?? this.toolsCache,
      localProcesses: localProcesses ?? this.localProcesses,
      lastErrors: lastErrors ?? this.lastErrors,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
    );
  }
}

enum McpConnectionStatus {
  disconnected,
  connecting,
  connected,

  /// 连接断了，正在按指数退避自动重连（见 [McpReconnectPolicy]）。
  reconnecting,
  error,
}

/// MCP 连接管理 Provider
final mcpConnectionsProvider =
    StateNotifierProvider<McpConnectionsNotifier, McpConnectionState>((ref) {
      return McpConnectionsNotifier();
    });

class McpConnectionsNotifier extends StateNotifier<McpConnectionState> {
  /// serverId → 断线监听。真正的"进程崩了/连接断了"由它来发现：
  /// 以前 onDisconnected 没有任何订阅者，传输层断开后 status 仍停在
  /// connected，UI 与 Agent 都会继续使用一个已经死掉的连接。
  final Map<String, StreamSubscription<String>> _disconnectSubs = {};

  /// serverId → 连接配置（自动重连需要它，否则只能拿到 client 没法重连）。
  final Map<String, McpServerConfig> _configs = {};

  /// serverId → 待触发的重连定时器。
  final Map<String, Timer> _retryTimers = {};

  /// serverId → 已经尝试过的自动重连次数。
  final Map<String, int> _retryAttempts = {};

  /// 重连策略（指数退避 + 次数上限）。
  final McpReconnectPolicy reconnectPolicy;

  McpConnectionsNotifier({this.reconnectPolicy = const McpReconnectPolicy()})
    : super(const McpConnectionState());

  /// 订阅某个连接的断线事件。主动 disconnect 前会先 cancel。
  void _watchDisconnect(String serverId, McpClient client) {
    _disconnectSubs.remove(serverId)?.cancel();
    final stream = client.onDisconnected;
    if (stream == null) return;
    _disconnectSubs[serverId] = stream.listen(
      (reason) => _onUnexpectedDisconnect(serverId, reason),
      onError: (Object e) => _onUnexpectedDisconnect(serverId, e.toString()),
    );
  }

  /// 连接在非预期情况下断开：立刻把状态改成 error 并把工具下线，
  /// 避免模型继续调用已经不可用的工具；随后按指数退避自动重连。
  void _onUnexpectedDisconnect(String serverId, String reason) {
    if (!mounted) return;
    // 已经处于 error/reconnecting 态说明已经安排过重连，不重复处理
    final current = state.statuses[serverId];
    if (current == null ||
        current == McpConnectionStatus.error ||
        current == McpConnectionStatus.reconnecting) {
      return;
    }

    AppLogger.instance.log('[MCP] 连接意外断开 ($serverId): $reason');
    state = state.copyWith(
      statuses: {...state.statuses, serverId: McpConnectionStatus.error},
      toolsCache: Map<String, List<Map<String, dynamic>>>.from(state.toolsCache)
        ..remove(serverId),
      lastErrors: {...state.lastErrors, serverId: reason},
    );

    _scheduleReconnect(serverId);
  }

  /// 安排下一次自动重连（指数退避；超过上限就停在 error 态）。
  ///
  /// 只有"意外断开"才走这里——用户主动 disconnect 会先取消定时器。
  void _scheduleReconnect(String serverId) {
    if (!mounted) return;
    final config = _configs[serverId];
    if (config == null) return; // 没记住配置就没法重连（理论上不会发生）
    if (_retryTimers.containsKey(serverId)) return;

    final attempt = (_retryAttempts[serverId] ?? 0) + 1;
    if (!reconnectPolicy.shouldRetry(attempt)) {
      final reason = state.lastErrors[serverId] ?? '连接断开';
      AppLogger.instance.log(
        '[MCP] $serverId 自动重连已达上限 (${reconnectPolicy.maxAttempts} 次)，停止重试',
      );
      state = state.copyWith(
        statuses: {...state.statuses, serverId: McpConnectionStatus.error},
        lastErrors: {
          ...state.lastErrors,
          serverId:
              '$reason（已自动重连 ${reconnectPolicy.maxAttempts} 次仍失败，请手动重连）',
        },
        reconnectAttempts: Map<String, int>.from(state.reconnectAttempts)
          ..remove(serverId),
      );
      _retryAttempts.remove(serverId);
      return;
    }

    _retryAttempts[serverId] = attempt;
    final delay = reconnectPolicy.delayForAttempt(attempt);
    state = state.copyWith(
      statuses: {...state.statuses, serverId: McpConnectionStatus.reconnecting},
      reconnectAttempts: {...state.reconnectAttempts, serverId: attempt},
    );
    AppLogger.instance.log(
      '[MCP] ${delay.inSeconds}s 后第 $attempt/${reconnectPolicy.maxAttempts} 次重连 $serverId',
    );

    _retryTimers[serverId] = Timer(delay, () {
      _retryTimers.remove(serverId);
      if (!mounted) return;
      unawaited(_reconnect(serverId, config));
    });
  }

  /// 执行一次重连；失败则继续排下一次（直到策略上限）。
  Future<void> _reconnect(String serverId, McpServerConfig config) async {
    if (!mounted) return;
    try {
      await connect(config, isReconnect: true);
      AppLogger.instance.log(
        '[MCP] $serverId 重连成功（第 ${_retryAttempts[serverId] ?? 1} 次尝试）',
      );
    } catch (e) {
      AppLogger.instance.log('[MCP] $serverId 重连失败: $e');
      if (!mounted) return;
      // connect() 失败已把状态置为 error，这里接着排下一次退避
      _scheduleReconnect(serverId);
    }
  }

  /// 连接到 MCP 服务器
  ///
  /// [isReconnect] 由自动重连内部使用：为 true 时不会重置重连计数，
  /// 否则失败后计数会被清零，退避永远停在第一档（等于无限快重试）。
  Future<List<Map<String, dynamic>>> connect(
    McpServerConfig config, {
    bool isReconnect = false,
  }) async {
    // 手动连接时取消尚未触发的自动重连并清零计数（用户已介入，重新给满配额）
    if (!isReconnect) {
      _retryTimers.remove(config.id)?.cancel();
      _retryAttempts.remove(config.id);
    }
    // 记住配置：断线后的自动重连需要它重建连接
    _configs[config.id] = config;

    // 更新状态为 connecting
    state = state.copyWith(
      statuses: {...state.statuses, config.id: McpConnectionStatus.connecting},
    );

    LocalProcessLauncher? launcher;
    try {
      final client = McpClient();

      switch (config.transportType) {
        case McpTransportType.stdio:
          // 确定 workingDirectory：优先使用显式 cwd，否则从 args 推断
          String? workingDirectory;
          if (config.cwd.isNotEmpty) {
            workingDirectory = config.cwd;
          } else if (config.args.isNotEmpty) {
            final firstArg = config.args.first;
            if (p.isAbsolute(firstArg) && File(firstArg).existsSync()) {
              workingDirectory = p.dirname(firstArg);
            }
          }
          await client.connectStdio(
            command: config.command,
            args: config.args,
            env: config.env,
            workingDirectory: workingDirectory,
          );
          break;

        case McpTransportType.sse:
        case McpTransportType.streamableHttp:
          // command 在 SSE/HTTP 模式下是可选的："本地拉起进程"配置——
          // 部分 MCP server 对外是 SSE/HTTP 接口，但本身要先手动跑一个
          // 进程才能把端口打开。留空 command 就是纯远程连接，行为和以前
          // 完全一致；填了才会先拉起进程、等端口就绪，再走 SSE/HTTP 连接。
          if (config.command.isNotEmpty) {
            final uri = Uri.tryParse(config.url);
            if (uri == null) {
              throw Exception('URL 格式不正确，无法解析出用于探测端口的 host:port');
            }

            // 先探测一次：如果 url 已经能连上 (用户手动起了进程，或上次的
            // 进程还没被清理干净)，就不再重复拉起，避免端口冲突导致新
            // 进程直接崩溃、却又"看似连接成功"(连到了旧进程)的怪异体验。
            final probe = LocalProcessLauncher();
            final alreadyUp = await probe.waitForPortOpen(
              uri,
              timeout: const Duration(milliseconds: 300),
              retryInterval: const Duration(milliseconds: 100),
            );

            if (!alreadyUp) {
              launcher = LocalProcessLauncher();
              await launcher.start(
                command: config.command,
                args: config.args,
                env: config.env.isNotEmpty ? config.env : null,
                workingDirectory: config.cwd.isNotEmpty ? config.cwd : null,
              );

              final portReady = await launcher.waitForPortOpen(uri);
              if (!portReady) {
                final stderr = launcher.stderrOutput;
                await launcher.kill();
                throw Exception(
                  '本地进程已启动但端口一直未就绪 (等待超时): '
                  '${stderr.isNotEmpty ? stderr : "${config.command} ${config.args.join(" ")}"}',
                );
              }
              AppLogger.instance.log(
                '[MCP] 本地进程已就绪 (pid=${launcher.pid})，开始连接 ${config.url}',
              );
            } else {
              AppLogger.instance.log(
                '[MCP] ${config.url} 已可连接，跳过拉起本地进程 (可能已在运行)',
              );
            }
          }

          if (config.transportType == McpTransportType.sse) {
            await client.connectSse(
              url: config.url,
              headers: config.httpHeaders.isNotEmpty
                  ? config.httpHeaders
                  : null,
            );
          } else {
            await client.connectStreamableHttp(
              url: config.url,
              headers: config.httpHeaders.isNotEmpty
                  ? config.httpHeaders
                  : null,
            );
          }
          break;
      }

      await client.initialize();
      final tools = await client.listTools();

      state = state.copyWith(
        clients: {...state.clients, config.id: client},
        statuses: {...state.statuses, config.id: McpConnectionStatus.connected},
        toolsCache: {...state.toolsCache, config.id: tools},
        localProcesses: launcher != null
            ? {...state.localProcesses, config.id: launcher}
            : state.localProcesses,
        // 重连成功即清掉上一次的断线原因与重连计数
        lastErrors: Map<String, String>.from(state.lastErrors)..remove(config.id),
        reconnectAttempts: Map<String, int>.from(state.reconnectAttempts)
          ..remove(config.id),
      );
      _retryAttempts.remove(config.id);
      _retryTimers.remove(config.id)?.cancel();

      // 连接建立后才订阅：避免初始化阶段的失败被误判为"运行期断线"。
      _watchDisconnect(config.id, client);

      return tools;
    } catch (e) {
      // 连接失败时，若已经拉起了本地进程也要一并杀掉，不留下孤儿进程。
      await launcher?.kill();
      state = state.copyWith(
        statuses: {...state.statuses, config.id: McpConnectionStatus.error},
      );
      rethrow;
    }
  }

  /// 断开连接
  void disconnect(String serverId) {
    // 先取消订阅：主动断开不该被记成"异常断线"
    _disconnectSubs.remove(serverId)?.cancel();
    // 主动断开＝用户要求停止：取消待触发的重连并清掉状态，避免它又被拉起来
    _retryTimers.remove(serverId)?.cancel();
    _retryAttempts.remove(serverId);
    _configs.remove(serverId);
    final client = state.clients[serverId];
    if (client != null) {
      client.disconnect();
    }
    // 若这个连接是由应用代为拉起的本地进程，断开时一并杀掉——否则用户
    // 每次"断开"只是断了通信通道，进程仍占着端口，下次连接会先探测到
    // "已可连接"从而复用它，行为上勉强能接受，但用户点了断开预期是
    // 彻底停掉，留着后台进程不符合直觉，所以这里直接杀。
    unawaited(state.localProcesses[serverId]?.kill());

    final newClients = Map<String, McpClient>.from(state.clients)
      ..remove(serverId);
    final newStatuses = Map<String, McpConnectionStatus>.from(state.statuses)
      ..remove(serverId);
    final newTools = Map<String, List<Map<String, dynamic>>>.from(
      state.toolsCache,
    )..remove(serverId);
    final newLocalProcesses = Map<String, LocalProcessLauncher>.from(
      state.localProcesses,
    )..remove(serverId);
    final newLastErrors = Map<String, String>.from(state.lastErrors)
      ..remove(serverId);
    final newAttempts = Map<String, int>.from(state.reconnectAttempts)
      ..remove(serverId);

    state = McpConnectionState(
      clients: newClients,
      statuses: newStatuses,
      toolsCache: newTools,
      localProcesses: newLocalProcesses,
      lastErrors: newLastErrors,
      reconnectAttempts: newAttempts,
    );
  }

  /// 调用 MCP 工具
  Future<String> callTool(
    String serverId,
    String name,
    Map<String, dynamic> args,
  ) async {
    final client = state.clients[serverId];
    if (client == null) {
      throw Exception('MCP 服务器未连接');
    }
    return client.callTool(name, args);
  }

  /// 获取所有已连接服务器的工具（对外暴露名已按命名空间规则改写）
  List<Map<String, dynamic>> getAllConnectedTools() {
    final defsByKey = <String, Map<String, dynamic>>{};
    for (final entry in state.toolsCache.entries) {
      if (state.statuses[entry.key] != McpConnectionStatus.connected) continue;
      for (final def in entry.value) {
        final name = mcpToolDefName(def);
        if (name != null) defsByKey['${entry.key}\u0000$name'] = def;
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final route in getConnectedToolRoutes()) {
      final def = defsByKey['${route.serverId}\u0000${route.toolName}'];
      if (def == null) continue;
      result.add(
        route.namespaced ? renameMcpToolDef(def, route.exposedName) : def,
      );
    }
    return result;
  }

  /// 已连接服务器的工具路由表（暴露名 → serverId + 原始工具名）。
  ///
  /// Agent 侧的工具列表与 ToolPipeline 的调用路由都必须来自这同一份计算，
  /// 否则"模型看到的名字"和"实际要调用的名字"会漂移。
  List<McpToolRoute> getConnectedToolRoutes() {
    final connected = <String, List<Map<String, dynamic>>>{};
    for (final entry in state.toolsCache.entries) {
      if (state.statuses[entry.key] == McpConnectionStatus.connected) {
        connected[entry.key] = entry.value;
      }
    }
    return buildMcpToolRoutes(connected);
  }

  /// 查找工具所属的服务器 ID（[toolName] 可以是暴露名，也可以是原始名）
  String? findServerForTool(String toolName) {
    for (final route in getConnectedToolRoutes()) {
      if (route.exposedName == toolName || route.toolName == toolName) {
        return route.serverId;
      }
    }
    return null;
  }

  /// 断开所有连接并杀掉所有本地拉起的进程——用于应用退出时的收尾清理。
  /// 与 [dispose] 的区别：这个方法可以显式 await，确保进程真的被杀掉后
  /// 才继续关闭流程；[dispose] 是 Riverpod 容器销毁时的同步兜底，不保证
  /// 异步 kill 已经完成 (进程终止信号已发出，但不等待其退出)。
  Future<void> disconnectAll() async {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAttempts.clear();
    _configs.clear();
    for (final sub in _disconnectSubs.values) {
      await sub.cancel();
    }
    _disconnectSubs.clear();
    for (final client in state.clients.values) {
      await client.disconnect();
    }
    for (final launcher in state.localProcesses.values) {
      await launcher.kill();
    }
    state = const McpConnectionState();
  }

  @override
  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAttempts.clear();
    _configs.clear();
    for (final sub in _disconnectSubs.values) {
      sub.cancel();
    }
    _disconnectSubs.clear();
    for (final client in state.clients.values) {
      client.disconnect();
    }
    for (final launcher in state.localProcesses.values) {
      launcher.kill();
    }
    super.dispose();
  }
}

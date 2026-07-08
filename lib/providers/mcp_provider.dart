import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logger/app_logger.dart';
import '../core/mcp/local_process_launcher.dart';
import '../core/mcp/mcp_client.dart';
import '../core/mcp/mcp_registry.dart';
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

  const McpConnectionState({
    this.clients = const {},
    this.statuses = const {},
    this.toolsCache = const {},
    this.localProcesses = const {},
  });

  McpConnectionState copyWith({
    Map<String, McpClient>? clients,
    Map<String, McpConnectionStatus>? statuses,
    Map<String, List<Map<String, dynamic>>>? toolsCache,
    Map<String, LocalProcessLauncher>? localProcesses,
  }) {
    return McpConnectionState(
      clients: clients ?? this.clients,
      statuses: statuses ?? this.statuses,
      toolsCache: toolsCache ?? this.toolsCache,
      localProcesses: localProcesses ?? this.localProcesses,
    );
  }
}

enum McpConnectionStatus { disconnected, connecting, connected, error }

/// MCP 连接管理 Provider
final mcpConnectionsProvider =
    StateNotifierProvider<McpConnectionsNotifier, McpConnectionState>((ref) {
      return McpConnectionsNotifier();
    });

class McpConnectionsNotifier extends StateNotifier<McpConnectionState> {
  McpConnectionsNotifier() : super(const McpConnectionState());

  /// 连接到 MCP 服务器
  Future<List<Map<String, dynamic>>> connect(McpServerConfig config) async {
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
      );

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

    state = McpConnectionState(
      clients: newClients,
      statuses: newStatuses,
      toolsCache: newTools,
      localProcesses: newLocalProcesses,
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

  /// 获取所有已连接服务器的工具
  List<Map<String, dynamic>> getAllConnectedTools() {
    final allTools = <Map<String, dynamic>>[];
    for (final entry in state.toolsCache.entries) {
      if (state.statuses[entry.key] == McpConnectionStatus.connected) {
        allTools.addAll(entry.value);
      }
    }
    return allTools;
  }

  /// 查找工具所属的服务器 ID
  String? findServerForTool(String toolName) {
    for (final entry in state.toolsCache.entries) {
      if (state.statuses[entry.key] != McpConnectionStatus.connected) continue;
      final hasTool = entry.value.any((t) {
        final fn = t['function'] as Map<String, dynamic>?;
        return fn?['name'] == toolName;
      });
      if (hasTool) return entry.key;
    }
    return null;
  }

  /// 断开所有连接并杀掉所有本地拉起的进程——用于应用退出时的收尾清理。
  /// 与 [dispose] 的区别：这个方法可以显式 await，确保进程真的被杀掉后
  /// 才继续关闭流程；[dispose] 是 Riverpod 容器销毁时的同步兜底，不保证
  /// 异步 kill 已经完成 (进程终止信号已发出，但不等待其退出)。
  Future<void> disconnectAll() async {
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
    for (final client in state.clients.values) {
      client.disconnect();
    }
    for (final launcher in state.localProcesses.values) {
      launcher.kill();
    }
    super.dispose();
  }
}

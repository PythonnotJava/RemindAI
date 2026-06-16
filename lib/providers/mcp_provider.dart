import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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

  const McpConnectionState({
    this.clients = const {},
    this.statuses = const {},
    this.toolsCache = const {},
  });

  McpConnectionState copyWith({
    Map<String, McpClient>? clients,
    Map<String, McpConnectionStatus>? statuses,
    Map<String, List<Map<String, dynamic>>>? toolsCache,
  }) {
    return McpConnectionState(
      clients: clients ?? this.clients,
      statuses: statuses ?? this.statuses,
      toolsCache: toolsCache ?? this.toolsCache,
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
          await client.connectSse(
            url: config.url,
            headers: config.httpHeaders.isNotEmpty ? config.httpHeaders : null,
          );
          break;

        case McpTransportType.streamableHttp:
          await client.connectStreamableHttp(
            url: config.url,
            headers: config.httpHeaders.isNotEmpty ? config.httpHeaders : null,
          );
          break;
      }

      await client.initialize();
      final tools = await client.listTools();

      state = state.copyWith(
        clients: {...state.clients, config.id: client},
        statuses: {...state.statuses, config.id: McpConnectionStatus.connected},
        toolsCache: {...state.toolsCache, config.id: tools},
      );

      return tools;
    } catch (e) {
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

    final newClients = Map<String, McpClient>.from(state.clients)
      ..remove(serverId);
    final newStatuses = Map<String, McpConnectionStatus>.from(state.statuses)
      ..remove(serverId);
    final newTools = Map<String, List<Map<String, dynamic>>>.from(
      state.toolsCache,
    )..remove(serverId);

    state = McpConnectionState(
      clients: newClients,
      statuses: newStatuses,
      toolsCache: newTools,
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

  @override
  void dispose() {
    for (final client in state.clients.values) {
      client.disconnect();
    }
    super.dispose();
  }
}

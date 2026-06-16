import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'transports/mcp_transport.dart';

/// MCP 服务器配置模型
class McpServerConfig {
  final String id;
  final String name;

  /// 传输类型
  final McpTransportType transportType;

  /// stdio 模式: 启动命令
  final String command;

  /// stdio 模式: 命令参数
  final List<String> args;

  /// stdio 模式: 环境变量
  final Map<String, String> env;

  /// stdio 模式: 工作目录
  final String cwd;

  /// SSE / Streamable HTTP 模式: 服务器 URL
  final String url;

  /// SSE / Streamable HTTP 模式: 自定义请求头 (如 Authorization)
  final Map<String, String> httpHeaders;

  final bool enabled;
  final DateTime createdAt;
  final int sortIndex;

  const McpServerConfig({
    required this.id,
    required this.name,
    this.transportType = McpTransportType.stdio,
    this.command = '',
    this.args = const [],
    this.env = const {},
    this.cwd = '',
    this.url = '',
    this.httpHeaders = const {},
    this.enabled = true,
    required this.createdAt,
    this.sortIndex = 0,
  });

  McpServerConfig copyWith({
    String? name,
    McpTransportType? transportType,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    String? url,
    Map<String, String>? httpHeaders,
    bool? enabled,
    int? sortIndex,
  }) {
    return McpServerConfig(
      id: id,
      name: name ?? this.name,
      transportType: transportType ?? this.transportType,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: cwd ?? this.cwd,
      url: url ?? this.url,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }

  /// 是否是 HTTP 类型传输 (SSE 或 Streamable HTTP)
  bool get isHttpTransport => transportType != McpTransportType.stdio;
}

/// MCP 注册表 - 管理 MCP 服务器配置 (持久化到 SQLite)
class McpRegistry {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  McpRegistry(this._dbHelper);

  /// 获取所有 MCP 服务器配置
  Future<List<McpServerConfig>> getAll() async {
    final db = await _dbHelper.database;
    final result = db.select(
      'SELECT * FROM mcp_servers ORDER BY sort_index ASC, created_at DESC',
    );
    return result.map((row) {
      // 解析传输类型 (旧数据默认 stdio)
      final transportStr = _safeColumn(row, 'transport_type') ?? 'stdio';
      final transportType = McpTransportType.values.firstWhere(
        (t) => t.name == transportStr,
        orElse: () => McpTransportType.stdio,
      );

      // 解析 HTTP headers
      Map<String, String> httpHeaders = const {};
      final headersJson = _safeColumn(row, 'http_headers');
      if (headersJson != null && headersJson.isNotEmpty) {
        try {
          httpHeaders = (jsonDecode(headersJson) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v as String),
          );
        } catch (_) {}
      }

      return McpServerConfig(
        id: row['id'] as String,
        name: row['name'] as String,
        transportType: transportType,
        command: row['command'] as String,
        args: (jsonDecode(row['args'] as String) as List).cast<String>(),
        env: (jsonDecode(row['env'] as String) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as String),
        ),
        cwd: row['cwd'] as String? ?? '',
        url: _safeColumn(row, 'url') ?? '',
        httpHeaders: httpHeaders,
        enabled: (row['enabled'] as int) == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        sortIndex: (row['sort_index'] as int?) ?? 0,
      );
    }).toList();
  }

  /// 添加 MCP 服务器配置
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
    final db = await _dbHelper.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final maxResult = db.select('SELECT MAX(sort_index) as m FROM mcp_servers');
    final nextIndex = ((maxResult.first['m'] as int?) ?? -1) + 1;

    db.execute(
      '''INSERT INTO mcp_servers (id, name, transport_type, command, args, env, cwd, url, http_headers, enabled, created_at, sort_index)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        name,
        transportType.name,
        command,
        jsonEncode(args),
        jsonEncode(env),
        cwd,
        url,
        jsonEncode(httpHeaders),
        1,
        now,
        nextIndex,
      ],
    );

    return McpServerConfig(
      id: id,
      name: name,
      transportType: transportType,
      command: command,
      args: args,
      env: env,
      cwd: cwd,
      url: url,
      httpHeaders: httpHeaders,
      enabled: true,
      createdAt: DateTime.parse(now),
      sortIndex: nextIndex,
    );
  }

  /// 更新 MCP 服务器配置
  Future<void> update(McpServerConfig config) async {
    final db = await _dbHelper.database;
    db.execute(
      '''UPDATE mcp_servers
         SET name = ?, transport_type = ?, command = ?, args = ?, env = ?, cwd = ?, url = ?, http_headers = ?, enabled = ?
         WHERE id = ?''',
      [
        config.name,
        config.transportType.name,
        config.command,
        jsonEncode(config.args),
        jsonEncode(config.env),
        config.cwd,
        config.url,
        jsonEncode(config.httpHeaders),
        config.enabled ? 1 : 0,
        config.id,
      ],
    );
  }

  /// 删除 MCP 服务器配置
  Future<void> remove(String id) async {
    final db = await _dbHelper.database;
    db.execute('DELETE FROM mcp_servers WHERE id = ?', [id]);
  }

  /// 切换启用状态
  Future<void> setEnabled(String id, bool enabled) async {
    final db = await _dbHelper.database;
    db.execute('UPDATE mcp_servers SET enabled = ? WHERE id = ?', [
      enabled ? 1 : 0,
      id,
    ]);
  }

  /// 按给定 id 顺序重写 sort_index
  Future<void> reorder(List<String> orderedIds) async {
    final db = await _dbHelper.database;
    db.execute('BEGIN TRANSACTION');
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        db.execute('UPDATE mcp_servers SET sort_index = ? WHERE id = ?', [
          i,
          orderedIds[i],
        ]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// 安全读取列值（列不存在时返回 null）
  String? _safeColumn(dynamic row, String column) {
    try {
      return row[column] as String?;
    } catch (_) {
      return null;
    }
  }
}

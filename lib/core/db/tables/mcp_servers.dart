/// MCP 服务器表定义
///
/// CREATE TABLE IF NOT EXISTS mcp_servers (
///   id TEXT PRIMARY KEY,
///   name TEXT NOT NULL,
///   command TEXT NOT NULL,
///   args TEXT NOT NULL DEFAULT '[]',
///   env TEXT NOT NULL DEFAULT '{}',
///   cwd TEXT NOT NULL DEFAULT '',
///   enabled INTEGER NOT NULL DEFAULT 1,
///   created_at TEXT NOT NULL
/// )
const String mcpServersTableSql = '''
  CREATE TABLE IF NOT EXISTS mcp_servers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    command TEXT NOT NULL,
    args TEXT NOT NULL DEFAULT '[]',
    env TEXT NOT NULL DEFAULT '{}',
    cwd TEXT NOT NULL DEFAULT '',
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
  )
''';

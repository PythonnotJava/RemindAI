import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import '../settings/app_settings.dart';

class DatabaseHelper {
  static DatabaseHelper? _instance;
  static Database? _db;

  /// 自定义数据库路径（来自设置）。为空则使用默认路径。
  static String? _customDbPath;

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  /// 在打开数据库前设置自定义路径。若数据库已打开且路径变化，需先 close()。
  static void configurePath(String dbPath) {
    _customDbPath = dbPath;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    String dbPath;
    if (_customDbPath != null && _customDbPath!.isNotEmpty) {
      dbPath = _customDbPath!;
    } else {
      // 回退: 从全局根目录获取
      final root = await AppSettings.getRootDir();
      dbPath = p.join(root, 'sqlite', 'remind_ai.db');
    }

    // 确保目录存在
    final dbDir = Directory(p.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final db = sqlite3.open(dbPath);

    // 性能优化配置
    db.execute('PRAGMA journal_mode = WAL');  // WAL 模式，写入不阻塞读取
    db.execute('PRAGMA synchronous = NORMAL');  // 平衡性能和安全
    db.execute('PRAGMA cache_size = -64000');  // 64MB 缓存
    db.execute('PRAGMA temp_store = MEMORY');  // 临时表存内存

    _createTables(db);
    return db;
  }

  void _createTables(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS model_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT NOT NULL,
        model_id TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        model_card_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (model_card_id) REFERENCES model_cards(id)
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT,
        tool_calls TEXT,
        tool_call_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    db.execute('''
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
    ''');

    // Migration: add cwd column if missing (for existing databases)
    _migrateAddCwdColumn(db);
    // Migration: add sort_index columns for reorderable cards
    _migrateAddSortIndex(db, 'model_cards');
    _migrateAddSortIndex(db, 'mcp_servers');
    // Migration: add logo_path column for model cards (空字符串表示无 logo)
    _migrateAddColumn(
      db,
      'model_cards',
      'logo_path',
      "TEXT NOT NULL DEFAULT ''",
    );
    // Migration: add provider column for model cards (协议类型，默认 openai)
    _migrateAddColumn(
      db,
      'model_cards',
      'provider',
      "TEXT NOT NULL DEFAULT 'openai'",
    );
    // Migration: add attachments column for chat messages (JSON 数组，默认空)
    _migrateAddColumn(
      db,
      'chat_messages',
      'attachments',
      "TEXT NOT NULL DEFAULT '[]'",
    );
    // Migration: add interrupted flag for chat messages (用户手动中断标记)
    _migrateAddColumn(
      db,
      'chat_messages',
      'interrupted',
      "INTEGER NOT NULL DEFAULT 0",
    );
    // Migration: add thinking_content for chat messages (思考/推理过程内容)
    _migrateAddColumn(
      db,
      'chat_messages',
      'thinking_content',
      "TEXT DEFAULT NULL",
    );
    // Migration: MCP 多传输类型支持
    _migrateAddColumn(
      db,
      'mcp_servers',
      'transport_type',
      "TEXT NOT NULL DEFAULT 'stdio'",
    );
    _migrateAddColumn(db, 'mcp_servers', 'url', "TEXT NOT NULL DEFAULT ''");
    _migrateAddColumn(
      db,
      'mcp_servers',
      'http_headers',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    // Migration: add context_window for model cards (模型上下文窗口大小, 0=未知)
    _migrateAddColumn(
      db,
      'model_cards',
      'context_window',
      "INTEGER NOT NULL DEFAULT 0",
    );

    // 性能优化：为 model_cards 的 is_default 字段创建索引
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_model_cards_default
      ON model_cards(is_default)
    ''');

    // 记忆持久化表 (SQLite 备份层)
    db.execute('''
      CREATE TABLE IF NOT EXISTS memory_entries (
        id INTEGER PRIMARY KEY,
        collection TEXT NOT NULL,
        text TEXT NOT NULL,
        metadata TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_memory_collection ON memory_entries(collection)
    ''');

    // 知识库表 — 每个知识库指定不可修改的嵌入模型快照，独占一个 Qdrant collection
    db.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_bases (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        collection TEXT NOT NULL,
        embedding_base_url TEXT NOT NULL DEFAULT '',
        embedding_api_key TEXT NOT NULL DEFAULT '',
        embedding_model TEXT NOT NULL DEFAULT '',
        embedding_dimension INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 知识库文档表 — 记录每个知识库导入的文档及其解析(炼丹)状态
    db.execute('''
      CREATE TABLE IF NOT EXISTS kb_documents (
        id TEXT PRIMARY KEY,
        kb_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        source_path TEXT NOT NULL DEFAULT '',
        source_group TEXT NOT NULL DEFAULT '',
        chunk_count INTEGER NOT NULL DEFAULT 0,
        char_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        error TEXT NOT NULL DEFAULT '',
        imported_at TEXT NOT NULL,
        FOREIGN KEY (kb_id) REFERENCES knowledge_bases(id)
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_kb_documents_kb ON kb_documents(kb_id)
    ''');

    // 迁移: 为已有 kb_documents 表添加 source_group 列
    _migrateAddColumn(
      db,
      'kb_documents',
      'source_group',
      "TEXT NOT NULL DEFAULT ''",
    );

    // Worktree 会话持久化表 — 记录每次版本工作流的开启/结束状态，
    // 使应用重启后能恢复"哪些实验分支还在跑、哪些已结束"的全局状态，
    // 并提供历史查询能力(LLM 可以通过 toolshell_worktree_list 查看)。
    db.execute('''
      CREATE TABLE IF NOT EXISTS worktree_sessions (
        id TEXT PRIMARY KEY,
        work_dir TEXT NOT NULL,
        worktree_path TEXT NOT NULL,
        branch TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        base_commit TEXT NOT NULL DEFAULT '',
        end_action TEXT NOT NULL DEFAULT '',
        end_commit TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        ended_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_worktree_sessions_status
        ON worktree_sessions(status)
    ''');
  }

  /// 通用：为指定表添加缺失的列。
  void _migrateAddColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) {
    final columns = db.select("PRAGMA table_info('$table')");
    final has = columns.any((row) => row['name'] == column);
    if (!has) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void _migrateAddCwdColumn(Database db) {
    final columns = db.select("PRAGMA table_info('mcp_servers')");
    final hasCwd = columns.any((row) => row['name'] == 'cwd');
    if (!hasCwd) {
      db.execute(
        "ALTER TABLE mcp_servers ADD COLUMN cwd TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  /// 为指定表添加 sort_index 列 (用于卡片拖拽排序)。
  /// 新列默认 0；首次添加后按 created_at 初始化顺序，保持现有视觉顺序。
  void _migrateAddSortIndex(Database db, String table) {
    final columns = db.select("PRAGMA table_info('$table')");
    final hasSortIndex = columns.any((row) => row['name'] == 'sort_index');
    if (!hasSortIndex) {
      db.execute(
        'ALTER TABLE $table ADD COLUMN sort_index INTEGER NOT NULL DEFAULT 0',
      );
      // 按 created_at 倒序初始化 sort_index (与旧的默认展示顺序一致)
      final rows = db.select('SELECT id FROM $table ORDER BY created_at DESC');
      for (var i = 0; i < rows.length; i++) {
        db.execute('UPDATE $table SET sort_index = ? WHERE id = ?', [
          i,
          rows[i]['id'],
        ]);
      }
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}

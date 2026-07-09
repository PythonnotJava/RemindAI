import 'package:uuid/uuid.dart';
import '../database.dart';

/// Worktree 会话 DAO — 对 `worktree_sessions` 表的增删改查。
///
/// 设计目标:
/// 1. 应用重启后能恢复"当前有哪些活跃的实验分支"(status='active')，
///    不再依赖纯内存态的 [activeWorktreeProvider]。
/// 2. 提供历史查询——LLM 可以问"之前做过的实验都有哪些"。
/// 3. 所有字段都是 NOT NULL(带默认值)，避免 null 检查散落各处。
class WorktreeSessionsDao {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  WorktreeSessionsDao(this._dbHelper);

  /// 记录一次 worktree 开始(status='active')。
  Future<String> recordStart({
    required String workDir,
    required String worktreePath,
    required String branch,
    required String name,
    required String baseCommit,
  }) async {
    final db = await _dbHelper.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    db.execute(
      '''INSERT INTO worktree_sessions
         (id, work_dir, worktree_path, branch, name, status, base_commit, created_at)
         VALUES (?, ?, ?, ?, ?, 'active', ?, ?)''',
      [id, workDir, worktreePath, branch, name, baseCommit, now],
    );
    return id;
  }

  /// 标记一条会话为已结束(merge/discard)。
  Future<void> recordEnd({
    required String worktreePath,
    required String action,
    String endCommit = '',
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    db.execute(
      '''UPDATE worktree_sessions
         SET status = 'ended', end_action = ?, end_commit = ?, ended_at = ?
         WHERE worktree_path = ? AND status = 'active' ''',
      [action, endCommit, now, worktreePath],
    );
  }

  /// 获取所有仍处于 active 状态的会话(用于应用启动时恢复状态)。
  Future<List<WorktreeSession>> getActive({String? workDir}) async {
    final db = await _dbHelper.database;
    final query = workDir != null
        ? 'SELECT * FROM worktree_sessions WHERE status = ? AND work_dir = ? ORDER BY created_at DESC'
        : 'SELECT * FROM worktree_sessions WHERE status = ? ORDER BY created_at DESC';
    final params = workDir != null ? ['active', workDir] : ['active'];
    final rows = db.select(query, params);
    return rows.map((r) => WorktreeSession.fromRow(r)).toList();
  }

  /// 获取历史会话(包括已结束的)，最近的在前。
  Future<List<WorktreeSession>> getHistory({
    String? workDir,
    int limit = 20,
  }) async {
    final db = await _dbHelper.database;
    final query = workDir != null
        ? 'SELECT * FROM worktree_sessions WHERE work_dir = ? ORDER BY created_at DESC LIMIT ?'
        : 'SELECT * FROM worktree_sessions ORDER BY created_at DESC LIMIT ?';
    final params = workDir != null ? [workDir, limit] : [limit];
    final rows = db.select(query, params);
    return rows.map((r) => WorktreeSession.fromRow(r)).toList();
  }

  /// 根据 worktreePath 获取当前活跃会话(可能为 null)。
  Future<WorktreeSession?> findActiveByPath(String worktreePath) async {
    final db = await _dbHelper.database;
    final rows = db.select(
      'SELECT * FROM worktree_sessions WHERE worktree_path = ? AND status = ? LIMIT 1',
      [worktreePath, 'active'],
    );
    if (rows.isEmpty) return null;
    return WorktreeSession.fromRow(rows.first);
  }
}

/// worktree_sessions 表行的数据模型。
class WorktreeSession {
  final String id;
  final String workDir;
  final String worktreePath;
  final String branch;
  final String name;
  final String status; // 'active' | 'ended'
  final String baseCommit;
  final String endAction; // '' | 'merge' | 'discard'
  final String endCommit;
  final DateTime createdAt;
  final DateTime? endedAt;

  WorktreeSession({
    required this.id,
    required this.workDir,
    required this.worktreePath,
    required this.branch,
    required this.name,
    required this.status,
    required this.baseCommit,
    required this.endAction,
    required this.endCommit,
    required this.createdAt,
    this.endedAt,
  });

  factory WorktreeSession.fromRow(Map<String, dynamic> row) {
    final endedAtStr = row['ended_at'] as String? ?? '';
    return WorktreeSession(
      id: row['id'] as String,
      workDir: row['work_dir'] as String,
      worktreePath: row['worktree_path'] as String,
      branch: row['branch'] as String,
      name: row['name'] as String? ?? '',
      status: row['status'] as String,
      baseCommit: row['base_commit'] as String? ?? '',
      endAction: row['end_action'] as String? ?? '',
      endCommit: row['end_commit'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
      endedAt: endedAtStr.isNotEmpty ? DateTime.tryParse(endedAtStr) : null,
    );
  }

  bool get isActive => status == 'active';

  Map<String, dynamic> toJson() => {
        'id': id,
        'work_dir': workDir,
        'worktree_path': worktreePath,
        'branch': branch,
        'name': name,
        'status': status,
        'base_commit': baseCommit,
        'end_action': endAction,
        'end_commit': endCommit,
        'created_at': createdAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String() ?? '',
      };
}

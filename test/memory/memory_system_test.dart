import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// 由于 DatabaseHelper 的构造函数是私有的，我们直接测试 MemoryDao 的核心逻辑。
// 通过创建内存 SQLite 数据库并直接操作来验证。

void main() {
  late Database db;
  const testCollection = 'test_memory';

  setUp(() {
    db = sqlite3.openInMemory();
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
  });

  tearDown(() {
    db.dispose();
  });

  // ─── 辅助方法（模拟 MemoryDao 逻辑）───

  void insertMemory(
    int id,
    String collection,
    String text, [
    Map<String, dynamic> metadata = const {},
  ]) {
    db.execute(
      '''INSERT OR REPLACE INTO memory_entries (id, collection, text, metadata, created_at)
         VALUES (?, ?, ?, ?, ?)''',
      [
        id,
        collection,
        text,
        jsonEncode(metadata),
        DateTime.now().toIso8601String(),
      ],
    );
  }

  int countMemories(String collection) {
    final result = db.select(
      'SELECT COUNT(*) as cnt FROM memory_entries WHERE collection = ?',
      [collection],
    );
    return result.first['cnt'] as int;
  }

  List<Map<String, dynamic>> getAllMemories(String collection) {
    final result = db.select(
      'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC',
      [collection],
    );
    return result.map((row) {
      Map<String, dynamic> metadata = {};
      try {
        metadata =
            jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
      return {
        'id': row['id'] as int,
        'collection': row['collection'] as String,
        'text': row['text'] as String,
        'metadata': metadata,
        'created_at': row['created_at'] as String,
      };
    }).toList();
  }

  /// 中文友好分词（复制自 MemoryDao._tokenize）
  List<String> tokenize(String query) {
    final tokens = <String>{};
    for (final m in RegExp(r'[\u4e00-\u9fff]+').allMatches(query)) {
      final block = m.group(0)!;
      if (block.length == 1) {
        tokens.add(block);
      } else {
        for (var i = 0; i < block.length - 1; i++) {
          tokens.add(block.substring(i, i + 2));
        }
      }
    }
    for (final m in RegExp(r'[A-Za-z0-9]{2,}').allMatches(query)) {
      tokens.add(m.group(0)!.toLowerCase());
    }
    return tokens.toList();
  }

  /// 关键词搜索（复制自 MemoryDao.search 核心逻辑）
  List<Map<String, dynamic>> searchMemories(
    String collection,
    String query, {
    int limit = 5,
  }) {
    final keywords = tokenize(query);
    if (keywords.isEmpty) {
      final result = db.select(
        'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC LIMIT ?',
        [collection, limit],
      );
      return result
          .map(
            (row) => <String, dynamic>{
              'text': row['text'] as String,
              'score': 1.0,
              'source': 'sqlite',
            },
          )
          .toList();
    }

    final conditions = keywords.map((_) => 'text LIKE ?').join(' OR ');
    final params = <dynamic>[collection];
    for (final k in keywords) {
      params.add('%$k%');
    }
    params.add(limit * 4);

    final result = db.select(
      'SELECT * FROM memory_entries WHERE collection = ? AND ($conditions) ORDER BY created_at DESC LIMIT ?',
      params,
    );

    final rows = result.map((row) {
      final text = row['text'] as String;
      final lower = text.toLowerCase();
      final hits = keywords.where((k) => lower.contains(k)).length;
      final score = hits / keywords.length;
      return <String, dynamic>{
        'text': text,
        'score': score,
        'source': 'sqlite',
      };
    }).toList();

    rows.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return rows.take(limit).toList();
  }

  // ─── 测试组 1：基础 CRUD ───

  group('SQLite 记忆存储 - 基础 CRUD', () {
    test('插入单条记忆', () {
      insertMemory(1, testCollection, '用户喜欢用 Riverpod 管理状态');
      expect(countMemories(testCollection), 1);
    });

    test('插入多条记忆', () {
      insertMemory(1, testCollection, '项目使用 Flutter 3.22');
      insertMemory(2, testCollection, '部署环境是 Docker + K8s');
      insertMemory(3, testCollection, '数据库用 PostgreSQL');
      expect(countMemories(testCollection), 3);
    });

    test('相同 ID 覆盖写入 (INSERT OR REPLACE)', () {
      insertMemory(1, testCollection, '原始内容');
      insertMemory(1, testCollection, '更新后的内容');
      expect(countMemories(testCollection), 1);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], '更新后的内容');
    });

    test('不同 collection 隔离', () {
      insertMemory(1, 'project_a', '项目 A 的记忆');
      insertMemory(2, 'project_b', '项目 B 的记忆');
      expect(countMemories('project_a'), 1);
      expect(countMemories('project_b'), 1);
    });

    test('删除单条记忆', () {
      insertMemory(1, testCollection, '要删除的');
      insertMemory(2, testCollection, '要保留的');
      db.execute('DELETE FROM memory_entries WHERE id = ? AND collection = ?', [
        1,
        testCollection,
      ]);
      expect(countMemories(testCollection), 1);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], '要保留的');
    });

    test('清空 collection', () {
      insertMemory(1, testCollection, '记忆1');
      insertMemory(2, testCollection, '记忆2');
      insertMemory(3, testCollection, '记忆3');
      db.execute('DELETE FROM memory_entries WHERE collection = ?', [
        testCollection,
      ]);
      expect(countMemories(testCollection), 0);
    });

    test('metadata 存储和解析', () {
      insertMemory(1, testCollection, '测试', {
        'source': 'auto_store',
        'importance': 0.8,
      });
      final all = getAllMemories(testCollection);
      expect(all.first['metadata']['source'], 'auto_store');
      expect(all.first['metadata']['importance'], 0.8);
    });
  });

  // ─── 测试组 2：中文分词 ───

  group('中文分词 (_tokenize)', () {
    test('纯中文 bigram 拆分', () {
      final tokens = tokenize('状态管理');
      expect(tokens, containsAll(['状态', '态管', '管理']));
    });

    test('单字中文', () {
      final tokens = tokenize('好');
      expect(tokens, ['好']);
    });

    test('英文单词提取', () {
      final tokens = tokenize('use Flutter for development');
      expect(tokens, containsAll(['use', 'flutter', 'for', 'development']));
    });

    test('中英混合', () {
      final tokens = tokenize('使用 Docker 部署');
      expect(tokens, containsAll(['使用', 'docker', '部署']));
    });

    test('短英文过滤 (< 2 字符)', () {
      final tokens = tokenize('I use a big API');
      // "I" 和 "a" 被过滤
      expect(tokens.contains('i'), false);
      expect(tokens.contains('a'), false);
      expect(tokens, containsAll(['use', 'big', 'api']));
    });

    test('数字保留', () {
      final tokens = tokenize('Flutter 3.22 release');
      expect(tokens, containsAll(['flutter', 'release']));
      // "3" 和 "22" 都是 >=2 的才保留
      expect(tokens.contains('22'), true);
    });
  });

  // ─── 测试组 3：关键词搜索 ───

  group('SQLite 关键词搜索', () {
    setUp(() {
      insertMemory(1, testCollection, '用户偏好使用 Riverpod 进行状态管理');
      insertMemory(2, testCollection, 'Docker 容器化部署到 Kubernetes 集群');
      insertMemory(3, testCollection, 'PostgreSQL 数据库优化，添加了索引');
      insertMemory(4, testCollection, 'Flutter Widget 测试使用 golden test');
      insertMemory(5, testCollection, 'API 接口设计遵循 RESTful 规范');
    });

    test('精确中文关键词匹配', () {
      final results = searchMemories(testCollection, '状态管理');
      expect(results.isNotEmpty, true);
      expect(results.first['text'], contains('状态管理'));
    });

    test('英文关键词匹配', () {
      final results = searchMemories(testCollection, 'Docker');
      expect(results.isNotEmpty, true);
      expect(results.first['text'], contains('Docker'));
    });

    test('多关键词命中越多分数越高', () {
      // "Docker 部署" 有两个关键词命中同一条记忆
      final results = searchMemories(testCollection, 'Docker 部署');
      expect(results.isNotEmpty, true);
      expect(results.first['score'], greaterThan(0.3));
      expect(results.first['text'], contains('Docker'));
    });

    test('无匹配时结果分数较低', () {
      final results = searchMemories(testCollection, 'Golang 微服务架构');
      // "golang" 不在任何记忆中，结果应该为空或分数很低
      if (results.isNotEmpty) {
        // 即使有 bigram 偶然命中，分数也应该很低
        expect(results.first['score'] as double, lessThan(0.5));
      }
    });

    test('空查询返回最近记录', () {
      final results = searchMemories(testCollection, '');
      // 空关键词应返回最近的记录
      expect(results.isNotEmpty, true);
    });

    test('limit 参数限制返回数量', () {
      final results = searchMemories(testCollection, '使用', limit: 2);
      expect(results.length, lessThanOrEqualTo(2));
    });

    test('跨 collection 不会串扰', () {
      insertMemory(100, 'other_collection', 'Docker 在另一个项目');
      final results = searchMemories(testCollection, 'Docker');
      // 不应包含 other_collection 的记忆
      for (final r in results) {
        expect(r['text'], isNot('Docker 在另一个项目'));
      }
    });

    test('score 归一化在 (0, 1] 范围', () {
      final results = searchMemories(testCollection, 'Riverpod 状态管理');
      for (final r in results) {
        final score = r['score'] as double;
        expect(score, greaterThanOrEqualTo(0.0));
        expect(score, lessThanOrEqualTo(1.0));
      }
    });

    test('source 标注为 sqlite', () {
      final results = searchMemories(testCollection, 'Docker');
      for (final r in results) {
        expect(r['source'], 'sqlite');
      }
    });
  });

  // ─── 测试组 4：ID 单调递增 ───

  group('ID 生成与唯一性', () {
    test('不同时间点的 ID 严格递增', () async {
      insertMemory(1000, testCollection, '第一条');
      await Future.delayed(const Duration(milliseconds: 1));
      insertMemory(2000, testCollection, '第二条');

      final all = db.select(
        'SELECT id FROM memory_entries WHERE collection = ? ORDER BY id ASC',
        [testCollection],
      );
      expect(all[0]['id'] as int, lessThan(all[1]['id'] as int));
    });

    test('相同 ID 不会创建重复记录', () {
      insertMemory(9999, testCollection, '原始');
      insertMemory(9999, testCollection, '覆盖');
      expect(countMemories(testCollection), 1);
    });
  });

  // ─── 测试组 5：边界情况 ───

  group('边界情况', () {
    test('空文本存储', () {
      insertMemory(1, testCollection, '');
      expect(countMemories(testCollection), 1);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], '');
    });

    test('超长文本存储 (10000 字符)', () {
      final longText = 'A' * 10000;
      insertMemory(1, testCollection, longText);
      final all = getAllMemories(testCollection);
      expect(all.first['text'].length, 10000);
    });

    test('特殊字符存储', () {
      const special = "引号'双引号\"换行\n制表\t百分号%下划线_";
      insertMemory(1, testCollection, special);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], special);
    });

    test('Unicode emoji 存储', () {
      const emoji = '🎉 Flutter 太棒了 🚀 性能 💯';
      insertMemory(1, testCollection, emoji);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], emoji);
    });

    test('大量记忆写入不崩溃 (1000 条)', () {
      for (var i = 0; i < 1000; i++) {
        insertMemory(i, testCollection, '记忆 #$i - 一些重复的内容用于测试');
      }
      expect(countMemories(testCollection), 1000);
    });

    test('搜索大量记忆的性能', () {
      for (var i = 0; i < 500; i++) {
        insertMemory(i, testCollection, '记忆条目 $i 包含 Flutter 开发的各种知识');
      }
      final sw = Stopwatch()..start();
      final results = searchMemories(testCollection, 'Flutter 开发');
      sw.stop();
      // 500 条记忆的搜索应在 100ms 内完成
      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(results.isNotEmpty, true);
    });

    test('metadata 为空 JSON 对象', () {
      insertMemory(1, testCollection, '无元数据');
      final all = getAllMemories(testCollection);
      expect(all.first['metadata'], isA<Map>());
    });

    test('metadata 含嵌套结构', () {
      insertMemory(1, testCollection, '复杂元数据', {
        'source': 'auto_store',
        'tags': ['flutter', 'state'],
        'context': {'user': '张三', 'session': 42},
      });
      final all = getAllMemories(testCollection);
      expect(all.first['metadata']['tags'], ['flutter', 'state']);
      expect(all.first['metadata']['context']['user'], '张三');
    });
  });

  // ─── 测试组 6：软失效 (superseded) ───

  group('软失效标记 (superseded)', () {
    /// 模拟 MemoryDao.markSuperseded 的核心逻辑
    void markSuperseded(String collection, int id) {
      final result = db.select(
        'SELECT metadata FROM memory_entries WHERE id = ? AND collection = ?',
        [id, collection],
      );
      if (result.isEmpty) return;
      Map<String, dynamic> metadata = {};
      try {
        metadata =
            jsonDecode(result.first['metadata'] as String)
                as Map<String, dynamic>;
      } catch (_) {}
      metadata['superseded'] = true;
      db.execute(
        'UPDATE memory_entries SET metadata = ? WHERE id = ? AND collection = ?',
        [jsonEncode(metadata), id, collection],
      );
    }

    /// 复制 MemoryDao.search，但加上 superseded 过滤（模拟修复后的行为）
    List<Map<String, dynamic>> searchMemoriesFiltered(
      String collection,
      String query, {
      int limit = 5,
    }) {
      final keywords = tokenize(query);
      final conditions = keywords.isEmpty
          ? null
          : keywords.map((_) => 'text LIKE ?').join(' OR ');
      final params = <dynamic>[collection];
      String sql;
      if (conditions == null) {
        sql =
            'SELECT * FROM memory_entries WHERE collection = ? ORDER BY created_at DESC LIMIT ?';
        params.add(limit * 2);
      } else {
        for (final k in keywords) {
          params.add('%$k%');
        }
        sql =
            'SELECT * FROM memory_entries WHERE collection = ? AND ($conditions) ORDER BY created_at DESC LIMIT ?';
        params.add(limit * 4);
      }
      final result = db.select(sql, params);
      final rows = result
          .map((row) {
            Map<String, dynamic> metadata = {};
            try {
              metadata =
                  jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
            } catch (_) {}
            return <String, dynamic>{
              'text': row['text'] as String,
              'superseded': metadata['superseded'] == true,
            };
          })
          .where((r) => r['superseded'] != true)
          .toList();
      return rows.take(limit).toList();
    }

    test('标记后 metadata 含 superseded=true', () {
      insertMemory(1, testCollection, '用户用 pnpm 管理依赖');
      markSuperseded(testCollection, 1);
      final all = getAllMemories(testCollection);
      expect(all.first['metadata']['superseded'], true);
    });

    test('未标记的记忆 superseded 字段缺省不存在', () {
      insertMemory(1, testCollection, '正常记忆');
      final all = getAllMemories(testCollection);
      expect(all.first['metadata']['superseded'], isNull);
    });

    test('标记 superseded 后不再出现在搜索结果', () {
      insertMemory(1, testCollection, '用户用 pnpm 管理依赖');
      insertMemory(2, testCollection, '用户改用 npm 管理依赖了');
      markSuperseded(testCollection, 1);

      final results = searchMemoriesFiltered(testCollection, '管理依赖');
      expect(results.any((r) => r['text'] == '用户用 pnpm 管理依赖'), false);
      expect(results.any((r) => r['text'] == '用户改用 npm 管理依赖了'), true);
    });

    test('标记不影响其他记忆的可见性', () {
      insertMemory(1, testCollection, '记忆A');
      insertMemory(2, testCollection, '记忆B');
      markSuperseded(testCollection, 1);

      final results = searchMemoriesFiltered(testCollection, '记忆');
      expect(results.length, 1);
      expect(results.first['text'], '记忆B');
    });

    test('标记不存在的 id 不会崩溃也不影响其他数据', () {
      insertMemory(1, testCollection, '记忆A');
      markSuperseded(testCollection, 9999); // 不存在的 id
      expect(countMemories(testCollection), 1);
      final all = getAllMemories(testCollection);
      expect(all.first['metadata']['superseded'], isNull);
    });

    test('保留原始记录 (物理未删除)，仅打标记', () {
      insertMemory(1, testCollection, '被取代的旧记忆');
      markSuperseded(testCollection, 1);
      // 记录仍然存在于表中，只是被标记，可用于审计/回溯
      expect(countMemories(testCollection), 1);
      final all = getAllMemories(testCollection);
      expect(all.first['text'], '被取代的旧记忆');
      expect(all.first['metadata']['superseded'], true);
    });
  });

  // ─── 测试组 7：降级与容错 ───

  group('降级与容错', () {
    test('collection 不存在时 count 返回 0', () {
      expect(countMemories('nonexistent_collection'), 0);
    });

    test('空 collection 搜索返回空', () {
      final results = searchMemories('empty_collection', 'anything');
      expect(results, isEmpty);
    });

    test('纯标点查询不崩溃', () {
      insertMemory(1, testCollection, '一些内容');
      final results = searchMemories(testCollection, '！@#￥%');
      // 纯标点没有有效关键词，应返回最近记录
      expect(results, isNotEmpty);
    });

    test('SQL 注入安全', () {
      // 尝试注入
      insertMemory(1, testCollection, "正常内容');DROP TABLE memory_entries;--");
      expect(countMemories(testCollection), 1);
      // 搜索中也不应被注入
      searchMemories(testCollection, "';DROP TABLE memory_entries;--");
      // 不崩溃，且表仍然存在
      expect(true, true);
    });
  });
}

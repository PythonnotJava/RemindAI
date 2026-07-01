import 'package:dio/dio.dart';

import '../db/daos/memory_dao.dart';
import '../logger/app_logger.dart';
import 'qdrant_service.dart';

/// 向量维度不匹配异常。
///
/// 当尝试向已存在的 collection 写入与其创建维度不同的向量时抛出
/// (通常是更换了 embedding 模型)。上层应提示用户重建索引，
/// 而不是让 Qdrant 静默返回 400 后被吞掉。
class VectorDimensionMismatch implements Exception {
  final String collection;
  final int existing;
  final int incoming;

  VectorDimensionMismatch({
    required this.collection,
    required this.existing,
    required this.incoming,
  });

  @override
  String toString() =>
      'VectorDimensionMismatch(collection=$collection, '
      '已存在维度=$existing, 当前向量维度=$incoming) — '
      'embedding 模型已变更，需重建索引 (rebuildFromSqlite)';
}

/// 记忆管理器 — 负责向量存储/召回
///
/// 使用 Qdrant HTTP API + 外部嵌入模型 (OpenAI compatible)
/// 支持全局记忆 (跨项目) 和项目级记忆
///
/// 可选 SQLite 双写: 当 [memoryDao] 不为 null 时，store/delete 同步写入 SQLite，
/// 作为持久备份层。Qdrant 数据丢失时可从 SQLite 重建向量索引。
class MemoryManager {
  final String embeddingBaseUrl;
  final String embeddingApiKey;
  final String embeddingModel;
  final int embeddingDimension;

  /// 可选的 SQLite 持久化层
  final MemoryDao? memoryDao;

  late final Dio _dio;
  late final Dio _embeddingDio;

  /// 规范化后的 embedding base（去掉末尾斜杠）。
  late final String _embeddingBase;

  MemoryManager({
    required this.embeddingBaseUrl,
    required this.embeddingApiKey,
    required this.embeddingModel,
    this.embeddingDimension = 1536,
    this.memoryDao,
  }) {
    final qdrant = QdrantService.instance;
    _dio = Dio(
      BaseOptions(
        baseUrl: qdrant.baseUrl,
        headers: {'Content-Type': 'application/json'},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    _embeddingBase = _normalizeBase(embeddingBaseUrl);
    // 注意：不设置 baseUrl。Dio 解析以 "/" 开头的 path 时会按 host 根绝对路径处理，
    // 从而丢弃 baseUrl 中的 "/v1" 等子路径。统一改用绝对 URL 拼接规避该坑。
    _embeddingDio = Dio(
      BaseOptions(
        headers: {
          'Authorization': 'Bearer $embeddingApiKey',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
  }

  /// 去掉末尾斜杠，避免拼出双斜杠。
  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 单调递增的 point id 生成器。
  ///
  /// 旧实现用 millisecondsSinceEpoch，同一毫秒内的多条记忆 id 会碰撞，
  /// 经 `INSERT OR REPLACE` 静默覆盖。这里以"上次值+1"保证严格递增，
  /// 同时仍贴近时间戳 (便于阅读/排序)。进程级静态，跨实例共享。
  static int _lastId = 0;
  static int _nextId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastId = now > _lastId ? now : _lastId + 1;
    return _lastId;
  }

  // ─── Collection 管理 ────────────────────────────────────────

  /// 全局记忆 collection 名称 (所有项目共享)
  static const String globalCollection = 'global_memory';

  /// 确保 collection 存在
  ///
  /// [vectorSize]: 向量维度。优先使用实际嵌入向量的维度，
  /// 避免配置 embeddingDimension 与模型真实输出不一致导致插入 400。
  ///
  /// 若 collection 已存在但维度与 [vectorSize] 不一致 (通常是更换了
  /// embedding 模型)，抛出 [VectorDimensionMismatch]，由上层决定是否
  /// 重建 (rebuildFromSqlite)。绝不静默写入错误维度导致后续全部 400。
  Future<void> ensureCollection(
    String collectionName, {
    int? vectorSize,
  }) async {
    try {
      final resp = await _dio.get('/collections/$collectionName');
      if (resp.statusCode == 200) {
        // 校验已存在 collection 的维度是否与当前向量一致
        if (vectorSize != null) {
          final existing = _extractVectorSize(resp.data);
          if (existing != null && existing != vectorSize) {
            throw VectorDimensionMismatch(
              collection: collectionName,
              existing: existing,
              incoming: vectorSize,
            );
          }
        }
        return; // 已存在且维度匹配
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }

    // 创建 collection
    await _dio.put(
      '/collections/$collectionName',
      data: {
        'vectors': {
          'size': vectorSize ?? embeddingDimension,
          'distance': 'Cosine',
        },
      },
    );
  }

  /// 从 collection info 响应中解析向量维度 (兼容单向量配置结构)。
  int? _extractVectorSize(dynamic data) {
    try {
      final vectors = data['result']['config']['params']['vectors'];
      if (vectors is Map && vectors['size'] is int) {
        return vectors['size'] as int;
      }
    } catch (_) {}
    return null;
  }

  // ─── 嵌入 ─────────────────────────────────────────────────

  /// 调用嵌入模型获取向量（公开接口）。
  ///
  /// 供外部模块（如 SkillRouter 语义匹配）使用。
  /// 内部自带重试机制（3 次，指数退避）。
  Future<List<double>> embed(String text) => _embed(text);

  /// 调用嵌入模型获取向量。
  ///
  /// 针对 TLS 握手中断 / 连接被重置等瞬时网络故障做有限次重试，
  /// 避免一次抖动就丢掉整条记忆。
  Future<List<double>> _embed(String text) async {
    const maxAttempts = 3;
    DioException? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await _embeddingDio.post(
          '$_embeddingBase/embeddings',
          data: {'model': embeddingModel, 'input': text},
        );
        final data = resp.data as Map<String, dynamic>;
        final embedding = data['data'][0]['embedding'] as List;
        return embedding.cast<double>();
      } on DioException catch (e) {
        lastError = e;
        if (!_isTransient(e) || attempt == maxAttempts) rethrow;
        // 退避后重试：200ms, 400ms ...
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
    throw lastError!;
  }

  /// 判断是否为可重试的瞬时网络错误（握手中断 / 连接重置 / 超时等）。
  bool _isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        final msg = (e.error?.toString() ?? e.message ?? '').toLowerCase();
        return msg.contains('handshake') ||
            msg.contains('connection terminated') ||
            msg.contains('connection reset') ||
            msg.contains('connection closed') ||
            msg.contains('socket');
      default:
        return false;
    }
  }

  // ─── 存储 ─────────────────────────────────────────────────

  /// 存储一条记忆
  ///
  /// [text]: 记忆文本
  /// [collectionName]: 目标 collection (全局/项目)
  /// [metadata]: 额外元数据 (source, timestamp 等)
  /// [useQdrant]: 是否同时写入 Qdrant 向量库
  /// [supersedeThreshold]: 软失效检测的相似度阈值。写入前会以该阈值检索
  /// 语义高度重合的旧记忆并标记 superseded=true（不物理删除，只降权），
  /// 避免新旧事实同权重共存导致检索到过时信息。设为 null/<=0 可关闭该检测。
  ///
  /// 返回 point id
  Future<String> store({
    required String text,
    required String collectionName,
    Map<String, dynamic>? metadata,
    bool useQdrant = true,
    double? supersedeThreshold = 0.85,
  }) async {
    final pointId = _nextId().toString();

    final payload = <String, dynamic>{
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
      'superseded': false,
      ...?metadata,
    };

    // ① SQLite 始终写入 (持久备份)
    try {
      await memoryDao?.insert(
        id: int.parse(pointId),
        collection: collectionName,
        text: text,
        metadata: payload,
      );
    } catch (e) {
      AppLogger.instance.log('[Memory] SQLite 写入失败: $e');
    }

    // ② Qdrant 可选写入 (语义搜索增强)
    if (useQdrant) {
      try {
        final vector = await _embed(text);
        await ensureCollection(collectionName, vectorSize: vector.length);

        // ─── 软失效检测: 写入前标记语义高度重合的旧记忆为 superseded ───
        if (supersedeThreshold != null && supersedeThreshold > 0) {
          await _supersedeSimilar(
            collectionName: collectionName,
            vector: vector,
            threshold: supersedeThreshold,
          );
        }

        await _dio.put(
          '/collections/$collectionName/points',
          data: {
            'points': [
              {'id': int.parse(pointId), 'vector': vector, 'payload': payload},
            ],
          },
        );
      } on VectorDimensionMismatch catch (e) {
        // 维度不一致: 明确告警，提示重建。不静默吞错。
        AppLogger.instance.log('[Qdrant] 跳过写入 — $e');
      } on DioException catch (e) {
        AppLogger.instance.log(
          '[Qdrant] 插入失败 status=${e.response?.statusCode}, '
          'body=${e.response?.data}',
        );
        // Qdrant 失败不影响 SQLite 已存的数据
      }
    }

    return pointId;
  }

  /// 软失效检测: 查找与新记忆语义高度重合的旧记忆，标记为 superseded。
  ///
  /// 不物理删除旧记忆（保留可追溯性，符合保守维护原则），仅打标记降权，
  /// 使其在 [recall] 时被过滤掉。典型场景: 用户先说"用 pnpm"，后来说
  /// "改用 npm 了"——若不处理，两条记忆会以同等相关性被召回，模型可能
  /// 读到过时结论。
  Future<void> _supersedeSimilar({
    required String collectionName,
    required List<double> vector,
    required double threshold,
  }) async {
    try {
      final resp = await _dio.post(
        '/collections/$collectionName/points/search',
        data: {
          'vector': vector,
          'limit': 3,
          'score_threshold': threshold,
          'with_payload': true,
        },
      );
      final hits = resp.data['result'] as List;
      if (hits.isEmpty) return;

      final idsToSupersede = <dynamic>[];
      for (final hit in hits) {
        final payload = hit['payload'] as Map<String, dynamic>?;
        if (payload?['superseded'] == true) continue; // 已标记过，跳过
        idsToSupersede.add(hit['id']);
      }
      if (idsToSupersede.isEmpty) return;

      // Qdrant: 更新 payload 标记 (不改动向量，只改 payload)
      await _dio.post(
        '/collections/$collectionName/points/payload',
        data: {
          'payload': {'superseded': true},
          'points': idsToSupersede,
        },
      );

      // SQLite: 同步标记 (尽力而为，失败不影响主流程)
      if (memoryDao != null) {
        for (final id in idsToSupersede) {
          try {
            await memoryDao!.markSuperseded(collectionName, id as int);
          } catch (_) {}
        }
      }

      AppLogger.instance.log(
        '[Memory] 软失效: 已标记 ${idsToSupersede.length} 条旧记忆为 superseded '
        '(collection=$collectionName, threshold=$threshold)',
      );
    } catch (e) {
      // 软失效检测失败不影响主流程，新记忆仍会正常写入
      AppLogger.instance.log('[Memory] 软失效检测失败 (不影响写入): $e');
    }
  }

  // ─── 召回 ─────────────────────────────────────────────────

  /// 召回记忆
  ///
  /// [query]: 查询文本
  /// [collectionName]: 目标 collection
  /// [topK]: 返回最相似的 K 条
  /// [scoreThreshold]: 最低相似度阈值 (仅 Qdrant 模式有效)
  /// [useQdrant]: 是否使用 Qdrant 语义搜索 (false 则降级 SQLite 关键词)
  ///
  /// 已被标记 superseded (软失效，通常因为有更新的记忆覆盖了它) 的记忆
  /// 默认不会被召回，避免模型读到过时结论。
  ///
  /// 返回: [{text, score, timestamp, ...metadata}]
  Future<List<Map<String, dynamic>>> recall({
    required String query,
    required String collectionName,
    int topK = 5,
    double scoreThreshold = 0.5,
    bool useQdrant = true,
  }) async {
    // 优先尝试 Qdrant 语义搜索
    if (useQdrant) {
      try {
        // 先检查 collection 是否存在
        await _dio.get('/collections/$collectionName');

        final queryVector = await _embed(query);
        final resp = await _dio.post(
          '/collections/$collectionName/points/search',
          data: {
            'vector': queryVector,
            'limit': topK,
            'score_threshold': scoreThreshold,
            'with_payload': true,
            // 过滤掉被软失效标记的旧记忆，避免过时结论污染检索结果
            'filter': {
              'must_not': [
                {
                  'key': 'superseded',
                  'match': {'value': true},
                },
              ],
            },
          },
        );

        final results = (resp.data['result'] as List).map((item) {
          final payload = item['payload'] as Map<String, dynamic>;
          return {
            ...payload,
            'score': item['score'],
            'source': 'qdrant', // 标注来源: 语义检索
          };
        }).toList();

        if (results.isNotEmpty) return results;
        // Qdrant 返回空则降级 SQLite
        AppLogger.instance.log('[Memory] Qdrant 召回为空，降级 SQLite 关键词');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) {
          AppLogger.instance.log('[Memory] Qdrant 召回异常，降级 SQLite: $e');
        }
        // collection 不存在或 Qdrant 异常 → 降级 SQLite
      } catch (e) {
        AppLogger.instance.log('[Memory] Qdrant 召回异常，降级 SQLite: $e');
      }
    }

    // 降级: SQLite 关键词搜索
    if (memoryDao != null) {
      try {
        return await memoryDao!.search(collectionName, query, limit: topK);
      } catch (e) {
        AppLogger.instance.log('[Memory] SQLite 召回也失败: $e');
      }
    }

    return [];
  }

  // ─── 删除 ─────────────────────────────────────────────────

  /// 删除指定 point
  Future<void> deletePoint(String collectionName, int pointId) async {
    await _dio.post(
      '/collections/$collectionName/points/delete',
      data: {
        'points': [pointId],
      },
    );
    // SQLite 同步删除
    try {
      await memoryDao?.delete(collectionName, pointId);
    } catch (_) {}
  }

  /// 删除整个 collection
  Future<void> deleteCollection(String collectionName) async {
    try {
      await _dio.delete('/collections/$collectionName');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    // SQLite 同步清空
    try {
      await memoryDao?.deleteAll(collectionName);
    } catch (_) {}
  }

  // ─── 统计 ─────────────────────────────────────────────────

  /// 获取 collection 中的 point 数量
  Future<int> getPointCount(String collectionName) async {
    try {
      final resp = await _dio.get('/collections/$collectionName');
      final info = resp.data['result'] as Map<String, dynamic>;
      return info['points_count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 获取所有 collection 列表
  Future<List<String>> listCollections() async {
    try {
      final resp = await _dio.get('/collections');
      final collections = resp.data['result']['collections'] as List;
      return collections.map((c) => c['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// 列出指定 collection 中的记忆条目 (使用 scroll API)
  ///
  /// 返回: [{id, text, timestamp, ...metadata}]，按时间倒序
  Future<List<Map<String, dynamic>>> listPoints(
    String collectionName, {
    int limit = 100,
  }) async {
    try {
      final resp = await _dio.post(
        '/collections/$collectionName/points/scroll',
        data: {'limit': limit, 'with_payload': true, 'with_vector': false},
      );
      final points = resp.data['result']['points'] as List;
      final items = points.map((pt) {
        final payload = (pt['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        return <String, dynamic>{'id': pt['id'], ...payload};
      }).toList();

      // 按 timestamp 倒序 (最新的在前)
      items.sort((a, b) {
        final ta = a['timestamp'] as String? ?? '';
        final tb = b['timestamp'] as String? ?? '';
        return tb.compareTo(ta);
      });
      return items;
    } catch (_) {
      return [];
    }
  }

  // ─── 重建 ─────────────────────────────────────────────────

  /// 从 SQLite 备份重建 Qdrant 向量索引。
  ///
  /// 场景: Qdrant 数据丢失/损坏，或更换 embedding 模型导致维度变化。
  /// 会先删除旧 collection (规避维度不一致)，再按新模型的实际维度重建，
  /// 对每条记忆重新调用 embedding 接口生成向量后插入。
  ///
  /// 返回成功恢复的条数。
  Future<int> rebuildFromSqlite(String collectionName) async {
    if (memoryDao == null) return 0;

    final entries = await memoryDao!.getAll(collectionName);
    if (entries.isEmpty) return 0;

    // 先删除旧 collection，确保按新维度重建 (换模型场景)。
    try {
      await _dio.delete('/collections/$collectionName');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        AppLogger.instance.log('[Memory] 重建前删除旧 collection 失败: $e');
      }
    }

    int restored = 0;
    for (final entry in entries) {
      final text = entry['text'] as String;
      final id = entry['id'] as int;
      final metadata = entry['metadata'] as Map<String, dynamic>;

      try {
        final vector = await _embed(text);
        await ensureCollection(collectionName, vectorSize: vector.length);
        await _dio.put(
          '/collections/$collectionName/points',
          data: {
            'points': [
              {'id': id, 'vector': vector, 'payload': metadata},
            ],
          },
        );
        restored++;
      } catch (e) {
        AppLogger.instance.log('[Memory] 重建跳过 id=$id: $e');
      }
    }
    AppLogger.instance.log('[Memory] 重建完成: $restored/${entries.length} 条');
    return restored;
  }
}

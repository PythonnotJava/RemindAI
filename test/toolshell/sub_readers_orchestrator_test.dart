import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/llm/llm_client.dart';
import 'package:remind_ai/core/toolshell/read_only_executor.dart';
import 'package:remind_ai/core/toolshell/sub_readers_orchestrator.dart';

/// 可编程的假 LlmClient：
/// - [chat] 按调用顺序从 [chatResponses] 队列里取一个预设回复
///   （规划阶段/合并阶段都走 chat()，可分别控制其输出）。
/// - [chatStreamFull] 按调用顺序从 [streamResponses] 队列里取一个预设的
///   最终 StreamComplete（子 Agent 的 AgentLoop 走这个），
///   直接以单个 StreamComplete 结束（不产生 ContentToken，模拟一次响应
///   即给出最终答案、无需工具调用的简单场景）。
class FakeLlmClient implements LlmClient {
  final List<String> chatResponses;
  final List<String> streamResponses;
  int _chatCalls = 0;
  int _streamCalls = 0;

  /// 记录每次 chatStreamFull 收到的完整消息历史，供测试断言子 Agent
  /// 看到的 system prompt / instruction 是否正确。
  final List<List<Map<String, dynamic>>> streamCallMessages = [];

  FakeLlmClient({
    this.chatResponses = const [],
    this.streamResponses = const [],
  });

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    final content = _chatCalls < chatResponses.length
        ? chatResponses[_chatCalls]
        : '';
    _chatCalls++;
    return ChatResponse(content: content, finishReason: 'stop');
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    streamCallMessages.add(messages);
    final content = _streamCalls < streamResponses.length
        ? streamResponses[_streamCalls]
        : '';
    _streamCalls++;
    yield StreamComplete(content: content, finishReason: 'stop');
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remindai_subreaders_');
    await File(
      '${root.path}${Platform.pathSeparator}a.md',
    ).writeAsString('文章A的内容');
    await File(
      '${root.path}${Platform.pathSeparator}b.md',
    ).writeAsString('文章B的内容');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('阶段 1: 规划 (plan)', () {
    test('正常 JSON 输出解析为对应数量的子任务', () async {
      final fake = FakeLlmClient(
        chatResponses: [
          '[{"scope": "文章A", "instruction": "分析文章A"}, '
              '{"scope": "文章B", "instruction": "分析文章B"}]',
        ],
      );
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final tasks = await orchestrator.plan('理解 a.md 和 b.md');
      expect(tasks.length, 2);
      expect(tasks[0].scope, '文章A');
      expect(tasks[1].scope, '文章B');
    });

    test('模型输出被 ```json 代码块包裹时仍能解析', () async {
      final fake = FakeLlmClient(
        chatResponses: [
          '```json\n[{"scope": "全部", "instruction": "理解全部内容"}]\n```',
        ],
      );
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final tasks = await orchestrator.plan('理解这个项目');
      expect(tasks.length, 1);
      expect(tasks[0].scope, '全部');
    });

    test('模型输出无法解析为 JSON 时降级为单任务，不会导致整体失败', () async {
      final fake = FakeLlmClient(chatResponses: ['我不知道怎么拆分这个任务']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final tasks = await orchestrator.plan('理解这批文章');
      expect(tasks.length, 1);
      expect(tasks[0].instruction, '理解这批文章');
    });

    test('任务数超过 maxSubtasks 时被截断', () async {
      final items = List.generate(
        10,
        (i) => '{"scope": "任务$i", "instruction": "处理任务$i"}',
      ).join(',');
      final fake = FakeLlmClient(chatResponses: ['[$items]']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
        maxSubtasks: 3,
      );

      final tasks = await orchestrator.plan('处理大量任务');
      expect(tasks.length, 3);
    });

    test('空数组输出降级为单任务', () async {
      final fake = FakeLlmClient(chatResponses: ['[]']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final tasks = await orchestrator.plan('理解这个东西');
      expect(tasks.length, 1);
      expect(tasks[0].instruction, '理解这个东西');
    });
  });

  group('阶段 2: 单个子任务执行 (runSubtask)', () {
    test('子 Agent 使用独立的 LlmClient，收到的 system prompt 含任务范围', () async {
      final fake = FakeLlmClient(streamResponses: ['文章A的总结']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final task = SubReaderTask(id: 't1', scope: '文章A', instruction: '分析文章A');
      final result = await orchestrator.runSubtask(task);

      expect(result, '文章A的总结');
      expect(fake.streamCallMessages, isNotEmpty);
      final systemMsg = fake.streamCallMessages.first.first;
      expect(systemMsg['role'], 'system');
      expect(systemMsg['content'], contains('文章A'));
    });

    test('子 Agent 报错时 runSubtask 抛出异常（供上层捕获为失败结果）', () async {
      // AgentError 场景通过让 fake 抛异常间接触发比较复杂，这里改为验证：
      // 若底层 chatStreamFull 抛出异常，runSubtask 会向上传播。
      final throwingLlm = _ThrowingLlmClient();
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => throwingLlm,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final task = SubReaderTask(id: 't1', scope: 'x', instruction: 'y');
      expect(() => orchestrator.runSubtask(task), throwsA(isA<Exception>()));
    });
  });

  group('阶段 3: 合并 (merge)', () {
    test('合并阶段把所有子任务结果和原始需求一起交给模型', () async {
      final fake = FakeLlmClient(chatResponses: ['这是综合理解']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final results = [
        SubReaderResult(
          task: SubReaderTask(id: 't1', scope: '文章A', instruction: 'x'),
          content: 'A的总结',
          success: true,
        ),
        SubReaderResult(
          task: SubReaderTask(id: 't2', scope: '文章B', instruction: 'y'),
          content: '',
          success: false,
          error: '超时',
        ),
      ];

      final merged = await orchestrator.merge('理解这两篇文章', results);
      expect(merged, '这是综合理解');
    });

    test('模型合并输出为空时降级为原始拼接文本，不丢信息', () async {
      final fake = FakeLlmClient(chatResponses: ['']);
      final orchestrator = SubReadersOrchestrator(
        createLlm: () => fake,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final results = [
        SubReaderResult(
          task: SubReaderTask(id: 't1', scope: '文章A', instruction: 'x'),
          content: 'A的关键内容',
          success: true,
        ),
      ];

      final merged = await orchestrator.merge('理解文章', results);
      expect(merged, contains('A的关键内容'));
    });
  });

  group('完整流程 (run): 事件序列与并行性', () {
    test('规划→并行执行→合并的完整事件序列', () async {
      var chatCallCount = 0;
      final planAndMergeLlm = _SequencedLlmClient(
        chatSequence: [
          // 第一次 chat() 调用来自 plan()
          '[{"scope": "文章A", "instruction": "分析A"}, '
              '{"scope": "文章B", "instruction": "分析B"}]',
          // 第二次 chat() 调用来自 merge()
          '综合理解: A和B都讨论了xx',
        ],
        onChatCall: () => chatCallCount++,
      );

      final orchestrator = SubReadersOrchestrator(
        // 规划/合并阶段和子任务阶段都用同一个 fake，
        // 子任务阶段走 chatStreamFull（该 fake 对此返回默认空实现）。
        createLlm: () => planAndMergeLlm,
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final events = await orchestrator.run('理解 a.md 和 b.md').toList();

      // 必须先有一次 Planned 事件
      expect(events.whereType<SubReadersPlanned>().length, 1);
      final planned = events.whereType<SubReadersPlanned>().first;
      expect(planned.tasks.length, 2);

      // 每个任务都应有 Started 和 Finished
      expect(events.whereType<SubReaderStarted>().length, 2);
      expect(events.whereType<SubReaderFinished>().length, 2);

      // 最终应有且仅有一次 Merged
      expect(events.whereType<SubReadersMerged>().length, 1);
      final merged = events.whereType<SubReadersMerged>().first;
      expect(merged.finalContent, '综合理解: A和B都讨论了xx');
      expect(merged.results.length, 2);

      // Planned 必须在所有 Started/Finished 之前，Merged 必须在最后
      final plannedIdx = events.indexWhere((e) => e is SubReadersPlanned);
      final mergedIdx = events.indexWhere((e) => e is SubReadersMerged);
      expect(plannedIdx, 0);
      expect(mergedIdx, events.length - 1);
      for (final e in events) {
        if (e is SubReaderStarted || e is SubReaderFinished) {
          expect(events.indexOf(e), greaterThan(plannedIdx));
          expect(events.indexOf(e), lessThan(mergedIdx));
        }
      }
    });

    test('子任务失败不阻塞其他子任务，也不阻塞最终合并', () async {
      // createLlm 每次调用返回一个新实例：规划/合并阶段共用第一个实例的
      // chatSequence；子任务阶段则按 instruction 是否含"失败"决定是否抛异常。
      final planAndMergeLlm = _SequencedLlmClient(
        chatSequence: [
          '[{"scope": "会失败", "instruction": "请故意失败"}, '
              '{"scope": "会成功", "instruction": "正常处理"}]',
          '综合: 一个失败一个成功',
        ],
      );

      final orchestrator = SubReadersOrchestrator(
        createLlm: () => _MixedResultLlmClient(planAndMerge: planAndMergeLlm),
        createReadOnlyExecutor: () => ReadOnlyExecutor(projectRoot: root.path),
        readOnlyTools: ReadOnlyExecutor.toolDefinitions,
      );

      final events = await orchestrator.run('理解两个任务').toList();

      // 两个子任务都应有 Finished 事件，一个成功一个失败
      final finished = events.whereType<SubReaderFinished>().toList();
      expect(finished.length, 2);
      expect(finished.where((e) => e.success).length, 1);
      expect(finished.where((e) => !e.success).length, 1);

      // 即使有子任务失败，最终仍应推进到合并阶段
      expect(events.whereType<SubReadersMerged>().length, 1);
      expect(
        events.whereType<SubReadersMerged>().first.finalContent,
        '综合: 一个失败一个成功',
      );

      // merge() 阶段应能看到失败任务的结果 (success=false)，供其在提示词中说明缺失
      final mergedResults = events.whereType<SubReadersMerged>().first.results;
      expect(mergedResults.where((r) => !r.success).length, 1);
    });
  });
}

/// 用于"混合成功/失败"场景：plan/merge 阶段的 chat() 转发给
/// [planAndMerge]（复用其顺序化脚本），子任务阶段的 chatStreamFull()
/// 按 instruction 是否包含"失败"决定正常返回还是抛异常。
class _MixedResultLlmClient implements LlmClient {
  final _SequencedLlmClient planAndMerge;

  _MixedResultLlmClient({required this.planAndMerge});

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) => planAndMerge.chat(messages, tools: tools);

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    final lastUser = messages.lastWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': ''},
    );
    final instruction = lastUser['content']?.toString() ?? '';
    if (instruction.contains('失败')) {
      throw Exception('模拟该子任务执行失败');
    }
    yield StreamComplete(content: '已处理: $instruction', finishReason: 'stop');
  }
}

/// 子任务阶段调用 chatStreamFull 时直接抛异常，用于验证 runSubtask 的异常传播。
class _ThrowingLlmClient implements LlmClient {
  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    return ChatResponse(content: '', finishReason: 'stop');
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    throw Exception('模拟网络故障');
  }
}

/// 按调用顺序消费 [chatSequence] 的假 LlmClient，用于驱动 plan() → merge()
/// 这种"同一个 llm 实例被顺序调用两次 chat()"的场景。
/// chatStreamFull（子任务阶段）总是直接返回一个基于 instruction 的简单回复，
/// 不依赖工具调用，聚焦于验证编排逻辑而非 AgentLoop 内部机制。
class _SequencedLlmClient implements LlmClient {
  final List<String> chatSequence;
  final void Function()? onChatCall;
  int _chatIndex = 0;

  _SequencedLlmClient({required this.chatSequence, this.onChatCall});

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    onChatCall?.call();
    final content = _chatIndex < chatSequence.length
        ? chatSequence[_chatIndex]
        : '';
    _chatIndex++;
    return ChatResponse(content: content, finishReason: 'stop');
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    // 子 Agent 场景：直接给出一个基于最后一条 user 消息的简单回复
    final lastUser = messages.lastWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': ''},
    );
    yield StreamComplete(
      content: '已处理: ${lastUser['content']}',
      finishReason: 'stop',
    );
  }
}

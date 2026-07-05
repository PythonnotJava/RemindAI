import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/llm/llm_client.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/agent_loop.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 AgentLoop 单轮对话内的 tool_call 轮次熔断 (maxToolCallRounds)。
///
/// 背景: AgentLoop.chat() 内部是一个 while(true)，只要 LLM 持续返回
/// tool_calls 就会一直执行工具再问 LLM，直到收到无 tool_calls 的最终回复
/// 才退出。此前这个内层循环没有任何上限保护——如果模型卡在反复调用同一个
/// 工具、永不给出最终回复，会真的无限循环下去。这与更外层的
/// AutonomousLoop.maxIterations(管"调用几次 chat()"，即 Loop 模式的迭代
/// 上限)是完全不同粒度的保护，两者互不替代。
///
/// 这里测的是循环的轮次计数/熔断逻辑本身，不涉及真实大型项目的压力场景，
/// 所以用临时目录自包含即可，测试结束自动清理，不留悬空依赖。
/// 用一个永远返回 tool_calls、从不给最终回复的 FakeLlmClient 模拟
/// "模型卡死不收敛"的场景。
void main() {
  late Directory tempDir;
  late String projectRoot;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agent_loop_limit_');
    projectRoot = tempDir.path;
    await File(
      '${tempDir.path}${Platform.pathSeparator}hello.txt',
    ).writeAsString('hello world');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('AgentLoop - maxToolCallRounds 熔断', () {
    test('LLM 永远返回 tool_calls 不收敛时，达到上限后触发 AgentLoopLimitReached', () async {
      final llm = _AlwaysToolCallLlmClient(
        toolName: 'toolshell_read',
        args: {'path': 'hello.txt'},
      );
      final executor = Executor(
        projectRoot: projectRoot,
        permissionMode: PermissionMode.auto,
      );

      final loop = AgentLoop(
        llm: llm,
        executor: executor,
        tools: const [],
        messages: [],
        maxToolCallRounds: 5, // 故意设小一点，避免测试跑太久
      );

      final events = await loop.chat('请一直读这个文件').toList();

      print('[测试] 事件序列: ${events.map((e) => e.runtimeType).toList()}');
      print('[测试] LLM 被调用次数: ${llm.callCount}');

      // 最后一个事件必须是 AgentLoopLimitReached，且不能有 AgentDone
      expect(events.last, isA<AgentLoopLimitReached>());
      expect(events.whereType<AgentDone>(), isEmpty);
      expect(events.whereType<AgentError>(), isEmpty);

      final limitEvent = events.last as AgentLoopLimitReached;
      expect(limitEvent.rounds, 5);

      // LLM 恰好被调用 maxToolCallRounds 次，多一次都不应该发生
      // (第6次调用应该被熔断拦住，不会真的再打一次 LLM)
      expect(llm.callCount, 5);

      // 期间工具确实真实执行了 (每轮一次 AgentToolStart + AgentToolResult)
      expect(events.whereType<AgentToolStart>().length, 5);
      expect(events.whereType<AgentToolResult>().length, 5);

      print(
        '[测试] 结论: 熔断在第 ${limitEvent.rounds} 轮触发，LLM 未被继续调用，'
        '循环正确终止而非无限进行下去',
      );
    });

    test('正常收敛场景不受影响: 1轮 tool_call 后给出最终回复', () async {
      final llm = _OneShotToolThenDoneLlmClient(
        toolName: 'toolshell_read',
        args: {'path': 'hello.txt'},
        finalContent: '文件内容已读取完毕',
      );
      final executor = Executor(
        projectRoot: projectRoot,
        permissionMode: PermissionMode.auto,
      );

      final loop = AgentLoop(
        llm: llm,
        executor: executor,
        tools: const [],
        messages: [],
        maxToolCallRounds: 5,
      );

      final events = await loop.chat('读一下这个文件').toList();

      expect(events.whereType<AgentLoopLimitReached>(), isEmpty);
      expect(events.whereType<AgentError>(), isEmpty);
      final done = events.whereType<AgentDone>().single;
      expect(done.content, '文件内容已读取完毕');

      print('[测试] 结论: 正常在上限之内收敛的场景，熔断不会误触发');
    });
  });
}

/// 永远返回同一个 tool_call、从不给最终回复的假 LLM —— 模拟"模型卡死"。
class _AlwaysToolCallLlmClient implements LlmClient {
  final String toolName;
  final Map<String, dynamic> args;
  int callCount = 0;

  _AlwaysToolCallLlmClient({required this.toolName, required this.args});

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    throw UnimplementedError('本测试只走 chatStreamFull');
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    callCount++;
    yield StreamComplete(
      content: null,
      toolCalls: [
        ToolCall(id: 'call_$callCount', name: toolName, arguments: args),
      ],
      finishReason: 'tool_calls',
    );
  }
}

/// 第一轮返回 tool_call，第二轮给出最终回复 —— 模拟正常收敛场景。
class _OneShotToolThenDoneLlmClient implements LlmClient {
  final String toolName;
  final Map<String, dynamic> args;
  final String finalContent;
  int callCount = 0;

  _OneShotToolThenDoneLlmClient({
    required this.toolName,
    required this.args,
    required this.finalContent,
  });

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    throw UnimplementedError('本测试只走 chatStreamFull');
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    callCount++;
    if (callCount == 1) {
      yield StreamComplete(
        content: null,
        toolCalls: [ToolCall(id: 'call_1', name: toolName, arguments: args)],
        finishReason: 'tool_calls',
      );
    } else {
      yield StreamComplete(
        content: finalContent,
        toolCalls: null,
        finishReason: 'stop',
      );
    }
  }
}

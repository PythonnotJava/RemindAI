import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/llm/llm_client.dart';
import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/agent_loop.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 AgentLoop 单轮对话内的 tool_call 轮次熔断，以及不完整响应的终止语义。
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
        maxToolCallRounds: 5,
      );

      final events = await loop.chat('请一直读这个文件').toList();

      expect(events.last, isA<AgentLoopLimitReached>());
      expect(events.whereType<AgentDone>(), isEmpty);
      expect(events.whereType<AgentError>(), isEmpty);
      expect((events.last as AgentLoopLimitReached).rounds, 5);
      expect(llm.callCount, 5);
      expect(events.whereType<AgentToolStart>().length, 5);
      expect(events.whereType<AgentToolResult>().length, 5);
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
      expect(events.whereType<AgentDone>().single.content, '文件内容已读取完毕');
    });

    test('reasoning-only 响应不得被当作正常完成', () async {
      final loop = AgentLoop(
        llm: _ReasoningOnlyLlmClient(),
        executor: Executor(
          projectRoot: projectRoot,
          permissionMode: PermissionMode.auto,
        ),
        tools: const [],
        messages: [],
      );

      final events = await loop.chat('完成任务').toList();

      expect(events.whereType<AgentReasoningToken>().length, 1);
      expect(events.whereType<AgentDone>(), isEmpty);
      expect(events.whereType<AgentError>().single.message, contains('只返回了推理内容'));
    });

    test('流截断响应不得被当作正常完成', () async {
      final loop = AgentLoop(
        llm: _TruncatedLlmClient(),
        executor: Executor(
          projectRoot: projectRoot,
          permissionMode: PermissionMode.auto,
        ),
        tools: const [],
        messages: [],
      );

      final events = await loop.chat('完成任务').toList();

      expect(events.whereType<AgentDone>(), isEmpty);
      expect(events.whereType<AgentError>().single.message, contains('响应被截断'));
    });
  });
}

class _AlwaysToolCallLlmClient implements LlmClient {
  final String toolName;
  final Map<String, dynamic> args;
  int callCount = 0;

  _AlwaysToolCallLlmClient({required this.toolName, required this.args});

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => throw UnimplementedError('本测试只走 chatStreamFull');

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    callCount++;
    yield StreamComplete(
      toolCalls: [ToolCall(id: 'call_$callCount', name: toolName, arguments: args)],
      finishReason: 'tool_calls',
    );
  }
}

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
  }) async => throw UnimplementedError('本测试只走 chatStreamFull');

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    callCount++;
    if (callCount == 1) {
      yield StreamComplete(
        toolCalls: [ToolCall(id: 'call_1', name: toolName, arguments: args)],
        finishReason: 'tool_calls',
      );
    } else {
      yield StreamComplete(content: finalContent, finishReason: 'stop');
    }
  }
}

class _ReasoningOnlyLlmClient implements LlmClient {
  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => throw UnimplementedError();

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    yield ReasoningToken('正在思考但还没有最终答案');
    yield StreamComplete(
      reasoningContent: '正在思考但还没有最终答案',
      finishReason: 'stop',
    );
  }
}

class _TruncatedLlmClient implements LlmClient {
  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => throw UnimplementedError();

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    yield ContentToken('尚未完成的部分输出');
    yield StreamComplete(
      content: '尚未完成的部分输出',
      finishReason: 'stream_incomplete',
      isTruncated: true,
    );
  }
}

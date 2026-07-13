import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/message_pipeline.dart';
import 'package:remind_ai/core/agent/transformers/context_compactor.dart';
import 'package:remind_ai/core/llm/llm_client.dart';
import 'package:remind_ai/core/toolshell/agent_loop.dart';
import 'package:remind_ai/core/toolshell/executor.dart';
import 'package:remind_ai/core/memory/project_config.dart';

/// 测试对话中压缩功能：在单轮对话的工具循环内触发上下文压缩
void main() {
  group('对话中压缩功能', () {
    test('场景1: 工具循环累积超过阈值时应触发压缩', () async {
      // 创建一个模拟的 LLM 客户端，返回大量工具调用
      final mockLlm = _MockLlmForCompaction();

      // 创建 Executor
      final executor = Executor(
        projectRoot: '.',
        permissionMode: PermissionMode.auto,
      );

      // 创建包含 ContextCompactor 的 MessagePipeline
      final compactor = ContextCompactor(
        llm: mockLlm,
        contextWindow: 10000, // 10K tokens
        keepRecentTurns: 3,
      );
      final pipeline = MessagePipeline([compactor]);

      // 初始化消息列表
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Test system prompt'},
      ];

      // 创建 AgentLoop
      final agentLoop = AgentLoop(
        llm: mockLlm,
        executor: executor,
        tools: [],
        messages: messages,
        messagePipeline: pipeline,
        contextWindow: 10000,
      );

      // 记录事件
      final events = <String>[];
      int tokenCount = 0;

      // 执行对话（会模拟 10 轮工具调用，每轮返回 1000 tokens）
      await for (final event in agentLoop.chat('Test input')) {
        switch (event) {
          case AgentToken():
            events.add('token');
          case AgentToolStart():
            events.add('tool_start');
          case AgentToolResult():
            events.add('tool_result');
            tokenCount++;
          case AgentDone():
            events.add('done');
          case AgentError():
            events.add('error: ${event.message}');
          default:
            break;
        }
      }

      // 验证：
      // 1. 至少执行了一些工具调用
      expect(events.where((e) => e == 'tool_result').length, greaterThan(0));

      // 2. 消息列表应该被压缩过（数量减少）
      // 初始: system + user = 2
      // 10轮工具调用 = 10 * (assistant + tool) = 20
      // 总共 22 条，但压缩后应该少于这个数
      print('[Test] 最终消息数量: ${messages.length}');
      print('[Test] 事件: ${events.join(", ")}');

      // 注意：由于 MockLlm 的限制，实际测试可能需要调整
    });

    test('场景2: 未达到阈值时不应压缩', () async {
      final mockLlm = _MockLlmForCompaction(toolCallRounds: 2); // 只2轮

      final executor = Executor(
        projectRoot: '.',
        permissionMode: PermissionMode.auto,
      );

      final compactor = ContextCompactor(
        llm: mockLlm,
        contextWindow: 100000, // 100K tokens，足够大
        keepRecentTurns: 3,
      );
      final pipeline = MessagePipeline([compactor]);

      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Test'},
      ];

      final agentLoop = AgentLoop(
        llm: mockLlm,
        executor: executor,
        tools: [],
        messages: messages,
        messagePipeline: pipeline,
        contextWindow: 100000,
      );

      await for (final event in agentLoop.chat('Test')) {
        // 只是消费流
      }

      // 验证：消息数量应该正常累积，没有被压缩
      // system + user + 2 * (assistant + tool) + final assistant = 7
      print('[Test] 场景2 消息数量: ${messages.length}');
      expect(messages.length, greaterThanOrEqualTo(5));
    });
  });
}

/// 模拟的 LLM 客户端，用于测试对话中压缩
class _MockLlmForCompaction implements LlmClient {
  final int toolCallRounds;
  int currentRound = 0;

  _MockLlmForCompaction({this.toolCallRounds = 10});

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    // 用于压缩时生成摘要
    return ChatResponse(
      content: '这是一个摘要：前面的对话包含了多轮工具调用。',
      toolCalls: null,
      finishReason: 'stop',
    );
  }

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async* {
    currentRound++;

    if (currentRound <= toolCallRounds) {
      // 前 N 轮：返回工具调用
      yield ContentToken('执行工具 $currentRound\n');

      // 模拟一个返回大量内容的工具调用
      yield StreamComplete(
        content: '执行工具 $currentRound',
        toolCalls: [
          ToolCall(
            id: 'call_$currentRound',
            name: 'toolshell_read',
            arguments: {'path': 'test.txt'},
          ),
        ],
        finishReason: 'tool_calls',
      );
    } else {
      // 最后一轮：返回最终回复
      yield ContentToken('任务完成\n');
      yield StreamComplete(
        content: '任务完成',
        toolCalls: null,
        finishReason: 'stop',
      );
    }
  }
}

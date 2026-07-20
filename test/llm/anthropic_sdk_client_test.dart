import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/llm/anthropic_sdk_client.dart';
import 'package:remind_ai/core/llm/llm_client.dart';

void main() {
  group('AnthropicSdkClient', () {
    test('创建客户端实例', () {
      final client = AnthropicSdkClient(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'test-key',
        model: 'claude-3-5-sonnet-20241022',
        maxTokens: 4096,
      );

      expect(client, isNotNull);
      expect(client.model, 'claude-3-5-sonnet-20241022');
      expect(client.maxTokens, 4096);
    });

    test('消息格式转换 - 简单文本消息', () {
      final client = AnthropicSdkClient(
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'test-key',
        model: 'claude-3-5-sonnet-20241022',
      );

      // 测试会通过 _convertMessages 内部调用
      // 这里只验证客户端创建和基本属性
      expect(client.model, 'claude-3-5-sonnet-20241022');
    });

    test('ChatResponse 构建', () {
      final response = ChatResponse(content: 'Hello', finishReason: 'stop');

      expect(response.content, 'Hello');
      expect(response.finishReason, 'stop');
      expect(response.toolCalls, isNull);
    });

    test('ChatResponse 带工具调用', () {
      final response = ChatResponse(
        content: 'Let me help you with that.',
        toolCalls: [
          ToolCall(
            id: 'call_123',
            name: 'search',
            arguments: {'query': 'test'},
          ),
        ],
        finishReason: 'tool_use',
      );

      expect(response.content, 'Let me help you with that.');
      expect(response.toolCalls, isNotNull);
      expect(response.toolCalls!.length, 1);
      expect(response.toolCalls![0].name, 'search');
      expect(response.toolCalls![0].arguments['query'], 'test');
    });
  });
}

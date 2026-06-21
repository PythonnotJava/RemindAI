import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/server/anthropic_proxy.dart';

void main() {
  group('AnthropicProxy.blocksToText', () {
    test('字符串原样返回', () {
      expect(AnthropicProxy.blocksToText('hello'), 'hello');
    });
    test('block 数组抽取 text', () {
      final blocks = [
        {'type': 'text', 'text': 'a'},
        {'type': 'tool_use', 'name': 'x'},
        {'type': 'text', 'text': 'b'},
      ];
      expect(AnthropicProxy.blocksToText(blocks), 'a\nb');
    });
    test('null 返回空串', () {
      expect(AnthropicProxy.blocksToText(null), '');
    });
  });

  group('AnthropicProxy.convertTools', () {
    test('Anthropic tools → OpenAI function', () {
      final tools = [
        {
          'name': 'Bash',
          'description': '执行命令',
          'input_schema': {
            'type': 'object',
            'properties': {
              'command': {'type': 'string'},
            },
          },
        },
      ];
      final out = AnthropicProxy.convertTools(tools)!;
      expect(out.length, 1);
      expect(out[0]['type'], 'function');
      final fn = out[0]['function'] as Map;
      expect(fn['name'], 'Bash');
      expect(fn['description'], '执行命令');
      expect((fn['parameters'] as Map)['type'], 'object');
    });
    test('空/非列表返回 null', () {
      expect(AnthropicProxy.convertTools(null), isNull);
      expect(AnthropicProxy.convertTools([]), isNull);
    });
  });

  group('AnthropicProxy.convertMessages 双向还原', () {
    test('system + 普通文本', () {
      final msgs = AnthropicProxy.convertMessages([
        {'role': 'user', 'content': 'hi'},
      ], systemText: 'you are helpful');
      expect(msgs[0], {'role': 'system', 'content': 'you are helpful'});
      expect(msgs[1], {'role': 'user', 'content': 'hi'});
    });

    test('assistant tool_use → tool_calls', () {
      final msgs = AnthropicProxy.convertMessages([
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': '我来执行'},
            {
              'type': 'tool_use',
              'id': 'tu_1',
              'name': 'Bash',
              'input': {'command': 'ls'},
            },
          ],
        },
      ]);
      final m = msgs[0];
      expect(m['role'], 'assistant');
      expect(m['content'], '我来执行');
      final calls = m['tool_calls'] as List;
      expect(calls.length, 1);
      expect(calls[0]['id'], 'tu_1');
      expect(calls[0]['function']['name'], 'Bash');
      expect(jsonDecode(calls[0]['function']['arguments'] as String), {
        'command': 'ls',
      });
    });

    test('user tool_result → role:tool 消息', () {
      final msgs = AnthropicProxy.convertMessages([
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'tu_1',
              'content': 'file1.txt\nfile2.txt',
            },
          ],
        },
      ]);
      expect(msgs[0]['role'], 'tool');
      expect(msgs[0]['tool_call_id'], 'tu_1');
      expect(msgs[0]['content'], 'file1.txt\nfile2.txt');
    });

    test('完整一轮: user → assistant(tool_use) → user(tool_result)', () {
      final msgs = AnthropicProxy.convertMessages([
        {'role': 'user', 'content': '列出文件'},
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'tu_9',
              'name': 'Bash',
              'input': {'command': 'ls'},
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'tu_9', 'content': 'a.txt'},
          ],
        },
      ]);
      // user → assistant(含tool_calls) → tool
      expect(msgs[0]['role'], 'user');
      expect(msgs[1]['role'], 'assistant');
      expect((msgs[1]['tool_calls'] as List).length, 1);
      expect(msgs[2]['role'], 'tool');
      expect(msgs[2]['tool_call_id'], 'tu_9');
    });
  });

  group('AnthropicProxy Kimi token 解析', () {
    test('识别并解析 Kimi 内嵌工具调用', () {
      const text =
          '我来帮你建项目。<|tool_calls_section_begin|><|tool_call_begin|>'
          'functions.Bash:0<|tool_call_argument_begin|>'
          '{"command":"flutter create todo"}<|tool_call_end|>'
          '<|tool_calls_section_end|>';
      expect(AnthropicProxy.hasKimiToolCalls(text), isTrue);
      final (cleaned, calls) = AnthropicProxy.parseKimiToolCalls(text);
      expect(cleaned, '我来帮你建项目。');
      expect(calls.length, 1);
      expect(calls[0].name, 'Bash');
      expect(calls[0].arguments, {'command': 'flutter create todo'});
    });

    test('多个工具调用', () {
      const text =
          '<|tool_calls_section_begin|>'
          '<|tool_call_begin|>functions.Read:0<|tool_call_argument_begin|>'
          '{"path":"a"}<|tool_call_end|>'
          '<|tool_call_begin|>functions.Write:1<|tool_call_argument_begin|>'
          '{"path":"b","content":"x"}<|tool_call_end|>'
          '<|tool_calls_section_end|>';
      final (_, calls) = AnthropicProxy.parseKimiToolCalls(text);
      expect(calls.length, 2);
      expect(calls[0].name, 'Read');
      expect(calls[1].name, 'Write');
    });

    test('普通文本不误判', () {
      expect(AnthropicProxy.hasKimiToolCalls('正常回复, 没有工具调用'), isFalse);
    });
  });
}

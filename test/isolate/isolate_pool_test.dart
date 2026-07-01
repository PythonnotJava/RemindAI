import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/isolate/isolate_pool.dart';
import 'package:remind_ai/core/isolate/compute_service.dart';
import 'package:remind_ai/core/isolate/tasks/json_task.dart';
import 'package:remind_ai/core/isolate/tasks/markdown_task.dart';
import 'package:remind_ai/core/isolate/tasks/highlight_task.dart';
import 'package:remind_ai/core/isolate/tasks/memory_task.dart';
import 'package:remind_ai/core/isolate/tasks/skill_task.dart';
import 'package:remind_ai/core/isolate/tasks/context_task.dart';
import 'package:remind_ai/core/isolate/tasks/export_task.dart';

void main() {
  group('IsolatePool', () {
    late IsolatePool pool;

    setUp(() async {
      pool = IsolatePool.instance;
      await pool.init(2); // 测试用 2 个 worker
    });

    tearDown(() {
      pool.dispose();
    });

    test('初始化成功', () {
      expect(pool.isInitialized, isTrue);
      expect(pool.poolSize, 2);
    });

    test('执行简单计算任务', () async {
      final result = await pool.run(_double, 21);
      expect(result, 42);
    });

    test('并行执行多个任务', () async {
      final futures = List.generate(10, (i) => pool.run(_double, i));
      final results = await Future.wait(futures);
      for (int i = 0; i < 10; i++) {
        expect(results[i], i * 2);
      }
    });

    test('runBatch 批量执行', () async {
      final results = await pool.runBatch(_double, [1, 2, 3, 4, 5]);
      expect(results, [2, 4, 6, 8, 10]);
    });

    test('任务异常正确传播', () async {
      expect(() => pool.run(_throwError, 'test error'), throwsA(isA<Object>()));
    });

    test('dispose 后不可使用', () {
      pool.dispose();
      expect(pool.isInitialized, isFalse);
      expect(() => pool.run(_double, 1), throwsStateError);
    });

    test('重复 init 幂等', () async {
      await pool.init(4); // 已经 init 过了，应该忽略
      expect(pool.poolSize, 2); // 仍然是第一次 init 的 2 个
    });
  });

  group('JSON 任务', () {
    test('jsonEncodeTask 序列化', () {
      final data = {
        'name': 'test',
        'values': [1, 2, 3],
      };
      final result = jsonEncodeTask(data);
      expect(result, contains('"name":"test"'));
      expect(result, contains('"values":[1,2,3]'));
    });

    test('jsonDecodeTask 反序列化', () {
      const json = '{"name":"test","values":[1,2,3]}';
      final result = jsonDecodeTask(json) as Map<String, dynamic>;
      expect(result['name'], 'test');
      expect(result['values'], [1, 2, 3]);
    });

    test('jsonEncodePrettyTask 格式化输出', () {
      final data = {'key': 'value'};
      final result = jsonEncodePrettyTask(data);
      expect(result, contains('\n'));
      expect(result, contains('  "key"'));
    });

    test('conversationEncodeTask', () {
      final param = ConversationEncodeParam(
        messages: [
          {'role': 'user', 'content': 'hello'},
          {'role': 'assistant', 'content': 'hi'},
        ],
        metadata: {'model': 'gpt-4'},
      );
      final result = conversationEncodeTask(param);
      expect(result, contains('"messages"'));
      expect(result, contains('"metadata"'));
      expect(result, contains('"exportedAt"'));
    });
  });

  group('Markdown 任务', () {
    test('markdownPreprocessTask 基础解析', () {
      const md = '''
# Hello

Some text here.

```dart
void main() {
  print("hello");
}
```

More text.

```python
print("world")
```
''';
      final result = markdownPreprocessTask(md);
      expect(result.codeBlocks.length, 2);
      expect(result.codeBlocks[0].language, 'dart');
      expect(result.codeBlocks[1].language, 'python');
      expect(result.textSegments.length, 3);
      expect(result.hasMath, isFalse);
      expect(result.hasTable, isFalse);
    });

    test('markdownPreprocessTask 检测数学公式', () {
      const md = r'The formula is $E = mc^2$ and also $$\int_0^1 x dx$$';
      final result = markdownPreprocessTask(md);
      expect(result.hasMath, isTrue);
    });

    test('markdownPreprocessTask 检测表格', () {
      const md = '| A | B |\n|---|---|\n| 1 | 2 |';
      final result = markdownPreprocessTask(md);
      expect(result.hasTable, isTrue);
    });

    test('markdownSplitTask 分段', () {
      final longMd = List.generate(
        100,
        (i) => '## Section $i\n\nContent $i\n',
      ).join('\n');
      final param = MarkdownSplitParam(markdown: longMd, maxSegmentLength: 500);
      final segments = markdownSplitTask(param);
      expect(segments.length, greaterThan(1));
      // 合并后应等于原文
      expect(segments.join('').trim(), longMd.trim());
    });

    test('markdownSplitTask 短文本不分段', () {
      const short = '# Hello\n\nWorld';
      final param = MarkdownSplitParam(markdown: short, maxSegmentLength: 3000);
      final segments = markdownSplitTask(param);
      expect(segments.length, 1);
    });
  });

  group('高亮任务', () {
    test('highlightPreTokenizeTask Dart 代码', () {
      const code = '''void main() {
  final x = 42;
  print("hello");
}''';
      final result = highlightPreTokenizeTask(
        HighlightParam(code: code, language: 'dart'),
      );
      expect(result.language, 'dart');
      expect(result.lineCount, 4);
      // 应该识别关键字
      final keywords = result.tokens
          .where((t) => t.type == CodeTokenType.keyword)
          .map((t) => t.text)
          .toSet();
      expect(keywords, contains('void'));
      expect(keywords, contains('final'));
    });

    test('highlightPreTokenizeTask Python 注释', () {
      const code = '# This is a comment\nx = 42';
      final result = highlightPreTokenizeTask(
        HighlightParam(code: code, language: 'python'),
      );
      final comments = result.tokens
          .where((t) => t.type == CodeTokenType.comment)
          .toList();
      expect(comments.length, 1);
      expect(comments[0].text, '# This is a comment');
    });

    test('highlightPreTokenizeTask 字符串识别', () {
      const code = 'let s = "hello world"';
      final result = highlightPreTokenizeTask(
        HighlightParam(code: code, language: 'javascript'),
      );
      final strings = result.tokens
          .where((t) => t.type == CodeTokenType.string)
          .toList();
      expect(strings.length, 1);
      expect(strings[0].text, '"hello world"');
    });

    test('highlightBatchTask 批量', () {
      final params = [
        HighlightParam(code: 'int x = 1;', language: 'dart'),
        HighlightParam(code: 'x = 1', language: 'python'),
      ];
      final results = highlightBatchTask(params);
      expect(results.length, 2);
    });
  });

  group('记忆搜索任务', () {
    test('vectorSearchTask 余弦相似度', () {
      final entries = [
        VectorEntry(id: 1, text: 'hello', embedding: [1.0, 0.0, 0.0]),
        VectorEntry(id: 2, text: 'world', embedding: [0.0, 1.0, 0.0]),
        VectorEntry(id: 3, text: 'similar', embedding: [0.9, 0.1, 0.0]),
      ];
      final param = VectorSearchParam(
        queryEmbedding: [1.0, 0.0, 0.0],
        entries: entries,
        topK: 2,
        threshold: 0.5,
      );
      final results = vectorSearchTask(param);
      expect(results.length, 2);
      expect(results[0].id, 1); // 完全匹配
      expect(results[0].score, closeTo(1.0, 0.001));
      expect(results[1].id, 3); // 近似匹配
    });

    test('vectorSearchTask 空结果', () {
      final entries = [
        VectorEntry(id: 1, text: 'far', embedding: [0.0, 0.0, 1.0]),
      ];
      final param = VectorSearchParam(
        queryEmbedding: [1.0, 0.0, 0.0],
        entries: entries,
        topK: 5,
        threshold: 0.8,
      );
      final results = vectorSearchTask(param);
      expect(results, isEmpty);
    });

    test('keywordSearchTask 中文关键词', () {
      final entries = [
        MemoryTextEntry(id: 1, text: '我喜欢用 Flutter 开发桌面应用'),
        MemoryTextEntry(id: 2, text: '今天天气很好'),
        MemoryTextEntry(id: 3, text: 'Flutter 的 Isolate 可以做并行计算'),
      ];
      final param = KeywordSearchParam(
        query: 'Flutter 并行',
        entries: entries,
        topK: 5,
      );
      final results = keywordSearchTask(param);
      expect(results.isNotEmpty, isTrue);
      // 第三条应该排名最高（同时包含 Flutter 和 并行）
      expect(results[0].id, 3);
    });
  });

  group('技能加载任务', () {
    test('skillParseTask 完整解析', () {
      final info = SkillFileInfo(
        dirPath: '/skills/test-skill',
        skillMdContent: '# Test Skill\n\nA test skill for unit testing.',
        toolsJsonContent: '''[
          {"name": "tool1", "description": "First tool", "parameters": {"type": "object"}},
          {"name": "tool2", "description": "Second tool", "parameters": {"type": "object"}}
        ]''',
        metaJsonContent: '{"name": "Test Skill", "description": "A test"}',
      );
      final result = skillParseTask(info);
      expect(result.name, 'Test Skill');
      expect(result.description, 'A test');
      expect(result.toolCount, 2);
      expect(result.tools[0].name, 'tool1');
      expect(result.tools[1].name, 'tool2');
      expect(result.systemPrompt, contains('Test Skill'));
      expect(result.error, isNull);
    });

    test('skillParseTask OpenAI 格式', () {
      final info = SkillFileInfo(
        dirPath: '/skills/openai-style',
        toolsJsonContent: '''[
          {"type": "function", "function": {"name": "search", "description": "Search", "parameters": {}}}
        ]''',
      );
      final result = skillParseTask(info);
      expect(result.toolCount, 1);
      expect(result.tools[0].name, 'search');
    });

    test('skillParseTask 无 tools.json', () {
      final info = SkillFileInfo(
        dirPath: '/skills/no-tools',
        skillMdContent: '# Simple Skill',
      );
      final result = skillParseTask(info);
      expect(result.toolCount, 0);
      expect(result.error, isNull);
    });

    test('skillBatchParseTask 批量', () {
      final infos = List.generate(
        5,
        (i) => SkillFileInfo(
          dirPath: '/skills/skill-$i',
          skillMdContent: '# Skill $i',
          metaJsonContent: '{"name": "Skill $i"}',
        ),
      );
      final results = skillBatchParseTask(infos);
      expect(results.length, 5);
      for (int i = 0; i < 5; i++) {
        expect(results[i].name, 'Skill $i');
      }
    });
  });

  group('上下文压缩任务', () {
    test('contextCompressTask 不超限全部保留', () {
      final messages = List.generate(
        5,
        (i) => ContextMessage(
          index: i,
          role: i % 2 == 0 ? 'user' : 'assistant',
          content: 'Message $i',
          estimatedTokens: 10,
        ),
      );
      final param = ContextCompressParam(messages: messages, maxTokens: 100);
      final result = contextCompressTask(param);
      expect(result.retainedIndices.length, 5);
      expect(result.removedCount, 0);
      expect(result.ratio, 1.0);
    });

    test('contextCompressTask 超限时保留系统和最近消息', () {
      final messages = <ContextMessage>[
        ContextMessage(
          index: 0,
          role: 'system',
          content: 'System prompt',
          estimatedTokens: 50,
        ),
        ...List.generate(
          20,
          (i) => ContextMessage(
            index: i + 1,
            role: i % 2 == 0 ? 'user' : 'assistant',
            content: 'Message ${i + 1}' * 10,
            estimatedTokens: 30,
          ),
        ),
      ];
      final param = ContextCompressParam(
        messages: messages,
        maxTokens: 200,
        keepRecentCount: 5,
      );
      final result = contextCompressTask(param);
      // 系统消息必须保留
      expect(result.retainedIndices, contains(0));
      // 最近 5 条必须保留
      for (int i = messages.length - 5; i < messages.length; i++) {
        expect(result.retainedIndices, contains(i));
      }
      // 总 token 不超限
      expect(result.totalTokens, lessThanOrEqualTo(200));
      expect(result.removedCount, greaterThan(0));
    });

    test('contextCompressTask 优先保留含代码的消息', () {
      final messages = <ContextMessage>[
        ContextMessage(
          index: 0,
          role: 'system',
          content: 'sys',
          estimatedTokens: 10,
        ),
        ContextMessage(
          index: 1,
          role: 'user',
          content: 'plain text message',
          estimatedTokens: 20,
        ),
        ContextMessage(
          index: 2,
          role: 'assistant',
          content: '```dart\nvoid main() {}\n```',
          estimatedTokens: 20,
        ),
        ContextMessage(
          index: 3,
          role: 'user',
          content: 'another plain message',
          estimatedTokens: 20,
        ),
        // 最近消息
        ContextMessage(
          index: 4,
          role: 'user',
          content: 'recent',
          estimatedTokens: 20,
        ),
      ];
      final param = ContextCompressParam(
        messages: messages,
        maxTokens: 70, // 只能保留 system + 2条
        keepRecentCount: 1,
      );
      final result = contextCompressTask(param);
      // 含代码块的消息(index=2)应该优先于纯文本(index=1, 3)
      expect(result.retainedIndices, contains(0)); // system
      expect(result.retainedIndices, contains(4)); // recent
      expect(result.retainedIndices, contains(2)); // code block
    });

    test('tokenEstimateTask 中英文混合', () {
      final chinese = '你好世界';
      final english = 'Hello World';
      final mixed = '你好 Hello 世界 World';

      final chTokens = tokenEstimateTask(chinese);
      final enTokens = tokenEstimateTask(english);
      final mixTokens = tokenEstimateTask(mixed);

      // 中文 4 字符 ≈ 6 tokens
      expect(chTokens, greaterThan(4));
      // 英文 11 字符 ≈ 3 tokens
      expect(enTokens, lessThan(11));
      // 混合在两者之间
      expect(mixTokens, greaterThan(enTokens));
    });
  });

  group('导出任务', () {
    test('exportBuildMarkdownTask 中文', () {
      final messages = [
        ExportMessage(
          role: 'user',
          content: '你好',
          timestamp: DateTime(2024, 1, 1),
        ),
        ExportMessage(
          role: 'assistant',
          content: '你好！有什么可以帮你的？',
          timestamp: DateTime(2024, 1, 1),
        ),
      ];
      final param = ExportBuildParam(
        messages: messages,
        title: '测试对话',
        locale: 'zh',
      );
      final result = exportBuildMarkdownTask(param);
      expect(result, contains('# 对话: 测试对话'));
      expect(result, contains('导出时间'));
      expect(result, contains('用户'));
      expect(result, contains('助手'));
      expect(result, contains('你好'));
    });

    test('exportBuildMarkdownTask 英文', () {
      final messages = [
        ExportMessage(
          role: 'user',
          content: 'Hello',
          timestamp: DateTime(2024, 1, 1),
        ),
      ];
      final param = ExportBuildParam(
        messages: messages,
        title: 'Test',
        locale: 'en',
      );
      final result = exportBuildMarkdownTask(param);
      expect(result, contains('# Conversation: Test'));
      expect(result, contains('Exported at'));
    });

    test('exportBuildMarkdownTask 跳过 system/tool 消息', () {
      final messages = [
        ExportMessage(
          role: 'system',
          content: 'sys',
          timestamp: DateTime(2024, 1, 1),
        ),
        ExportMessage(
          role: 'user',
          content: 'hi',
          timestamp: DateTime(2024, 1, 1),
        ),
        ExportMessage(
          role: 'tool',
          content: 'result',
          timestamp: DateTime(2024, 1, 1),
        ),
        ExportMessage(
          role: 'assistant',
          content: 'hello',
          timestamp: DateTime(2024, 1, 1),
        ),
      ];
      final param = ExportBuildParam(messages: messages, title: 'Test');
      final result = exportBuildMarkdownTask(param);
      expect(result, isNot(contains('sys')));
      expect(result, isNot(contains('result')));
      expect(result, contains('hi'));
      expect(result, contains('hello'));
    });

    test('exportBuildMarkdownTask 附件', () {
      final messages = [
        ExportMessage(
          role: 'user',
          content: 'Check this',
          attachments: [
            ExportAttachment(
              name: 'photo.png',
              path: '/tmp/photo.png',
              isImage: true,
            ),
            ExportAttachment(
              name: 'doc.pdf',
              path: '/tmp/doc.pdf',
              isImage: false,
            ),
          ],
          timestamp: DateTime(2024, 1, 1),
        ),
      ];
      final param = ExportBuildParam(messages: messages, title: 'Attach Test');
      final result = exportBuildMarkdownTask(param);
      expect(result, contains('![photo.png]'));
      expect(result, contains('doc.pdf'));
    });
  });

  group('ComputeService 集成测试', () {
    setUpAll(() async {
      await IsolatePool.instance.init(2);
    });

    tearDownAll(() {
      IsolatePool.instance.dispose();
    });

    test('jsonEncode 小数据同步执行', () async {
      final result = await ComputeService.jsonEncode({'a': 1});
      expect(result, '{"a":1}');
    });

    test('markdownPreprocess 小数据同步执行', () async {
      final result = await ComputeService.markdownPreprocess('hello');
      expect(result.raw, 'hello');
      expect(result.codeBlocks, isEmpty);
    });

    test('estimateTokens 同步', () {
      final tokens = ComputeService.estimateTokens('Hello World');
      expect(tokens, greaterThan(0));
    });
  });
}

// 测试用顶层函数
int _double(int x) => x * 2;
String _throwError(String msg) => throw Exception(msg);

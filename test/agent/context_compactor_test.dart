import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/transformers/context_compactor.dart';
import 'package:remind_ai/core/llm/llm_client.dart';

/// 只用于构造 ContextCompactor 的桩；测试不会真的调用它。
class _StubLlm implements LlmClient {
  @override
  String get model => 'stub-model';

  @override
  int get outputTokenBudget => 12800;

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => throw UnimplementedError('测试不应真正调用摘要');

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    int? maxTokensOverride,
  }) => const Stream<StreamEvent>.empty();
}

/// 返回固定摘要内容的桩（用于验证 transform 的重组逻辑）
class _SummaryLlm implements LlmClient {
  _SummaryLlm(this._content);
  final String _content;

  @override
  String get model => 'stub-model';

  @override
  int get outputTokenBudget => 12800;

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => ChatResponse(content: _content, finishReason: 'stop');

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    int? maxTokensOverride,
  }) => const Stream<StreamEvent>.empty();
}

Map<String, dynamic> _msg(String role, String content) => {
  'role': role,
  'content': content,
};

void main() {
  group('有效上下文 / 阈值口径', () {
    test('1M 模型窗口被接入上限封顶到 128K', () {
      final c = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 1000000,
        modelName: 'deepseek-v4.1-flash',
        relayContextCap: 128000,
      );
      expect(c.effectiveContextWindow, 128000);
    });

    test('relayContextCap=0 表示不封顶', () {
      final c = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 200000,
        modelName: 'gpt-4',
        relayContextCap: 0,
      );
      expect(c.effectiveContextWindow, 200000);
    });

    test('输出预留跟模型卡走，且不超过有效上下文的一半', () {
      final normal = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 128000,
        maxOutputTokens: 32000,
        relayContextCap: 128000,
      );
      expect(normal.outputReserve, 32000);
      expect(normal.effectiveOutputReserve, 32000);

      // 模型卡填了不合理的大值 → 被夹到 50%
      final absurd = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 128000,
        maxOutputTokens: 256000,
        relayContextCap: 128000,
      );
      expect(absurd.effectiveOutputReserve, 64000);
    });

    test('阈值 = (有效上下文 - 输出预留) * ratio，且远离上限', () {
      final c = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 1000000, // 被 128K 封顶
        modelName: 'deepseek-v4.1-flash',
        maxOutputTokens: 12800,
        relayContextCap: 128000,
      );
      final threshold = c.effectiveThreshold;
      // 128K - 12.8K = 115.2K，deepseek ratio 0.45 → 约 51.8K
      expect(threshold, greaterThan(40000));
      expect(threshold, lessThan(60000));
      // 必须显著早于上游 128K，不能像旧实现那样要 59 万才压
      expect(threshold, lessThan(128000 * 0.7));
    });

    test('tightenThreshold 会下调阈值并强制下一次压缩', () {
      final c = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 128000,
        maxOutputTokens: 12800,
        relayContextCap: 128000,
      );
      final before = c.effectiveThreshold;
      c.tightenThreshold(0.5);
      final after = c.effectiveThreshold;
      expect(after, lessThan(before));
      // 强制压缩标记：即使消息很少也应激活
      expect(c.shouldActivate([_msg('system', 'sys')]), isTrue);
      // 第二次不再强制
      expect(c.shouldActivate([_msg('system', 'sys')]), isFalse);
    });
  });

  group('分块摘要', () {
    test('按 token 预算切块且不丢消息、不乱序', () {
      final c = ContextCompactor(llm: _StubLlm());
      final messages = [
        for (var i = 0; i < 12; i++)
          _msg(i.isEven ? 'user' : 'assistant', 'x' * 800),
      ];
      final chunks = c.chunkByTokenBudget(messages, 200);

      expect(chunks.length, greaterThan(1));
      // 顺序与完整性
      final flat = chunks.expand((c) => c).toList();
      expect(flat.length, messages.length);
      for (var i = 0; i < messages.length; i++) {
        expect(identical(flat[i], messages[i]), isTrue);
      }
    });

    test('单条超预算时独占一块而不是被丢弃', () {
      final c = ContextCompactor(llm: _StubLlm());
      final messages = [_msg('user', 'x' * 5000), _msg('assistant', 'y' * 10)];
      final chunks = c.chunkByTokenBudget(messages, 100);
      expect(chunks.length, 2);
      expect(chunks.first.length, 1);
      expect(chunks.last.length, 1);
    });
  });

  group('降级摘要（结构化）', () {
    test('保留用户需求、文件路径与最近结论，且不超长度上限', () {
      final c = ContextCompactor(llm: _StubLlm());
      final messages = <Map<String, dynamic>>[
        _msg(
          'user',
          '请修改 lib/features/chat/chat_page.dart 并跑 test/toolshell 测试，不要动 UI 布局',
        ),
        _msg('assistant', '好的，我先读取文件'),
        _msg('user', '继续'),
        _msg('assistant', '已修改 lib/core/toolshell/agent_loop.dart，测试通过'),
      ];
      final summary = c.buildFallbackSummary(messages);

      expect(summary, contains('## 用户需求'));
      expect(summary, contains('lib/features/chat/chat_page.dart'));
      expect(summary, contains('## 涉及的文件 / 路径'));
      expect(summary, contains('## 最近结论'));
      expect(summary.length, lessThanOrEqualTo(2000));
    });

    test('空输入不抛异常', () {
      final c = ContextCompactor(llm: _StubLlm());
      expect(c.buildFallbackSummary(const []), isEmpty);
    });
  });

  group('transform 重组', () {
    test('重组为 [system, 摘要, ...保真区] 且不破坏工具配对', () async {
      final c = ContextCompactor(
        llm: _SummaryLlm('这是一段摘要'),
        contextWindow: 6000,
        maxOutputTokens: 1000,
        keepRecentTurns: 2,
        cacheAlignedSummary: false,
      );
      final messages = <Map<String, dynamic>>[
        _msg('system', 'SYS'),
        // 早期：一组工具调用（压缩区里，应被整体移除）
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'toolshell_read', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': '结果${'x' * 400}'},
        for (var i = 0; i < 8; i++) ...[
          _msg('user', '问题$i ${'y' * 200}'),
          _msg('assistant', '回答$i ${'z' * 200}'),
        ],
      ];

      final result = await c.transform(messages);

      expect(result.first['content'], 'SYS');
      expect(result[1]['role'], 'system');
      expect(result[1]['content'], contains('这是一段摘要'));
      expect(result.length, lessThan(messages.length));

      // 工具配对完整性：存在的结果必须有对应调用，反之亦然
      final callIds = <String>{};
      final resultIds = <String>{};
      for (final m in result) {
        final calls = m['tool_calls'];
        if (calls is List) {
          for (final tc in calls) {
            callIds.add((tc as Map)['id'] as String);
          }
        }
        if (m['role'] == 'tool') {
          resultIds.add(m['tool_call_id'] as String);
        }
      }
      expect(resultIds.difference(callIds), isEmpty);
      expect(callIds.difference(resultIds), isEmpty);
    });

    test('超大工具结果压缩保留头尾而非只留开头', () async {
      final c = ContextCompactor(llm: _StubLlm());
      final head = 'HEAD_MARK';
      final tail = 'TAIL_MARK';
      final big = '$head${'a' * 6000}$tail';
      final messages = <Map<String, dynamic>>[
        _msg('system', 'SYS'),
        _msg('user', 'go'),
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'toolshell_exec', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': big},
      ];

      final result = await c.transform(messages);
      final toolMsg = result.firstWhere((m) => m['role'] == 'tool');
      final content = toolMsg['content'] as String;
      expect(content, contains(head));
      expect(content, contains(tail));
      expect(content, contains('工具结果已自动压缩'));
      expect(content.length, lessThan(big.length));
    });
  });
}

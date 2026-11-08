import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/agent/transformers/context_compactor.dart';
import 'package:remind_ai/core/llm/context_capacity.dart';
import 'package:remind_ai/core/llm/llm_client.dart';

class _StubLlm implements LlmClient {
  @override
  String get model => 'stub-model';

  @override
  int get outputTokenBudget => 12800;

  @override
  Future<ChatResponse> chat(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async => throw UnimplementedError();

  @override
  Stream<StreamEvent> chatStreamFull(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
    int? maxTokensOverride,
  }) => const Stream<StreamEvent>.empty();
}

void main() {
  final registry = ContextCapacityRegistry.instance;

  setUp(registry.resetForTest);

  group('报文解析', () {
    test('OpenAI / DeepSeek 老格式', () {
      const text =
          'HTTP 400: {"error":{"message":"This model\'s maximum context length '
          'is 131072 tokens. However, you requested 200000"}}';
      expect(ContextCapacityRegistry.parseLimitFromError(text), 131072);
    });

    test('context length of only 格式', () {
      const text =
          'This model\'s maximum context length is 128000 tokens. '
          'However, your messages resulted in 150000 tokens. '
          'Please reduce the length of the messages. context length of only 128000';
      expect(ContextCapacityRegistry.parseLimitFromError(text), 128000);
    });

    test('Anthropic prompt is too long', () {
      const text = 'prompt is too long: 210000 tokens > 200000 maximum';
      expect(ContextCapacityRegistry.parseLimitFromError(text), 200000);
    });

    test('中文中转措辞', () {
      const text = '请求失败：最大上下文长度 65536 tokens，请减少输入';
      expect(ContextCapacityRegistry.parseLimitFromError(text), 65536);
      expect(
        ContextCapacityRegistry.parseLimitFromError('输入超出 32768 tokens 限制'),
        32768,
      );
    });

    test('普通错误不误报', () {
      expect(
        ContextCapacityRegistry.parseLimitFromError('HTTP 401: unauthorized'),
        isNull,
      );
      expect(
        ContextCapacityRegistry.parseLimitFromError('HTTP 400: bad request'),
        isNull,
      );
      expect(ContextCapacityRegistry.parseLimitFromError(''), isNull);
    });
  });

  group('容量推算', () {
    test('模型卡理论值（1M）先打折起步，避免 59 万才压缩', () {
      final cap = registry.resolveCapForKey('k|m', 1000000);
      expect(cap, 256000);
    });

    test('模型卡是现实值（128K）时直接采用', () {
      expect(registry.resolveCapForKey('k|m', 128000), 128000);
    });

    test('模型卡没填时兜底 128K', () {
      expect(registry.resolveCapForKey('k|m', 0), 128000);
    });

    test('报文学到上限后以报文为准', () {
      final key = ContextCapacityRegistry.keyOf('https://relay.test/', 'm');
      registry.learnFromErrorForKey(
        key: key,
        errorText: 'maximum context length is 131072 tokens',
        cardContextWindow: 1000000,
      );
      expect(registry.resolveCapForKey(key, 1000000), 131072);
    });

    test('实测成功值只向上抬，且留 15% 余量', () {
      const key = 'relay|m';
      registry.observeSuccessForKey(
        key: key,
        promptTokens: 200000,
        measured: true,
        cardContextWindow: 1000000,
      );
      // 起步 256K，实测 200K×1.15=230K → 取较大者 256K
      expect(registry.resolveCapForKey(key, 1000000), 256000);

      registry.observeSuccessForKey(
        key: key,
        promptTokens: 300000,
        measured: true,
        cardContextWindow: 1000000,
      );
      // 345000 超过起步猜测 → 抬到实测口径
      expect(registry.resolveCapForKey(key, 1000000), 345000);
    });

    test('估算值（非实测）不参与向上抬容量', () {
      const key = 'relay|m';
      registry.observeSuccessForKey(
        key: key,
        promptTokens: 999999,
        measured: false,
        cardContextWindow: 1000000,
      );
      expect(registry.resolveCapForKey(key, 1000000), 256000);
    });

    test('多次报错取更小的那个', () {
      const key = 'relay|m';
      registry.learnFromErrorForKey(
        key: key,
        errorText: 'maximum context length is 131072 tokens',
        cardContextWindow: 0,
      );
      registry.learnFromErrorForKey(
        key: key,
        errorText: 'context length of only 65536 tokens',
        cardContextWindow: 0,
      );
      expect(registry.resolveCapForKey(key, 0), 65536);
    });
  });

  group('持久化', () {
    test('toJson / load 往返', () {
      const key = 'relay|m';
      registry.learnFromErrorForKey(
        key: key,
        errorText: 'maximum context length is 131072 tokens',
        cardContextWindow: 0,
      );
      final dumped = registry.toJson();
      expect(dumped, contains(key));

      registry.resetForTest();
      expect(registry.toJson(), isEmpty);

      registry.load(dumped);
      expect(registry.resolveCapForKey(key, 0), 131072);
    });

    test('损坏条目不影响其它', () {
      registry.load({
        'good|m': {'rejected': 32768},
        'bad|m': 'not-a-map',
      });
      expect(registry.resolveCapForKey('good|m', 0), 32768);
      expect(registry.resolveCapForKey('bad|m', 0), 128000);
    });
  });

  group('Compactor 接线', () {
    test('学到容量后阈值立刻按新口径重算', () {
      final compactor = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 1000000,
        modelName: 'deepseek-v4.1-flash',
        maxOutputTokens: 32000,
        capacityKey: 'relay|m',
      );
      final before = compactor.effectiveThreshold;
      // 自动推算：1M 卡先按 256K 起步
      expect(compactor.effectiveContextWindow, 256000);

      final learned = compactor.learnCapacityFromError(
        'HTTP 413: maximum context length is 131072 tokens',
      );
      expect(learned, 131072);
      expect(compactor.effectiveContextWindow, 131072);
      expect(compactor.effectiveThreshold, lessThan(before));
    });

    test('无 capacityKey 时不做学习（不影响纯内存用法）', () {
      final compactor = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 128000,
        maxOutputTokens: 12800,
      );
      expect(
        compactor.learnCapacityFromError('maximum context length is 4096'),
        isNull,
      );
      expect(compactor.effectiveContextWindow, 128000);
    });

    test('实测 usage 能把容量抬上去', () {
      final compactor = ContextCompactor(
        llm: _StubLlm(),
        contextWindow: 1000000,
        maxOutputTokens: 32000,
        capacityKey: 'relay|m',
      );
      expect(compactor.effectiveContextWindow, 256000);
      compactor.observeUsage(400000);
      expect(compactor.effectiveContextWindow, 460000); // 400000 × 1.15
    });
  });
}

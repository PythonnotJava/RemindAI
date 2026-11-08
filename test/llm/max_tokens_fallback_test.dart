import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/llm/anthropic_client.dart';
import 'package:remind_ai/core/llm/gemini_client.dart';
import 'package:remind_ai/core/llm/llm_client.dart';

/// 输出 token 兜底值 + 「上游拒绝 max_tokens 时自动降档」的判定逻辑。
///
/// 这些是纯函数/只读属性，不需要真实网络。
void main() {
  group('kDefaultMaxOutputTokens', () {
    test('兜底值为 128K，三种协议共用', () {
      expect(kDefaultMaxOutputTokens, 128000);

      // 未配置 maxOutputTokens 时，三家客户端声明的输出预算一致
      final openai = OpenAiClient(
        baseUrl: 'https://example.com/v1',
        apiKey: 'k',
        model: 'gpt-4o',
      );
      final anthropic = AnthropicClient(
        baseUrl: 'https://example.com/v1/messages',
        apiKey: 'k',
        model: 'claude-3-5-sonnet',
      );
      final gemini = GeminiClient(
        baseUrl: 'https://example.com',
        apiKey: 'k',
        model: 'gemini-2.0-flash',
      );

      expect(openai.outputTokenBudget, kDefaultMaxOutputTokens);
      expect(anthropic.outputTokenBudget, kDefaultMaxOutputTokens);
      expect(gemini.outputTokenBudget, kDefaultMaxOutputTokens);
    });

    test('模型卡配置了值就优先用配置值', () {
      final anthropic = AnthropicClient(
        baseUrl: 'https://example.com/v1/messages',
        apiKey: 'k',
        model: 'claude-3-5-sonnet',
        maxOutputTokens: 8192,
      );
      final gemini = GeminiClient(
        baseUrl: 'https://example.com',
        apiKey: 'k',
        model: 'gemini-2.0-flash',
        maxOutputTokens: 4096,
      );

      expect(anthropic.outputTokenBudget, 8192);
      expect(gemini.outputTokenBudget, 4096);
    });
  });

  group('nextLowerMaxTokens', () {
    test('逐级下落且不会重复当前档', () {
      expect(nextLowerMaxTokens(128000), 64000);
      expect(nextLowerMaxTokens(64000), 32000);
      expect(nextLowerMaxTokens(32000), 16384);
      expect(nextLowerMaxTokens(16384), 8192);
    });

    test('已到最小档或低于最小档时返回 null', () {
      expect(nextLowerMaxTokens(8192), isNull);
      expect(nextLowerMaxTokens(1024), isNull);
    });

    test('用户配置了非梯度值也能落到最近的更低档', () {
      expect(nextLowerMaxTokens(50000), 32000);
      expect(nextLowerMaxTokens(128001), 128000);
    });
  });

  group('looksLikeMaxTokensRejected', () {
    test('识别"超出模型输出上限"', () {
      expect(
        looksLikeMaxTokensRejected(
          '{"error":{"message":"max_tokens: 128000 > 64000, which is the maximum '
          'allowed number of output tokens"}}',
        ),
        isTrue,
      );
      expect(
        looksLikeMaxTokensRejected('max_tokens is too large for this model'),
        isTrue,
      );
    });

    test('识别"输入+输出超过上下文窗口"', () {
      expect(
        looksLikeMaxTokensRejected(
          'input length and max_tokens exceed context limit: 200000 + 128000 > 200000',
        ),
        isTrue,
      );
      expect(
        looksLikeMaxTokensRejected('max_tokens too large given prompt'),
        isTrue,
      );
    });

    test('识别 Gemini 的 maxOutputTokens 与中文中转报错', () {
      expect(
        looksLikeMaxTokensRejected(
          '{"error":{"message":"maxOutputTokens must be less than or equal to 8192"}}',
        ),
        isTrue,
      );
      expect(looksLikeMaxTokensRejected('max_tokens 超出该模型上限'), isTrue);
    });

    test('无关的 400 不误判', () {
      expect(
        looksLikeMaxTokensRejected('{"error":{"message":"invalid api key"}}'),
        isFalse,
      );
      expect(
        looksLikeMaxTokensRejected(
          'messages: text content blocks must be non-empty',
        ),
        isFalse,
      );
      // 只提到 max_tokens 但没有超限语义：交给原有错误处理
      expect(
        looksLikeMaxTokensRejected('unsupported field temperature'),
        isFalse,
      );
    });
  });
}

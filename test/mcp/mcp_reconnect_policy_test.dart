import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/mcp/mcp_reconnect_policy.dart';
import 'package:remind_ai/providers/mcp_provider.dart';

void main() {
  group('McpReconnectPolicy', () {
    const policy = McpReconnectPolicy();

    test('默认 5 次上限', () {
      expect(policy.maxAttempts, 5);
      expect(policy.shouldRetry(1), isTrue);
      expect(policy.shouldRetry(5), isTrue);
      expect(policy.shouldRetry(6), isFalse);
      expect(policy.shouldRetry(0), isFalse);
      expect(policy.shouldRetry(-1), isFalse);
    });

    test('指数退避：2s → 4s → 8s → 16s → 32s', () {
      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 4));
      expect(policy.delayForAttempt(3), const Duration(seconds: 8));
      expect(policy.delayForAttempt(4), const Duration(seconds: 16));
      expect(policy.delayForAttempt(5), const Duration(seconds: 32));
    });

    test('单次等待不超过 maxDelay（默认 60s）', () {
      // 6 次及以上会算出 64s/128s……这里必须被夹到 60s
      expect(policy.delayForAttempt(6), const Duration(seconds: 60));
      expect(policy.delayForAttempt(30), const Duration(seconds: 60));
      // 极端 attempt 不能因 pow 溢出而崩
      expect(policy.delayForAttempt(9999), const Duration(seconds: 60));
    });

    test('attempt <= 0 不等待', () {
      expect(policy.delayForAttempt(0), Duration.zero);
      expect(policy.delayForAttempt(-3), Duration.zero);
    });

    test('可自定义策略', () {
      const custom = McpReconnectPolicy(
        maxAttempts: 2,
        baseDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 1),
      );
      expect(custom.shouldRetry(2), isTrue);
      expect(custom.shouldRetry(3), isFalse);
      expect(custom.delayForAttempt(1), const Duration(milliseconds: 500));
      expect(custom.delayForAttempt(2), const Duration(seconds: 1));
      expect(custom.delayForAttempt(3), const Duration(seconds: 1));
    });
  });

  group('McpConnectionState.reconnectAttempts', () {
    test('copyWith 保留/替换重连计数', () {
      const base = McpConnectionState(
        reconnectAttempts: {'srv-a': 2},
      );

      expect(base.copyWith().reconnectAttempts, {'srv-a': 2});
      // 不传该字段时保留原值
      expect(
        base.copyWith(statuses: const {}).reconnectAttempts,
        {'srv-a': 2},
      );
      // 显式传空 map 时清空
      expect(base.copyWith(reconnectAttempts: const {}).reconnectAttempts, isEmpty);
    });

    test('默认状态不携带断线与重连信息', () {
      const state = McpConnectionState();
      expect(state.lastErrors, isEmpty);
      expect(state.reconnectAttempts, isEmpty);
      expect(state.statuses, isEmpty);
    });
  });
}

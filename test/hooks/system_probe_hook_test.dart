import 'package:flutter_test/flutter_test.dart';

import 'package:remind_ai/core/agent/hooks/system_probe_hook.dart';

void main() {
  group('SystemProbeHook', () {
    late SystemProbeHook hook;

    setUp(() {
      hook = SystemProbeHook();
    });

    test('onSessionStart 注入环境信息', () async {
      final messages = <Map<String, dynamic>>[];
      await hook.onSessionStart(1, messages);

      // 应该注入了一条 system message
      expect(messages.length, 1);
      expect(messages[0]['role'], 'system');

      final content = messages[0]['content'] as String;
      expect(content, contains('[系统环境]'));
      expect(content, contains('OS:'));

      // 至少检测到一些常见工具
      print('注入内容:\n$content');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('探测结果包含已安装的工具', () async {
      final messages = <Map<String, dynamic>>[];
      await hook.onSessionStart(1, messages);

      final content = messages[0]['content'] as String;

      // Windows 系统上应该至少有 git
      // (CI 环境可能不同，这里宽松断言)
      final hasAnyTool =
          content.contains('运行时:') ||
          content.contains('包管理:') ||
          content.contains('版本控制:') ||
          content.contains('构建工具:') ||
          content.contains('搜索:');
      expect(hasAnyTool, isTrue, reason: '至少应检测到一个类别的工具');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('不会注入到非首轮', () async {
      // onSessionStart 只在首次触发，后续 onBeforeUserMessage 不做任何事
      final messages = <Map<String, dynamic>>[];
      final result = await hook.onBeforeUserMessage('hello', messages);
      expect(result, isNull);
      expect(messages, isEmpty);
    });
  });
}

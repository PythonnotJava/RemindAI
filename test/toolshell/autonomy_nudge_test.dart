import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/toolshell/autonomy_nudge.dart';

/// auto 模式"只说不做"兜底的判定逻辑：
/// 只有"像目标型指令"的用户消息才触发提醒，避免把正常问答变成强行执行。
void main() {
  group('looksActionableGoal', () {
    test('明确的动手请求 → true', () {
      const cases = [
        '帮我安装这个 apk 到手机上',
        '把项目跑起来看看',
        '部署到测试服并检查日志',
        'build the app and install it on the phone',
        'adb 连上之后抓一下 logcat',
        '把这个 bug 修复了',
        '生成一份 PDF 导出',
      ];
      for (final text in cases) {
        expect(looksActionableGoal(text), isTrue, reason: text);
      }
    });

    test('寒暄/闲聊 → false', () {
      const cases = ['你好', '谢谢', '在吗', 'hello', 'thanks a lot', '早上好'];
      for (final text in cases) {
        expect(looksActionableGoal(text), isFalse, reason: text);
      }
    });

    test('纯知识性提问 → false', () {
      const cases = [
        '这个函数是干什么的',
        '为什么会有这种设计',
        'flutter 和 react native 有什么区别',
      ];
      for (final text in cases) {
        expect(looksActionableGoal(text), isFalse, reason: text);
      }
    });

    test('太短的消息不触发', () {
      expect(looksActionableGoal('跑'), isFalse);
      expect(looksActionableGoal(''), isFalse);
      expect(looksActionableGoal('   '), isFalse);
    });
  });

  group('lastUserText', () {
    test('取最后一条 user 文本', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': '第一条'},
        {'role': 'assistant', 'content': '好的'},
        {'role': 'user', 'content': '帮我安装 apk'},
      ];
      expect(lastUserText(messages), '帮我安装 apk');
    });

    test('多模态 content 只拼文本段', () {
      final messages = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '看这张图'},
            {'type': 'image_url', 'image_url': {'url': 'data:...'}},
          ],
        },
      ];
      expect(lastUserText(messages), '看这张图');
    });

    test('没有 user 消息时返回空串', () {
      expect(lastUserText(const []), '');
      expect(
        lastUserText(<Map<String, dynamic>>[
          {'role': 'assistant', 'content': 'hi'},
        ]),
        '',
      );
    });
  });

  test('提醒文案包含"直接执行"和"不要问要不要继续"', () {
    expect(kAutonomyNudgePrompt, contains('直接执行'));
    expect(kAutonomyNudgePrompt, contains('不要'));
  });
}

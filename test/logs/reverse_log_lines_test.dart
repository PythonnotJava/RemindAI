import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/features/logs/logs_page.dart';

/// 覆盖日志页面"最新在前"展示逻辑的核心纯函数 [reverseLogLines]。
/// 该函数只影响展示层顺序，不涉及 AppLogger 底层文件读写，
/// 因此可以脱离 Flutter widget 树、纯粹以字符串输入输出验证。
void main() {
  group('reverseLogLines()', () {
    test('空字符串原样返回', () {
      expect(reverseLogLines(''), '');
    });

    test('单行内容原样返回', () {
      expect(reverseLogLines('[10:00:00] only line'), '[10:00:00] only line');
    });

    test('多行内容按行整体倒序，最新一行排到最前', () {
      const content = '[10:00:00] line1\n[10:00:01] line2\n[10:00:02] line3';
      final result = reverseLogLines(content);
      expect(result, '[10:00:02] line3\n[10:00:01] line2\n[10:00:00] line1');
    });

    test('末尾存在空行时保留空行语义（空行倒序后跑到最前）', () {
      // AppLogger.log() 用 writeln，文件末尾通常有一个尾随的空字符串项
      const content = '[10:00:00] line1\n[10:00:01] line2\n';
      final result = reverseLogLines(content);
      expect(result, '\n[10:00:01] line2\n[10:00:00] line1');
    });

    test('倒序不改变原字符串（不修改传入内容，仅返回新字符串）', () {
      const content = '[10:00:00] a\n[10:00:01] b';
      final copy = content;
      reverseLogLines(content);
      expect(content, copy);
    });

    test('倒序两次等于原内容（对合行为，无信息丢失）', () {
      const content = '[10:00:00] a\n[10:00:01] b\n[10:00:02] c';
      final twice = reverseLogLines(reverseLogLines(content));
      expect(twice, content);
    });
  });
}

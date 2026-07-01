import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:remind_ai/core/agent/hooks/schedule_hook.dart';
import 'package:remind_ai/core/llm/llm_client.dart';

void main() {
  late Directory tempDir;
  late ScheduleHook hook;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('schedule_hook_test_');
    hook = ScheduleHook(
      projectRoot: tempDir.path,
      firstRecallProbability: 1.0, // 测试时必定触发
      subsequentRecallProbability: 1.0, // 测试时必定触发
      recallInterval: 3,
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ScheduleHook', () {
    test('无 SCHEDULE.md 时不注入', () async {
      final messages = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('你好', messages);
      expect(messages, isEmpty);
    });

    test('有 SCHEDULE.md 时首轮注入摘要', () async {
      // 写入一个测试 SCHEDULE.md
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划
> 最后更新: 2026-07-01 10:00

## 🔴 P0 - 紧急
- [ ] 修复登录崩溃 `#bugfix`

## 🟡 P1 - 重要
- [ ] 添加用户头像功能 `#feature`
- [ ] 优化列表性能 `#perf`

## 🟢 P2 - 一般
- [ ] 更新文档

## ✅ 已完成
- [x] 项目初始化 — 2026-06-30 完成
''');

      final messages = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('开始工作', messages);

      expect(messages.length, 1);
      expect(messages[0]['role'], 'system');
      final content = messages[0]['content'] as String;
      expect(content, contains('[当前工作计划]'));
      expect(content, contains('P0:1'));
      expect(content, contains('P1:2'));
      expect(content, contains('P2:1'));
      expect(content, contains('修复登录崩溃'));
      expect(content, contains('添加用户头像功能'));
    });

    test('关键词强制触发', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划
> 最后更新: 2026-07-01 10:00

## 🟡 P1 - 重要
- [ ] 任务A

## ✅ 已完成
''');

      // 先消耗首次注入
      final msgs1 = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('你好', msgs1);
      expect(msgs1.length, 1); // 首次注入

      // 创建概率为 0 的新 hook（排除概率因素），但关键词仍触发
      final strictHook = ScheduleHook(
        projectRoot: tempDir.path,
        firstRecallProbability: 1.0,
        subsequentRecallProbability: 0.0, // 概率为 0
        recallInterval: 999, // 不会周期触发
      );

      // 首轮消耗掉
      final msgs2 = <Map<String, dynamic>>[];
      await strictHook.onBeforeUserMessage('hi', msgs2);

      // 非关键词不触发
      final msgs3 = <Map<String, dynamic>>[];
      await strictHook.onBeforeUserMessage('写一段代码', msgs3);
      expect(msgs3, isEmpty);

      // 关键词触发
      final msgs4 = <Map<String, dynamic>>[];
      await strictHook.onBeforeUserMessage('当前进度怎么样了', msgs4);
      expect(msgs4.length, 1);
      expect(msgs4[0]['content'], contains('[当前工作计划]'));
    });

    test('空任务列表不注入', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划
> 最后更新: 2026-07-01 10:00

## 🔴 P0 - 紧急

## 🟡 P1 - 重要

## 🟢 P2 - 一般

## ✅ 已完成
''');

      final messages = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('开始', messages);
      expect(messages, isEmpty);
    });

    test('摘要只包含 P0 和 P1 任务（不含 P2 详情）', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划
> 最后更新: 2026-07-01

## 🔴 P0 - 紧急
- [ ] 紧急修复A

## 🟡 P1 - 重要
- [ ] 重要任务B

## 🟢 P2 - 一般
- [ ] 普通任务C
- [ ] 普通任务D

## ✅ 已完成
- [x] 完成X — 2026-06-30 完成
''');

      final messages = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('继续', messages);

      final content = messages[0]['content'] as String;
      expect(content, contains('紧急修复A'));
      expect(content, contains('重要任务B'));
      // P2 只在统计里出现，不列出详情
      expect(content, contains('P2:2'));
      expect(content, isNot(contains('普通任务C')));
      expect(content, isNot(contains('普通任务D')));
    });

    test('统计数据正确', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划

## 🔴 P0 - 紧急
- [ ] A
- [ ] B

## 🟡 P1 - 重要
- [ ] C

## 🟢 P2 - 一般
- [ ] D
- [ ] E
- [ ] F

## ✅ 已完成
- [x] G — done
- [x] H — done
''');

      final messages = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('开始', messages);

      final content = messages[0]['content'] as String;
      expect(content, contains('待办: 6项'));
      expect(content, contains('P0:2'));
      expect(content, contains('P1:1'));
      expect(content, contains('P2:3'));
      expect(content, contains('已完成: 2'));
    });

    test('完成检测: 实质工作后提醒标记', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划

## 🔴 P0 - 紧急
- [ ] 修复登录页面崩溃 `#bugfix`

## 🟡 P1 - 重要
- [ ] 添加暗黑模式支持

## ✅ 已完成
''');

      // 第1轮: 注入计划（加载待办缓存）
      final msgs1 = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('帮我修复登录页面的崩溃', msgs1);
      expect(msgs1.length, 1); // 计划注入

      // 模拟 LLM 调用了 toolshell_write（实质性工作）
      await hook.onAfterLlmCall('已修复登录页面崩溃问题', [
        _fakeToolCall('toolshell_write'),
      ], 1000);

      // 模拟 assistant 回复包含完成信号
      final msgs2 = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': '已完成修复登录页面崩溃的问题，原因是空指针异常。'},
      ];

      // 第2轮: 用户输入 → 应检测到上轮完成了任务
      await hook.onBeforeUserMessage('好的', msgs2);

      // 应该有完成提醒
      final hasHint = msgs2.any(
        (m) =>
            m['role'] == 'system' &&
            (m['content'] as String).contains('Schedule 提醒'),
      );
      expect(hasHint, isTrue, reason: '应注入任务完成提醒');
    });

    test('完成检测: 模型已调 schedule_complete 则不再提醒', () async {
      final file = File('${tempDir.path}/SCHEDULE.md');
      file.writeAsStringSync('''# 工作计划

## 🔴 P0 - 紧急
- [ ] 修复登录崩溃

## ✅ 已完成
''');

      // 加载计划
      final msgs1 = <Map<String, dynamic>>[];
      await hook.onBeforeUserMessage('修复', msgs1);

      // 模型调了 schedule_complete → 不需要再提醒
      await hook.onAfterLlmCall(null, [
        _fakeToolCall('toolshell_write'),
        _fakeToolCall('schedule_complete'),
      ], 1000);

      // 下一轮不应该有提醒
      final msgs2 = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': '已修复并标记完成。'},
      ];
      await hook.onBeforeUserMessage('继续', msgs2);

      final hasHint = msgs2.any(
        (m) =>
            m['role'] == 'system' &&
            (m['content'] as String).contains('Schedule 提醒'),
      );
      expect(hasHint, isFalse, reason: '模型已自己标记完成，不需要提醒');
    });
  });
}

/// 测试用的假 ToolCall
ToolCall _fakeToolCall(String name) =>
    ToolCall(id: 'fake', name: name, arguments: {});

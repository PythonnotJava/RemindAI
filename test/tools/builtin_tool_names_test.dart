import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/tools/builtin_tool_names.dart';

/// 保证「内置工具名权威表」与随包发布的 skills tools.json 不漂移。
///
/// 技能 tools.json 只是声明：声明了却没有执行者的工具名会在装配时被剔除，
/// 调用也只会得到 UNKNOWN_TOOL。所以每次改动 tools.json 或 Executor 的
/// switch，本测试都应该保持通过。
void main() {
  const skillDirs = [
    'assets/default_skills/toolshell',
    'assets/default_skills/schedule',
    'assets/default_skills/system',
    'assets/default_skills/office',
  ];

  List<Map<String, dynamic>> readToolDefs(String dir) {
    final file = File('$dir/tools.json');
    expect(file.existsSync(), isTrue, reason: '缺少 ${file.path}');
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<List>());
    return (decoded as List)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  group('builtin_tool_names 与 assets 保持一致', () {
    for (final dir in skillDirs) {
      test('$dir 里的工具名都有执行者登记', () {
        final defs = readToolDefs(dir);
        expect(defs, isNotEmpty);

        final unknown = defs
            .map((d) => toolDefName(d))
            .whereType<String>()
            .where((name) => !isKnownBuiltinTool(name))
            .toList();

        expect(
          unknown,
          isEmpty,
          reason: '这些工具名没有登记在 lib/core/tools/builtin_tool_names.dart 里，'
              '装配时会被当成"无执行者"剔除: $unknown',
        );
      });
    }

    test('权威表不含重复项且全集覆盖各分组', () {
      final all = kBuiltinToolNames;
      expect(all.length, greaterThan(20));
      expect(all.contains('toolshell_read'), isTrue);
      expect(all.contains('schedule_review'), isTrue);
      expect(all.contains('system_probe'), isTrue);
      expect(all.contains('office_excel_read'), isTrue);
      expect(all.contains('toolshell_run_parallel'), isTrue);
      expect(all.contains('web_search'), isTrue);
    });

    test('toolshell 的 memory 工具字段与 schema 对齐', () {
      final defs = readToolDefs('assets/default_skills/toolshell');

      // store: 必填字段是 content（与 Executor._memStore 读取的键一致）
      final store = defs.firstWhere(
        (d) => toolDefName(d) == 'toolshell_memory_store',
      );
      final storeParams =
          (store['function'] as Map)['parameters'] as Map<String, dynamic>;
      expect(storeParams['required'], contains('content'));
      final storeProps = storeParams['properties'] as Map<String, dynamic>;
      expect(storeProps.keys, containsAll(['content', 'type', 'importance']));

      // recall: limit / threshold 是 Executor._memRecall 读取的键
      final recall = defs.firstWhere(
        (d) => toolDefName(d) == 'toolshell_memory_recall',
      );
      final recallParams =
          (recall['function'] as Map)['parameters'] as Map<String, dynamic>;
      expect(recallParams['required'], contains('query'));
      final recallProps = recallParams['properties'] as Map<String, dynamic>;
      expect(recallProps.keys, containsAll(['query', 'limit', 'threshold']));
    });
  });
}

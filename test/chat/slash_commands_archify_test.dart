import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/features/chat/slash_commands.dart';

/// 覆盖 `/archify-draw` slash 命令的解析与展开行为：
/// - 命令注册在 kSlashCommands 中，且要求工作目录、要求描述、非动作类
/// - 无描述时应阻止发送并提示补充
/// - 有描述时应展开为完整指令，且指令里包含 archify 技能目录路径与关键步骤提示
void main() {
  test('kSlashCommands 中注册了 /archify-draw，且为模板类命令', () {
    final cmd = kSlashCommands.firstWhere((c) => c.command == '/archify-draw');
    expect(cmd.requiresWorkspace, isTrue);
    expect(cmd.requiresDescription, isTrue);
    expect(cmd.isAction, isFalse);
    expect(cmd.expand, isNotNull);
  });

  test('/archify-draw 后无描述 → SlashNeedsDescription', () {
    final result = parseSlashCommand('/archify-draw');
    expect(result, isA<SlashNeedsDescription>());
    expect((result as SlashNeedsDescription).command.command, '/archify-draw');
  });

  test('/archify-draw + 描述 → 展开为完整指令，包含技能目录路径与渲染步骤', () {
    final result = parseSlashCommand('/archify-draw 画一个三层 web 应用的架构图');
    expect(result, isA<SlashExpanded>());
    final expanded = result as SlashExpanded;
    expect(expanded.command.command, '/archify-draw');
    expect(expanded.expandedText, contains('画一个三层 web 应用的架构图'));
    expect(expanded.expandedText, contains('archify'));
    expect(expanded.expandedText, contains('SKILL.md'));
    expect(expanded.expandedText, contains('render-'));
    expect(expanded.expandedText, contains('assets/scripts/archify'));
  });

  test('命令前缀不完整时按普通消息处理', () {
    final result = parseSlashCommand('archify-draw 画个图');
    expect(result, isA<PlainMessage>());
  });
}

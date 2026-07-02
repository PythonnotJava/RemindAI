import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/features/chat/widgets/markdown_view.dart';
import 'package:remind_ai/l10n/app_localizations.dart';

/// 覆盖代码高亮插件迁移 (flutter_highlight/highlight 0.7.0 → 本地 packages/
/// 下的 0.7.1 fork) 之后，MarkdownView 里的代码块仍能正常渲染语法高亮，
/// 不抛异常、且高亮后的文本内容与原始代码一致（不丢字符）。
///
/// MarkdownView 内部的代码块通过 context.s (S.of(context)) 读取本地化文案
/// (复制按钮等)，因此测试用的 MaterialApp 必须挂上 S.localizationsDelegates，
/// 否则会在 _SafeCodeFieldState.build 里因 S.of 返回 null 而崩溃——
/// 这与本次高亮插件迁移无关，是本文件测试基础设施本身的必要配置。
void main() {
  Future<void> pumpMarkdown(
    WidgetTester tester,
    String data, {
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: MarkdownView(data: data, textColor: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染带语言标注的代码块不抛异常，且能找到高亮后的 SelectableText', (tester) async {
    const data = '```dart\nvoid main() {\n  print("hello");\n}\n```';
    await pumpMarkdown(tester, data);

    expect(tester.takeException(), isNull);
    // HighlightView 内部用 SelectableText.rich 渲染，能找到即代表高亮流程走通
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('渲染语言标注为空的代码块 (自动检测) 不抛异常', (tester) async {
    const data = '```\nSELECT * FROM users;\n```';
    await pumpMarkdown(tester, data);

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('高亮后的文本内容完整包含原始代码字符（不丢字符）', (tester) async {
    const code = 'const greeting = "hi there";';
    const data = '```javascript\n$code\n```';
    await pumpMarkdown(tester, data);

    expect(tester.takeException(), isNull);

    // 从渲染树里收集所有 SelectableText.rich 的纯文本，拼接后应包含原始代码
    final selectableTexts = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    final allText = selectableTexts
        .map((w) => w.textSpan?.toPlainText() ?? '')
        .join();
    expect(allText, contains('const greeting'));
    expect(allText, contains('hi there'));
  });

  testWidgets('明暗主题切换时代码块都能正常渲染 (atom_one_dark / atom_one_light)', (
    tester,
  ) async {
    const data = '```python\nprint("hello")\n```';

    await pumpMarkdown(tester, data, theme: ThemeData.light());
    expect(tester.takeException(), isNull);

    await pumpMarkdown(tester, data, theme: ThemeData.dark());
    expect(tester.takeException(), isNull);
  });

  testWidgets('语言标注不是 hljs 已注册语言（如误粘的文件路径/URL）时自动降级为纯检测，不抛异常', (
    tester,
  ) async {
    // 复现真实故障：gpt_markdown 解析异常 Markdown 时，代码块围栏的语言标注
    // 位置混入了一段文件路径 + 残留反引号（而非真实语言名），
    // 旧实现会把它原样传给 hljs.highlight(language: ...) 精确匹配模式，
    // 该语言不存在于已注册语言表时直接 throw ArgumentError('Unknown language')，
    // 导致整条消息气泡渲染崩溃。修复后应校验语言合法性，非法则回退到 null（自动检测）。
    const data =
        '```file:///c:/users/25654/desktop/pythonnotjava.github.io/'
        'extend/remindai/agent-workflow.html```\nSELECT 1;\n```';
    await pumpMarkdown(tester, data);

    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/export/conversation_image_exporter.dart';
import 'package:remind_ai/core/llm/models.dart';
import 'package:remind_ai/features/chat/widgets/message_bubble.dart';
import 'package:remind_ai/l10n/app_localizations.dart';
import 'package:remind_ai/providers/settings_provider.dart';

/// "长截图"两条最容易翻车的逻辑，抽出来单独验证：
/// 1. 分页永远切在块之间（不把一条消息劈成两半）；
/// 2. 0×0 裁剪容器里的 `RepaintBoundary` 仍然会完整绘制，`toImage` 能拿到
///    整块高度——这是整个离屏方案成立的前提。
void main() {
  group('splitImagePages', () {
    test('总高不超一页时只有一页', () {
      final pages = ConversationImageExporter.splitImagePages(
        [100, 200, 300],
        maxHeight: 5000,
      );
      expect(pages, hasLength(1));
      expect(pages.first, [0, 1, 2]);
    });

    test('切点落在块之间，不拆分单块', () {
      // 每块 400，maxHeight=1000 → 每页最多 2 块
      final heights = List<double>.filled(5, 400);
      final pages = ConversationImageExporter.splitImagePages(
        heights,
        maxHeight: 1000,
      );

      expect(pages, [
        [0, 1],
        [2, 3],
        [4],
      ]);
      // 每页累计高度都不超过上限
      for (final page in pages) {
        final sum = page.fold<double>(0, (acc, i) => acc + heights[i]);
        expect(sum, lessThanOrEqualTo(1000));
      }
    });

    test('单块超过一页时独占一页（不会被切成两半）', () {
      final pages = ConversationImageExporter.splitImagePages(
        [100, 9000, 100],
        maxHeight: 5000,
      );

      expect(pages, [
        [0],
        [1],
        [2],
      ]);
    });

    test('空输入返回空页列表', () {
      expect(ConversationImageExporter.splitImagePages(const []), isEmpty);
    });
  });

  group('离屏渲染容器', () {
    testWidgets('0×0 + ClipRect + OverflowBox 里的内容仍能被 toImage 截全', (tester) async {
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 与 ConversationImageExporter._buildOverlayEntry 相同的结构
                Positioned(
                  left: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: SizedBox(
                        width: 0,
                        height: 0,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: RepaintBoundary(
                            key: boundaryKey,
                            child: SizedBox(
                              width: 300,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  50,
                                  (i) => SizedBox(
                                    height: 40,
                                    child: Text('row $i'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      // 子节点按自然高度排版（50 × 40 = 2000），没有被 0 高度压扁
      expect(render.size.width, 300);
      expect(render.size.height, 2000);

      // 关键：被父级裁剪掉的内容依然完整存在于图层里
      final image = await tester.runAsync(
        () => render.toImage(pixelRatio: 1.0),
      );
      expect(image, isNotNull);
      expect(image!.width, 300);
      expect(image.height, 2000);
      image.dispose();
    });
  });

  group('ConversationImagePage', () {
    testWidgets('渲染气泡、隐藏操作按钮、HTML 卡换成占位卡', (tester) async {
      final headerKey = GlobalKey();
      final footerKey = GlobalKey();
      final bubbleKeys = <GlobalKey>[GlobalKey(), GlobalKey()];
      final messages = <ChatMessage>[
        ChatMessage.user('第一句'),
        ChatMessage.assistant('回答', htmlFiles: ['C:/tmp/chart.html']),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatFontProvider.overrideWith((ref) => 'monospace'),
            chatFontSizeProvider.overrideWith((ref) => 14.0),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ConversationImagePage(
                  headerKey: headerKey,
                  footerKey: footerKey,
                  bubbleKeys: bubbleKeys,
                  messages: messages,
                  title: '测试对话',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 每条消息都进图（没有被虚拟化裁掉）
      expect(find.byType(MessageBubble), findsNWidgets(2));
      // showActions: false → 不画"复制 / 导出"那排图标
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
      expect(find.byIcon(Icons.ios_share_outlined), findsNothing);
      // HTML 卡是 WebView2 平台视图，导出时替换成占位说明卡
      expect(find.textContaining('HTML'), findsOneWidget);
      // 页眉标题
      expect(find.text('测试对话'), findsOneWidget);
    });
  });
}

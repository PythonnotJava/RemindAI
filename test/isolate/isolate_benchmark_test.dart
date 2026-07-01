import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/isolate/isolate_pool.dart';
import 'package:remind_ai/core/isolate/tasks/markdown_task.dart';
import 'package:remind_ai/core/isolate/tasks/highlight_task.dart';
import 'package:remind_ai/core/isolate/tasks/context_task.dart';
import 'package:remind_ai/core/isolate/tasks/memory_task.dart';
import 'package:remind_ai/core/isolate/tasks/json_task.dart';

/// 性能基准测试 — 验证 Isolate 并行化的实际效果
void main() {
  group('性能基准: Isolate 池 vs 主线程', () {
    setUpAll(() async {
      await IsolatePool.instance.init(4);
    });

    tearDownAll(() {
      IsolatePool.instance.dispose();
    });

    test('Markdown 预处理 - 大文本 (~50KB)', () async {
      // 模拟一个长 AI 回复: ~50KB 的 markdown
      final bigMarkdown = _generateLargeMarkdown(200);
      expect(bigMarkdown.length, greaterThan(40000));

      // 主线程执行
      final swMain = Stopwatch()..start();
      final resultMain = markdownPreprocessTask(bigMarkdown);
      swMain.stop();

      // Isolate 执行
      final swIsolate = Stopwatch()..start();
      final resultIsolate = await IsolatePool.instance.run(
        markdownPreprocessTask,
        bigMarkdown,
      );
      swIsolate.stop();

      // 结果一致
      expect(resultIsolate.codeBlocks.length, resultMain.codeBlocks.length);
      expect(resultIsolate.complexity, resultMain.complexity);

      print('Markdown 预处理 (~50KB):');
      print('  主线程: ${swMain.elapsedMilliseconds}ms');
      print('  Isolate: ${swIsolate.elapsedMilliseconds}ms');
      print('  代码块数: ${resultMain.codeBlocks.length}');
      print('  复杂度: ${resultMain.complexity}');
    });

    test('JSON 序列化 - 大对话 (500条消息)', () async {
      final bigConversation = List.generate(
        500,
        (i) => {
          'role': i % 2 == 0 ? 'user' : 'assistant',
          'content': '这是第 $i 条消息。' * 20,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // 主线程
      final swMain = Stopwatch()..start();
      final resultMain = jsonEncodeTask(bigConversation);
      swMain.stop();

      // Isolate
      final swIsolate = Stopwatch()..start();
      final resultIsolate = await IsolatePool.instance.run(
        jsonEncodeTask,
        bigConversation,
      );
      swIsolate.stop();

      expect(resultIsolate.length, resultMain.length);

      print('JSON 序列化 (500条消息, ${resultMain.length ~/ 1024}KB):');
      print('  主线程: ${swMain.elapsedMilliseconds}ms');
      print('  Isolate: ${swIsolate.elapsedMilliseconds}ms');
    });

    test('代码高亮 - 大代码块 (1000行 Dart)', () async {
      final bigCode = _generateLargeCode(1000);

      final param = HighlightParam(code: bigCode, language: 'dart');

      // 主线程
      final swMain = Stopwatch()..start();
      final resultMain = highlightPreTokenizeTask(param);
      swMain.stop();

      // Isolate
      final swIsolate = Stopwatch()..start();
      final resultIsolate = await IsolatePool.instance.run(
        highlightPreTokenizeTask,
        param,
      );
      swIsolate.stop();

      expect(resultIsolate.tokens.length, resultMain.tokens.length);

      print('代码高亮 (1000行 Dart, ${resultMain.tokens.length} tokens):');
      print('  主线程: ${swMain.elapsedMilliseconds}ms');
      print('  Isolate: ${swIsolate.elapsedMilliseconds}ms');
    });

    test('上下文压缩 - 200条消息', () async {
      final messages = List.generate(
        200,
        (i) => ContextMessage(
          index: i,
          role: i % 3 == 0 ? 'system' : (i % 2 == 0 ? 'user' : 'assistant'),
          content: '消息内容 $i。' * 50 + (i % 5 == 0 ? '```code```' : ''),
          estimatedTokens: 100 + (i * 3),
        ),
      );
      final param = ContextCompressParam(
        messages: messages,
        maxTokens: 5000,
        keepRecentCount: 10,
      );

      // 主线程
      final swMain = Stopwatch()..start();
      final resultMain = contextCompressTask(param);
      swMain.stop();

      // Isolate
      final swIsolate = Stopwatch()..start();
      final resultIsolate = await IsolatePool.instance.run(
        contextCompressTask,
        param,
      );
      swIsolate.stop();

      expect(
        resultIsolate.retainedIndices.length,
        resultMain.retainedIndices.length,
      );

      print('上下文压缩 (200条消息 → ${resultMain.retainedIndices.length}条):');
      print('  主线程: ${swMain.elapsedMilliseconds}ms');
      print('  Isolate: ${swIsolate.elapsedMilliseconds}ms');
      print('  压缩比: ${(resultMain.ratio * 100).toStringAsFixed(1)}%');
    });

    test('向量搜索 - 1000条记忆', () async {
      final entries = List.generate(1000, (i) {
        // 生成随机-ish向量
        final embedding = List.generate(
          128,
          (j) => (i * 7 + j * 3) % 100 / 100.0,
        );
        return VectorEntry(
          id: i,
          text: '记忆条目 $i: 一些内容描述',
          embedding: embedding,
        );
      });
      final queryEmbedding = List.generate(
        128,
        (j) => (42 * 7 + j * 3) % 100 / 100.0,
      );

      final param = VectorSearchParam(
        queryEmbedding: queryEmbedding,
        entries: entries,
        topK: 10,
        threshold: 0.5,
      );

      // 主线程
      final swMain = Stopwatch()..start();
      final resultMain = vectorSearchTask(param);
      swMain.stop();

      // Isolate
      final swIsolate = Stopwatch()..start();
      final resultIsolate = await IsolatePool.instance.run(
        vectorSearchTask,
        param,
      );
      swIsolate.stop();

      expect(resultIsolate.length, resultMain.length);

      print('向量搜索 (1000条, 128维):');
      print('  主线程: ${swMain.elapsedMilliseconds}ms');
      print('  Isolate: ${swIsolate.elapsedMilliseconds}ms');
      print('  结果数: ${resultMain.length}');
    });

    test('并行 vs 串行 - 多任务吞吐', () async {
      final tasks = List.generate(
        20,
        (i) => '# Task $i\n\n```dart\nvoid main() { print("$i"); }\n```\n' * 10,
      );

      // 串行
      final swSerial = Stopwatch()..start();
      for (final task in tasks) {
        markdownPreprocessTask(task);
      }
      swSerial.stop();

      // 并行（通过 pool）
      final swParallel = Stopwatch()..start();
      await IsolatePool.instance.runBatch(markdownPreprocessTask, tasks);
      swParallel.stop();

      print('20 个 Markdown 任务:');
      print('  串行: ${swSerial.elapsedMilliseconds}ms');
      print('  Isolate 并行: ${swParallel.elapsedMilliseconds}ms');
      print(
        '  加速比: ${(swSerial.elapsedMicroseconds / swParallel.elapsedMicroseconds).toStringAsFixed(2)}x',
      );
    });
  });
}

/// 生成大量 Markdown 内容（模拟 AI 长回复）
String _generateLargeMarkdown(int sections) {
  final buffer = StringBuffer();
  for (int i = 0; i < sections; i++) {
    buffer.writeln('## Section $i');
    buffer.writeln();
    buffer.writeln(
      'This is paragraph $i with some text content that simulates a real AI response. '
      'It includes various elements like **bold**, *italic*, and `inline code`.',
    );
    buffer.writeln();
    if (i % 3 == 0) {
      buffer.writeln('```dart');
      buffer.writeln('class Example$i {');
      buffer.writeln('  final String name;');
      buffer.writeln('  final int value = $i;');
      buffer.writeln('  Example$i(this.name);');
      buffer.writeln('  void run() => print(name);');
      buffer.writeln('}');
      buffer.writeln('```');
      buffer.writeln();
    }
    if (i % 5 == 0) {
      buffer.writeln(
        r'The formula is $E = mc^2$ and the integral $$\int_0^1 x^2 dx$$',
      );
      buffer.writeln();
    }
    if (i % 7 == 0) {
      buffer.writeln('| Column A | Column B | Column C |');
      buffer.writeln('|----------|----------|----------|');
      buffer.writeln('| value 1  | value 2  | value 3  |');
      buffer.writeln();
    }
  }
  return buffer.toString();
}

/// 生成大量 Dart 代码
String _generateLargeCode(int lines) {
  final buffer = StringBuffer();
  buffer.writeln('import \'dart:async\';');
  buffer.writeln('import \'dart:isolate\';');
  buffer.writeln();
  buffer.writeln('/// Auto-generated benchmark code');
  buffer.writeln('class BenchmarkClass {');
  for (int i = 0; i < lines - 10; i++) {
    if (i % 20 == 0) {
      buffer.writeln('  // Section $i');
      buffer.writeln('  /// Documentation for method$i');
    }
    if (i % 5 == 0) {
      buffer.writeln('  Future<String> method$i(int param) async {');
      buffer.writeln('    final result = await compute(param);');
      buffer.writeln('    return "result_$i: \$result";');
      buffer.writeln('  }');
    } else {
      buffer.writeln('  final int field$i = ${i * 42};');
    }
  }
  buffer.writeln('}');
  return buffer.toString();
}

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/knowledge/kb_indexer.dart';

void main() {
  group('KbIndexer.chunkText 切块', () {
    test('短文本不切分，原样返回', () {
      final chunks = KbIndexer.chunkText('这是一段很短的文本。');
      expect(chunks.length, 1);
      expect(chunks.first, '这是一段很短的文本。');
    });

    test('空文本返回空列表', () {
      expect(KbIndexer.chunkText(''), isEmpty);
      expect(KbIndexer.chunkText('   \n\n  '), isEmpty);
    });

    test('长文本被切成多块', () {
      final longText = List.generate(
        50,
        (i) => '这是第$i个句子，包含了一些用于测试切块逻辑的中文内容。',
      ).join('');
      final chunks = KbIndexer.chunkText(
        longText,
        const ChunkConfig(chunkSize: 200, overlap: 20),
      );
      expect(chunks.length, greaterThan(1));
    });

    test('按段落聚合切分', () {
      final text = List.generate(20, (i) => '段落$i的内容。' * 5).join('\n\n');
      final chunks = KbIndexer.chunkText(
        text,
        const ChunkConfig(chunkSize: 300, overlap: 30),
      );
      expect(chunks.length, greaterThan(1));
      // 每块不应过度超出目标大小 (允许 overlap + 单段冗余)
      for (final c in chunks) {
        expect(c.length, lessThan(600));
      }
    });

    test('相邻块存在重叠上下文', () {
      final text = List.generate(30, (i) => '句子$i。').join('') * 3;
      final chunks = KbIndexer.chunkText(
        text,
        const ChunkConfig(chunkSize: 150, overlap: 30),
      );
      if (chunks.length >= 2) {
        // 第二块开头应包含来自第一块末尾的重叠字符
        final prevTail = chunks[0].substring(
          (chunks[0].length - 30).clamp(0, chunks[0].length),
        );
        // 重叠会以 prevTail + \n + 新内容 的形式出现在块二开头
        expect(chunks[1].startsWith(prevTail.split('\n').last), isTrue);
      }
    });

    test('无标点超长文本按长度硬切', () {
      final noPunct = 'A' * 2500;
      final chunks = KbIndexer.chunkText(
        noPunct,
        const ChunkConfig(chunkSize: 500, overlap: 0),
      );
      expect(chunks.length, greaterThanOrEqualTo(5));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(500));
      }
    });

    test('CRLF 换行被规范化', () {
      final text = '第一行。\r\n\r\n第二行。';
      final chunks = KbIndexer.chunkText(text);
      expect(chunks.length, 1);
      expect(chunks.first.contains('\r'), isFalse);
    });

    test('中英混合长文本正常切分', () {
      final text = List.generate(
        40,
        (i) => 'Sentence number $i with some 中文内容 mixed in here. ',
      ).join('');
      final chunks = KbIndexer.chunkText(
        text,
        const ChunkConfig(chunkSize: 300, overlap: 40),
      );
      expect(chunks.length, greaterThan(1));
      // 所有块拼起来应覆盖原始内容的主要片段
      expect(chunks.join('').contains('Sentence number 0'), isTrue);
      expect(chunks.join('').contains('Sentence number 39'), isTrue);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/features/multi_agent/dock_layout_storage.dart';

/// [FileDockStorage] 的最小回归：读写删 + 坏文件不炸。
///
/// 这层以前是缺的——`packages/dock_panel` 只提供内存实现，`setStorage`
/// 也没有任何调用点，所以 dock 布局从来不会被持久化。
void main() {
  group('FileDockStorage', () {
    late Directory tempDir;
    late File file;
    late FileDockStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dock_storage_test_');
      file = File(p.join(tempDir.path, 'multi_agent_dock.json'));
      storage = FileDockStorage(file);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('没有文件时 read 返回 null', () {
      expect(storage.read(), isNull);
    });

    test('write 后能原样 read 回来', () {
      final layout = <String, dynamic>{
        'type': 'split',
        'axis': 'horizontal',
        'flexes': [0.18, 0.82],
        'children': [
          {
            'type': 'group',
            'panels': ['__explorer__'],
            'activeIndex': 0,
          },
          {
            'type': 'group',
            'panels': ['__command_center__'],
            'activeIndex': 0,
          },
        ],
      };

      storage.write(layout);

      expect(file.existsSync(), isTrue);
      final restored = storage.read();
      expect(restored, isNotNull);
      expect(restored!['type'], 'split');
      expect((restored['flexes'] as List).length, 2);
    });

    test('写入空 map 表示"没有布局"，应删除文件', () {
      storage.write({'type': 'group', 'panels': <String>[]});
      expect(file.existsSync(), isTrue);

      storage.write({});
      expect(file.existsSync(), isFalse);
      expect(storage.read(), isNull);
    });

    test('布局文件损坏时不抛异常，按"没有布局"处理', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ this is not json');

      expect(storage.read(), isNull);
    });

    test('clear 之后回到初始状态', () {
      storage.write({'type': 'group'});
      storage.clear();

      expect(file.existsSync(), isFalse);
      expect(storage.read(), isNull);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/memory/project_config.dart';

/// 覆盖记忆设置 chip 依赖的核心持久化前提：
/// - 没有 memory.json 时，所有开关必须默认关闭（不是硬编码开启）
/// - save() 之后重新 load() 必须能读回同样的值（真正落盘，不是纯内存态）
/// - save() 不应破坏文件中已有的、本类不识别的自定义字段
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remindai_projectconfig_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('load(): 默认全关闭', () {
    test('工作目录下没有 memory.json 时，返回的配置全部为默认关闭值', () async {
      final config = await ProjectConfig.load(root.path);
      expect(config.embeddings, false);
      expect(config.longTermStore, false);
      expect(config.longTermRecall, false);
      expect(config.mode, PermissionMode.normal);
    });

    test('memory.json 内容非法 JSON 时，降级为默认关闭配置而不抛异常', () async {
      final file = File(p.join(root.path, 'memory.json'));
      await file.writeAsString('{not valid json');

      final config = await ProjectConfig.load(root.path);
      expect(config.embeddings, false);
      expect(config.longTermStore, false);
      expect(config.longTermRecall, false);
    });
  });

  group('save(): 真正落盘，且可被重新 load() 读回', () {
    test('save() 后 load() 能读到同样的开关状态 (往返一致性)', () async {
      const config = ProjectConfig(longTermRecall: true, longTermStore: true);
      await config.save(root.path);

      final reloaded = await ProjectConfig.load(root.path);
      expect(reloaded.longTermRecall, true);
      expect(reloaded.longTermStore, true);
      expect(reloaded.embeddings, false);
      expect(reloaded.mode, PermissionMode.normal);
    });

    test('save() 会创建工作目录 (若尚不存在)', () async {
      final nested = Directory(p.join(root.path, 'not_yet_created'));
      expect(await nested.exists(), false);

      const config = ProjectConfig(longTermRecall: true);
      await config.save(nested.path);

      expect(await nested.exists(), true);
      final file = File(p.join(nested.path, 'memory.json'));
      expect(await file.exists(), true);
    });

    test('多次 save() 切换开关，最终文件内容以最后一次为准', () async {
      const configOn = ProjectConfig(longTermRecall: true, longTermStore: true);
      await configOn.save(root.path);

      const configOff = ProjectConfig(
        longTermRecall: false,
        longTermStore: false,
      );
      await configOff.save(root.path);

      final reloaded = await ProjectConfig.load(root.path);
      expect(reloaded.longTermRecall, false);
      expect(reloaded.longTermStore, false);
    });

    test('save() 保留文件中已存在的、本类不识别的自定义字段', () async {
      final file = File(p.join(root.path, 'memory.json'));
      await file.writeAsString(
        jsonEncode({
          'embeddings': false,
          'long_term_store': false,
          'long_term_recall': false,
          'mode': 'normal',
          'custom_field': 'should survive',
        }),
      );

      const config = ProjectConfig(longTermRecall: true);
      await config.save(root.path);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      expect(json['custom_field'], 'should survive');
      expect(json['long_term_recall'], true);
    });

    test('mode=auto 能正确序列化并读回', () async {
      const config = ProjectConfig(mode: PermissionMode.auto);
      await config.save(root.path);

      final reloaded = await ProjectConfig.load(root.path);
      expect(reloaded.mode, PermissionMode.auto);
    });
  });

  group('copyWith(): 只覆盖指定字段', () {
    test('copyWith 保留未指定字段的原值', () {
      const original = ProjectConfig(
        embeddings: true,
        longTermRecall: true,
        mode: PermissionMode.auto,
      );
      final updated = original.copyWith(longTermStore: true);

      expect(updated.embeddings, true);
      expect(updated.longTermRecall, true);
      expect(updated.longTermStore, true);
      expect(updated.mode, PermissionMode.auto);
    });
  });
}

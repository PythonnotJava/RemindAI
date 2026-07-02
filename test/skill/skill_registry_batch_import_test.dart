import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remind_ai/core/skill/skill_registry.dart';

/// 覆盖技能批量导入 (`SkillsNotifier.importFromZips` 的底层 `SkillRegistry
/// .importFromZip` 逐个调用) 混合成功/失败场景下的聚合行为。
///
/// 不直接测 Provider 层 (`SkillsNotifier`)，因为它依赖 Riverpod
/// container + `settingsProvider` 异步初始化，属于集成测试范畴；
/// 这里聚焦 `SkillRegistry` 本身 —— Provider 层的 `importFromZips` 只是
/// 对本类 `importFromZip` 的简单循环 + try/catch 聚合，逻辑本身在
/// SkillRegistry 侧验证即可覆盖核心行为（成功技能正确落盘、
/// 失败 ZIP 不中断后续导入、错误信息保留原始异常文案）。
void main() {
  late Directory tempRoot;
  late Directory skillsDir;
  late SkillRegistry registry;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('remindai_skillbatch_');
    skillsDir = Directory(p.join(tempRoot.path, 'Skills'));
    registry = SkillRegistry(skillsPath: skillsDir.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  /// 构造一个最小合法技能 ZIP：根目录直接包含 SKILL.md。
  String writeValidSkillZip(String fileName, {String skillMd = '# demo'}) {
    final archive = Archive();
    final bytes = skillMd.codeUnits;
    archive.addFile(ArchiveFile('SKILL.md', bytes.length, bytes));
    final zipBytes = ZipEncoder().encode(archive);
    final zipPath = p.join(tempRoot.path, fileName);
    File(zipPath).writeAsBytesSync(zipBytes);
    return zipPath;
  }

  /// 构造一个无效 ZIP：根目录缺少 SKILL.md，导入应失败。
  String writeInvalidSkillZip(String fileName) {
    final archive = Archive();
    final bytes = 'not a skill'.codeUnits;
    archive.addFile(ArchiveFile('readme.txt', bytes.length, bytes));
    final zipBytes = ZipEncoder().encode(archive);
    final zipPath = p.join(tempRoot.path, fileName);
    File(zipPath).writeAsBytesSync(zipBytes);
    return zipPath;
  }

  group('SkillRegistry.importFromZip 批量场景基础行为', () {
    test('多个合法 ZIP 依次导入都成功，且都能在 listInstalled 中查到', () async {
      final zip1 = writeValidSkillZip('skill-a.zip');
      final zip2 = writeValidSkillZip('skill-b.zip');

      final skillA = await registry.importFromZip(zip1);
      final skillB = await registry.importFromZip(zip2);

      expect(skillA.name, 'skill-a');
      expect(skillB.name, 'skill-b');

      final installed = await registry.listInstalled();
      final names = installed.map((s) => s.name).toSet();
      expect(names, containsAll(['skill-a', 'skill-b']));
    });

    test('一个 ZIP 缺少 SKILL.md 时导入失败并抛出带说明的异常，不影响其余文件继续导入', () async {
      final goodZip = writeValidSkillZip('good.zip');
      final badZip = writeInvalidSkillZip('bad.zip');

      // 模拟 SkillsNotifier.importFromZips 的循环 + try/catch 聚合逻辑
      final paths = [goodZip, badZip];
      final successes = <String>[];
      final failures = <String>[];
      for (final path in paths) {
        try {
          final skill = await registry.importFromZip(path);
          successes.add(skill.name);
        } catch (e) {
          failures.add(e.toString());
        }
      }

      expect(successes, ['good']);
      expect(failures, hasLength(1));
      expect(failures.single, contains('SKILL.md'));

      // 好的那个应该已经落盘，坏的不应该产生半成品目录
      final installed = await registry.listInstalled();
      expect(installed.map((s) => s.name), ['good']);
      expect(await Directory(p.join(skillsDir.path, 'bad')).exists(), false);
    });

    test('ZIP 文件本身不存在时导入失败并给出明确错误，不抛出未捕获异常', () async {
      final missingPath = p.join(tempRoot.path, 'missing.zip');
      expect(
        () => registry.importFromZip(missingPath),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('不存在'),
          ),
        ),
      );
    });

    test('全部失败时不影响后续独立导入 —— 每个路径的结果互不干扰', () async {
      final bad1 = writeInvalidSkillZip('bad1.zip');
      final bad2 = writeInvalidSkillZip('bad2.zip');

      final results = <String, Object?>{};
      for (final path in [bad1, bad2]) {
        try {
          await registry.importFromZip(path);
          results[path] = null;
        } catch (e) {
          results[path] = e;
        }
      }

      expect(results.values.every((v) => v != null), true);
      final installed = await registry.listInstalled();
      expect(installed, isEmpty);
    });

    test('同名 ZIP 重复导入会覆盖旧技能目录（与单文件导入行为一致）', () async {
      final zip1 = writeValidSkillZip('dup.zip', skillMd: '# v1');
      await registry.importFromZip(zip1);

      final zip2 = writeValidSkillZip('dup.zip', skillMd: '# v2');
      final skill = await registry.importFromZip(zip2);

      final content = await registry.loadSkillPrompt(skill);
      expect(content, '# v2');

      final installed = await registry.listInstalled();
      expect(installed.where((s) => s.name == 'dup'), hasLength(1));
    });
  });
}

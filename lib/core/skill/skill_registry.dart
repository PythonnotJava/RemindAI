import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'skill_model.dart';

/// 技能注册表 - 管理技能的导入、删除、加载
class SkillRegistry {
  static const _uuid = Uuid();

  /// 技能存放目录。为空时回退到旧的默认位置 (应用支持目录/Skills)。
  final String skillsPath;

  SkillRegistry({this.skillsPath = ''});

  /// 获取技能目录
  Future<Directory> getSkillsDir() async {
    final String dirPath;
    if (skillsPath.isNotEmpty) {
      dirPath = skillsPath;
    } else {
      final appData = await getApplicationSupportDirectory();
      dirPath = p.join(appData.path, 'Skills');
    }
    final skillsDir = Directory(dirPath);
    if (!await skillsDir.exists()) {
      await skillsDir.create(recursive: true);
    }
    return skillsDir;
  }

  /// 旧版默认技能目录 (应用支持目录/Skills)，用于一次性迁移。
  static Future<String> legacySkillsDir() async {
    final appData = await getApplicationSupportDirectory();
    return p.join(appData.path, 'Skills');
  }

  /// 列出所有已安装的技能
  Future<List<Skill>> listInstalled() async {
    final skillsDir = await getSkillsDir();
    final skills = <Skill>[];

    if (!await skillsDir.exists()) return skills;

    await for (final entity in skillsDir.list()) {
      if (entity is Directory) {
        final skill = await _loadSkillFromDir(entity);
        if (skill != null) {
          skills.add(skill);
        }
      }
    }

    // 按 sortIndex 升序排序 (相同则按安装时间倒序)
    skills.sort((a, b) {
      final c = a.sortIndex.compareTo(b.sortIndex);
      if (c != 0) return c;
      return b.installedAt.compareTo(a.installedAt);
    });
    return skills;
  }

  /// 项目级临时技能目录的相对路径约定: `<workDir>/.toolshell/skills/`
  static const projectSkillsRelPath = '.toolshell/skills';

  /// 扫描工作目录下的项目级临时技能 (`.toolshell/skills/<名字>/`)。
  ///
  /// 与全局技能不同:
  /// - 不要求 .skill_meta.json (模型/用户手建时通常不会写)
  /// - 恒定 isActive=true、isProjectLevel=true
  /// - id 用 "project:<目录名>" 前缀，避免与全局技能 id 冲突
  /// - 生命周期跟随工作目录，不写入/不修改任何元数据
  ///
  /// [workDir] 为空或目录不存在时返回空列表。
  Future<List<Skill>> listProjectSkills(String workDir) async {
    if (workDir.isEmpty) return [];

    final dir = Directory(p.join(workDir, '.toolshell', 'skills'));
    if (!await dir.exists()) return [];

    final skills = <Skill>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final skillMdFile = File(p.join(entity.path, 'SKILL.md'));
      if (!await skillMdFile.exists()) continue;

      final name = p.basename(entity.path);

      // 统计工具数量 (tools.json 可选)
      int toolCount = 0;
      final toolsJsonFile = File(p.join(entity.path, 'tools.json'));
      if (await toolsJsonFile.exists()) {
        try {
          final tools = jsonDecode(await toolsJsonFile.readAsString()) as List;
          toolCount = tools.length;
        } catch (_) {}
      }

      DateTime installedAt = DateTime.now();
      try {
        installedAt = await skillMdFile
            .lastModified()
            .timeout(const Duration(seconds: 2));
      } catch (_) {}

      skills.add(
        Skill(
          id: 'project:$name',
          name: name,
          description: '',
          path: entity.path,
          toolCount: toolCount,
          isActive: true, // 项目技能恒定激活
          installedAt: installedAt,
          sortIndex: 0,
          isProjectLevel: true,
        ),
      );
    }

    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  /// 从 ZIP 文件导入技能
  Future<Skill> importFromZip(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('ZIP 文件不存在: $zipPath');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 检测公共顶层目录前缀（如 "gurobi-expert/"），解压时统一剥离，
    // 避免出现 Skills/<name>/<name>/SKILL.md 这样的多余嵌套。
    final commonPrefix = _detectCommonPrefix(archive);

    // 验证必需文件 (仅 SKILL.md 必须，tools.json 可选)
    final hasSkillMd = archive.files.any(
      (f) => f.isFile && _stripPrefix(f.name, commonPrefix) == 'SKILL.md',
    );

    if (!hasSkillMd) {
      throw Exception(
        '压缩包根目录缺少 SKILL.md 文件。请确认 SKILL.md 位于压缩包顶层'
        '或单层目录内（当前检测到的文件：'
        '${archive.files.where((f) => f.isFile).map((f) => f.name).take(5).join('、')} …）',
      );
    }

    // 确定技能名称 (使用 ZIP 文件名)
    final skillName = p.basenameWithoutExtension(zipPath);
    final skillId = _uuid.v4();
    final skillsDir = await getSkillsDir();
    final skillDir = Directory(p.join(skillsDir.path, skillName));

    // 如果已存在同名目录则覆盖
    if (await skillDir.exists()) {
      await skillDir.delete(recursive: true);
    }
    await skillDir.create(recursive: true);

    // 解压文件（剥离公共顶层目录前缀）
    for (final file in archive.files) {
      if (file.isFile) {
        final relPath = _stripPrefix(file.name, commonPrefix);
        if (relPath.isEmpty) continue;
        final outPath = p.join(skillDir.path, relPath);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    // 写入元数据
    final meta = {
      'id': skillId,
      'installed_at': DateTime.now().toIso8601String(),
      'is_active': true,
      'sort_index': await _nextSortIndex(),
    };
    final metaFile = File(p.join(skillDir.path, '.skill_meta.json'));
    await metaFile.writeAsString(jsonEncode(meta));

    final skill = await _loadSkillFromDir(skillDir);
    if (skill == null) {
      throw Exception('技能加载失败');
    }
    return skill;
  }

  /// 从普通目录安装技能到全局技能库 (应用支持目录/Skills 或设置指定目录)。
  ///
  /// 用于把工作目录里临时做好的技能 (如 `.toolshell/skills/<名字>/`) "提升"为
  /// 全局技能：递归复制目录内容到 `Skills/<名字>/`，并补写 `.skill_meta.json`。
  /// 与 [importFromZip] 共享同一套元数据与加载逻辑，安装后即出现在技能页。
  ///
  /// [sourceDir] 源技能目录，必须直接包含 SKILL.md。
  /// [name] 可选的目标技能名 (默认取源目录名)。
  /// 已存在同名全局技能目录时覆盖。
  Future<Skill> installFromDirectory(String sourceDir, {String? name}) async {
    final src = Directory(sourceDir);
    if (!await src.exists()) {
      throw Exception('源目录不存在: $sourceDir');
    }
    final srcSkillMd = File(p.join(src.path, 'SKILL.md'));
    if (!await srcSkillMd.exists()) {
      throw Exception('源目录缺少 SKILL.md，无法识别为技能: $sourceDir');
    }

    final skillName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : p.basename(src.path);
    final skillId = _uuid.v4();
    final skillsDir = await getSkillsDir();
    final skillDir = Directory(p.join(skillsDir.path, skillName));

    // 已存在同名目录则覆盖
    if (await skillDir.exists()) {
      await skillDir.delete(recursive: true);
    }
    await skillDir.create(recursive: true);

    // 递归复制源目录内容 (跳过源自带的 .skill_meta.json，下面重写)
    await for (final entity in src.list(recursive: true)) {
      final rel = p.relative(entity.path, from: src.path);
      if (rel == '.skill_meta.json') continue;
      final outPath = p.join(skillDir.path, rel);
      if (entity is Directory) {
        await Directory(outPath).create(recursive: true);
      } else if (entity is File) {
        await File(outPath).parent.create(recursive: true);
        await entity.copy(outPath);
      }
    }

    // 写入元数据
    final meta = {
      'id': skillId,
      'installed_at': DateTime.now().toIso8601String(),
      'is_active': true,
      'sort_index': await _nextSortIndex(),
    };
    final metaFile = File(p.join(skillDir.path, '.skill_meta.json'));
    await metaFile.writeAsString(jsonEncode(meta));

    final skill = await _loadSkillFromDir(skillDir);
    if (skill == null) {
      throw Exception('技能加载失败');
    }
    return skill;
  }

  /// 删除技能
  Future<void> remove(String skillId) async {
    final skills = await listInstalled();
    final skill = skills.firstWhere(
      (s) => s.id == skillId,
      orElse: () => throw Exception('技能不存在'),
    );

    final dir = Directory(skill.path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 切换技能激活状态
  Future<void> setActive(String skillId, bool active) async {
    final skills = await listInstalled();
    final skill = skills.firstWhere(
      (s) => s.id == skillId,
      orElse: () => throw Exception('技能不存在'),
    );

    final metaFile = File(p.join(skill.path, '.skill_meta.json'));
    if (await metaFile.exists()) {
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      meta['is_active'] = active;
      await metaFile.writeAsString(jsonEncode(meta));
    }
  }

  /// 更新技能描述 (用户手动编辑，写入 .skill_meta.json)
  Future<void> setDescription(String skillId, String description) async {
    final skills = await listInstalled();
    final skill = skills.firstWhere(
      (s) => s.id == skillId,
      orElse: () => throw Exception('技能不存在'),
    );

    final metaFile = File(p.join(skill.path, '.skill_meta.json'));
    Map<String, dynamic> meta = {};
    if (await metaFile.exists()) {
      meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    } else {
      meta = {
        'id': skill.id,
        'installed_at': skill.installedAt.toIso8601String(),
        'is_active': skill.isActive,
        'sort_index': skill.sortIndex,
      };
    }
    meta['description'] = description;
    await metaFile.writeAsString(jsonEncode(meta));
  }

  /// 按给定 id 顺序重写各技能的 sort_index (写入各自的 .skill_meta.json)
  Future<void> reorder(List<String> orderedIds) async {
    final skills = await listInstalled();
    final byId = {for (final s in skills) s.id: s};
    for (var i = 0; i < orderedIds.length; i++) {
      final skill = byId[orderedIds[i]];
      if (skill == null) continue;
      final metaFile = File(p.join(skill.path, '.skill_meta.json'));
      Map<String, dynamic> meta = {};
      if (await metaFile.exists()) {
        meta =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      } else {
        meta = {
          'id': skill.id,
          'installed_at': skill.installedAt.toIso8601String(),
          'is_active': skill.isActive,
        };
      }
      meta['sort_index'] = i;
      await metaFile.writeAsString(jsonEncode(meta));
    }
  }

  /// 计算下一个 sort_index (现有最大值 + 1)
  Future<int> _nextSortIndex() async {
    final skills = await listInstalled();
    if (skills.isEmpty) return 0;
    final maxIndex = skills
        .map((s) => s.sortIndex)
        .reduce((a, b) => a > b ? a : b);
    return maxIndex + 1;
  }

  /// 读取技能的 SKILL.md 内容
  Future<String> loadSkillPrompt(Skill skill) async {
    final file = File(p.join(skill.path, 'SKILL.md'));
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// 解析技能的 tools.json
  Future<List<Map<String, dynamic>>> loadSkillTools(Skill skill) async {
    final file = File(p.join(skill.path, 'tools.json'));
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    final list = jsonDecode(content) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ─── 私有方法 ─────────────────────────────────────────────

  /// 从目录加载技能信息
  Future<Skill?> _loadSkillFromDir(Directory dir) async {
    final skillMdFile = File(p.join(dir.path, 'SKILL.md'));
    final toolsJsonFile = File(p.join(dir.path, 'tools.json'));

    // 只要求 SKILL.md 存在，tools.json 可选
    if (!await skillMdFile.exists()) {
      return null;
    }

    // 读取元数据
    String id = p.basename(dir.path);
    bool isActive = true;
    DateTime installedAt = DateTime.now();
    int sortIndex = 0;
    // 描述完全由用户编辑，默认无描述 (不再自动解析 SKILL.md / frontmatter)
    String description = '';

    final metaFile = File(p.join(dir.path, '.skill_meta.json'));
    if (await metaFile.exists()) {
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      id = meta['id'] as String? ?? id;
      isActive = meta['is_active'] as bool? ?? true;
      sortIndex = (meta['sort_index'] as num?)?.toInt() ?? 0;
      description = (meta['description'] as String?)?.trim() ?? '';
      if (meta['installed_at'] != null) {
        installedAt = DateTime.parse(meta['installed_at'] as String);
      }
    }

    // 统计工具数量
    int toolCount = 0;
    try {
      final toolsContent = await toolsJsonFile.readAsString();
      final tools = jsonDecode(toolsContent) as List;
      toolCount = tools.length;
    } catch (_) {}

    return Skill(
      id: id,
      name: p.basename(dir.path),
      description: description,
      path: dir.path,
      toolCount: toolCount,
      isActive: isActive,
      installedAt: installedAt,
      sortIndex: sortIndex,
    );
  }

  /// 检测压缩包内是否所有文件都包裹在同一个顶层目录下。
  /// 若是，返回该目录前缀（含末尾斜杠，如 "gurobi-expert/"）；否则返回空串。
  String _detectCommonPrefix(Archive archive) {
    String? prefix;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final slash = name.indexOf('/');
      // 存在顶层文件（无目录），说明没有统一包裹目录
      if (slash < 0) return '';
      final top = name.substring(0, slash + 1);
      if (prefix == null) {
        prefix = top;
      } else if (prefix != top) {
        // 顶层目录不一致，无法统一剥离
        return '';
      }
    }
    return prefix ?? '';
  }

  /// 剥离文件名的公共顶层目录前缀，并统一为正斜杠路径。
  String _stripPrefix(String name, String prefix) {
    final normalized = name.replaceAll('\\', '/');
    if (prefix.isNotEmpty && normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length);
    }
    return normalized;
  }
}

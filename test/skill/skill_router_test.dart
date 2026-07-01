import 'package:flutter_test/flutter_test.dart';

import 'package:remind_ai/core/skill/skill_model.dart';
import 'package:remind_ai/core/skill/skill_router.dart';

void main() {
  group('SkillRouter', () {
    late SkillRouter router;

    final testSkills = [
      Skill(
        id: 'skill-1',
        name: 'flutter-dev',
        description: 'Flutter 开发辅助，Widget 构建、状态管理',
        path: '/skills/flutter-dev',
        toolCount: 3,
        installedAt: DateTime(2024, 1, 1),
      ),
      Skill(
        id: 'skill-2',
        name: 'git-helper',
        description: 'Git 版本控制操作，提交、分支管理',
        path: '/skills/git-helper',
        toolCount: 2,
        installedAt: DateTime(2024, 1, 2),
      ),
      Skill(
        id: 'skill-3',
        name: 'docker-deploy',
        description: 'Docker 容器化部署，Dockerfile 编写',
        path: '/skills/docker-deploy',
        toolCount: 4,
        installedAt: DateTime(2024, 1, 3),
      ),
      Skill(
        id: 'skill-4',
        name: 'api-design',
        description: 'RESTful API 设计，接口文档生成',
        path: '/skills/api-design',
        toolCount: 2,
        installedAt: DateTime(2024, 1, 4),
      ),
      Skill(
        id: 'skill-5',
        name: 'database',
        description: '数据库设计与优化，SQL 查询',
        path: '/skills/database',
        toolCount: 3,
        installedAt: DateTime(2024, 1, 5),
      ),
    ];

    final testSkillPrompts = <String, String>{
      'skill-1': '# Flutter Dev\n帮助构建 Flutter Widget，管理状态，使用 Riverpod 或 Bloc',
      'skill-2': '# Git Helper\n管理 git 仓库，提交代码，创建分支，处理合并冲突',
      'skill-3': '# Docker Deploy\n创建 Dockerfile，docker-compose 配置，容器编排',
      'skill-4': '# API Design\n设计 RESTful 接口，生成 OpenAPI 文档，mock 服务',
      'skill-5': '# Database\n设计数据库表结构，优化 SQL 查询，索引分析',
    };

    setUp(() {
      router = SkillRouter(); // 无 embedding，纯关键词匹配
    });

    test('技能名直接匹配 - 用户输入包含技能名时得高分', () async {
      final results = await router.resolve(
        userInput: '帮我用 flutter-dev 创建一个页面',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      expect(results.isNotEmpty, true);
      expect(results.first.skill.id, 'skill-1');
      expect(results.first.score, greaterThanOrEqualTo(0.5));
    });

    test('关键词匹配 - 用户输入含技能描述中的词', () async {
      final results = await router.resolve(
        userInput: '我想部署一个 Docker 容器',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      expect(results.isNotEmpty, true);
      final dockerSkill = results.where((r) => r.skill.id == 'skill-3');
      expect(dockerSkill.isNotEmpty, true);
    });

    test('多技能同时匹配 - 输入涉及多个领域', () async {
      final results = await router.resolve(
        userInput: '设计一个 API 接口，然后用 Docker 部署',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      expect(results.length, greaterThanOrEqualTo(2));
      final ids = results.map((r) => r.skill.id).toSet();
      expect(ids.contains('skill-3'), true); // docker
      expect(ids.contains('skill-4'), true); // api
    });

    test('pinned skill 始终注入', () async {
      router.pinSkill('skill-5');

      final results = await router.resolve(
        userInput: '帮我写一个 Flutter 页面',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      final dbSkill = results.where((r) => r.skill.id == 'skill-5');
      expect(dbSkill.isNotEmpty, true);
      expect(dbSkill.first.score, 1.0);
      expect(dbSkill.first.matchReason, contains('pinned'));
    });

    test('clearPins 清除所有 pin', () async {
      router.pinSkill('skill-5');
      router.clearPins();

      final results = await router.resolve(
        userInput: '今天天气真好',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      final dbPinned = results.where(
        (r) => r.skill.id == 'skill-5' && r.matchReason.contains('pinned'),
      );
      expect(dbPinned, isEmpty);
    });

    test('最大注入限制为 10', () async {
      final manySkills = List.generate(
        15,
        (i) => Skill(
          id: 'many-$i',
          name: 'skill-$i',
          description: '通用技能$i 关键词匹配测试',
          path: '/skills/skill-$i',
          toolCount: 1,
          installedAt: DateTime(2024, 1, i + 1),
        ),
      );
      final manyPrompts = <String, String>{
        for (var i = 0; i < 15; i++) 'many-$i': '通用 技能 测试 关键词',
      };

      final results = await router.resolve(
        userInput: '通用 技能 测试 关键词 匹配',
        recentContext: [],
        allSkills: manySkills,
        skillPrompts: manyPrompts,
      );

      expect(results.length, lessThanOrEqualTo(SkillRouter.maxActiveSkills));
    });

    test('空技能列表返回空结果', () async {
      final results = await router.resolve(
        userInput: '随便什么输入',
        recentContext: [],
        allSkills: [],
        skillPrompts: {},
      );

      expect(results, isEmpty);
    });

    test('recentContext 辅助匹配', () async {
      final results = await router.resolve(
        userInput: '继续',
        recentContext: ['我想创建一个 git 分支来开发新功能'],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      final gitSkill = results.where((r) => r.skill.id == 'skill-2');
      expect(gitSkill.isNotEmpty, true);
    });

    test('SKILL.md 内容参与匹配', () async {
      final results = await router.resolve(
        userInput: '帮我处理 Riverpod 状态管理的问题',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      final flutterSkill = results.where((r) => r.skill.id == 'skill-1');
      expect(flutterSkill.isNotEmpty, true);
    });

    test('ScoredSkill 数据完整性', () async {
      final results = await router.resolve(
        userInput: 'docker 部署',
        recentContext: [],
        allSkills: testSkills,
        skillPrompts: testSkillPrompts,
      );

      for (final r in results) {
        expect(r.score, greaterThan(0));
        expect(r.score, lessThanOrEqualTo(1.0));
        expect(r.matchReason.isNotEmpty, true);
        expect(r.skill.id.isNotEmpty, true);
      }
    });
  });
}

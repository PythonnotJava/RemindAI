import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/mcp/mcp_tool_names.dart';

Map<String, dynamic> _def(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': 'desc of $name',
    'parameters': {'type': 'object', 'properties': {}},
  },
};

void main() {
  group('buildMcpToolRoutes', () {
    test('无冲突时沿用原始工具名', () {
      final routes = buildMcpToolRoutes({
        'srv-a': [_def('list_notes'), _def('add_note')],
      });

      expect(routes.map((r) => r.exposedName), ['list_notes', 'add_note']);
      expect(routes.every((r) => !r.namespaced), isTrue);
      expect(routes.first.serverId, 'srv-a');
      expect(routes.first.toolName, 'list_notes');
    });

    test('与内置工具同名 → 命名空间改名', () {
      final routes = buildMcpToolRoutes({
        'srv-a': [_def('toolshell_read'), _def('list_notes')],
      });

      final read = routes.firstWhere((r) => r.toolName == 'toolshell_read');
      expect(read.namespaced, isTrue);
      expect(read.exposedName, 'mcp__srv-a__toolshell_read');
      // 未冲突的那个保持原名
      expect(
        routes.firstWhere((r) => r.toolName == 'list_notes').exposedName,
        'list_notes',
      );
    });

    test('两台服务器同名 → 两边都改名，不会互相覆盖', () {
      final routes = buildMcpToolRoutes({
        'srv-a': [_def('search')],
        'srv-b': [_def('search')],
      });

      expect(routes.length, 2);
      expect(routes.map((r) => r.exposedName).toSet(), {
        'mcp__srv-a__search',
        'mcp__srv-b__search',
      });
      expect(routes.every((r) => r.namespaced), isTrue);
    });

    test('reserved 额外占用名也会触发改名', () {
      final routes = buildMcpToolRoutes(
        {
          'srv-a': [_def('ask')],
        },
        reserved: {'ask'},
      );

      expect(routes.single.exposedName, 'mcp__srv-a__ask');
      expect(routes.single.namespaced, isTrue);
    });

    test('serverId 里的非法字符被归一化，仍可读', () {
      final routes = buildMcpToolRoutes({
        'x:y/z': [_def('toolshell_exec')],
      });

      expect(routes.single.exposedName, 'mcp__x_y_z__toolshell_exec');
    });

    test('顺序稳定：同一输入两次计算结果一致', () {
      final cache = {
        'srv-a': [_def('a1'), _def('a2')],
        'srv-b': [_def('b1')],
      };
      final first = buildMcpToolRoutes(cache).map((r) => r.exposedName).toList();
      final second = buildMcpToolRoutes(cache)
          .map((r) => r.exposedName)
          .toList();
      expect(first, second);
    });
  });

  group('renameMcpToolDef', () {
    test('只改名字，其余字段保留且不改原对象', () {
      final original = _def('search');
      final renamed = renameMcpToolDef(original, 'mcp__srv-a__search');

      final fn = renamed['function'] as Map<String, dynamic>;
      expect(fn['name'], 'mcp__srv-a__search');
      expect(fn['description'], 'desc of search');
      expect(fn['parameters'], isA<Map>());
      // 原定义不受影响（缓存可复用）
      expect((original['function'] as Map)['name'], 'search');
    });
  });

  group('mcpToolDefName', () {
    test('读嵌套格式与扁平格式', () {
      expect(mcpToolDefName(_def('x')), 'x');
      expect(mcpToolDefName({'name': 'flat'}), 'flat');
      expect(mcpToolDefName({'foo': 'bar'}), isNull);
    });
  });
}

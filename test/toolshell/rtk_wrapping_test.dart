import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:remind_ai/core/memory/project_config.dart';
import 'package:remind_ai/core/toolshell/executor.dart';

/// 验证 `[RTK]` 包裹逻辑到底有没有真正命中过，而不是像
/// test/hooks/bundled_exe_test.dart 那样只断言"命令执行成功"。
///
/// Executor._exec() 里唯一对外暴露的"是否经过 rtk 包裹"信号是响应 JSON
/// 里的 `optimized: true` 字段(executor.dart:620)，其判定条件是
/// `_rtkPath != null && effectiveCommand != command`——即 rtk.exe 存在，
/// 且命令字符串确实被改写过。本文件直接断言这个字段，而不是靠肉眼看
/// 控制台的 [RTK] 日志。
///
/// 注意：`_rtkPath` 的探测依赖 `Directory.current.path` 能找到
/// `assets/bin/rtk.exe`（executor.dart:76-83），`flutter test` 默认
/// 工作目录就是项目根目录，所以这里不额外处理路径问题；如果换成
/// `dart test` 或改变了 cwd，_rtkPath 会是 null，所有包裹判断直接短路，
/// 对应本文件的"rtk 不可用时跳过"分组会覆盖这种退化情况。
void main() {
  late Directory tempDir;
  late Executor executor;
  final rtkAvailable = File(
    p.join(Directory.current.path, 'assets', 'bin', 'rtk.exe'),
  ).existsSync();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remindai_rtk_test_');
    executor = Executor(
      projectRoot: tempDir.path,
      permissionMode: PermissionMode.auto,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('rtk 真正命中: 干净的白名单命令', () {
    test('git status (无重定向、无clone/init前缀) 应带 optimized:true', () async {
      await Process.run('git', ['init'], workingDirectory: tempDir.path);

      final raw = await executor.run('toolshell_exec', {
        'command': 'git status',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      if (rtkAvailable) {
        // rtk.exe 存在时，git status 是白名单命令、无重定向、
        // 不匹配 git clone/init 跳过前缀，必须真正被包裹。
        expect(
          result['optimized'],
          true,
          reason:
              'rtk.exe 存在时，一条干净的 git status 必须被 rtk 包裹，'
              '否则说明白名单/重定向/前缀判断逻辑出现回归',
        );
      } else {
        // CI 或裸机环境可能没有打包 assets/bin/rtk.exe，
        // 此时不应误判为"逻辑坏了"，只跳过强断言。
        expect(result['optimized'], isNot(true));
      }
    });
  });

  group('rtk 不会命中: 已知会被跳过的场景', () {
    test('带 2>&1 重定向的命令不会被包裹', () async {
      final raw = await executor.run('toolshell_exec', {
        // 用一个白名单命令 (git) 但带重定向，验证重定向优先级更高
        'command': 'git --version 2>&1',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(
        result['optimized'],
        isNot(true),
        reason: '命令包含 ">" (2>&1 也算) 时，_wrapWithRtk 应直接跳过包裹',
      );
    });

    test('git clone 前缀命中不兼容黑名单，不会被包裹', () async {
      // 用一个必定失败但足够快的 clone (无效地址)，只关心是否被包裹，不关心业务结果
      final raw = await executor.run('toolshell_exec', {
        'command': 'git clone https://invalid.invalid/nowhere.git',
        'timeout': 10,
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(
        result['optimized'],
        isNot(true),
        reason: 'git clone 命中 _rtkSkipPrefixes，必须原样执行不包裹',
      );
    });

    test('非白名单命令 (echo) 不会被包裹', () async {
      final raw = await executor.run('toolshell_exec', {
        'command': 'echo rtk_test_marker',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(result['stdout'], contains('rtk_test_marker'));
      expect(
        result['optimized'],
        isNot(true),
        reason: 'echo 不在 _rtkWrapCommands 白名单里，必须原样执行',
      );
    });

    test('PowerShell 内联多语句脚本 (Write-Host 开头) 不会被包裹', () async {
      final raw = await executor.run('toolshell_exec', {
        'command': r'Write-Host "hello from ps"',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(
        result['optimized'],
        isNot(true),
        reason: 'Write-Host 是 PowerShell cmdlet，不在真实可执行文件白名单里',
      );
    });
  });

  group('rtk 不可用时的降级行为', () {
    test('rtk.exe 缺失场景下 optimized 字段永不出现 (逻辑自洽性检查)', () async {
      // 这个测试不真正卸载 rtk，而是复核判定条件本身的自洽性：
      // wasWrapped = (_rtkPath != null) && (effectiveCommand != command)
      // 只要 rtk 不可用，无论命令是否在白名单里，都不应该出现 optimized。
      // 用一个必定命中白名单的命令验证契约仍然只在 rtkAvailable 时为真。
      final raw = await executor.run('toolshell_exec', {
        'command': 'git --version',
      });
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['status'], 'ok');
      expect(result['optimized'] == true, rtkAvailable);
    });
  });
}

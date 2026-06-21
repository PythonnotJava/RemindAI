import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:path/path.dart' as p;

import '../memory/memory_manager.dart';
import '../memory/project_config.dart';
import 'schedule_executor.dart';
import 'system_executor.dart';

/// ToolShell 工具执行器 (Dart 原生实现)
/// 等价于 Python runtime/executor.py
class Executor {
  final String projectRoot;

  /// 本次对话指定的 Python 解释器路径 (可执行文件或其所在目录)。为空则用系统默认。
  final String pythonPath;

  /// 本次对话指定的 Node/npm 路径 (可执行文件或其所在目录)。为空则用系统默认。
  final String npmPath;

  /// 权限模式: normal 时写/删/执行需确认, auto 时自动执行
  final PermissionMode permissionMode;

  /// 权限确认回调 (normal 模式下触发)
  /// 返回 true=允许执行, false=拒绝
  final Future<bool> Function(String operation, Map<String, dynamic> args)?
  onPermissionRequest;

  /// 记忆管理器 (可选，启用长期记忆时由外部注入)
  final MemoryManager? memoryManager;

  /// 记忆所属的 collection 名称 (全局或项目级)
  final String? memoryCollection;

  /// 额外可读目录列表 (如已激活 skill 的安装目录)
  /// 这些目录下的文件只允许读取，不允许写入/删除
  final List<String> readableExtraPaths;

  /// 是否允许访问 projectRoot 之外的路径 (读/写/删/执行)。
  /// false (默认): 严格沙箱，越界路径直接拒绝 —— 用于无人值守的服务器会话。
  /// true: 解除目录边界限制，可操作任意绝对/相对路径 —— 用于交互式桌面会话
  /// (越界写/删/执行仍由权限中间件逐次确认，受保护文件名仍被拦截)。
  final bool allowOutsideRoot;

  late final ScheduleExecutor _scheduleExecutor;
  late final SystemExecutor _systemExecutor;

  static const _protected = ['.git', 'node_modules', '.env', '.env.local'];

  Executor({
    required this.projectRoot,
    this.pythonPath = '',
    this.npmPath = '',
    this.permissionMode = PermissionMode.normal,
    this.onPermissionRequest,
    this.memoryManager,
    this.memoryCollection,
    this.readableExtraPaths = const [],
    this.allowOutsideRoot = false,
  }) {
    _scheduleExecutor = ScheduleExecutor(projectRoot: projectRoot);
    _systemExecutor = SystemExecutor();
    _initBundledTools();
  }

  // ─── 内置工具路径 (rg / fd / rtk) ──────────────────────────

  String? _rgPath;
  String? _fdPath;
  String? _rtkPath;

  /// 初始化随包分发的 CLI 工具路径。
  void _initBundledTools() {
    final exeSuffix = Platform.isWindows ? '.exe' : '';
    for (final candidate in _bundledBinCandidates()) {
      final rg = p.join(candidate, 'rg$exeSuffix');
      final fd = p.join(candidate, 'fd$exeSuffix');
      final rtk = p.join(candidate, 'rtk$exeSuffix');
      if (_rgPath == null && File(rg).existsSync()) _rgPath = rg;
      if (_fdPath == null && File(fd).existsSync()) _fdPath = fd;
      if (_rtkPath == null && File(rtk).existsSync()) _rtkPath = rtk;
    }
    // 启动探测结果打印到终端，便于诊断 rtk 是否就位
    if (_rtkPath != null) {
      print('[RTK] ✓ 已找到 rtk: $_rtkPath');
    } else {
      print(
        '[RTK] ✗ 未找到 rtk.exe，命令输出压缩功能关闭。'
        '搜索路径: ${_bundledBinCandidates().join(", ")}',
      );
    }
  }

  /// assets/bin 候选目录（开发模式 + release 打包后）。
  List<String> _bundledBinCandidates() => [
    p.normalize(p.join(Directory.current.path, 'assets', 'bin')),
    p.normalize(
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'flutter_assets',
        'assets',
        'bin',
      ),
    ),
  ];

  /// 统一执行入口
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    try {
      // Schedule 工具路由 (无需权限确认)
      if (toolName.startsWith('schedule_')) {
        return await _scheduleExecutor.run(toolName, args);
      }

      // System 工具路由 (只读探测，无需权限确认)
      if (toolName.startsWith('system_')) {
        return await _systemExecutor.run(toolName, args);
      }

      // 读/搜索/记忆 = 无需确认; 写/删/执行/Python = normal 模式需确认
      if (permissionMode == PermissionMode.normal) {
        final needsApproval =
            toolName == 'toolshell_write' ||
            toolName == 'toolshell_delete' ||
            toolName == 'toolshell_exec' ||
            toolName == 'toolshell_run_python' ||
            toolName == 'toolshell_run_js';
        if (needsApproval && onPermissionRequest != null) {
          final approved = await onPermissionRequest!(toolName, args);
          if (!approved) {
            return _err('PERMISSION_DENIED', '用户拒绝了操作');
          }
        }
      }

      return switch (toolName) {
        'toolshell_read' => await _read(args),
        'toolshell_write' => await _write(args),
        'toolshell_delete' => await _delete(args),
        'toolshell_search' => await _search(args),
        'toolshell_exec' => await _exec(args),
        'toolshell_run_python' => await _runPython(args),
        'toolshell_run_js' => await _runJs(args),
        'toolshell_memory_store' => await _memStore(args),
        'toolshell_memory_recall' => await _memRecall(args),
        _ => _err('UNKNOWN_TOOL', toolName),
      };
    } catch (e) {
      return _err('EXCEPTION', e.toString());
    }
  }

  // ─── 路径安全 ─────────────────────────────────────────────

  /// 解析路径 — 默认限制在 projectRoot 内。
  /// allowOutsideRoot=true 时解除边界限制：绝对路径原样规范化，
  /// 相对路径仍以 projectRoot 为基准 join。
  String _resolve(String path) {
    // 解除边界：绝对路径直接用，相对路径相对 projectRoot 解析
    if (allowOutsideRoot) {
      return p.isAbsolute(path)
          ? p.normalize(path)
          : p.normalize(p.join(projectRoot, path));
    }
    final resolved = p.normalize(p.join(projectRoot, path));
    if (!p.isWithin(projectRoot, resolved) && resolved != projectRoot) {
      throw Exception('路径越界: $path');
    }
    return resolved;
  }

  /// 解析路径 (只读) — 允许 projectRoot + 额外可读路径
  /// 如果是绝对路径且在可读目录中，直接返回
  /// 否则回退到 _resolve (projectRoot 内 / 或解除边界)
  String _resolveReadable(String path) {
    // 绝对路径 → 检查是否在额外可读目录中
    if (p.isAbsolute(path)) {
      final normalized = p.normalize(path);
      for (final extra in readableExtraPaths) {
        if (p.isWithin(extra, normalized) || normalized == extra) {
          return normalized;
        }
      }
      // 不在可读范围内 → 仍尝试 _resolve (解除边界时直接放行)
    }
    return _resolve(path);
  }

  /// 受保护文件/目录拦截 —— 无论是否解除目录边界都生效。
  /// 解除边界后路径可能在 projectRoot 之外，故按路径的各段名匹配，
  /// 不再依赖相对 projectRoot 的前缀判断。
  bool _isProtected(String path) {
    final segments = p.split(p.normalize(path));
    return segments.any((seg) => _protected.contains(seg));
  }

  // ─── 文件操作 ─────────────────────────────────────────────

  Future<String> _read(Map<String, dynamic> args) async {
    final path = _resolveReadable(args['path']);
    final file = File(path);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', args['path']);

    final encoding = Encoding.getByName(args['encoding'] ?? 'utf-8') ?? utf8;
    final content = await file.readAsString(encoding: encoding);
    final lines = content.split('\n');
    final total = lines.length;

    String result = content;
    final start = args['start_line'] as int?;
    final end = args['end_line'] as int?;
    if (start != null || end != null) {
      final s = (start ?? 1) - 1;
      final e = end ?? total;
      result = lines.sublist(s.clamp(0, total), e.clamp(0, total)).join('\n');
    }

    return _ok({
      'content': result,
      'total_lines': total,
      'size': await file.length(),
    });
  }

  Future<String> _write(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    if (_isProtected(path)) return _err('PROTECTED_PATH', args['path']);

    final file = File(path);
    final mode = args['mode'] as String;
    final content = args['content'] as String;

    await file.parent.create(recursive: true);

    if (mode == 'create' && await file.exists()) {
      return _err('PATH_EXISTS', args['path']);
    }
    if (mode == 'append') {
      await file.writeAsString(content, mode: FileMode.append);
    } else {
      await file.writeAsString(content);
    }

    return _ok({
      'path': args['path'],
      'size': await file.length(),
      'mode': mode,
    });
  }

  Future<String> _delete(Map<String, dynamic> args) async {
    final path = _resolve(args['path']);
    if (_isProtected(path)) return _err('PROTECTED_PATH', args['path']);

    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      return _err('NOT_FOUND', args['path']);
    }

    final recursive = args['recursive'] == true;
    if (type == FileSystemEntityType.directory) {
      if (recursive) {
        await Directory(path).delete(recursive: true);
      } else {
        final dir = Directory(path);
        if (await dir.list().isEmpty) {
          await dir.delete();
        } else {
          return _err('NOT_EMPTY', args['path']);
        }
      }
    } else {
      await File(path).delete();
    }

    return _ok({'deleted': args['path']});
  }

  Future<String> _search(Map<String, dynamic> args) async {
    final pattern = args['pattern'] as String;
    final scope = _resolveReadable(args['scope'] ?? '.');
    final maxResults = args['max_results'] ?? 20;
    final contentRe = args['content'] as String?;

    final dir = Directory(scope);
    if (!await dir.exists()) return _err('SCOPE_NOT_FOUND', scope);

    // ── 有 content 参数 → 内容搜索，优先用 rg ──
    if (contentRe != null && contentRe.isNotEmpty) {
      if (_rgPath != null) {
        return _searchWithRg(contentRe, scope, pattern, maxResults as int);
      }
    }

    // ── 纯文件名搜索，优先用 fd ──
    if ((contentRe == null || contentRe.isEmpty) && _fdPath != null) {
      return _searchWithFd(pattern, scope, maxResults as int);
    }

    // ── Fallback: 纯 Dart 实现 ──
    return _searchDart(pattern, scope, maxResults as int, contentRe);
  }

  /// rg 内容搜索：输出格式 path:line:content，限制行数。
  Future<String> _searchWithRg(
    String contentPattern,
    String scope,
    String fileGlob,
    int maxResults,
  ) async {
    try {
      final args = <String>[
        '--no-heading', '--line-number', '--color', 'never',
        '--max-count', '5', // 每文件最多 5 行
        if (fileGlob != '*' && fileGlob != '**') ...['--glob', fileGlob],
        contentPattern,
        scope,
      ];
      final result = await Process.run(
        _rgPath!,
        args,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 15));

      // rg exit 1 = no matches, exit 2 = error
      if (result.exitCode == 2) {
        return _err('RG_ERROR', _decodeBytes(result.stderr).trim());
      }

      final lines = _decodeBytes(result.stdout)
          .split(RegExp(r'\r?\n'))
          .where((l) => l.isNotEmpty)
          .take(maxResults)
          .toList();

      final matches = lines.map((line) {
        final parts = line.split(':');
        if (parts.length >= 3) {
          final filePath = parts[0];
          final lineNo = parts[1];
          final text = parts.sublist(2).join(':').trim();
          return {
            'path': p.relative(filePath, from: projectRoot),
            'line': int.tryParse(lineNo),
            'text': text.length > 200 ? '${text.substring(0, 200)}...' : text,
          };
        }
        return {'text': line};
      }).toList();

      return _ok({'matches': matches, 'total': matches.length, 'engine': 'rg'});
    } catch (e) {
      // rg 执行失败 → 降级到 Dart
      return _searchDart('*', scope, maxResults, contentPattern);
    }
  }

  /// fd 文件名搜索：快速递归查找。
  Future<String> _searchWithFd(
    String pattern,
    String scope,
    int maxResults,
  ) async {
    try {
      final args = <String>[
        '--color',
        'never',
        '--max-results',
        maxResults.toString(),
        pattern,
        scope,
      ];
      final result = await Process.run(
        _fdPath!,
        args,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 15));

      final fdStdout = _decodeBytes(result.stdout);
      if (result.exitCode != 0 && fdStdout.isEmpty) {
        return _searchDart(pattern, scope, maxResults, null);
      }

      final lines = fdStdout
          .split(RegExp(r'\r?\n'))
          .where((l) => l.isNotEmpty)
          .toList();

      final matches = lines.map((line) {
        final full = p.normalize(line.trim());
        return {
          'path': p.relative(full, from: projectRoot),
          'type': FileSystemEntity.isDirectorySync(full) ? 'dir' : 'file',
        };
      }).toList();

      return _ok({'matches': matches, 'total': matches.length, 'engine': 'fd'});
    } catch (e) {
      // fd 执行失败 → 降级到 Dart
      return _searchDart(pattern, scope, maxResults, null);
    }
  }

  /// 纯 Dart fallback 搜索实现。
  Future<String> _searchDart(
    String pattern,
    String scope,
    int maxResults,
    String? contentRe,
  ) async {
    final matches = <Map<String, dynamic>>[];
    final glob = RegExp(
      pattern.replaceAll('.', r'\.').replaceAll('*', '.*').replaceAll('?', '.'),
    );

    await for (final entity in Directory(scope).list(recursive: true)) {
      final name = p.basename(entity.path);
      if (!glob.hasMatch(name)) continue;
      if (_isProtected(entity.path)) continue;

      if (contentRe != null && entity is File) {
        try {
          final text = await entity.readAsString();
          if (!RegExp(contentRe).hasMatch(text)) continue;
        } catch (_) {
          continue;
        }
      }

      matches.add({
        'path': p.relative(entity.path, from: projectRoot),
        'type': entity is Directory ? 'dir' : 'file',
        'size': entity is File ? await entity.length() : null,
      });

      if (matches.length >= maxResults) break;
    }

    return _ok({'matches': matches, 'total': matches.length, 'engine': 'dart'});
  }

  // ─── Shell 执行 ───────────────────────────────────────────

  /// 智能解码进程输出字节。
  /// 优先 UTF-8（严格模式），失败则回退 GBK（中文 Windows 默认编码），
  /// 再失败则用 UTF-8 宽松模式（非法字节替换为 ）。
  /// 解决中文 Windows 下命令输出为 GBK 导致 UTF-8 解码抛 FormatException 的问题。
  String _decodeBytes(dynamic raw) {
    if (raw is String) return raw;
    if (raw is! List<int>) return raw.toString();
    final bytes = raw;
    try {
      return utf8.decode(bytes); // 严格 UTF-8
    } catch (_) {}
    try {
      return gbk.decode(bytes); // 回退 GBK
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true); // 兜底
  }

  // ─── Shell 解析 ───────────────────────────────────────────

  /// 已解析的 shell 缓存 (进程级一次性探测)。
  static _ResolvedShell? _shellCache;

  /// 解析当前平台首选 shell。
  /// Windows: pwsh (PowerShell 7+, 支持 &&) > powershell (5.1) > cmd。
  /// Unix: bash > sh。
  Future<_ResolvedShell> _resolveShell() async {
    final cached = _shellCache;
    if (cached != null) return cached;

    _ResolvedShell resolved;
    if (Platform.isWindows) {
      if (await _existsOnPath('pwsh')) {
        // PowerShell 7+ 支持 && / || 链式
        resolved = const _ResolvedShell(
          _ShellKind.powershell,
          'pwsh',
          supportsChaining: true,
        );
      } else if (await _existsOnPath('powershell')) {
        // Windows PowerShell 5.1 不支持 && / ||
        resolved = const _ResolvedShell(
          _ShellKind.powershell,
          'powershell',
          supportsChaining: false,
        );
      } else {
        resolved = const _ResolvedShell(
          _ShellKind.cmd,
          'cmd',
          supportsChaining: true,
        );
      }
    } else {
      if (await _existsOnPath('bash')) {
        resolved = const _ResolvedShell(_ShellKind.bash, 'bash');
      } else {
        resolved = const _ResolvedShell(_ShellKind.sh, 'sh');
      }
    }

    print(
      '[Shell] 使用 ${resolved.executable} (chaining=${resolved.supportsChaining})',
    );
    _shellCache = resolved;
    return resolved;
  }

  /// 用 where/which 检测可执行文件是否在 PATH 中。
  Future<bool> _existsOnPath(String exe) async {
    try {
      final which = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(
        which,
        [exe],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 3));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 命令是否含链式操作符 (&& 或 ||)。
  bool _hasChaining(String command) =>
      command.contains('&&') || command.contains('||');

  /// 根据 shell 类型构建 (可执行文件, 参数列表)。
  (String, List<String>) _buildInvocation(
    _ResolvedShell shell,
    String command,
  ) {
    switch (shell.kind) {
      case _ShellKind.powershell:
        // -NoProfile 跳过用户配置加速启动; -Command 执行命令字符串
        return (
          shell.executable,
          ['-NoProfile', '-NonInteractive', '-Command', command],
        );
      case _ShellKind.cmd:
        return (shell.executable, ['/c', command]);
      case _ShellKind.bash:
      case _ShellKind.sh:
        return (shell.executable, ['-c', command]);
    }
  }

  Future<String> _exec(Map<String, dynamic> args) async {
    final command = args['command'] as String;
    final cwd = _resolve(args['cwd'] ?? '.');
    final timeout = Duration(seconds: (args['timeout'] ?? 120) as int);

    await Directory(cwd).create(recursive: true);

    // 构建环境变量：将指定的解释器目录前置到 PATH，优先使用本次对话指定版本
    final environment = _buildEnvironment();

    // 解析使用的 shell (一次性缓存)。
    // Windows: pwsh > powershell > cmd; Unix: bash > sh。
    final resolved = await _resolveShell();

    // Windows PowerShell 5.1 不支持 && / ||，遇到链式命令降级到 cmd 以保证兼容。
    var active = resolved;
    if (resolved.kind == _ShellKind.powershell &&
        !resolved.supportsChaining &&
        _hasChaining(command)) {
      active = const _ResolvedShell(
        _ShellKind.cmd,
        'cmd',
        supportsChaining: true,
      );
      print('[Shell] 链式命令降级 PowerShell → cmd: $command');
    }

    // 通过 rtk 包裹命令以压缩输出 (可用时)，降低 LLM token 消耗
    final effectiveCommand = _wrapWithRtk(command, active.kind);
    final invocation = _buildInvocation(active, effectiveCommand);

    try {
      final result = await Process.run(
        invocation.$1,
        invocation.$2,
        workingDirectory: cwd,
        environment: environment,
        stdoutEncoding: null, // 原始字节，自行智能解码
        stderrEncoding: null,
      ).timeout(timeout);

      final rawStdout = _decodeBytes(result.stdout);
      final rawStderr = _decodeBytes(result.stderr);

      // 打印执行完成后的输出规模，便于观察 rtk 压缩效果
      final wasWrapped = _rtkPath != null && effectiveCommand != command;
      print(
        '[RTK] 执行完成 exit=${result.exitCode} '
        '${wasWrapped ? "(经 rtk)" : "(未经 rtk)"} '
        'stdout=${rawStdout.length}字符 stderr=${rawStderr.length}字符',
      );

      final stdout = rawStdout.length > 8000
          ? rawStdout.substring(rawStdout.length - 8000)
          : rawStdout;
      final stderr = rawStderr.length > 4000
          ? rawStderr.substring(rawStderr.length - 4000)
          : rawStderr;

      return _ok({
        'exit_code': result.exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'truncated': rawStdout.length > 8000 || rawStderr.length > 4000,
        if (_rtkPath != null && effectiveCommand != command) 'optimized': true,
      });
    } on TimeoutException {
      return _err('TIMEOUT', '$command (>${timeout.inSeconds}s)');
    }
  }

  // ─── Python 代码执行 ──────────────────────────────────────────

  Future<String> _runPython(Map<String, dynamic> args) async {
    final code = args['code'] as String;
    final timeout = Duration(seconds: (args['timeout'] ?? 60) as int);

    // 创建临时目录用于脚本和输出
    final tmpDir = await Directory.systemTemp.createTemp('remindai_python_');
    final scriptFile = File(p.join(tmpDir.path, 'script.py'));
    final outputDir = p.join(tmpDir.path, 'output');
    await Directory(outputDir).create();

    // 注入 matplotlib 自动保存的 monkey-patch：
    // 拦截 plt.show() 和 plt.savefig()，将图片保存到 outputDir
    final patchedCode =
        '''
import sys, os
_output_dir = r"$outputDir"
_fig_counter = [0]

try:
    import matplotlib
    matplotlib.use("Agg")  # 非交互后端，不弹窗
    import matplotlib.pyplot as _plt

    _original_show = _plt.show
    _original_savefig = _plt.Figure.savefig

    def _patched_show(*args, **kwargs):
        for fig_num in _plt.get_fignums():
            fig = _plt.figure(fig_num)
            _fig_counter[0] += 1
            path = os.path.join(_output_dir, f"fig_{_fig_counter[0]}.png")
            fig.savefig(path, dpi=150, bbox_inches="tight")
        _plt.close("all")

    def _patched_savefig(self, fname, *args, **kwargs):
        _fig_counter[0] += 1
        path = os.path.join(_output_dir, f"fig_{_fig_counter[0]}.png")
        _original_savefig(self, path, *args, dpi=kwargs.pop("dpi", 150), bbox_inches=kwargs.pop("bbox_inches", "tight"), **kwargs)

    _plt.show = _patched_show
    _plt.Figure.savefig = _patched_savefig
except ImportError:
    pass

$code
''';

    await scriptFile.writeAsString(patchedCode, encoding: utf8);

    // 查找 Python 解释器
    final pythonCmd = await _findPython();
    if (pythonCmd == null) {
      await tmpDir.delete(recursive: true);
      return _err('PYTHON_NOT_FOUND', '未找到 Python 解释器 (python3/python)');
    }

    final environment = _buildEnvironment();

    try {
      final result = await Process.run(
        pythonCmd,
        [scriptFile.path],
        workingDirectory: projectRoot,
        environment: environment,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(timeout);

      // 收集输出的图片文件
      final outDir = Directory(outputDir);
      final images = <String>[];
      if (await outDir.exists()) {
        await for (final entity in outDir.list()) {
          if (entity is File && entity.path.endsWith('.png')) {
            images.add(entity.path);
          }
        }
        images.sort();
      }

      final rawStdout = _decodeBytes(result.stdout);
      final rawStderr = _decodeBytes(result.stderr);

      final stdout = rawStdout.length > 8000
          ? rawStdout.substring(rawStdout.length - 8000)
          : rawStdout;
      final stderr = rawStderr.length > 4000
          ? rawStderr.substring(rawStderr.length - 4000)
          : rawStderr;

      // 清理脚本文件（保留图片）
      await scriptFile.delete();

      return _ok({
        'exit_code': result.exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'images': images,
        'truncated': rawStdout.length > 8000 || rawStderr.length > 4000,
      });
    } on TimeoutException {
      await tmpDir.delete(recursive: true);
      return _err('TIMEOUT', 'Python 执行超时 (>${timeout.inSeconds}s)');
    }
  }

  /// 查找系统中可用的 Python 解释器
  Future<String?> _findPython() async {
    // 优先使用配置的 pythonPath
    if (pythonPath.isNotEmpty) {
      final file = File(pythonPath);
      if (await file.exists()) return pythonPath;
      // pythonPath 可能是目录，尝试拼接
      for (final name in ['python', 'python3']) {
        final candidate = p.join(
          pythonPath,
          Platform.isWindows ? '$name.exe' : name,
        );
        if (await File(candidate).exists()) return candidate;
      }
    }

    // 在 PATH 中搜索
    final names = Platform.isWindows
        ? ['python.exe', 'python3.exe']
        : ['python3', 'python'];
    for (final name in names) {
      try {
        final which = Platform.isWindows ? 'where' : 'which';
        final result = await Process.run(
          which,
          [name],
          stdoutEncoding: null,
          stderrEncoding: null,
        );
        if (result.exitCode == 0) {
          final path = _decodeBytes(
            result.stdout,
          ).trim().split('\n').first.trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
    }
    return null;
  }

  // ─── JavaScript/TypeScript 代码执行 ──────────────────────────────

  /// 检测代码是否使用了图表库，返回需要注入的依赖列表
  Map<String, String> _detectJsChartDeps(String code) {
    final deps = <String, String>{};
    // ECharts
    if (code.contains("echarts") ||
        code.contains("'echarts'") ||
        code.contains('"echarts"')) {
      deps['echarts'] = '^5.5.0';
      deps['@napi-rs/canvas'] = '^0.1.65';
    }
    // Chart.js
    if (code.contains("chart.js") ||
        code.contains("'chart.js'") ||
        code.contains('"chart.js"')) {
      deps['chart.js'] = '^4.4.0';
      deps['chartjs-node-canvas'] = '^4.1.6';
    }
    return deps;
  }

  /// 为 ECharts 代码注入无头渲染支持（SSR + canvas 输出 PNG）
  String _patchJsForChartRendering(String code, String outputDir) {
    // 如果代码中包含 echarts，注入 canvas 环境和自动保存逻辑
    if (!code.contains('echarts')) return code;

    // 将用户的 echarts.init(dom) 替换为无头 canvas 渲染
    return '''
import { createCanvas } from '@napi-rs/canvas';
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const _outputDir = ${_jsStringLiteral(outputDir)};
mkdirSync(_outputDir, { recursive: true });
let _figCounter = 0;

// Patch: 替换 echarts.init 使其使用 canvas 无头渲染
const _originalImport = await import('echarts');
const echarts = { ..._originalImport };

const _origInit = echarts.init;
const _charts = [];

echarts.init = function(dom, theme, opts) {
  const width = opts?.width || 800;
  const height = opts?.height || 600;
  const canvas = createCanvas(width, height);
  // ECharts 需要一个 canvas-like 对象
  const chart = _origInit.call(echarts, canvas, theme, {
    ...(opts || {}),
    width,
    height,
    renderer: 'canvas',
  });
  _charts.push({ chart, canvas, width, height });
  return chart;
};

// 用户代码开始 ─────────────────────────────────────
${code.replaceAll(RegExp(r'''import\s+\*\s+as\s+echarts\s+from\s+['"]echarts['"];?'''), '// [patched: echarts import above]').replaceAll(RegExp(r'''import\s+echarts\s+from\s+['"]echarts['"];?'''), '// [patched: echarts import above]').replaceAll(RegExp(r'''const\s*\{\s*[^}]+\}\s*=\s*require\s*\(\s*['"]echarts['"]\s*\)\s*;?'''), '// [patched: echarts require above]')}
// 用户代码结束 ─────────────────────────────────────

// 自动保存所有已渲染的图表为 PNG
for (const { chart, canvas } of _charts) {
  _figCounter++;
  const pngBuffer = canvas.toBuffer('image/png');
  const outPath = join(_outputDir, `fig_\${_figCounter}.png`);
  writeFileSync(outPath, pngBuffer);
  chart.dispose();
}

if (_figCounter > 0) {
  console.log(`[chart] Saved \${_figCounter} chart(s) to \${_outputDir}`);
}
''';
  }

  /// JS 字符串字面量转义
  String _jsStringLiteral(String s) {
    return "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";
  }

  Future<String> _runJs(Map<String, dynamic> args) async {
    final code = args['code'] as String;
    final runtimePref = (args['runtime'] ?? 'auto') as String;
    final timeout = Duration(seconds: (args['timeout'] ?? 60) as int);

    // 查找 JS 运行时
    final runtime = await _findJsRuntime(runtimePref);
    if (runtime == null) {
      return _err(
        'JS_RUNTIME_NOT_FOUND',
        '未找到 JavaScript 运行时 (bun/node)。请安装 bun 或 Node.js。',
      );
    }

    // 创建临时目录
    final tmpDir = await Directory.systemTemp.createTemp('remindai_js_');
    final outputDir = p.join(tmpDir.path, 'output');
    await Directory(outputDir).create();

    // 检测图表依赖
    final chartDeps = _detectJsChartDeps(code);
    final hasChartDeps = chartDeps.isNotEmpty;

    // 如果有图表依赖，创建 package.json 并安装
    if (hasChartDeps) {
      final packageJson = {
        'name': 'remindai-temp',
        'private': true,
        'type': 'module',
        'dependencies': chartDeps,
      };
      await File(
        p.join(tmpDir.path, 'package.json'),
      ).writeAsString(jsonEncode(packageJson), encoding: utf8);

      // 安装依赖
      final isBun = runtime.contains('bun');
      final installCmd = isBun ? 'bun' : 'npm';
      final installArgs = isBun ? ['install'] : ['install', '--prefer-offline'];

      try {
        final installResult = await Process.run(
          installCmd,
          installArgs,
          workingDirectory: tmpDir.path,
          stdoutEncoding: null,
          stderrEncoding: null,
        ).timeout(const Duration(seconds: 60));

        if (installResult.exitCode != 0) {
          await tmpDir.delete(recursive: true);
          return _err(
            'INSTALL_FAILED',
            '依赖安装失败 ($installCmd install):\n${_decodeBytes(installResult.stderr)}',
          );
        }
      } on TimeoutException {
        await tmpDir.delete(recursive: true);
        return _err('TIMEOUT', '依赖安装超时');
      }
    }

    // 处理代码：如果有图表库，注入渲染补丁
    String effectiveCode = code;
    if (chartDeps.containsKey('echarts')) {
      effectiveCode = _patchJsForChartRendering(code, outputDir);
    }

    // bun 原生支持 TS，node 用 .mjs (ESM)
    final ext = runtime.contains('bun') ? '.ts' : '.mjs';
    final scriptFile = File(p.join(tmpDir.path, 'script$ext'));
    await scriptFile.writeAsString(effectiveCode, encoding: utf8);

    final environment = _buildEnvironment();

    try {
      final result = await Process.run(
        runtime,
        ['run', scriptFile.path],
        workingDirectory: tmpDir.path,
        environment: environment,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(timeout);

      // 收集输出的图片文件
      final outDir = Directory(outputDir);
      final images = <String>[];
      if (await outDir.exists()) {
        await for (final entity in outDir.list()) {
          if (entity is File &&
              (entity.path.endsWith('.png') || entity.path.endsWith('.svg'))) {
            images.add(entity.path);
          }
        }
        images.sort();
      }

      final rawStdout = _decodeBytes(result.stdout);
      final rawStderr = _decodeBytes(result.stderr);

      final stdout = rawStdout.length > 8000
          ? rawStdout.substring(rawStdout.length - 8000)
          : rawStdout;
      final stderr = rawStderr.length > 4000
          ? rawStderr.substring(rawStderr.length - 4000)
          : rawStderr;

      // 清理脚本文件和 node_modules（保留输出图片）
      await scriptFile.delete();
      final nodeModules = Directory(p.join(tmpDir.path, 'node_modules'));
      if (await nodeModules.exists()) {
        await nodeModules.delete(recursive: true);
      }

      return _ok({
        'exit_code': result.exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'runtime': p.basename(runtime),
        'images': images,
        'truncated': rawStdout.length > 8000 || rawStderr.length > 4000,
      });
    } on TimeoutException {
      await tmpDir.delete(recursive: true);
      return _err('TIMEOUT', 'JS 执行超时 (>${timeout.inSeconds}s)');
    }
  }

  /// 查找系统中可用的 JS 运行时
  /// 优先级: bun > node (bun 更快且原生支持 TS)
  Future<String?> _findJsRuntime(String preference) async {
    List<String> candidates;
    switch (preference) {
      case 'bun':
        candidates = Platform.isWindows ? ['bun.exe'] : ['bun'];
      case 'node':
        candidates = Platform.isWindows ? ['node.exe'] : ['node'];
      default: // auto
        candidates = Platform.isWindows
            ? ['bun.exe', 'node.exe']
            : ['bun', 'node'];
    }

    // 优先检查配置的 npmPath 目录
    if (npmPath.isNotEmpty) {
      for (final name in candidates) {
        final candidate = p.join(npmPath, name);
        if (await File(candidate).exists()) return candidate;
      }
      // npmPath 本身可能就是可执行文件
      if (await File(npmPath).exists()) return npmPath;
    }

    // 在 PATH 中搜索
    for (final name in candidates) {
      try {
        final which = Platform.isWindows ? 'where' : 'which';
        final result = await Process.run(
          which,
          [name],
          stdoutEncoding: null,
          stderrEncoding: null,
        );
        if (result.exitCode == 0) {
          final path = _decodeBytes(
            result.stdout,
          ).trim().split('\n').first.trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 用 rtk 包裹命令以压缩输出。
  /// 仅包裹适合压缩的命令（git/ls/grep/test 等），不包裹交互式或管道复杂命令。
  /// rtk 对不认识的命令会透传执行，所以安全性有保证。
  String _wrapWithRtk(String command, _ShellKind shell) {
    if (_rtkPath == null) {
      print('[RTK] skip (rtk 不可用): $command');
      return command;
    }

    final trimmed = command.trim().toLowerCase();

    // 已经是 rtk 命令
    if (trimmed.startsWith('rtk ')) {
      print('[RTK] skip (已是 rtk 命令): $command');
      return command;
    }

    // 含重定向，rtk 可能干扰输出流
    if (command.contains('>') || command.contains('>>')) {
      print('[RTK] skip (含重定向): $command');
      return command;
    }

    // 纯 set 赋值命令 (cmd 的 set / PowerShell 不适用，但保持保守)
    if (trimmed.startsWith('set ')) {
      print('[RTK] skip (set 命令): $command');
      return command;
    }

    // ── cd X && Y 链式命令：保留 cd，包裹后续命令 ──
    if (trimmed.startsWith('cd ') && command.contains('&&')) {
      final parts = command.split('&&');
      final result = <String>[];
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i].trim();
        if (i == 0) {
          // 第一段是 cd，保持原样
          result.add(part);
        } else {
          // 后续命令尝试 rtk 包裹
          result.add(_wrapSingleCommand(part, shell));
        }
      }
      final joined = result.join(' && ');
      print('[RTK] ✓ 链式包裹: $command → $joined');
      return joined;
    }

    // 纯 cd 命令（不含 &&），无需包裹
    if (trimmed.startsWith('cd ')) {
      print('[RTK] skip (纯 cd 命令): $command');
      return command;
    }

    return _wrapSingleCommand(command, shell);
  }

  /// 不应被 rtk 包裹的命令前缀（这些命令的 stderr 输出会被 rtk 误处理）
  static const _rtkSkipPrefixes = ['git clone', 'git init'];

  /// rtk 有专门压缩过滤器的命令首词白名单。
  /// 只有这些命令才包裹 rtk —— 因为 rtk 通过启动子进程执行命令，
  /// 无法运行 shell 内建命令(exit/cd/set)或 PowerShell cmdlet(Get-*/Write-*)，
  /// 对它们包裹会导致执行失败。白名单全是真实可执行文件。
  static const _rtkWrapCommands = {
    'git',
    'cargo',
    'npm',
    'pnpm',
    'yarn',
    'npx',
    'node',
    'bun',
    'tsc',
    'next',
    'vitest',
    'playwright',
    'prettier',
    'eslint',
    'prisma',
    'docker',
    'kubectl',
    'curl',
    'wget',
    'rg',
    'fd',
    'grep',
    'find',
    'ls',
    'flutter',
    'dart',
    'pytest',
    'pip',
    'pip3',
    'python',
    'python3',
    'go',
    'gh',
    'make',
  };

  /// 提取命令首词 (去掉路径/扩展名)，用于白名单匹配。
  String _firstWord(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    final first = trimmed.split(RegExp(r'\s+')).first;
    // 去掉路径前缀和 .exe 扩展
    var word = first.split(RegExp(r'[/\\]')).last.toLowerCase();
    if (word.endsWith('.exe')) word = word.substring(0, word.length - 4);
    return word;
  }

  /// 包裹单条命令（不含 cd/链式逻辑）
  String _wrapSingleCommand(String command, _ShellKind shell) {
    final trimmed = command.trim().toLowerCase();

    // 跳过已知不兼容命令
    for (final prefix in _rtkSkipPrefixes) {
      if (trimmed.startsWith(prefix)) {
        print('[RTK] skip (不兼容命令): $command');
        return command;
      }
    }

    // 已经被 rtk 包裹
    if (trimmed.startsWith('rtk ')) return command;

    // 仅包裹白名单内、rtk 确有压缩过滤器的真实可执行命令。
    // 其它命令(shell 内建/PowerShell cmdlet/未知命令)原样执行，
    // 避免 rtk 子进程模型无法运行它们导致失败。
    final head = _firstWord(command);
    if (!_rtkWrapCommands.contains(head)) {
      print('[RTK] skip (非白名单命令: $head): $command');
      return command;
    }

    final String wrapped;
    final hasSpace = _rtkPath!.contains(' ');
    switch (shell) {
      case _ShellKind.powershell:
        // PowerShell: 含空格路径需用 & 调用操作符 + 引号
        //   & "C:\path with space\rtk.exe" args
        // 无空格可直接拼接 (但用 & 更稳妥)
        wrapped = hasSpace ? '& "$_rtkPath" $command' : '$_rtkPath $command';
      case _ShellKind.cmd:
        // Windows cmd /c 对引号的解析很特殊：
        //   cmd /c "C:\path\rtk.exe" arg  ← 引号被 cmd 吃掉导致路径断裂
        //   cmd /c C:\path\rtk.exe arg    ← 无空格路径直接用效果最好
        // 所以：无空格路径不加引号；含空格时整条命令外层再包一对引号
        wrapped = hasSpace ? '""$_rtkPath" $command"' : '$_rtkPath $command';
      case _ShellKind.bash:
      case _ShellKind.sh:
        // POSIX shell: 含空格路径用单引号
        wrapped = hasSpace ? "'$_rtkPath' $command" : '$_rtkPath $command';
    }
    print('[RTK] ✓ 包裹命令: $command');
    return wrapped;
  }

  /// 构建执行环境变量。
  /// 将指定的 Python / Node 解释器所在目录前置到 PATH，
  /// 使得 python/pip/npm/npx/node 优先解析到本次对话指定的版本。
  /// 若未指定任何解释器，返回 null（继承当前进程环境）。
  Map<String, String>? _buildEnvironment() {
    final prefixDirs = <String>[];

    // 注入 assets/bin/ (rg/fd/rtk 所在目录)
    if (_rgPath != null) {
      final binDir = p.dirname(_rgPath!);
      if (!prefixDirs.contains(binDir)) prefixDirs.add(binDir);
    } else if (_fdPath != null) {
      final binDir = p.dirname(_fdPath!);
      if (!prefixDirs.contains(binDir)) prefixDirs.add(binDir);
    } else if (_rtkPath != null) {
      final binDir = p.dirname(_rtkPath!);
      if (!prefixDirs.contains(binDir)) prefixDirs.add(binDir);
    }

    void addPath(String raw) {
      if (raw.trim().isEmpty) return;
      final path = raw.trim();
      // 如果传入的是可执行文件，取其所在目录；否则当作目录
      final dir = FileSystemEntity.isDirectorySync(path)
          ? path
          : p.dirname(path);
      if (dir.isNotEmpty && !prefixDirs.contains(dir)) {
        prefixDirs.add(dir);
      }
    }

    addPath(pythonPath);
    addPath(npmPath);

    if (prefixDirs.isEmpty) return null;

    // 找到现有 PATH（Windows 大小写不敏感，键名可能是 Path）
    final env = Map<String, String>.from(Platform.environment);
    final sep = Platform.isWindows ? ';' : ':';

    String pathKey = 'PATH';
    String existing = '';
    for (final entry in env.entries) {
      if (entry.key.toUpperCase() == 'PATH') {
        pathKey = entry.key;
        existing = entry.value;
        break;
      }
    }

    env[pathKey] = '${prefixDirs.join(sep)}$sep$existing';
    return env;
  }

  // ─── 记忆操作 ─────────────────────────────────────────────

  Future<String> _memStore(Map<String, dynamic> args) async {
    if (memoryManager == null || memoryCollection == null) {
      return _err('MEMORY_DISABLED', '当前未启用长期记忆 (需配置 memory.json)');
    }
    final text = args['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      return _err('INVALID_ARGS', '缺少 text 参数');
    }
    try {
      final metadata = <String, dynamic>{};
      if (args['source'] != null) metadata['source'] = args['source'];
      if (args['tags'] != null) metadata['tags'] = args['tags'];

      final pointId = await memoryManager!.store(
        text: text,
        collectionName: memoryCollection!,
        metadata: metadata,
      );
      return _ok({'memory_id': pointId, 'collection': memoryCollection});
    } catch (e) {
      return _err('MEMORY_STORE_ERROR', e.toString());
    }
  }

  Future<String> _memRecall(Map<String, dynamic> args) async {
    if (memoryManager == null || memoryCollection == null) {
      return jsonEncode({'memories': [], 'note': '长期记忆未启用'});
    }
    final query = args['query'] as String?;
    if (query == null || query.trim().isEmpty) {
      return _err('INVALID_ARGS', '缺少 query 参数');
    }
    try {
      final topK = args['top_k'] as int? ?? 5;
      final threshold = (args['threshold'] as num?)?.toDouble() ?? 0.7;

      final results = await memoryManager!.recall(
        query: query,
        collectionName: memoryCollection!,
        topK: topK,
        scoreThreshold: threshold,
      );
      return jsonEncode({'memories': results});
    } catch (e) {
      return _err('MEMORY_RECALL_ERROR', e.toString());
    }
  }

  // ─── 工具方法 ─────────────────────────────────────────────

  String _ok(Map<String, dynamic> data) =>
      jsonEncode({'status': 'ok', ...data});

  String _err(String code, String detail) =>
      jsonEncode({'status': 'error', 'code': code, 'detail': detail});
}

/// shell 类型
enum _ShellKind { powershell, cmd, bash, sh }

/// 已解析的 shell 信息
class _ResolvedShell {
  final _ShellKind kind;

  /// 调用用的可执行文件名 (pwsh / powershell / cmd / bash / sh)
  final String executable;

  /// 是否支持 && / || 链式 (PowerShell 5.1 不支持)
  final bool supportsChaining;

  const _ResolvedShell(
    this.kind,
    this.executable, {
    this.supportsChaining = true,
  });
}

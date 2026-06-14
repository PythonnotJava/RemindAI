import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
            toolName == 'toolshell_run_python';
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
        'toolshell_memory_store' => await _memStore(args),
        'toolshell_memory_recall' => await _memRecall(args),
        _ => _err('UNKNOWN_TOOL', toolName),
      };
    } catch (e) {
      return _err('EXCEPTION', e.toString());
    }
  }

  // ─── 路径安全 ─────────────────────────────────────────────

  /// 解析路径 — 限制在 projectRoot 内
  String _resolve(String path) {
    final resolved = p.normalize(p.join(projectRoot, path));
    if (!p.isWithin(projectRoot, resolved) && resolved != projectRoot) {
      throw Exception('路径越界: $path');
    }
    return resolved;
  }

  /// 解析路径 (只读) — 允许 projectRoot + 额外可读路径
  /// 如果是绝对路径且在可读目录中，直接返回
  /// 否则回退到 _resolve (projectRoot 内)
  String _resolveReadable(String path) {
    // 绝对路径 → 检查是否在额外可读目录中
    if (p.isAbsolute(path)) {
      final normalized = p.normalize(path);
      for (final extra in readableExtraPaths) {
        if (p.isWithin(extra, normalized) || normalized == extra) {
          return normalized;
        }
      }
      // 不在可读范围内 → 仍尝试 projectRoot
    }
    return _resolve(path);
  }

  bool _isProtected(String path) {
    final rel = p.relative(path, from: projectRoot);
    return _protected.any(
      (pat) => rel.startsWith(pat) || rel.contains('/$pat'),
    );
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));

      // rg exit 1 = no matches, exit 2 = error
      if (result.exitCode == 2) {
        return _err('RG_ERROR', (result.stderr as String).trim());
      }

      final lines = (result.stdout as String)
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0 && (result.stdout as String).isEmpty) {
        return _searchDart(pattern, scope, maxResults, null);
      }

      final lines = (result.stdout as String)
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

  Future<String> _exec(Map<String, dynamic> args) async {
    final command = args['command'] as String;
    final cwd = _resolve(args['cwd'] ?? '.');
    final timeout = Duration(seconds: (args['timeout'] ?? 120) as int);

    await Directory(cwd).create(recursive: true);

    // 构建环境变量：将指定的解释器目录前置到 PATH，优先使用本次对话指定版本
    final environment = _buildEnvironment();

    // 通过 rtk 包裹命令以压缩输出 (可用时)，降低 LLM token 消耗
    final effectiveCommand = _wrapWithRtk(command);

    try {
      final result = await Process.run(
        Platform.isWindows ? 'cmd' : 'sh',
        Platform.isWindows
            ? ['/c', effectiveCommand]
            : ['-c', effectiveCommand],
        workingDirectory: cwd,
        environment: environment,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);

      final stdout = result.stdout.length > 8000
          ? result.stdout.substring(result.stdout.length - 8000)
          : result.stdout;
      final stderr = result.stderr.length > 4000
          ? result.stderr.substring(result.stderr.length - 4000)
          : result.stderr;

      return _ok({
        'exit_code': result.exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'truncated': result.stdout.length > 8000 || result.stderr.length > 4000,
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
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
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

      final stdout = result.stdout.length > 8000
          ? result.stdout.substring(result.stdout.length - 8000)
          : result.stdout;
      final stderr = result.stderr.length > 4000
          ? result.stderr.substring(result.stderr.length - 4000)
          : result.stderr;

      // 清理脚本文件（保留图片）
      await scriptFile.delete();

      return _ok({
        'exit_code': result.exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'images': images,
        'truncated': result.stdout.length > 8000 || result.stderr.length > 4000,
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
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (result.exitCode == 0) {
          final path = (result.stdout as String)
              .trim()
              .split('\n')
              .first
              .trim();
          if (path.isNotEmpty) return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 用 rtk 包裹命令以压缩输出。
  /// 仅包裹适合压缩的命令（git/ls/grep/test 等），不包裹交互式或管道复杂命令。
  /// rtk 对不认识的命令会透传执行，所以安全性有保证。
  String _wrapWithRtk(String command) {
    if (_rtkPath == null) return command;

    // 不包裹的场景：
    // - 已经是 rtk 开头
    // - 包含重定向/管道到文件 (>)
    // - cd 命令
    // - 纯赋值命令
    final trimmed = command.trim().toLowerCase();
    if (trimmed.startsWith('rtk ')) return command;
    if (command.contains('>') || command.contains('>>')) return command;
    if (trimmed.startsWith('cd ') || trimmed.startsWith('set ')) return command;

    // 用 rtk 的绝对路径包裹，保证找到自带的 rtk
    return '"$_rtkPath" $command';
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

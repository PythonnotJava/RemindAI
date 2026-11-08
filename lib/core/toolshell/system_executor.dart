import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// System 技能执行器 — 探测系统开发环境
class SystemExecutor {
  /// 敏感环境变量关键词 (匹配到的只报告存在性，不返回值)
  static const _sensitivePatterns = [
    'KEY',
    'SECRET',
    'TOKEN',
    'PASSWORD',
    'PASS',
    'CREDENTIAL',
    'AUTH',
    'PRIVATE',
    'CERTIFICATE',
  ];

  /// 各类别对应要探测的工具列表
  static const _toolCategories = <String, List<String>>{
    'runtime': [
      'node',
      'python',
      'python3',
      'java',
      'go',
      'rustc',
      'dotnet',
      'ruby',
      'php',
      'perl',
      'lua',
    ],
    'package_manager': [
      'npm',
      'pnpm',
      'yarn',
      'bun',
      'pip',
      'pip3',
      'cargo',
      'maven',
      'gradle',
      'composer',
      'gem',
      'nuget',
    ],
    'vcs': ['git', 'svn', 'hg'],
    'build': [
      'cmake',
      'make',
      'msbuild',
      'ninja',
      'flutter',
      'dart',
      'gcc',
      'g++',
      'cl',
      'clang',
    ],
    'container': ['docker', 'podman', 'kubectl', 'helm', 'docker-compose'],
    'search': ['rg', 'fd', 'fzf', 'grep', 'findstr', 'ag'],
    'editor': ['code', 'vim', 'nvim', 'nano', 'emacs', 'subl', 'idea'],
    'db': ['sqlite3', 'psql', 'mysql', 'redis-cli', 'mongosh', 'mongo'],
    'network': ['curl', 'wget', 'ssh', 'openssl', 'nmap', 'nc'],
    'doc': ['pandoc', 'xelatex', 'pdflatex', 'typst', 'wkhtmltopdf'],
    'android': [
      'adb',
      'emulator',
      'sdkmanager',
      'avdmanager',
      'aapt2',
      'scrcpy',
    ],
  };

  /// 版本参数映射 (部分工具用不同的参数获取版本)
  static const _versionFlags = <String, String>{
    'java': '-version',
    'rustc': '--version',
    'flutter': '--version',
    'dart': '--version',
    'dotnet': '--version',
    'cl': '', // cl 无参数即输出版本
  };

  Future<String> run(String toolName, Map<String, dynamic> args) async {
    try {
      return switch (toolName) {
        'system_probe' => await _probe(args),
        'system_env' => await _env(args),
        _ => _err('UNKNOWN_TOOL', toolName),
      };
    } catch (e) {
      return _err('EXCEPTION', e.toString());
    }
  }

  // ─── system_probe ─────────────────────────────────────────

  Future<String> _probe(Map<String, dynamic> args) async {
    final category = args['category'] as String? ?? 'all';

    if (category == 'custom') {
      final tools = (args['tools'] as List?)?.cast<String>() ?? [];
      if (tools.isEmpty) {
        return _err('INVALID_ARGS', 'category=custom 时必须提供 tools 列表');
      }
      final results = await _probeTools(tools);
      return _ok({'category': 'custom', 'tools': results});
    }

    if (category == 'all') {
      // 类别之间同样互不依赖，一并并发探测 (而不是11个类别逐个串行、
      // 每个类别内部再并发)，否则总耗时仍是"类别数 × 单类别耗时"。
      final categories = _toolCategories.entries.toList();
      final perCategoryResults = await Future.wait(
        categories.map((entry) => _probeTools(entry.value)),
      );
      final allResults = <String, dynamic>{
        for (var i = 0; i < categories.length; i++)
          categories[i].key: perCategoryResults[i],
      };
      // 附加系统基本信息
      allResults['system'] = {
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart_version': Platform.version.split(' ').first,
        'locale': Platform.localeName,
        'home':
            Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '',
        'shell':
            Platform.environment['SHELL'] ??
            Platform.environment['COMSPEC'] ??
            '',
      };
      // Android 设备/SDK：模型装应用前最需要的一条信息，顺手带上。
      allResults['android_devices'] = await _androidDetails();
      return _ok(allResults);
    }

    // 单类别
    final tools = _toolCategories[category];
    if (tools == null) {
      return _err('INVALID_CATEGORY', '未知类别: $category');
    }
    final results = await _probeTools(tools);
    if (category == 'android') {
      return _ok({
        'category': category,
        'tools': results,
        ...await _androidDetails(),
      });
    }
    return _ok({'category': category, 'tools': results});
  }

  /// Android 环境：SDK 环境变量 + 当前已连接设备（`adb devices -l`）。
  ///
  /// 为什么单独做：模型准备 `adb install` 时最常见的两个坑是"不知道 SDK/adb 在哪"
  /// 和"连着多台设备导致 more than one device"。先探测一次就能省掉几轮试错，
  /// 也让它在多设备时知道该传 `env: {"ANDROID_SERIAL": "..."}`。
  Future<Map<String, dynamic>> _androidDetails() async {
    final env = <String, String>{};
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME']) {
      final value = Platform.environment[key];
      if (value != null && value.trim().isNotEmpty) env[key] = value;
    }

    final result = <String, dynamic>{'env': env};
    try {
      final run = await Process.run(
        'adb',
        ['devices', '-l'],
      ).timeout(const Duration(seconds: 6));
      final raw = '${run.stdout}'.trim();
      final devices = <Map<String, String>>[];
      for (final line in raw.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('List of devices')) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final device = <String, String>{
          'serial': parts.first,
          'state': parts[1],
        };
        for (final part in parts.skip(2)) {
          final idx = part.indexOf(':');
          if (idx > 0) {
            device[part.substring(0, idx)] = part.substring(idx + 1);
          }
        }
        devices.add(device);
      }
      result['devices'] = devices;
      result['exit_code'] = run.exitCode;
      final stderr = '${run.stderr}'.trim();
      if (stderr.isNotEmpty) result['stderr'] = stderr;
    } on TimeoutException {
      result['devices_error'] = 'adb devices 超时（6s）';
    } catch (e) {
      result['devices_error'] = '$e';
    }
    return result;
  }

  /// 批量探测工具列表，返回每个工具的探测结果。
  ///
  /// 每个工具的探测都是独立的只读子进程调用 (where/which + --version)，
  /// 互不依赖、无共享状态，因此并发执行是安全的——不存在资源竞态问题
  /// (对照 toolshell_run_parallel 对写/删/执行类工具的顾虑，这里没有那种风险)。
  /// 并发后 category=all 时(11个类别、五六十个工具)的总耗时约等于最慢的
  /// 单个探测，而不是所有探测耗时之和。
  Future<List<Map<String, dynamic>>> _probeTools(List<String> tools) async {
    return Future.wait(tools.map(_probeSingle));
  }

  /// 探测单个工具: 查找路径 + 获取版本
  Future<Map<String, dynamic>> _probeSingle(String tool) async {
    final locateCmd = Platform.isWindows ? 'where' : 'which';
    try {
      final locateResult = await Process.run(locateCmd, [
        tool,
      ], runInShell: true).timeout(const Duration(seconds: 3));

      if (locateResult.exitCode != 0) {
        return {'name': tool, 'found': false};
      }

      final path = (locateResult.stdout as String)
          .trim()
          .split('\n')
          .first
          .trim();

      // 尝试获取版本
      final version = await _getVersion(tool);

      final result = <String, dynamic>{
        'name': tool,
        'found': true,
        'path': path,
      };
      if (version != null) result['version'] = version;
      return result;
    } on TimeoutException {
      return {'name': tool, 'found': false, 'reason': 'timeout'};
    } catch (_) {
      return {'name': tool, 'found': false};
    }
  }

  /// 获取工具版本号
  Future<String?> _getVersion(String tool) async {
    final flag = _versionFlags[tool] ?? '--version';
    // cl.exe 无参数时输出到 stderr，特殊处理
    if (flag.isEmpty) return null;

    try {
      final result = await Process.run(tool, [
        flag,
      ], runInShell: true).timeout(const Duration(seconds: 3));

      final output =
          ((result.stdout as String).trim().isNotEmpty
                  ? result.stdout as String
                  : result.stderr as String)
              .trim();

      if (output.isEmpty) return null;

      // 提取版本号 (取第一行，截取合理长度)
      final firstLine = output.split('\n').first.trim();
      return firstLine.length > 120 ? firstLine.substring(0, 120) : firstLine;
    } catch (_) {
      return null;
    }
  }

  // ─── system_env ───────────────────────────────────────────

  Future<String> _env(Map<String, dynamic> args) async {
    final name = args['name'] as String?;
    final listAll = args['list_all'] as bool? ?? false;

    if (name != null && name.isNotEmpty) {
      // 查询单个变量
      final value = Platform.environment[name];
      if (value == null) {
        return _ok({'name': name, 'exists': false});
      }
      if (_isSensitive(name)) {
        return _ok({
          'name': name,
          'exists': true,
          'masked': true,
          'hint': '(已设置，值已脱敏)',
        });
      }
      return _ok({'name': name, 'exists': true, 'value': value});
    }

    if (listAll) {
      // 列出所有变量
      final env = <Map<String, dynamic>>[];
      final sorted = Platform.environment.keys.toList()..sort();
      for (final key in sorted) {
        if (_isSensitive(key)) {
          env.add({'name': key, 'masked': true});
        } else {
          final val = Platform.environment[key]!;
          // 截断过长的值 (如 PATH)
          env.add({
            'name': key,
            'value': val.length > 500 ? '${val.substring(0, 500)}...' : val,
          });
        }
      }
      return _ok({'count': env.length, 'variables': env});
    }

    // 默认: 列出常用开发相关变量
    final devVars = [
      'PATH',
      'HOME',
      'USERPROFILE',
      'SHELL',
      'COMSPEC',
      'JAVA_HOME',
      'GOPATH',
      'GOROOT',
      'CARGO_HOME',
      'RUSTUP_HOME',
      'PYTHON_HOME',
      'PYTHONPATH',
      'NODE_PATH',
      'NVM_DIR',
      'ANDROID_HOME',
      'FLUTTER_ROOT',
      'DART_SDK',
      'HTTP_PROXY',
      'HTTPS_PROXY',
      'NO_PROXY',
      'EDITOR',
      'VISUAL',
      'TERM',
      'LANG',
    ];

    final results = <Map<String, dynamic>>[];
    for (final key in devVars) {
      final value = Platform.environment[key];
      if (value != null) {
        results.add({
          'name': key,
          'value': value.length > 300 ? '${value.substring(0, 300)}...' : value,
        });
      }
    }
    return _ok({'count': results.length, 'variables': results});
  }

  /// 判断变量名是否为敏感信息
  bool _isSensitive(String name) {
    final upper = name.toUpperCase();
    return _sensitivePatterns.any((pat) => upper.contains(pat));
  }

  // ─── 工具方法 ─────────────────────────────────────────────

  String _ok(dynamic data) =>
      jsonEncode({'status': 'ok', ...data as Map<String, dynamic>});
  String _err(String code, String detail) =>
      jsonEncode({'status': 'error', 'code': code, 'detail': detail});
}

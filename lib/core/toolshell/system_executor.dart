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
      final allResults = <String, dynamic>{};
      for (final entry in _toolCategories.entries) {
        allResults[entry.key] = await _probeTools(entry.value);
      }
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
      return _ok(allResults);
    }

    // 单类别
    final tools = _toolCategories[category];
    if (tools == null) {
      return _err('INVALID_CATEGORY', '未知类别: $category');
    }
    final results = await _probeTools(tools);
    return _ok({'category': category, 'tools': results});
  }

  /// 批量探测工具列表，返回每个工具的探测结果
  Future<List<Map<String, dynamic>>> _probeTools(List<String> tools) async {
    final results = <Map<String, dynamic>>[];
    for (final tool in tools) {
      results.add(await _probeSingle(tool));
    }
    return results;
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

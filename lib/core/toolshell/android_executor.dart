import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一个可点击的 UI 节点（从 `uiautomator dump` 解析出来的精简视图）。
class UiNode {
  const UiNode({
    required this.text,
    required this.desc,
    required this.className,
    required this.package,
    required this.resourceId,
    required this.bounds,
    required this.clickable,
    required this.checkable,
    required this.checked,
    required this.enabled,
  });

  final String text;
  final String desc;
  final String className;
  final String package;
  final String resourceId;
  final String bounds;
  final bool clickable;
  final bool checkable;
  final bool checked;
  final bool enabled;

  /// 节点中心点（点这里等价于点这个控件）。
  int get centerX => ((boundsModel.$1 + boundsModel.$3) ~/ 2);
  int get centerY => ((boundsModel.$2 + boundsModel.$4) ~/ 2);

  (int, int, int, int) get boundsModel => parseBounds(bounds);

  /// 用于去重/日志的短标签。
  String get label {
    if (text.isNotEmpty) return text;
    if (desc.isNotEmpty) return desc;
    if (resourceId.isNotEmpty) return resourceId;
    return className.split('.').last;
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'desc': desc,
    'class': className,
    'package': package,
    'resource_id': resourceId,
    'bounds': bounds,
    'center': [centerX, centerY],
    'clickable': clickable,
    'checkable': checkable,
    'checked': checked,
    'enabled': enabled,
  };
}

/// 解析 `bounds="[x1,y1][x2,y2]"`。
(int, int, int, int) parseBounds(String raw) {
  final match = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]').firstMatch(raw);
  if (match == null) return (0, 0, 0, 0);
  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
  );
}

/// 从 `uiautomator dump` 的 XML 里抽取"有信息量"的节点。
///
/// 只保留有文本/描述、可点击、可勾选的节点：整棵树的原始 XML 动辄几千个节点
/// 几万字符，模型读不动；精简后一般只剩几十条，正好能判断"现在卡在哪个弹窗"。
///
/// 解析用正则而不是完整 XML 解析器：uiautomator 的输出是单行、属性值里的
/// 引号都被转义成 `&quot;`，所以 `<node ... />` 的属性抽取是安全的；
/// 这样也不用为一个工具给 pubspec 新增依赖。
List<UiNode> extractUiNodes(String xmlText) {
  final nodeTag = RegExp(r'<node\b([^>]*?)/?>');
  final attribute = RegExp(r'([\w-]+)="([^"]*)"');

  final nodes = <UiNode>[];
  for (final tag in nodeTag.allMatches(xmlText)) {
    final attrs = <String, String>{};
    for (final match in attribute.allMatches(tag.group(1)!)) {
      attrs[match.group(1)!] = _unescapeXml(match.group(2)!);
    }

    final text = attrs['text'] ?? '';
    final desc = attrs['content-desc'] ?? '';
    final clickable = attrs['clickable'] == 'true';
    final checkable = attrs['checkable'] == 'true';
    if (text.isEmpty && desc.isEmpty && !clickable && !checkable) continue;

    nodes.add(
      UiNode(
        text: text,
        desc: desc,
        className: attrs['class'] ?? '',
        package: attrs['package'] ?? '',
        resourceId: attrs['resource-id'] ?? '',
        bounds: attrs['bounds'] ?? '[0,0][0,0]',
        clickable: clickable,
        checkable: checkable,
        checked: attrs['checked'] == 'true',
        enabled: attrs['enabled'] != 'false',
      ),
    );
  }
  return nodes;
}

String _unescapeXml(String raw) {
  if (!raw.contains('&')) return raw;
  return raw
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// 安装确认弹窗里"需要先勾选"的文案特征（vivo/OPPO/小米/华为各有变体）。
const List<String> kRiskCheckboxPatterns = <String>[
  '已了解风险',
  '已了解',
  '风险检测',
  '风险提示',
  '我已阅读',
  '我已了解',
  '同意并继续',
  '同意',
];

/// 安装确认弹窗里"继续/安装"按钮的文案特征（长词优先，避免点到"取消安装"）。
const List<String> kInstallConfirmPatterns = <String>[
  '继续安装',
  '立即安装',
  '确认安装',
  '开始安装',
  '安装',
  '确定',
  '允许',
  '始终允许',
  '继续',
];

/// 绝不能点的文案（防止误触取消/拒绝）。
const List<String> kNeverTapPatterns = <String>[
  '取消',
  '拒绝',
  '禁止',
  '放弃',
  '暂不',
  '稍后',
  '关闭',
  '退出',
];

/// 安装流程中需要自动点击的目标。
class InstallTapTarget {
  const InstallTapTarget({required this.node, required this.reason});

  final UiNode node;
  final String reason;
}

/// 从当前屏幕节点里挑出下一步该点的控件。
///
/// 优先级：未勾选的风险勾选框 → 安装/继续按钮。
/// 返回 null 表示"屏幕上没有需要处理的东西"。
InstallTapTarget? pickInstallTarget(List<UiNode> nodes) {
  bool blocked(UiNode node) => kNeverTapPatterns.any(node.label.contains);

  /// 同一个文案可能出现多次（静态标题 + 真正的勾选框）。可勾选/可点击的
  /// 才是能生效的控件，纯文本标签点上去往往没反应，所以按"可操作性"打分。
  int score(UiNode node) {
    if (!node.enabled) return -1;
    if (node.checkable && !node.checked) return 3;
    if (node.clickable) return 2;
    return 1;
  }

  // 1) 勾选框：必须是可勾选且当前未勾选（已勾选就别再点，否则会取消勾选）
  //
  // 只认"能操作的"节点（可勾选/可点击）。弹窗里往往还有一个静态标题
  // "风险检测结果"，它同样命中关键词，但点它没有任何效果——如果把它当成
  // 勾选框，就会陷入"点了没反应 → 再点"的死循环。
  InstallTapTarget? checkbox;
  var checkboxScore = 1; // 只接受 score >= 2（可勾选 / 可点击）
  for (final node in nodes) {
    if (blocked(node)) continue;
    final label = '${node.text}${node.desc}';
    if (label.isEmpty) continue;
    if (!kRiskCheckboxPatterns.any(label.contains)) continue;
    if (node.checkable && node.checked) continue;
    final s = score(node);
    if (s > checkboxScore) {
      checkboxScore = s;
      checkbox = InstallTapTarget(node: node, reason: '勾选风险确认: ${node.label}');
    }
  }
  if (checkbox != null) return checkbox;

  // 2) 安装/继续按钮：先比"文案长度"（继续安装 > 安装），再比可操作性
  InstallTapTarget? best;
  var bestLen = 0;
  var bestScore = 0;
  for (final node in nodes) {
    if (blocked(node)) continue;
    final label = '${node.text}${node.desc}';
    if (label.isEmpty) continue;
    final s = score(node);
    if (s < 0) continue;
    for (final pattern in kInstallConfirmPatterns) {
      if (!label.contains(pattern)) continue;
      final len = pattern.length;
      if (len > bestLen || (len == bestLen && s > bestScore)) {
        bestLen = len;
        bestScore = s;
        best = InstallTapTarget(node: node, reason: '确认安装: ${node.label}');
      }
    }
  }
  if (best != null) return best;

  // 3) 最后兜底：只有纯文本标签可点（有些 ROM 把整行做成可点、文字在子节点）
  for (final node in nodes) {
    if (blocked(node)) continue;
    if (node.checkable && node.checked) continue;
    final label = '${node.text}${node.desc}';
    if (label.isEmpty) continue;
    if (!kRiskCheckboxPatterns.any(label.contains)) continue;
    return InstallTapTarget(node: node, reason: '勾选风险确认: ${node.label}');
  }
  return null;
}

/// Android 设备自动化：读屏幕、点控件、装 APK（含自动勾选风险确认）。
///
/// 为什么要单独做：`adb install` 在国产 ROM 上会被"安装确认弹窗"挡住
/// （vivo 的"风险检测结果 → 已了解风险"，小米的"继续安装"等）。这个弹窗是
/// 系统应用画的，`pm install` 只会卡住直到超时；截图又是 PNG，文本模型看不了。
/// 唯一可靠的办法是 `uiautomator dump` 拿到文本节点 → `input tap` 点掉它。
class AndroidExecutor {
  AndroidExecutor({String? adbPath}) : adbPath = adbPath ?? _resolveAdb();

  /// adb 可执行文件路径（优先用 SDK 里的，其次交给 PATH）。
  final String adbPath;

  /// 有些机器没把 platform-tools 加进 PATH，但设了 ANDROID_HOME/ANDROID_SDK_ROOT。
  static String _resolveAdb() {
    final exe = Platform.isWindows ? 'adb.exe' : 'adb';
    for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final root = Platform.environment[key];
      if (root == null || root.trim().isEmpty) continue;
      final candidate = '${root.trim()}${Platform.pathSeparator}'
          'platform-tools${Platform.pathSeparator}$exe';
      if (File(candidate).existsSync()) return candidate;
    }
    return 'adb';
  }

  /// 每个控件最短重复点击间隔，避免同一个勾选框被反复点（点两下=取消勾选）。
  static const Duration tapCooldown = Duration(seconds: 3);

  final Map<String, DateTime> _lastTap = <String, DateTime>{};

  Future<String> run(String toolName, Map<String, dynamic> args) async {
    try {
      return switch (toolName) {
        'android_ui_dump' => await _uiDump(args),
        'android_tap' => await _tap(args),
        'android_install_apk' => await _install(args),
        _ => _err('UNKNOWN_TOOL', toolName),
      };
    } catch (e) {
      return _err('EXCEPTION', '$e');
    }
  }

  // ─── android_ui_dump ────────────────────────────────────────

  Future<String> _uiDump(Map<String, dynamic> args) async {
    final serial = args['serial'] as String?;
    final maxNodes = (args['max_nodes'] as int?) ?? 80;

    final nodes = await _readScreen(serial);
    if (nodes == null) {
      return _err(
        'UI_DUMP_FAILED',
        'uiautomator dump 失败（屏幕可能正在动画，或设备未授权）。'
        '可重试一次；仍失败就用 adb shell dumpsys window 看前台窗口。',
      );
    }
    final focus = await _currentFocus(serial);
    final trimmed = nodes.length > maxNodes ? nodes.sublist(0, maxNodes) : nodes;
    return _ok({
      'focus': focus,
      'node_count': nodes.length,
      'truncated': nodes.length > maxNodes,
      'nodes': trimmed.map((n) => n.toJson()).toList(),
    });
  }

  // ─── android_tap ────────────────────────────────────────────

  Future<String> _tap(Map<String, dynamic> args) async {
    final serial = args['serial'] as String?;
    final x = args['x'];
    final y = args['y'];
    final text = args['text'] as String?;
    final desc = args['desc'] as String?;

    if (x is int && y is int) {
      await _adb(['shell', 'input', 'tap', '$x', '$y'], serial: serial);
      return _ok({'tapped': '[$x,$y]'});
    }

    final needle = (text ?? desc ?? '').trim();
    if (needle.isEmpty) {
      return _err(
        'INVALID_ARGS',
        'android_tap 需要 (x,y) 或 text/desc 之一',
      );
    }

    final nodes = await _readScreen(serial);
    if (nodes == null) return _err('UI_DUMP_FAILED', '读取屏幕失败');

    UiNode? match;
    // 完全相等优先，其次包含
    for (final node in nodes) {
      if (node.text == needle || node.desc == needle) {
        match = node;
        break;
      }
    }
    if (match == null) {
      for (final node in nodes) {
        if (node.text.contains(needle) || node.desc.contains(needle)) {
          match = node;
          break;
        }
      }
    }
    if (match == null) {
      return _err(
        'NODE_NOT_FOUND',
        '屏幕上没有包含「$needle」的节点。当前可见文本: '
        '${nodes.map((n) => n.label).where((l) => l.isNotEmpty).take(20).join(' | ')}',
      );
    }

    await _adb([
      'shell',
      'input',
      'tap',
      '${match.centerX}',
      '${match.centerY}',
    ], serial: serial);
    return _ok({
      'tapped': match.label,
      'bounds': match.bounds,
      'center': [match.centerX, match.centerY],
    });
  }

  // ─── android_install_apk ────────────────────────────────────

  Future<String> _install(Map<String, dynamic> args) async {
    final path = args['path'] as String?;
    if (path == null || path.isEmpty) {
      return _err('INVALID_ARGS', 'android_install_apk 缺少 path（APK 路径）');
    }
    final apk = File(path);
    if (!apk.existsSync()) {
      return _err('FILE_NOT_FOUND', 'APK 不存在: $path');
    }

    final serial = args['serial'] as String?;
    final autoConfirm = args['auto_confirm'] as bool? ?? true;
    final timeout = Duration(seconds: (args['timeout'] as int?) ?? 180);

    final steps = <String>[];
    final output = StringBuffer();
    final stopwatch = Stopwatch()..start();

    final process = await Process.start(adbPath, [
      if (serial != null) ...['-s', serial],
      'install',
      '-r',
      '-t',
      apk.path,
    ]);
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    process.stdout.listen((data) {
      output.write(utf8.decode(data, allowMalformed: true));
    }, onDone: outDone.complete, onError: (_) => outDone.complete());
    process.stderr.listen((data) {
      output.write(utf8.decode(data, allowMalformed: true));
    }, onDone: errDone.complete, onError: (_) => errDone.complete());

    var settled = false;
    int? exitCode;
    unawaited(process.exitCode.then((code) {
      settled = true;
      exitCode = code;
    }));

    try {
      while (stopwatch.elapsed < timeout) {
        final text = output.toString();
        if (text.contains('Success')) {
          return _ok({
            'installed': true,
            'output': _tail(text),
            'steps': steps,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          });
        }
        if (RegExp(r'Failure \[').hasMatch(text)) {
          return _ok({
            'installed': false,
            'failure': RegExp(r'Failure \[[^\]]*\]').firstMatch(text)?.group(0),
            'output': _tail(text),
            'steps': steps,
            'elapsed_ms': stopwatch.elapsedMilliseconds,
            'hint': '常见原因: USB 安装未开启(INSTALL_FAILED_USER_RESTRICTED)、'
                '签名冲突、降级安装、包名冲突。',
          });
        }
        if (settled && (exitCode ?? 0) != 0 && text.trim().isNotEmpty) {
          // adb 自己退出了（比如没授权）
          return _ok({
            'installed': false,
            'exit_code': exitCode,
            'output': _tail(text),
            'steps': steps,
          });
        }

        if (autoConfirm) {
          final tapped = await _autoConfirmStep(serial);
          if (tapped != null) steps.add(tapped);
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }

      // 超时：把 adb 收掉，别留僵尸
      await _killPid(process.pid);
      return _ok({
        'installed': false,
        'timeout': true,
        'output': _tail(output.toString()),
        'steps': steps,
        'hint': '安装流程超时。如果手机屏幕上有确认弹窗，可先用 android_ui_dump 看节点，'
            '再用 android_tap(text=...) 点掉；也可以 android_install_apk(auto_confirm=true) 重试。',
      });
    } finally {
      try {
        await Future.wait([outDone.future, errDone.future]).timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }
  }

  /// 读一次屏幕，按需点掉"勾选/继续安装"，返回做了什么（null = 无需操作）。
  Future<String?> _autoConfirmStep(String? serial) async {
    final nodes = await _readScreen(serial);
    if (nodes == null) return null;

    final target = pickInstallTarget(nodes);
    if (target == null) return null;

    final key = '${target.node.label}@${target.node.bounds}';
    final last = _lastTap[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < tapCooldown) return null;
    _lastTap[key] = now;

    await _adb([
      'shell',
      'input',
      'tap',
      '${target.node.centerX}',
      '${target.node.centerY}',
    ], serial: serial);
    return '${target.reason} @${target.node.bounds}';
  }

  // ─── 底层 ───────────────────────────────────────────────────

  Future<List<UiNode>?> _readScreen(String? serial) async {
    // 动画期间 uiautomator 可能报 "could not get idle state"，重试一次
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final dump = await _adb(
          ['shell', 'uiautomator', 'dump', '/sdcard/window_dump.xml'],
          serial: serial,
          timeout: const Duration(seconds: 20),
        );
        if (dump.exitCode != 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        final xml = await _adb(
          ['shell', 'cat', '/sdcard/window_dump.xml'],
          serial: serial,
          timeout: const Duration(seconds: 20),
        );
        final text = _decode(xml.stdout).trim();
        if (text.isEmpty) continue;
        return extractUiNodes(text);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return null;
  }

  Future<String> _currentFocus(String? serial) async {
    try {
      final result = await _adb(
        ['shell', 'dumpsys', 'window'],
        serial: serial,
        timeout: const Duration(seconds: 15),
      );
      final text = _decode(result.stdout);
      final match = RegExp(
        r'mCurrentFocus=(\S+)',
      ).firstMatch(text);
      return match?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<ProcessResult> _adb(
    List<String> args, {
    String? serial,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final full = <String>[if (serial != null) ...['-s', serial], ...args];
    return Process.run(
      adbPath,
      full,
    ).timeout(timeout);
  }

  Future<void> _killPid(int pid) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
      } else {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    } catch (_) {}
  }

  static String _decode(dynamic raw) {
    if (raw is String) return raw;
    if (raw is! List<int>) return '$raw';
    return utf8.decode(raw, allowMalformed: true);
  }

  static String _tail(String text) =>
      text.length <= 4000 ? text : text.substring(text.length - 4000);

  String _ok(Map<String, dynamic> data) =>
      jsonEncode({'status': 'ok', ...data});

  String _err(String code, String detail) =>
      jsonEncode({'status': 'error', 'code': code, 'detail': detail});
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';

/// 文档内容提取器 — 借助系统命令行工具把办公文档转成纯文本/Markdown
///
/// 设计原则：复用项目已能调用的命令行工具（pandoc / pdftotext），
/// 不引入任何 Dart 解析库，避免依赖膨胀与 license 约束。
/// 工具以系统环境变量 PATH 可寻为准（与「工具链」设置页理念一致）。
///
/// 各格式策略：
/// - PDF              → pdftotext (poppler)
/// - docx/pptx/odt    → pandoc -t markdown
/// - xlsx             → pandoc -t markdown (新版 pandoc 支持 xlsx 输入)
/// - doc/xls (旧二进制) → pandoc 尽力，多半失败
class DocumentExtractor {
  DocumentExtractor._();

  /// 工具是否存在的缓存 (命令名 -> 绝对路径 / null)。
  /// 进程级缓存，避免每个附件都重复探测。
  static final Map<String, String?> _toolCache = {};

  /// 提取结果
  static const int _maxChars = 100000; // 提取文本上限，超出截断

  /// 提取文档内容。成功返回提取的文本；失败返回 null（调用方降级为占位符）。
  ///
  /// [filePath] 文档绝对路径
  /// [ext] 小写扩展名 (不含点)
  static Future<DocExtractResult> extract(String filePath, String ext) async {
    switch (ext) {
      case 'pdf':
        return _extractPdf(filePath);
      case 'docx':
      case 'odt':
      case 'rtf':
        return _extractWithPandoc(filePath, ext, fromFormat: null);
      case 'pptx':
        return _extractWithPandoc(filePath, 'pptx', fromFormat: 'pptx');
      case 'xlsx':
        return _extractWithPandoc(filePath, 'xlsx', fromFormat: 'xlsx');
      case 'doc':
      case 'xls':
        // 旧版二进制格式，pandoc 多半不支持，尝试一次失败则降级
        return _extractWithPandoc(filePath, ext, fromFormat: null);
      default:
        return DocExtractResult.unsupported(ext);
    }
  }

  /// PDF → pdftotext
  static Future<DocExtractResult> _extractPdf(String filePath) async {
    final tool = await _locate('pdftotext');
    if (tool == null) {
      return DocExtractResult.toolMissing(
        'pdftotext',
        'PDF',
        hint: '安装 poppler（poppler-utils）后可自动提取 PDF 文本',
      );
    }
    try {
      // pdftotext -layout -enc UTF-8 input.pdf -   (输出到 stdout)
      final result = await Process.run(
        tool,
        ['-layout', '-enc', 'UTF-8', filePath, '-'],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        return DocExtractResult.failed(
          'PDF',
          _decodeBytes(result.stderr).trim(),
        );
      }
      final text = _decodeBytes(result.stdout).trim();
      if (text.isEmpty) {
        return DocExtractResult.empty('PDF', isPdf: true);
      }
      return DocExtractResult.success(_truncate(text));
    } on TimeoutException {
      return DocExtractResult.failed('PDF', '提取超时（30s）');
    } catch (e) {
      return DocExtractResult.failed('PDF', e.toString());
    }
  }

  /// docx/pptx/xlsx/odt → pandoc -t markdown
  static Future<DocExtractResult> _extractWithPandoc(
    String filePath,
    String ext, {
    String? fromFormat,
  }) async {
    final tool = await _locate('pandoc');
    final label = ext.toUpperCase();
    if (tool == null) {
      return DocExtractResult.toolMissing(
        'pandoc',
        label,
        hint: '在「工具链」设置页安装 Pandoc 后可自动提取此类文档',
      );
    }
    try {
      final args = <String>[
        if (fromFormat != null) ...['-f', fromFormat],
        '-t',
        'markdown',
        filePath,
      ];
      final result = await Process.run(
        tool,
        args,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        return DocExtractResult.failed(
          label,
          _decodeBytes(result.stderr).trim(),
        );
      }
      final text = _decodeBytes(result.stdout).trim();
      if (text.isEmpty) {
        return DocExtractResult.empty(label);
      }
      return DocExtractResult.success(_truncate(text));
    } on TimeoutException {
      return DocExtractResult.failed(label, '提取超时（30s）');
    } catch (e) {
      return DocExtractResult.failed(label, e.toString());
    }
  }

  /// 在 PATH 中定位命令行工具，结果缓存。
  static Future<String?> _locate(String command) async {
    if (_toolCache.containsKey(command)) return _toolCache[command];

    final locateCmd = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(
        locateCmd,
        [command],
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(const Duration(seconds: 4));

      if (result.exitCode == 0) {
        final path = _decodeBytes(
          result.stdout,
        ).trim().split('\n').first.trim();
        if (path.isNotEmpty) {
          _toolCache[command] = path;
          return path;
        }
      }
    } catch (_) {}
    _toolCache[command] = null;
    return null;
  }

  /// 清空工具探测缓存（用户安装新工具后可调用以重新探测）。
  static void clearCache() => _toolCache.clear();

  static String _truncate(String text) {
    if (text.length <= _maxChars) return text;
    return '${text.substring(0, _maxChars)}\n\n... [内容过大，已截断至 $_maxChars 字符]';
  }

  /// 智能字节解码：UTF-8 严格 → GBK 回退 → UTF-8 兜底（中文 Windows 兼容）
  static String _decodeBytes(dynamic raw) {
    if (raw is String) return raw;
    if (raw is! List<int>) return raw.toString();
    final bytes = raw;
    try {
      return utf8.decode(bytes);
    } catch (_) {}
    try {
      return gbk.decode(bytes);
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 文档提取结果
class DocExtractResult {
  /// 是否成功提取到内容
  final bool ok;

  /// 提取到的文本（ok=true 时有效）
  final String? text;

  /// 失败/降级时给模型的提示说明
  final String? note;

  const DocExtractResult._({required this.ok, this.text, this.note});

  factory DocExtractResult.success(String text) =>
      DocExtractResult._(ok: true, text: text);

  factory DocExtractResult.toolMissing(
    String tool,
    String label, {
    required String hint,
  }) =>
      DocExtractResult._(ok: false, note: '[未检测到 $tool，无法提取 $label 内容。$hint]');

  factory DocExtractResult.failed(String label, String reason) {
    final r = reason.isEmpty
        ? ''
        : '：${reason.length > 200 ? reason.substring(0, 200) : reason}';
    return DocExtractResult._(ok: false, note: '[$label 内容提取失败$r]');
  }

  factory DocExtractResult.empty(String label, {bool isPdf = false}) =>
      DocExtractResult._(
        ok: false,
        note: isPdf
            ? '[$label 未提取到文本，可能是扫描件/图片型 PDF，需 OCR 处理]'
            : '[$label 未提取到文本内容]',
      );

  factory DocExtractResult.unsupported(String ext) =>
      DocExtractResult._(ok: false, note: '[暂不支持提取 .$ext 文档内容]');
}

import 'dart:convert';
import 'dart:io';

import '../models/file_attachment.dart';
import 'document_extractor.dart';

/// 文件处理工具：将附件转换为 LLM 多模态内容格式
class FileProcessor {
  /// 单文件大小上限（跳过）
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB

  /// 单文件警告阈值
  static const int warnFileSize = 10 * 1024 * 1024; // 10MB

  /// 处理附件列表，返回 OpenAI content parts 格式
  /// 返回值为 `List<Map<String, dynamic>>`，每个元素为一个 content part
  static Future<List<Map<String, dynamic>>> processAttachments(
    List<FileAttachment> attachments,
  ) async {
    final parts = <Map<String, dynamic>>[];

    for (final attachment in attachments) {
      // 跳过超大文件
      if (attachment.size > maxFileSize) {
        parts.add({
          'type': 'text',
          'text':
              '--- 文件: ${attachment.name} ---\n'
              '[跳过: 文件大小 ${attachment.formattedSize} 超过 50MB 限制]',
        });
        continue;
      }

      final part = await _processFile(attachment);
      if (part != null) {
        parts.add(part);
      }
    }

    return parts;
  }

  /// 处理单个文件
  static Future<Map<String, dynamic>?> _processFile(
    FileAttachment attachment,
  ) async {
    try {
      final file = File(attachment.path);
      if (!await file.exists()) {
        return {
          'type': 'text',
          'text': '--- 文件: ${attachment.name} ---\n[错误: 文件不存在]',
        };
      }

      switch (attachment.type) {
        case FileAttachmentType.image:
          return await _processImage(file, attachment);
        case FileAttachmentType.text:
        case FileAttachmentType.code:
          return await _processTextFile(file, attachment);
        case FileAttachmentType.document:
          return await _processDocument(attachment);
        case FileAttachmentType.archive:
          return _processArchive(attachment);
      }
    } catch (e) {
      return {
        'type': 'text',
        'text': '--- 文件: ${attachment.name} ---\n[读取错误: $e]',
      };
    }
  }

  /// 处理图片文件：转为 base64 data URL
  static Future<Map<String, dynamic>> _processImage(
    File file,
    FileAttachment attachment,
  ) async {
    final bytes = await file.readAsBytes();
    final base64Data = base64Encode(bytes);
    final dataUrl = 'data:${attachment.mimeType};base64,$base64Data';

    return {
      'type': 'image_url',
      'image_url': {'url': dataUrl},
    };
  }

  /// 处理文本/代码文件：读取 UTF-8 内容
  static Future<Map<String, dynamic>> _processTextFile(
    File file,
    FileAttachment attachment,
  ) async {
    String content;
    try {
      content = await file.readAsString(encoding: utf8);
    } catch (_) {
      // 如果 UTF-8 解码失败，尝试 Latin-1
      final bytes = await file.readAsBytes();
      content = latin1.decode(bytes);
    }

    // 10MB 以上的文本文件截断
    if (attachment.size > warnFileSize) {
      const maxChars = 100000;
      if (content.length > maxChars) {
        content =
            '${content.substring(0, maxChars)}\n\n... [文件过大，已截断，'
            '总大小: ${attachment.formattedSize}]';
      }
    }

    return {'type': 'text', 'text': '--- 文件: ${attachment.name} ---\n$content'};
  }

  /// 处理文档类文件 (PDF/DOCX/XLSX/PPTX)：
  /// 借助系统命令行工具 (pandoc/pdftotext) 提取真实内容并内联。
  /// 提取失败时降级为带原因说明的占位符，引导用户安装相应工具。
  static Future<Map<String, dynamic>> _processDocument(
    FileAttachment attachment,
  ) async {
    final ext = attachment.name.contains('.')
        ? attachment.name.split('.').last.toLowerCase()
        : '';

    final result = await DocumentExtractor.extract(attachment.path, ext);

    if (result.ok && result.text != null) {
      return {
        'type': 'text',
        'text':
            '--- 文件: ${attachment.name} (${attachment.formattedSize}) ---\n'
            '${result.text}',
      };
    }

    // 提取失败：降级为占位符，附带原因/引导
    return {
      'type': 'text',
      'text':
          '--- 文件: ${attachment.name} (${attachment.formattedSize}) ---\n'
          '${result.note ?? '[无法提取文档内容]'}',
    };
  }

  /// 处理压缩包文件
  static Map<String, dynamic> _processArchive(FileAttachment attachment) {
    return {
      'type': 'text',
      'text':
          '--- 文件: ${attachment.name} ---\n'
          '[压缩包，大小: ${attachment.formattedSize}，'
          '用于技能导入上下文]',
    };
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

/// 附件文件类型枚举
enum FileAttachmentType { image, text, document, code, archive }

/// 文件附件模型
class FileAttachment {
  final String path;
  final String name;
  final int size;
  final FileAttachmentType type;
  final String mimeType;

  const FileAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.type,
    required this.mimeType,
  });

  /// 从文件路径创建附件
  factory FileAttachment.fromFile(File file) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final size = file.lengthSync();
    return FileAttachment(
      path: file.path,
      name: name,
      size: size,
      type: typeFromExtension(ext),
      mimeType: mimeTypeFromExtension(ext),
    );
  }

  /// 序列化为 JSON（用于随消息持久化到数据库）。
  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'size': size,
    'type': type.name,
    'mimeType': mimeType,
  };

  /// 从 JSON 反序列化。
  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    return FileAttachment(
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      type: FileAttachmentType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => FileAttachmentType.text,
      ),
      mimeType: (json['mimeType'] ?? 'application/octet-stream').toString(),
    );
  }

  /// 根据扩展名判断文件类型
  static FileAttachmentType typeFromExtension(String ext) {
    if (_imageExtensions.contains(ext)) return FileAttachmentType.image;
    if (_codeExtensions.contains(ext)) return FileAttachmentType.code;
    if (_textExtensions.contains(ext)) return FileAttachmentType.text;
    if (_archiveExtensions.contains(ext)) return FileAttachmentType.archive;
    if (_documentExtensions.contains(ext)) return FileAttachmentType.document;
    return FileAttachmentType.text; // 默认作为文本处理
  }

  /// 根据扩展名获取 MIME 类型
  static String mimeTypeFromExtension(String ext) {
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  /// 获取文件类型对应的图标
  IconData get icon {
    switch (type) {
      case FileAttachmentType.image:
        return Icons.image_outlined;
      case FileAttachmentType.text:
        return Icons.description_outlined;
      case FileAttachmentType.document:
        return Icons.article_outlined;
      case FileAttachmentType.code:
        return Icons.code;
      case FileAttachmentType.archive:
        return Icons.folder_zip_outlined;
    }
  }

  /// 获取文件类型对应的颜色
  Color get iconColor {
    switch (type) {
      case FileAttachmentType.image:
        return Colors.blue;
      case FileAttachmentType.text:
        return Colors.grey;
      case FileAttachmentType.document:
        return Colors.orange;
      case FileAttachmentType.code:
        return Colors.green;
      case FileAttachmentType.archive:
        return Colors.purple;
    }
  }

  /// 格式化文件大小显示
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 是否为图片类型
  bool get isImage => type == FileAttachmentType.image;

  /// 是否可读取为文本
  bool get isReadableAsText =>
      type == FileAttachmentType.text || type == FileAttachmentType.code;

  // 支持的文件扩展名集合
  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'};
  static const _textExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'xml',
    'yaml',
    'yml',
  };
  static const _codeExtensions = {
    'py',
    'js',
    'ts',
    'dart',
    'java',
    'c',
    'cpp',
    'h',
    'go',
    'rs',
    'rb',
    'php',
    'html',
    'css',
    'sql',
  };
  static const _documentExtensions = {'pdf', 'doc', 'docx', 'xls', 'xlsx'};
  static const _archiveExtensions = {'zip'};

  /// 所有支持的扩展名
  static const supportedExtensions = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'svg',
    'pdf',
    'doc',
    'docx',
    'txt',
    'md',
    'csv',
    'json',
    'xml',
    'yaml',
    'yml',
    'xls',
    'xlsx',
    'py',
    'js',
    'ts',
    'dart',
    'java',
    'c',
    'cpp',
    'h',
    'go',
    'rs',
    'rb',
    'php',
    'html',
    'css',
    'sql',
    'zip',
  ];

  static const _mimeTypes = <String, String>{
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'yaml': 'text/yaml',
    'yml': 'text/yaml',
    'zip': 'application/zip',
    'py': 'text/x-python',
    'js': 'text/javascript',
    'ts': 'text/typescript',
    'dart': 'text/x-dart',
    'java': 'text/x-java',
    'c': 'text/x-c',
    'cpp': 'text/x-c++',
    'h': 'text/x-c',
    'go': 'text/x-go',
    'rs': 'text/x-rust',
    'rb': 'text/x-ruby',
    'php': 'text/x-php',
    'html': 'text/html',
    'css': 'text/css',
    'sql': 'text/x-sql',
  };
}

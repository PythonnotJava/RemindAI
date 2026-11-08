import 'dart:io';

import '../models/file_attachment.dart';

/// 图片资产的来源类型。
enum ImageAssetKind { attachment, generated }

/// 会话内的一张可用图片。
class ImageAsset {
  /// 稳定 ID：用户上传为 `A1/A2...`，生成图为 `G1/G2...`。
  final String id;

  /// 磁盘绝对路径。
  final String path;

  final ImageAssetKind kind;

  /// 上传文件名，或生成时的提示词。
  final String label;

  /// 生成图的父图片 ID（图生图链路），上传图为空。
  final List<String> parentIds;

  final DateTime createdAt;

  const ImageAsset({
    required this.id,
    required this.path,
    required this.kind,
    required this.label,
    required this.createdAt,
    this.parentIds = const [],
  });

  bool get exists => File(path).existsSync();

  bool get isGenerated => kind == ImageAssetKind.generated;
}

/// 图片 ID 解析失败（不存在、文件丢失等）。
class ImageReferenceException implements Exception {
  final String message;
  final List<String> availableIds;

  ImageReferenceException(this.message, this.availableIds);

  @override
  String toString() => message;
}

/// 会话级图片注册表。
///
/// 目的：让模型使用稳定的图片 ID，而不是复制/猜测磁盘路径。
/// - 用户每轮上传的图片登记为 `A1`、`A2`……（同一路径复用已有 ID）
/// - 画图工具生成的结果登记为 `G1`、`G2`……，并记录父图片 ID
/// - [buildContextNote] 生成一段注入给 LLM 的图片清单与引用规则
/// - [resolveIds] 由框架把 ID 解析为真实路径，模型不需要接触路径
///
/// 注册表只保留最近 [maxAssets] 张图片；被裁剪的 ID 不能再引用，
/// 解析失败时会把当前可用 ID 一并返回，方便模型自我纠正。
class SessionImageRegistry {
  static const int maxAssets = 12;

  final List<ImageAsset> _assets = [];
  int _attachmentSeq = 0;
  int _generatedSeq = 0;

  List<ImageAsset> get assets => List.unmodifiable(_assets);

  bool get isEmpty => _assets.isEmpty;

  void clear() {
    _assets.clear();
    _attachmentSeq = 0;
    _generatedSeq = 0;
  }

  /// 登记本轮用户附加的图片（仅图片类型，文件必须存在）。
  ///
  /// 返回本轮新增的图片 ID；已登记过的同一路径不会重复添加。
  List<String> beginTurn(List<FileAttachment> attachments) {
    final addedIds = <String>[];
    for (final attachment in attachments) {
      if (!attachment.isImage) continue;
      if (!File(attachment.path).existsSync()) continue;
      final exists = _assets.any(
        (asset) =>
            asset.kind == ImageAssetKind.attachment &&
            asset.path == attachment.path,
      );
      if (exists) continue;
      final id = 'A${++_attachmentSeq}';
      _assets.add(
        ImageAsset(
          id: id,
          path: attachment.path,
          kind: ImageAssetKind.attachment,
          label: attachment.name,
          createdAt: DateTime.now(),
        ),
      );
      addedIds.add(id);
    }
    _prune();
    return addedIds;
  }

  /// 登记一张生成图，返回它的图片 ID。
  String registerGenerated(
    String path, {
    String prompt = '',
    List<String> parentIds = const [],
  }) {
    final id = 'G${++_generatedSeq}';
    _assets.add(
      ImageAsset(
        id: id,
        path: path,
        kind: ImageAssetKind.generated,
        label: prompt,
        parentIds: List.unmodifiable(parentIds),
        createdAt: DateTime.now(),
      ),
    );
    _prune();
    return id;
  }

  /// 从历史消息恢复用户上传的图片（不带 ID 语义，重新分配 A 编号）。
  void restoreAttachment(String path, {String label = ''}) {
    if (!File(path).existsSync()) return;
    if (_assets.any(
      (asset) => asset.kind == ImageAssetKind.attachment && asset.path == path,
    )) {
      return;
    }
    _assets.add(
      ImageAsset(
        id: 'A${++_attachmentSeq}',
        path: path,
        kind: ImageAssetKind.attachment,
        label: label,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 从历史消息恢复生成图（重新分配 G 编号）。
  void restoreGenerated(String path, {String prompt = ''}) {
    if (!File(path).existsSync()) return;
    _assets.add(
      ImageAsset(
        id: 'G${++_generatedSeq}',
        path: path,
        kind: ImageAssetKind.generated,
        label: prompt,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 根据 ID 查找图片，支持 `last` / `last_generated` / `last_attachment`。
  ImageAsset? findById(String raw) {
    final id = raw.trim();
    if (id.isEmpty) return null;

    final lower = id.toLowerCase();
    if (lower == 'last' ||
        lower == 'latest' ||
        lower == 'last_image' ||
        lower == 'previous') {
      return _assets.isEmpty ? null : _assets.last;
    }
    if (lower == 'last_generated' || lower == 'latest_generated') {
      return _lastOfKind(ImageAssetKind.generated);
    }
    if (lower == 'last_attachment' || lower == 'latest_attachment') {
      return _lastOfKind(ImageAssetKind.attachment);
    }

    for (final asset in _assets) {
      if (asset.id.toLowerCase() == lower) return asset;
    }
    return null;
  }

  /// 把一组 ID 解析为图片资产，保持输入顺序并去重。
  ///
  /// 任一 ID 不存在或文件已丢失时抛出 [ImageReferenceException]，
  /// 异常里带上当前可用 ID，模型可据此重试。
  List<ImageAsset> resolveIds(List<String> rawIds) {
    final result = <ImageAsset>[];
    for (final raw in rawIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final asset = findById(id);
      if (asset == null) {
        throw ImageReferenceException(
          '找不到图片 ID "$id"。当前可用图片：${availableIds.join(', ')}',
          availableIds,
        );
      }
      if (!asset.exists) {
        throw ImageReferenceException(
          '图片 ${asset.id} 的文件已不存在：${asset.path}',
          availableIds,
        );
      }
      if (!result.any((item) => item.id == asset.id)) {
        result.add(asset);
      }
    }
    return result;
  }

  /// 根据路径反查已有 ID（显式路径输入时用于记录父子关系）。
  String? idForPath(String path) {
    for (final asset in _assets) {
      if (asset.path == path) return asset.id;
    }
    return null;
  }

  List<String> get availableIds => _assets.map((asset) => asset.id).toList();

  /// 生成注入给 LLM 的图片清单与引用规则；没有图片时返回空字符串。
  ///
  /// [currentTurnIds] 标记本轮新上传的图片（显示为“本轮上传”），
  /// 帮助模型区分“这张刚传的”和历史图片。
  String buildContextNote({
    int maxItems = 8,
    Set<String> currentTurnIds = const {},
  }) {
    if (_assets.isEmpty) return '';

    final recent = _assets.length <= maxItems
        ? _assets
        : _assets.sublist(_assets.length - maxItems);
    final buffer = StringBuffer();
    buffer.writeln('[图片上下文]');
    buffer.writeln('本会话可用图片（只能使用以下 ID，不要臆造）：');
    for (final asset in recent) {
      final kind = asset.isGenerated
          ? '生成图'
          : currentTurnIds.contains(asset.id)
          ? '本轮上传'
          : '用户上传';
      final label = asset.label.trim();
      final suffix = label.isEmpty
          ? ''
          : ' · ${_truncate(label.replaceAll('\n', ' '), 60)}';
      final parents = asset.parentIds.isEmpty
          ? ''
          : '（基于 ${asset.parentIds.join(', ')}）';
      buffer.writeln('- ${asset.id}: $kind$suffix$parents');
    }
    buffer.writeln('注意：这些图片只是可用素材，不代表本轮必须使用；从零画新图时不要传 ID。');
    buffer.writeln('引用规则：');
    buffer.writeln('- 从零画新图：mode=new，不要传 input_image_ids。');
    buffer.writeln(
      '- 基于某张图修改/重绘/风格转换：mode=edit，并在 input_image_ids 中填对应 ID，例如 ["A1"]、["G2"]。',
    );
    buffer.writeln(
      '- 用户说“上一张/刚才那张”时可用 ["last"]；也可用 ["last_generated"] 或 ["last_attachment"]。',
    );
    buffer.writeln(
      '- 图片只是附带、用户明确要画全新内容且不要求参考时，用 mode=new；'
      '用户说“参考这张”时用 mode=edit。',
    );
    buffer.writeln('- 不要编造 ID，也不要把磁盘路径当作 ID。');
    return buffer.toString().trim();
  }

  ImageAsset? _lastOfKind(ImageAssetKind kind) {
    for (var i = _assets.length - 1; i >= 0; i--) {
      if (_assets[i].kind == kind) return _assets[i];
    }
    return null;
  }

  void _prune() {
    while (_assets.length > maxAssets) {
      _assets.removeAt(0);
    }
  }

  static String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}

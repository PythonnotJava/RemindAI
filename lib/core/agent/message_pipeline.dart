import 'message_transformer.dart';

/// 消息变换管线
///
/// 持有一组 [MessageTransformer]，按注册顺序依次执行。
/// 如果没有注册任何变换器，则原样返回（zero-cost 透传）。
///
/// 使用示例：
/// ```dart
/// final pipeline = MessagePipeline([
///   SlidingWindowTransformer(maxTurns: 20),
///   TokenBudgetTransformer(maxTokens: 8000),
/// ]);
///
/// final transformed = await pipeline.process(messages);
/// // transformed 是裁剪后的消息列表，原始 messages 不受影响
/// ```
class MessagePipeline {
  final List<MessageTransformer> _transformers;

  const MessagePipeline([this._transformers = const []]);

  /// 当前注册的变换器数量
  int get length => _transformers.length;

  /// 是否没有注册任何变换器（此时 process 是零开销透传）
  bool get isEmpty => _transformers.isEmpty;

  /// 访问变换器列表（用于对话中压缩的重置标记等操作）
  List<MessageTransformer> get transformers => _transformers;

  /// 执行变换管线
  ///
  /// 对 [messages] 的深拷贝依次应用所有激活的变换器。
  /// 原始列表不会被修改。
  ///
  /// 如果没有注册变换器，直接返回原始列表引用（避免拷贝开销）。
  Future<List<Map<String, dynamic>>> process(
    List<Map<String, dynamic>> messages,
  ) async {
    if (_transformers.isEmpty) return messages;

    // 深拷贝，避免变换器修改原始消息
    var result = messages.map((m) => Map<String, dynamic>.from(m)).toList();

    for (final transformer in _transformers) {
      if (transformer.shouldActivate(result)) {
        result = await transformer.transform(result);
      }
    }

    return result;
  }
}

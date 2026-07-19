import 'dart:async';

/// 全局单例，用于在卡片之间传递默认模型变化事件
/// 避免通过 Riverpod 全局刷新
class ModelCardEventBus {
  static final ModelCardEventBus _instance = ModelCardEventBus._();
  factory ModelCardEventBus() => _instance;
  ModelCardEventBus._();

  final _controller = StreamController<String>.broadcast();

  /// 监听默认模型变化
  Stream<String> get onDefaultChanged => _controller.stream;

  /// 通知默认模型已变化
  void notifyDefaultChanged(String newDefaultId) {
    _controller.add(newDefaultId);
  }

  void dispose() {
    _controller.close();
  }
}

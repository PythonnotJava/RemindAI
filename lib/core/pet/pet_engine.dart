import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pet_sprite.dart';
import 'pet_state.dart';

/// 宠物动画引擎 — 驱动精灵图帧循环和状态转换
///
/// 设计目标：
/// - 高效：使用单个 AnimationController + CustomPainter，不创建多个 Widget
/// - 解耦：接受 PetSpriteSheet 定义 + PetStateMachine 驱动
/// - 可观测：暴露 ValueNotifier 供外部监听当前帧/状态
/// - 支持热切换精灵图和行为配置
class PetEngine extends ChangeNotifier {
  PetSpriteSheet _sprite;
  PetStateMachine _stateMachine;
  ui.Image? _spriteImage;
  bool _imageLoaded = false;

  /// 当前帧索引（在当前动画内的）
  int _frameIndex = 0;

  /// 当前播放的动画
  SpriteAnimation? _currentAnimation;

  Timer? _frameTimer;
  Timer? _stateTimer;

  /// 水平翻转（用于左右行走）
  bool flipX = false;

  PetEngine({required PetSpriteSheet sprite, PetBehaviorConfig? behaviorConfig})
    // ignore: prefer_initializing_formals
    : _sprite = sprite,
      _stateMachine = PetStateMachine(
        config: behaviorConfig ?? PetBehaviorConfig.defaultCat,
      );

  // -- Getters --

  PetSpriteSheet get sprite => _sprite;
  PetStateMachine get stateMachine => _stateMachine;
  bool get imageLoaded => _imageLoaded;
  ui.Image? get spriteImage => _spriteImage;
  int get frameIndex => _frameIndex;
  SpriteAnimation? get currentAnimation => _currentAnimation;
  PetState get currentState => _stateMachine.current;

  // -- Lifecycle --

  /// 加载精灵图并启动动画循环
  Future<void> initialize() async {
    await _loadImage();
    _switchToAnimation(_stateMachine.currentAnimationName);
    _startStateTimer();
  }

  /// 切换精灵图（热替换）
  Future<void> changeSpriteSheet(PetSpriteSheet newSprite) async {
    _sprite = newSprite;
    _stopTimers();
    _imageLoaded = false;
    _currentAnimation = null; // 防止 painter 计算 srcRect
    notifyListeners(); // 先通知 UI 切换到 loading 状态，停止绘制旧 image
    // 等一帧确保 painter 不再引用旧图
    await Future<void>.delayed(Duration.zero);
    _spriteImage?.dispose();
    _spriteImage = null;
    await _loadImage();
    _switchToAnimation(_stateMachine.currentAnimationName);
    _startStateTimer();
  }

  /// 更换行为配置
  void changeBehavior(PetBehaviorConfig config) {
    _stateMachine = PetStateMachine(config: config);
    _switchToAnimation(_stateMachine.currentAnimationName);
    _restartStateTimer();
  }

  /// 外部事件注入
  void sendEvent(PetEvent event) {
    _stateMachine.handleEvent(event);
    _switchToAnimation(_stateMachine.currentAnimationName);
    _restartStateTimer();
  }

  /// 直接切换到指定动画（按名称）
  void playAnimation(String name) {
    _switchToAnimation(name);
  }

  @override
  void dispose() {
    _stopTimers();
    _spriteImage?.dispose();
    super.dispose();
  }

  // -- Internal --

  String? _loadError;
  String? get loadError => _loadError;

  Future<void> _loadImage() async {
    try {
      _loadError = null;
      final data = await rootBundle.load(_sprite.assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _spriteImage = frame.image;
      _imageLoaded = true;
    } catch (e) {
      _loadError = 'Failed to load ${_sprite.assetPath}: $e';
      _imageLoaded = false;
    }
    notifyListeners();
  }

  void _switchToAnimation(String name) {
    final anim = _sprite.findAnimation(name);
    if (anim == null && _currentAnimation != null) return; // 找不到就保持当前
    _currentAnimation = anim ?? _sprite.animations.firstOrNull;
    _frameIndex = 0;
    flipX = _currentAnimation?.direction == SpriteDirection.left;
    _restartFrameTimer();
    notifyListeners();
  }

  void _restartFrameTimer() {
    _frameTimer?.cancel();
    final anim = _currentAnimation;
    if (anim == null) return;
    final interval = Duration(milliseconds: (1000 / anim.fps).round());
    _frameTimer = Timer.periodic(interval, (_) => _advanceFrame());
  }

  void _advanceFrame() {
    final anim = _currentAnimation;
    if (anim == null) return;
    _frameIndex++;
    if (_frameIndex >= anim.frameCount) {
      if (anim.loop) {
        _frameIndex = 0;
      } else {
        _frameIndex = anim.frameCount - 1;
        _frameTimer?.cancel();
        // 非循环动画结束后触发超时事件
        _stateMachine.handleEvent(PetEvent.timeout);
        _switchToAnimation(_stateMachine.currentAnimationName);
        _restartStateTimer();
        return;
      }
    }
    notifyListeners();
  }

  void _startStateTimer() {
    _stateTimer?.cancel();
    final duration = _stateMachine.getStateDuration();
    _stateTimer = Timer(Duration(milliseconds: duration), () {
      _stateMachine.handleEvent(PetEvent.randomTick);
      _switchToAnimation(_stateMachine.currentAnimationName);
      _startStateTimer(); // 递归下一轮
    });
  }

  void _restartStateTimer() {
    _startStateTimer();
  }

  void _stopTimers() {
    _frameTimer?.cancel();
    _stateTimer?.cancel();
    _frameTimer = null;
    _stateTimer = null;
  }

  /// 计算当前帧在精灵图中的源矩形
  Rect? get currentFrameRect {
    final anim = _currentAnimation;
    if (anim == null) return null;
    final col = anim.startColumn + _frameIndex;
    final row = anim.startRow;
    return Rect.fromLTWH(
      (col * _sprite.frameWidth).toDouble(),
      (row * _sprite.frameHeight).toDouble(),
      _sprite.frameWidth.toDouble(),
      _sprite.frameHeight.toDouble(),
    );
  }
}

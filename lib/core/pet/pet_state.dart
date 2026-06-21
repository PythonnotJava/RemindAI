/// 宠物状态机 — 定义宠物行为状态及其转换
///
/// 设计目标：
/// - 状态驱动动画：每个状态对应一个 SpriteAnimation name
/// - 可扩展：后续可加入语音唤醒、TTS、交互等触发状态转换
/// - 与渲染层解耦：状态机只输出"当前应播放哪个动画"
library;

import 'dart:math';

/// 宠物当前行为状态
enum PetState {
  /// 待机（默认）
  idle,

  /// 行走
  walking,

  /// 奔跑
  running,

  /// 坐下
  sitting,

  /// 睡觉
  sleeping,

  /// 跳跃
  jumping,

  /// 被抚摸/互动
  interacting,

  /// 说话（TTS 播放中）
  speaking,

  /// 聆听（语音唤醒后等待指令）
  listening,

  /// 开心
  happy,

  /// 生气
  angry,
}

/// 状态转换事件
enum PetEvent {
  /// 无操作一段时间
  timeout,

  /// 用户点击/触摸
  tap,

  /// 用户拖拽
  drag,

  /// 用户双击
  doubleTap,

  /// 语音唤醒触发
  voiceWake,

  /// TTS 开始
  ttsStart,

  /// TTS 结束
  ttsEnd,

  /// 外部命令（如 API 调用改变状态）
  command,

  /// 随机触发（自发行为）
  randomTick,
}

/// 状态机配置 — 定义状态到动画名的映射和转换规则
class PetBehaviorConfig {
  /// 状态 → 动画名 映射
  final Map<PetState, String> stateAnimationMap;

  /// 各状态停留时长范围 (毫秒)，超时后触发 PetEvent.timeout
  final Map<PetState, (int min, int max)> stateDurations;

  /// idle 状态下随机切换到其他状态的权重
  final Map<PetState, double> randomTransitionWeights;

  const PetBehaviorConfig({
    required this.stateAnimationMap,
    this.stateDurations = const {},
    this.randomTransitionWeights = const {},
  });

  /// 默认行为配置（适用于标准猫咪精灵）
  static const defaultCat = PetBehaviorConfig(
    stateAnimationMap: {
      PetState.idle: 'idle',
      PetState.walking: 'walk',
      PetState.running: 'run',
      PetState.sitting: 'sit',
      PetState.sleeping: 'sleep',
      PetState.jumping: 'jump',
      PetState.interacting: 'interact',
      PetState.speaking: 'idle_groom',
      PetState.listening: 'idle_look',
      PetState.happy: 'happy',
      PetState.angry: 'stretch',
    },
    stateDurations: {
      PetState.idle: (3000, 6000),
      PetState.walking: (2000, 4000),
      PetState.running: (1500, 3000),
      PetState.sitting: (4000, 8000),
      PetState.sleeping: (6000, 12000),
      PetState.jumping: (800, 800),
      PetState.interacting: (1500, 2500),
      PetState.happy: (1000, 2000),
    },
    randomTransitionWeights: {
      PetState.idle: 0.30,
      PetState.walking: 0.20,
      PetState.sitting: 0.20,
      PetState.sleeping: 0.10,
      PetState.running: 0.10,
      PetState.jumping: 0.05,
      PetState.happy: 0.05,
    },
  );
}

/// 状态机运行时
class PetStateMachine {
  PetState _current = PetState.idle;
  final PetBehaviorConfig config;
  final Random _random = Random();

  PetStateMachine({required this.config});

  PetState get current => _current;

  /// 获取当前状态对应的动画名
  String get currentAnimationName =>
      config.stateAnimationMap[_current] ?? 'idle';

  /// 处理事件，返回新状态（如果发生了转换）
  PetState handleEvent(PetEvent event) {
    switch (event) {
      case PetEvent.tap:
        _current = PetState.interacting;
        break;
      case PetEvent.doubleTap:
        _current = PetState.happy;
        break;
      case PetEvent.drag:
        _current = PetState.jumping;
        break;
      case PetEvent.voiceWake:
        _current = PetState.listening;
        break;
      case PetEvent.ttsStart:
        _current = PetState.speaking;
        break;
      case PetEvent.ttsEnd:
        _current = PetState.idle;
        break;
      case PetEvent.timeout:
      case PetEvent.randomTick:
        _current = _pickRandomState();
        break;
      case PetEvent.command:
        // 外部设置，不在此处理
        break;
    }
    return _current;
  }

  /// 直接设置状态（外部命令）
  void setState(PetState state) => _current = state;

  /// 获取当前状态的停留时长（毫秒）
  int getStateDuration() {
    final range = config.stateDurations[_current];
    if (range == null) return 3000;
    return range.$1 + _random.nextInt(range.$2 - range.$1 + 1);
  }

  PetState _pickRandomState() {
    final weights = config.randomTransitionWeights;
    if (weights.isEmpty) return PetState.idle;

    final total = weights.values.fold(0.0, (a, b) => a + b);
    var roll = _random.nextDouble() * total;

    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll <= 0) return entry.key;
    }
    return PetState.idle;
  }
}

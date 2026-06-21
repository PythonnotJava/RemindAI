/// 宠物系统核心库
///
/// 架构分层：
/// - [PetSpriteSheet] / [SpriteAnimation] — 数据层，描述精灵图元数据
/// - [PetState] / [PetStateMachine] / [PetBehaviorConfig] — 逻辑层，状态驱动
/// - [PetEngine] — 引擎层，协调状态机 + 帧循环 + 图片加载
/// - [PetRegistry] — 注册层，管理所有可用精灵
/// - [PetObserver] — 观察层，收集全局事件驱动宠物反应
///
/// 后续扩展接口预留：
/// - 语音唤醒：通过 PetEngine.sendEvent(PetEvent.voiceWake) 切换到 listening
/// - TTS：通过 PetEngine.sendEvent(PetEvent.ttsStart/ttsEnd) 驱动说话动画
/// - 自定义精灵：通过 PetRegistry.register() 加入用户自定义精灵
/// - 交互系统：GestureDetector → PetEngine.sendEvent(tap/doubleTap/drag)
library;

export 'pet_sprite.dart';
export 'pet_state.dart';
export 'pet_engine.dart';
export 'pet_registry.dart';
export 'pet_observer.dart';
export 'pet_chat_service.dart';
export 'pet_economy.dart';

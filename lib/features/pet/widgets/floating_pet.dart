import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/l10n/l10n_ext.dart';

import '../../../core/pet/pet.dart';
import '../../../core/tts/tts_service.dart';
import 'food_sprite.dart';
import 'pet_canvas.dart';

/// 全局浮动宠物 Widget
///
/// 功能：
/// - 在程序范围内自动行走（walking/running 状态时移动位置）
/// - 长按拖拽到任意位置
/// - 右键弹出菜单（关闭宠物等）
/// - 单击/双击交互
/// - 全局唯一（通过 FloatingPetController 单例管理）
class FloatingPet extends StatefulWidget {
  const FloatingPet({super.key});

  @override
  State<FloatingPet> createState() => _FloatingPetState();
}

class _FloatingPetState extends State<FloatingPet> {
  final _controller = FloatingPetController.instance;
  late final PetEngine _engine;

  // 位置
  double _x = 100;
  double _y = 100;

  // 移动相关
  double _velocityX = 0;
  double _velocityY = 0;
  Timer? _moveTimer;

  // 拖拽状态
  bool _isDragging = false;
  Offset? _lastDragOffset;

  // 显示尺寸
  static const double _petSize = 96;

  @override
  void initState() {
    super.initState();
    _engine = _controller.engine;
    _engine.addListener(_onEngineUpdate);
    _controller.visibleNotifier.addListener(_onVisibilityChange);
    _startMoveLoop();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdate);
    _controller.visibleNotifier.removeListener(_onVisibilityChange);
    _moveTimer?.cancel();
    super.dispose();
  }

  void _onVisibilityChange() {
    if (!mounted) return;
    // 隐藏时停止移动 Timer 节省 CPU
    if (!_controller.visible) {
      _moveTimer?.cancel();
      _moveTimer = null;
    } else if (_moveTimer == null) {
      _startMoveLoop();
    }
    setState(() {});
  }

  void _onEngineUpdate() {
    if (!mounted) return;
    final state = _engine.currentState;
    // 状态变化时决定是否开始/停止移动
    if (state == PetState.walking || state == PetState.running) {
      if (_velocityX == 0 && _velocityY == 0 && !_isDragging) {
        _startMoving();
      }
    } else {
      _stopMoving();
    }
    setState(() {});
  }

  void _startMoveLoop() {
    _moveTimer?.cancel();
    // 16ms ≈ 60fps 位置更新
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_isDragging || (_velocityX == 0 && _velocityY == 0)) return;
      _updatePosition();
    });
  }

  void _startMoving() {
    final random = Random();
    final speed = _engine.currentState == PetState.running ? 2.0 : 1.0;
    // 随机方向
    final angle = random.nextDouble() * 2 * pi;
    _velocityX = cos(angle) * speed;
    _velocityY = sin(angle) * speed;
    // 根据移动方向翻转精灵
    _engine.flipX = _velocityX < 0;
  }

  void _stopMoving() {
    _velocityX = 0;
    _velocityY = 0;
  }

  void _updatePosition() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final maxX = size.width - _petSize;
    final maxY = size.height - _petSize;

    var newX = _x + _velocityX;
    var newY = _y + _velocityY;

    // 碰到边界反弹
    if (newX <= 0 || newX >= maxX) {
      _velocityX = -_velocityX;
      newX = newX.clamp(0, maxX);
      _engine.flipX = _velocityX < 0;
    }
    if (newY <= 0 || newY >= maxY) {
      _velocityY = -_velocityY;
      newY = newY.clamp(0, maxY);
    }

    setState(() {
      _x = newX;
      _y = newY;
    });
    _controller.positionNotifier.value = Offset(_x, _y);
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.visible) return const SizedBox.shrink();

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onTap: () => _engine.sendEvent(PetEvent.tap),
        onDoubleTap: () => _engine.sendEvent(PetEvent.doubleTap),
        // 右键菜单
        onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
        // 长按开始拖拽
        onLongPressStart: (details) {
          setState(() => _isDragging = true);
          _lastDragOffset = details.globalPosition;
          _stopMoving();
          _engine.sendEvent(PetEvent.drag);
        },
        onLongPressMoveUpdate: (details) {
          final delta = details.globalPosition - (_lastDragOffset ?? details.globalPosition);
          _lastDragOffset = details.globalPosition;
          setState(() {
            _x += delta.dx;
            _y += delta.dy;
            // 限制在窗口内
            final size = MediaQuery.of(context).size;
            _x = _x.clamp(0, size.width - _petSize);
            _y = _y.clamp(0, size.height - _petSize);
          });
          _controller.positionNotifier.value = Offset(_x, _y);
        },
        onLongPressEnd: (_) {
          setState(() {
            _isDragging = false;
            _lastDragOffset = null;
          });
        },
        child: MouseRegion(
          cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _isDragging ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: SizedBox.square(
              dimension: _petSize,
              child: PetCanvas(engine: _engine, displaySize: _petSize),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final sprites = PetRegistry.instance.all;
    final economy = PetEconomy.instance;
    final hasFood = economy.inventory.isNotEmpty;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        // 状态显示（不可点击）
        PopupMenuItem(enabled: false, height: 40, child: Row(
          children: [
            const Icon(Icons.monetization_on, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text('${economy.coins}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            const Icon(Icons.fastfood, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Text('${economy.satiety}', style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 12),
            const Icon(Icons.favorite, size: 14, color: Colors.pink),
            const SizedBox(width: 4),
            Text('${economy.happiness}', style: const TextStyle(fontSize: 12)),
          ],
        )),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'feed', enabled: hasFood, child: ListTile(
          dense: true,
          leading: const Icon(Icons.restaurant, size: 18),
          title: Text(hasFood ? context.s.petFeedButton : context.s.petFeedButtonEmpty, style: const TextStyle(fontSize: 13)),
        )),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'hide', child: ListTile(
          dense: true,
          leading: const Icon(Icons.visibility_off, size: 18),
          title: Text(context.s.petContextHide, style: const TextStyle(fontSize: 13)),
        )),
        const PopupMenuDivider(),
        ...sprites.map((sprite) => PopupMenuItem(
          value: 'sprite:${sprite.id}',
          child: ListTile(
            dense: true,
            leading: Icon(
              sprite.id == _engine.sprite.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
            ),
            title: Text(sprite.name, style: const TextStyle(fontSize: 13)),
          ),
        )),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      if (value == 'hide') {
        _controller.hide();
      } else if (value == 'feed') {
        _showFeedDialog(context);
      } else if (value.startsWith('sprite:')) {
        final id = value.substring(7);
        final sprite = sprites.firstWhere((s) => s.id == id);
        _controller.switchSprite(sprite);
      }
    });
  }

  void _showFeedDialog(BuildContext context) {
    final economy = PetEconomy.instance;
    final s = context.s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.petFeedTitle),
        content: SizedBox(
          width: 300,
          child: economy.inventory.isEmpty
              ? Text(s.petFeedEmpty)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: economy.inventory.map((entry) {
                    final item = PetShop.instance.getItem(entry.itemId);
                    if (item == null) return const SizedBox.shrink();
                    return ListTile(
                      leading: FoodSprite(item: item, size: 32),
                      title: Text(petL10n(s, item.nameKey)),
                      subtitle: Text(s.petFeedStat(entry.quantity, item.satietyRestore, item.happinessBoost)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final fed = await economy.feedPet(entry.itemId);
                        if (fed != null) {
                          // 触发宠物开心动画
                          if (fed.specialEffect == 'crazy') {
                            _engine.sendEvent(PetEvent.drag); // 发疯
                          } else if (fed.specialEffect == 'play') {
                            _engine.playAnimation('run');
                          } else {
                            _engine.sendEvent(PetEvent.doubleTap); // 开心
                          }
                        }
                      },
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.petFeedClose),
          ),
        ],
      ),
    );
  }
}

/// 全局浮动宠物控制器 — 单例
///
/// 确保全局只有一个宠物实例，管理 PetEngine 生命周期、可见性和全局观察
class FloatingPetController {
  FloatingPetController._() {
    _engine = PetEngine(sprite: PetRegistry.instance.all.first);
    _engine.initialize();
    _subscribeObserver();
    _bindTts();
    _bindChat();
    _loadVisibility();
  }

  static final FloatingPetController instance = FloatingPetController._();

  late final PetEngine _engine;
  final ValueNotifier<bool> visibleNotifier = ValueNotifier(true);
  final ValueNotifier<Offset> positionNotifier = ValueNotifier(const Offset(100, 100));
  StreamSubscription<PetObserveEvent>? _observerSub;

  PetEngine get engine => _engine;
  bool get visible => visibleNotifier.value;

  /// 显示宠物
  void show() {
    visibleNotifier.value = true;
    _persistVisibility();
  }

  /// 隐藏宠物
  void hide() {
    visibleNotifier.value = false;
    _persistVisibility();
  }

  /// 切换显示/隐藏
  void toggleVisibility() {
    visibleNotifier.value = !visibleNotifier.value;
    _persistVisibility();
  }

  // ─── 可见性持久化 ───

  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'pet_config.json'));
  }

  /// 从本地加载可见性状态
  Future<void> _loadVisibility() async {
    try {
      final file = await _configFile();
      if (file.existsSync()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final visible = json['visible'] as bool? ?? true;
        visibleNotifier.value = visible;
      }
    } catch (_) {}
  }

  /// 持久化当前可见性状态
  Future<void> _persistVisibility() async {
    try {
      final file = await _configFile();
      final json = <String, dynamic>{'visible': visibleNotifier.value};
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  /// 切换精灵
  Future<void> switchSprite(PetSpriteSheet sprite) async {
    await _engine.changeSpriteSheet(sprite);
  }

  /// 发送事件
  void sendEvent(PetEvent event) {
    _engine.sendEvent(event);
  }

  /// 让宠物说话（TTS）
  Future<void> petSpeak(String text, {String? emotion}) async {
    _engine.sendEvent(PetEvent.ttsStart);
    await TtsService.instance.speak(text, context: emotion);
    _engine.sendEvent(PetEvent.ttsEnd);
  }

  /// 释放资源（app 退出时调用）
  void dispose() {
    _observerSub?.cancel();
    _engine.dispose();
    visibleNotifier.dispose();
  }

  // ─── TTS 绑定 ───

  void _bindTts() {
    TtsService.instance.onSpeakStart = () {
      _engine.sendEvent(PetEvent.ttsStart);
    };
    TtsService.instance.onSpeakEnd = () {
      _engine.sendEvent(PetEvent.ttsEnd);
    };
  }

  // ─── Chat 绑定 ───

  void _bindChat() {
    PetChatService.instance.onSummonPet = () {
      if (!visible) show();
    };
  }

  // ─── 观察者订阅：将全局事件映射为宠物行为 ───

  void _subscribeObserver() {
    _observerSub = PetObserver.instance.stream.listen(_onObserveEvent);
  }

  void _onObserveEvent(PetObserveEvent event) {
    switch (event.type) {
      // 用户长时间没操作 → 宠物睡觉
      case PetObserveType.userIdle:
        _engine.stateMachine.setState(PetState.sleeping);
        _engine.playAnimation('sleep');
        break;

      // 用户回来了 → 宠物开心迎接
      case PetObserveType.userActive:
      case PetObserveType.windowFocused:
        _engine.sendEvent(PetEvent.doubleTap); // happy
        break;

      // AI 正在生成 → 宠物观望（look 动画）
      case PetObserveType.aiGenerating:
        _engine.stateMachine.setState(PetState.listening);
        _engine.playAnimation('idle_look');
        break;

      // AI 完成回复 → 宠物开心
      case PetObserveType.aiCompleted:
        _engine.sendEvent(PetEvent.doubleTap);
        break;

      // AI 出错 → 宠物做伸展（angry/stretch 动画）
      case PetObserveType.aiError:
        _engine.stateMachine.setState(PetState.angry);
        _engine.playAnimation('stretch');
        break;

      // 提醒触发 → 宠物跳跃引起注意
      case PetObserveType.reminderFired:
        _engine.sendEvent(PetEvent.drag); // jump
        break;

      // 窗口失去焦点 → 宠物坐下等待
      case PetObserveType.windowBlurred:
        _engine.stateMachine.setState(PetState.sitting);
        _engine.playAnimation('sit');
        break;

      // 用户切换页面 → 宠物短暂看一下
      case PetObserveType.pageChanged:
        _engine.playAnimation('idle_look');
        break;

      // 其他事件暂不处理，让状态机自然运转
      default:
        break;
    }
  }
}

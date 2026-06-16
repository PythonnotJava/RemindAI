import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tts/tts_service.dart';

/// 提问模式的基类 — 支持内置模式和用户自定义模式
class PetAskModeBase {
  final String label;
  final String systemPrompt;

  const PetAskModeBase({required this.label, required this.systemPrompt});
}

/// 内置的向小猫提问模式
enum PetAskMode implements PetAskModeBase {
  /// 是什么 — 解释概念
  what('是什么', '请用简洁易懂的语言解释以下内容是什么：'),

  /// 为什么 — 分析原因
  why('为什么', '请分析以下内容的原因或背后的逻辑：'),

  /// 怎么做 — 给出方法
  how('怎么做', '请给出具体的操作步骤或解决方案：'),

  /// 帮我实现 — 代码实现
  implement('帮我实现', '请帮我实现以下需求，给出完整代码：');

  @override
  final String label;
  @override
  final String systemPrompt;
  const PetAskMode(this.label, this.systemPrompt);
}

/// 用户自定义的提问指令
class CustomPetCommand extends PetAskModeBase {
  final String id;

  CustomPetCommand({
    required this.id,
    required super.label,
    required super.systemPrompt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'systemPrompt': systemPrompt,
  };

  factory CustomPetCommand.fromJson(Map<String, dynamic> json) {
    return CustomPetCommand(
      id: json['id'] as String,
      label: json['label'] as String,
      systemPrompt: json['systemPrompt'] as String,
    );
  }
}

/// 小猫回复内容
class PetReply {
  final String text;
  final bool useTts; // 是否使用语音
  final DateTime timestamp;

  PetReply({required this.text, required this.useTts})
      : timestamp = DateTime.now();
}

/// 宠物对话服务 — 管理小猫的 AI 对话能力
///
/// 接收用户选中的文本 + 提问模式，调用绑定的模型生成回答，
/// 根据长度阈值决定用 TTS 语音回答还是文本气泡展示。
class PetChatService extends ChangeNotifier {
  PetChatService._();
  static final PetChatService instance = PetChatService._();

  /// 语音回答的长度阈值（字符数），超过此长度用文本气泡
  int ttsMaxLength = 80;

  /// 气泡自动关闭倒计时（秒），0 表示手动关闭
  int bubbleDismissSeconds = 5;

  /// 当前回复（供 UI 监听展示气泡）
  PetReply? _currentReply;
  PetReply? get currentReply => _currentReply;

  /// 是否正在思考
  bool _isThinking = false;
  bool get isThinking => _isThinking;

  /// 倒计时剩余秒数 (供 UI 显示)
  int _countdown = 0;
  int get countdown => _countdown;

  /// 倒计时定时器
  Timer? _dismissTimer;

  /// 无模型时的提示文本（由 UI 层注入国际化文本）
  String noModelText = '喵~ 我还没有绑定模型，请在宠物设置中选择一个模型。';

  /// 错误提示格式化函数（由 UI 层注入）
  String Function(String error) formatError = (e) => '喵呜...出错了: $e';

  /// 绑定的模型 ID（从宠物设置中选择）
  String? modelId;

  /// AI 生成回调 — 由外部注入（连接到 LLM 调用链）
  Future<String> Function(String prompt)? onGenerate;

  /// 召唤宠物显示的回调（由 FloatingPetController 注入）
  VoidCallback? onSummonPet;

  /// 用户自定义的提问指令列表
  final List<CustomPetCommand> _customCommands = [];
  List<CustomPetCommand> get customCommands => List.unmodifiable(_customCommands);

  /// 所有可用的提问模式（内置 + 自定义）
  List<PetAskModeBase> get allAskModes => [
    ...PetAskMode.values,
    ..._customCommands,
  ];

  /// 添加自定义指令
  void addCustomCommand(CustomPetCommand command) {
    _customCommands.add(command);
    notifyListeners();
  }

  /// 删除自定义指令
  void removeCustomCommand(String id) {
    _customCommands.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// 更新自定义指令
  void updateCustomCommand(CustomPetCommand command) {
    final idx = _customCommands.indexWhere((c) => c.id == command.id);
    if (idx >= 0) {
      _customCommands[idx] = command;
      notifyListeners();
    }
  }

  /// 批量设置自定义指令（从持久化恢复）
  void setCustomCommands(List<CustomPetCommand> commands) {
    _customCommands
      ..clear()
      ..addAll(commands);
    notifyListeners();
  }

  /// 向小猫提问
  Future<void> ask(String selectedText, PetAskModeBase mode) async {
    if (selectedText.trim().isEmpty) return;

    // 召唤宠物（如果被隐藏）
    onSummonPet?.call();

    if (onGenerate == null) {
      _showReply(noModelText, forceText: true);
      return;
    }

    _isThinking = true;
    _currentReply = null;
    notifyListeners();

    try {
      final prompt = '${mode.systemPrompt}\n\n「$selectedText」\n\n'
          '要求：回答简洁有用，不要啰嗦。如果内容简单，一两句话即可。';
      final reply = await onGenerate!(prompt);
      _showReply(reply);
    } catch (e) {
      _showReply(formatError(e.toString()), forceText: true);
    } finally {
      _isThinking = false;
      notifyListeners();
    }
  }

  /// 用户手动投喂文本给小猫（从气泡中再次提问）
  Future<void> feedText(String text, PetAskModeBase mode) async {
    await ask(text, mode);
  }

  /// 关闭当前气泡（同时取消倒计时）
  void dismissReply() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _countdown = 0;
    _currentReply = null;
    notifyListeners();
  }

  void _showReply(String text, {bool forceText = false}) {
    final useTts = !forceText && text.length <= ttsMaxLength;
    _currentReply = PetReply(text: text, useTts: useTts);
    notifyListeners();

    if (useTts) {
      // TTS 失败时降级为文本气泡
      TtsService.instance.speak(text).then((success) {
        if (!success && _currentReply?.text == text) {
          _currentReply = PetReply(text: text, useTts: false);
          _startDismissCountdown();
          notifyListeners();
        }
      });
    }

    // 非 TTS 的气泡启动自动关闭倒计时
    if (!useTts) {
      _startDismissCountdown();
    }
  }

  /// 启动气泡自动关闭倒计时
  void _startDismissCountdown() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _countdown = 0;

    if (bubbleDismissSeconds <= 0) return; // 0 = 手动关闭

    _countdown = bubbleDismissSeconds;
    notifyListeners();

    _dismissTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdown--;
      if (_countdown <= 0) {
        timer.cancel();
        _dismissTimer = null;
        dismissReply();
      } else {
        notifyListeners();
      }
    });
  }

  /// 用户交互时重置倒计时（如滚动、选中文本）
  void resetDismissCountdown() {
    if (_currentReply != null && bubbleDismissSeconds > 0) {
      _startDismissCountdown();
    }
  }

  /// 宠物币奖励文本格式化（由 UI 层注入国际化文本）
  String Function(int amount) formatCoinReward = (amount) => '+$amount 宠物币~';

  /// 显示宠物币奖励通知（不触发 TTS，短暂展示后自动消失）
  void showCoinReward(int amount) {
    if (amount <= 0) return;
    // 如果当前正在显示其他内容，不打断
    if (_currentReply != null || _isThinking) return;

    _currentReply = PetReply(text: formatCoinReward(amount), useTts: false);
    notifyListeners();

    // 2 秒后自动消失
    _dismissTimer?.cancel();
    _countdown = 2;
    _dismissTimer = Timer(const Duration(seconds: 2), () {
      _dismissTimer = null;
      _countdown = 0;
      _currentReply = null;
      notifyListeners();
    });
  }
}

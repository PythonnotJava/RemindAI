import 'dart:async';

import 'package:flutter/widgets.dart';

/// 宠物可观察的全局事件类型
enum PetObserveType {
  /// 用户切换页面
  pageChanged,

  /// 用户发送了消息
  userMessageSent,

  /// AI 开始生成回复
  aiGenerating,

  /// AI 回复完成
  aiCompleted,

  /// AI 回复出错
  aiError,

  /// 用户长时间无操作
  userIdle,

  /// 用户从 idle 恢复操作
  userActive,

  /// 窗口获得焦点
  windowFocused,

  /// 窗口失去焦点
  windowBlurred,

  /// 剪贴板有新内容
  clipboardChanged,

  /// 提醒/通知触发
  reminderFired,

  /// 定时任务完成
  taskCompleted,

  /// 用户复制了代码
  codeCopied,
}

/// 全局观察事件
class PetObserveEvent {
  final PetObserveType type;
  final String? detail;
  final DateTime timestamp;

  PetObserveEvent({required this.type, this.detail})
    : timestamp = DateTime.now();

  @override
  String toString() => 'PetObserveEvent($type, detail: $detail)';
}

/// 全局宠物观察者 — 事件总线
///
/// 设计：
/// - App 各处调用 [emit] 发射事件
/// - 宠物引擎订阅 [stream] 做出反应
/// - 内置用户活跃检测（idle/active）
/// - 维护最近事件历史（供 AI 总结上下文用）
class PetObserver with WidgetsBindingObserver {
  PetObserver._();
  static final PetObserver instance = PetObserver._();

  final _controller = StreamController<PetObserveEvent>.broadcast();
  final List<PetObserveEvent> _history = [];
  static const int _maxHistory = 50;

  Timer? _idleTimer;
  bool _isIdle = false;
  Duration idleThreshold = const Duration(minutes: 3);

  /// 当前用户所在页面
  String _currentPage = 'chat';
  String get currentPage => _currentPage;

  /// 事件流 — 宠物引擎订阅
  Stream<PetObserveEvent> get stream => _controller.stream;

  /// 最近事件历史（供 AI 做上下文感知）
  List<PetObserveEvent> get history => List.unmodifiable(_history);

  /// 初始化（在 app 启动时调用一次）
  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();
  }

  /// 释放
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _controller.close();
  }

  // ─── 公开 API：各处调用 ───

  /// 发射事件
  void emit(PetObserveType type, {String? detail}) {
    final event = PetObserveEvent(type: type, detail: detail);
    _history.add(event);
    if (_history.length > _maxHistory) _history.removeAt(0);
    _controller.add(event);

    // 任何用户主动操作都重置 idle 计时
    if (_isUserAction(type)) {
      _onUserActive();
    }
  }

  /// 页面切换
  void notifyPageChanged(String pageId) {
    _currentPage = pageId;
    emit(PetObserveType.pageChanged, detail: pageId);
  }

  /// 用户发消息
  void notifyUserMessage({String? preview}) {
    emit(PetObserveType.userMessageSent, detail: preview);
  }

  /// AI 开始生成
  void notifyAiGenerating() {
    emit(PetObserveType.aiGenerating);
  }

  /// AI 完成回复
  void notifyAiCompleted({String? summary}) {
    emit(PetObserveType.aiCompleted, detail: summary);
  }

  /// AI 出错
  void notifyAiError({String? error}) {
    emit(PetObserveType.aiError, detail: error);
  }

  /// 提醒触发
  void notifyReminder({String? title}) {
    emit(PetObserveType.reminderFired, detail: title);
  }

  /// 任务完成
  void notifyTaskCompleted({String? taskName}) {
    emit(PetObserveType.taskCompleted, detail: taskName);
  }

  // ─── 窗口焦点 ───

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        emit(PetObserveType.windowFocused);
        _onUserActive();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        emit(PetObserveType.windowBlurred);
        break;
      default:
        break;
    }
  }

  // ─── Idle 检测 ───

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleThreshold, _onUserIdle);
  }

  void _onUserIdle() {
    if (_isIdle) return;
    _isIdle = true;
    emit(PetObserveType.userIdle);
  }

  void _onUserActive() {
    if (_isIdle) {
      _isIdle = false;
      emit(PetObserveType.userActive);
    }
    _resetIdleTimer();
  }

  bool _isUserAction(PetObserveType type) {
    return type == PetObserveType.userMessageSent ||
        type == PetObserveType.pageChanged ||
        type == PetObserveType.codeCopied ||
        type == PetObserveType.clipboardChanged ||
        type == PetObserveType.windowFocused;
  }

  /// 获取最近 N 条事件的文字摘要（喂给 AI 用）
  String getRecentContext({int count = 10}) {
    final recent = _history.length > count
        ? _history.sublist(_history.length - count)
        : _history;
    if (recent.isEmpty) return '暂无活动';
    final buffer = StringBuffer();
    for (final e in recent) {
      final time =
          '${e.timestamp.hour}:${e.timestamp.minute.toString().padLeft(2, '0')}';
      buffer.writeln(
        '[$time] ${e.type.name}${e.detail != null ? ': ${e.detail}' : ''}',
      );
    }
    return buffer.toString();
  }
}

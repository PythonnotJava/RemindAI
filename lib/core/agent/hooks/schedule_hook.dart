import 'dart:io';
import 'dart:math';

import '../../logger/app_logger.dart';
import '../../llm/llm_client.dart';
import '../agent_hook.dart';

/// Schedule 元技能 Hook — 在框架层强制驱动计划回顾与更新
///
/// 三重机制确保计划不被遗忘：
/// 1. 对话首轮 + 每隔 N 轮自动注入 SCHEDULE.md 摘要
/// 2. 检测到实质性工作完成时，提醒模型调 schedule_complete
/// 3. 关键词触发时强制注入
class ScheduleHook extends AgentHook {
  final String projectRoot;

  /// 每隔多少轮用户消息强制注入一次 schedule 上下文
  final int recallInterval;

  /// 首次注入的概率 (1.0 = 必定注入)
  final double firstRecallProbability;

  /// 后续注入的概率 (0.5 = 50% 触发)
  final double subsequentRecallProbability;

  /// 用户消息计数器
  int _messageCount = 0;

  /// 是否已在本次会话中注入过
  bool _hasInjected = false;

  /// 上一轮是否有实质性工具调用（写文件/执行命令/完成修改等）
  bool _lastRoundHadWork = false;

  /// 当前会话的待办任务缓存（用于匹配是否完成）
  List<String> _pendingTasks = [];

  final _random = Random();

  ScheduleHook({
    required this.projectRoot,
    this.recallInterval = 5,
    this.firstRecallProbability = 1.0,
    this.subsequentRecallProbability = 0.5,
  });

  @override
  Future<String?> onBeforeUserMessage(
    String input,
    List<Map<String, dynamic>> messages,
  ) async {
    _messageCount++;

    // ─── 完成检测: 上一轮有实质工作 → 提醒模型标记完成 ───
    if (_lastRoundHadWork && _pendingTasks.isNotEmpty) {
      final hint = _buildCompletionHint(messages);
      if (hint != null) {
        messages.add({'role': 'system', 'content': hint});
        AppLogger.instance.log('[Schedule] 已注入任务完成提醒');
        print('[Schedule] 💡 检测到任务可能已完成，已提醒模型标记');
      }
    }
    _lastRoundHadWork = false;

    // ─── 计划注入 ───
    if (!_shouldInject(input)) return null;

    try {
      final content = await _loadSchedule();
      if (content == null) return null;

      final summary = _buildSummary(content);
      if (summary.isEmpty) return null;

      messages.add({'role': 'system', 'content': '[当前工作计划]\n$summary'});

      _hasInjected = true;
      AppLogger.instance.log(
        '[Schedule] 已注入计划上下文 (第$_messageCount轮, '
        '${content.length}字)',
      );
      print('[Schedule] ✓ 计划上下文已注入 (第$_messageCount轮)');
    } catch (e) {
      AppLogger.instance.log('[Schedule] 注入失败: $e');
    }

    return null;
  }

  @override
  Future<void> onAfterLlmCall(
    String? content,
    List<ToolCall> toolCalls,
    int durationMs,
  ) async {
    // 检测本轮是否有实质性工具调用
    if (toolCalls.isNotEmpty) {
      const workTools = {
        'toolshell_write',
        'toolshell_exec',
        'toolshell_run_python',
        'toolshell_run_js',
        'toolshell_delete',
        'schedule_complete', // 如果模型自己调了 complete，不用再提醒
      };
      final hasWork = toolCalls.any((tc) => workTools.contains(tc.name));
      if (hasWork) {
        _lastRoundHadWork = true;
      }
      // 如果模型已经自己调了 schedule_complete，就不用再提醒
      if (toolCalls.any((tc) => tc.name == 'schedule_complete')) {
        _lastRoundHadWork = false;
      }
    }
  }

  /// 判断本轮是否应该注入 schedule
  bool _shouldInject(String input) {
    final inputLower = input.toLowerCase();

    // 强制触发关键词
    const forceKeywords = [
      '计划',
      '进度',
      '任务',
      'schedule',
      'todo',
      '接下来',
      '做什么',
      '下一步',
      '优先级',
      '还剩',
    ];
    if (forceKeywords.any(inputLower.contains)) return true;

    // 首次: 高概率注入（让模型一开始就看到计划）
    if (!_hasInjected) {
      return _random.nextDouble() < firstRecallProbability;
    }

    // 周期性: 每 N 轮必定触发一次
    if (_messageCount % recallInterval == 0) return true;

    // 中间轮次: 按概率触发
    return _random.nextDouble() < subsequentRecallProbability;
  }

  /// 读取 SCHEDULE.md 文件
  Future<String?> _loadSchedule() async {
    final file = File('$projectRoot/SCHEDULE.md');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// 构建任务完成提醒
  ///
  /// 分析 messages 中最近的 assistant 回复，判断是否提到了
  /// 某个待办任务相关的完成信号。
  String? _buildCompletionHint(List<Map<String, dynamic>> messages) {
    // 取最近的 assistant 回复
    String? lastAssistant;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'assistant') {
        final c = messages[i]['content'];
        if (c is String && c.isNotEmpty) {
          lastAssistant = c;
          break;
        }
      }
    }
    if (lastAssistant == null) return null;

    final replyLower = lastAssistant.toLowerCase();

    // 完成信号词
    const doneSignals = [
      '已完成',
      '完成了',
      '搞定',
      '修好了',
      '已修复',
      '已实现',
      '已添加',
      '已创建',
      '已删除',
      '已更新',
      '已重构',
      'done',
      'fixed',
      'implemented',
      'completed',
    ];
    final hasDoneSignal = doneSignals.any(replyLower.contains);
    if (!hasDoneSignal) return null;

    // 匹配哪个任务可能被完成了
    for (final task in _pendingTasks) {
      final taskKeywords = _extractTaskKeywords(task);
      final matchCount = taskKeywords.where(replyLower.contains).length;
      // 至少匹配到 2 个关键词才认为相关
      if (matchCount >= 2) {
        return '[Schedule 提醒] '
            '你刚才的工作似乎完成了计划中的任务: "$task"。'
            '如果确实已完成，请调用 schedule_complete(task_match: "${_taskMatchKey(task)}") 标记。';
      }
    }

    // 有完成信号但无法匹配到具体任务 → 通用提醒
    return '[Schedule 提醒] '
        '你刚才似乎完成了一项工作。如果它对应 SCHEDULE 中的某个任务，'
        '请用 schedule_complete 标记完成。';
  }

  /// 从任务描述中提取关键词（用于模糊匹配）
  List<String> _extractTaskKeywords(String task) {
    // 去除标签和备注
    final cleaned = task
        .replaceAll(RegExp(r'`#\w+`'), '')
        .replaceAll(RegExp(r'—.*$'), '')
        .trim()
        .toLowerCase();
    // 按空格/标点分词，保留 >= 2 字符的 token
    final tokens = cleaned
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), ' ')
        .split(' ')
        .where((w) => w.length >= 2)
        .toList();
    // 中文 bigram
    final result = <String>{...tokens};
    for (final token in tokens) {
      final zhChars = RegExp(r'[\u4e00-\u9fff]+').allMatches(token);
      for (final m in zhChars) {
        final chars = m.group(0)!;
        for (var i = 0; i < chars.length - 1; i++) {
          result.add(chars.substring(i, i + 2));
        }
      }
    }
    return result.toList();
  }

  /// 提取任务匹配 key（取前 20 字符作为 task_match 参数）
  String _taskMatchKey(String task) {
    final cleaned = task
        .replaceAll(RegExp(r'`#\w+`'), '')
        .replaceAll(RegExp(r'—.*$'), '')
        .trim();
    return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
  }

  /// 从 SCHEDULE.md 内容构建精简摘要（注入到 context 的内容）
  String _buildSummary(String content) {
    final lines = content.split('\n');
    final summary = StringBuffer();

    // 提取统计
    int p0 = 0, p1 = 0, p2 = 0, done = 0;
    String currentSection = '';
    final p0Tasks = <String>[];
    final p1Tasks = <String>[];

    for (final line in lines) {
      if (line.startsWith('## 🔴')) {
        currentSection = 'P0';
      } else if (line.startsWith('## 🟡')) {
        currentSection = 'P1';
      } else if (line.startsWith('## 🟢')) {
        currentSection = 'P2';
      } else if (line.startsWith('## ✅')) {
        currentSection = 'done';
      } else if (line.startsWith('- [ ]')) {
        final task = line.replaceFirst('- [ ] ', '').trim();
        switch (currentSection) {
          case 'P0':
            p0++;
            p0Tasks.add(task);
          case 'P1':
            p1++;
            if (p1Tasks.length < 5) p1Tasks.add(task);
          case 'P2':
            p2++;
        }
      } else if (line.startsWith('- [x]')) {
        done++;
      }
    }

    // 更新待办任务缓存（供完成检测用）
    _pendingTasks = [...p0Tasks, ...p1Tasks];

    final total = p0 + p1 + p2;
    if (total == 0 && done == 0) return '';

    summary.writeln('待办: $total项 (P0:$p0 P1:$p1 P2:$p2) | 已完成: $done');

    if (p0Tasks.isNotEmpty) {
      summary.writeln('');
      summary.writeln('🔴 紧急 (必须优先处理):');
      for (final t in p0Tasks) {
        summary.writeln('  - $t');
      }
    }

    if (p1Tasks.isNotEmpty) {
      summary.writeln('');
      summary.writeln('🟡 重要:');
      for (final t in p1Tasks) {
        summary.writeln('  - $t');
      }
    }

    if (total > 0) {
      summary.writeln('');
      summary.writeln(
        '提示: 完成当前任务后请用 schedule_complete 标记; '
        '发现新问题请用 schedule_add_task 插入。',
      );
    }

    return summary.toString().trim();
  }
}

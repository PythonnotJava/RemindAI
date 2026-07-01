import 'dart:async';

import '../llm/llm_client.dart';
import '../agent/agent_hook.dart';
import '../agent/message_pipeline.dart';
import '../logger/app_logger.dart';
import 'agent_loop.dart';
import 'executor.dart';

/// Loop 模式配置
class LoopConfig {
  /// 最大迭代次数
  final int maxIterations;

  /// 是否自动批准工具操作（Loop 模式默认 true）
  final bool autoApprove;

  const LoopConfig({this.maxIterations = 10, this.autoApprove = true});
}

/// Loop 事件 (驱动 UI 更新)
sealed class LoopEvent {}

/// 新一轮迭代开始
class LoopIterStart extends LoopEvent {
  final int iteration;
  final int maxIterations;
  LoopIterStart(this.iteration, this.maxIterations);
}

/// 迭代中的 Agent 事件（透传 AgentLoop 的事件）
class LoopAgentEvent extends LoopEvent {
  final AgentEvent event;
  LoopAgentEvent(this.event);
}

/// Loop 正常完成（Agent 声明完成）
class LoopDone extends LoopEvent {
  final int totalIterations;
  final String summary;
  LoopDone({required this.totalIterations, required this.summary});
}

/// Loop 因达到最大迭代而终止
class LoopExhausted extends LoopEvent {
  final int maxIterations;
  final String lastOutput;
  LoopExhausted({required this.maxIterations, required this.lastOutput});
}

/// Loop 被 Agent 主动放弃
class LoopAbort extends LoopEvent {
  final int iteration;
  final String reason;
  LoopAbort({required this.iteration, required this.reason});
}

/// Loop 出错
class LoopError extends LoopEvent {
  final int iteration;
  final String message;
  LoopError({required this.iteration, required this.message});
}

/// 无进展检测触发
class LoopStalled extends LoopEvent {
  final int iteration;
  LoopStalled(this.iteration);
}

/// 自治循环 — 让 Agent 自主执行、验证、修复直到完成。
///
/// 包裹 [AgentLoop]，在每轮结束后检查 Agent 输出：
/// - 包含 [LOOP_DONE] → 提取总结，结束循环
/// - 包含 [LOOP_ABORT] → 提取原因，放弃循环
/// - 否则 → 自动发起下一轮（将上一轮结果作为上下文）
///
/// 上下文策略：保留完整历史，依赖 MessagePipeline 的 ContextCompactor
/// 在 token 超限时自动压缩。这保证了 Agent 在早期轮次的操作不会丢失。
class AutonomousLoop {
  final LlmClient llm;
  final Executor executor;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, dynamic>> messages;
  final MessagePipeline messagePipeline;
  final List<AgentHook> hooks;
  final LoopConfig config;

  AutonomousLoop({
    required this.llm,
    required this.executor,
    required this.tools,
    required this.messages,
    required this.config,
    this.messagePipeline = const MessagePipeline(),
    this.hooks = const [],
  });

  /// Loop 模式注入到 system prompt 的指令
  static const String loopSystemInstruction = '''

[LOOP MODE ACTIVE]
你当前处于 Loop 模式 — 你可以自主迭代直到任务完成。

规则：
1. 每轮清晰说明：目标 → 操作 → 验证 → 结果
2. 主动验证你的修改（运行测试、检查输出、重新编译等）
3. 如果验证失败，先分析根因再修复，不要盲目重试相同方案
4. 连续失败时换一个完全不同的思路
5. 任务完成时，你必须输出标记 [LOOP_DONE]，后面跟你的完成总结（做了什么、结果如何）
6. 如果你判断任务无法完成，输出 [LOOP_ABORT]，后面跟原因

示例输出格式：
- 完成时: "...验证通过。[LOOP_DONE] 修复了3个测试失败：1) xxx 2) yyy 3) zzz，全部测试现在通过。"
- 放弃时: "[LOOP_ABORT] 该问题需要升级依赖版本，超出当前任务范围。"
''';

  /// 执行自治循环
  Stream<LoopEvent> run(String userInput) async* {
    // 注入 Loop 指令到 system prompt
    _injectLoopInstruction();

    String? lastOutput;

    for (var iteration = 1; iteration <= config.maxIterations; iteration++) {
      yield LoopIterStart(iteration, config.maxIterations);
      AppLogger.instance.log('[Loop] 开始第 $iteration/${config.maxIterations} 轮');

      // 构建本轮输入
      final String input;
      if (iteration == 1) {
        input = userInput;
      } else {
        // 后续轮次：提醒 Agent 继续
        input = _buildContinuePrompt(iteration, lastOutput);
      }

      // 执行 AgentLoop
      final agentLoop = AgentLoop(
        llm: llm,
        executor: executor,
        tools: tools,
        messages: messages,
        messagePipeline: messagePipeline,
        hooks: hooks,
      );

      final buffer = StringBuffer();
      bool hasError = false;

      await for (final event in agentLoop.chat(input)) {
        // 透传所有 AgentEvent 给 UI
        yield LoopAgentEvent(event);

        switch (event) {
          case AgentToken(text: final text):
            buffer.write(text);
          case AgentToolStart(name: _, args: _):
            break;
          case AgentToolResult(toolCallId: _, result: _):
            break;
          case AgentDone(content: final content):
            if (content.isNotEmpty) {
              buffer.clear();
              buffer.write(content);
            }
          case AgentError(message: final msg):
            hasError = true;
            yield LoopError(iteration: iteration, message: msg);
            return;
        }
      }

      final output = buffer.toString();
      final previousOutput = lastOutput;
      lastOutput = output;

      AppLogger.instance.log('[Loop] 第 $iteration 轮完成, 输出长度=${output.length}');

      // 检查终止条件
      if (_isDone(output)) {
        final summary = _extractSummary(output, '[LOOP_DONE]');
        AppLogger.instance.log('[Loop] Agent 声明完成: $summary');
        yield LoopDone(totalIterations: iteration, summary: summary);
        return;
      }

      if (_isAbort(output)) {
        final reason = _extractSummary(output, '[LOOP_ABORT]');
        AppLogger.instance.log('[Loop] Agent 放弃: $reason');
        yield LoopAbort(iteration: iteration, reason: reason);
        return;
      }

      // 无进展检测：连续两轮输出高度相似
      if (previousOutput != null && _isStalledOutput(previousOutput, output)) {
        AppLogger.instance.log('[Loop] 检测到无进展，终止');
        yield LoopStalled(iteration);
        return;
      }

      if (hasError) return;
    }

    // 达到最大迭代
    AppLogger.instance.log('[Loop] 达到最大迭代 ${config.maxIterations}');
    yield LoopExhausted(
      maxIterations: config.maxIterations,
      lastOutput: lastOutput ?? '',
    );
  }

  // ─── 内部方法 ─────────────────────────────────────────────

  /// 注入 Loop 指令到第一条 system message
  void _injectLoopInstruction() {
    if (messages.isNotEmpty && messages.first['role'] == 'system') {
      final existing = messages.first['content'] as String;
      if (!existing.contains('[LOOP MODE ACTIVE]')) {
        messages.first['content'] = existing + loopSystemInstruction;
      }
    }
  }

  /// 构建后续轮次的 continue prompt
  String _buildContinuePrompt(int iteration, String? lastOutput) {
    final buffer = StringBuffer();
    buffer.writeln('[Loop 第 $iteration 轮 — 请继续]');
    buffer.writeln('上一轮你的操作已执行完毕。请检查结果并继续推进任务。');
    buffer.writeln('如果任务已完成，请输出 [LOOP_DONE] + 总结。');
    buffer.writeln('如果需要继续，请直接执行下一步操作。');
    return buffer.toString();
  }

  bool _isDone(String output) => output.contains('[LOOP_DONE]');
  bool _isAbort(String output) => output.contains('[LOOP_ABORT]');

  /// 从输出中提取标记后的内容作为总结
  String _extractSummary(String output, String marker) {
    final idx = output.indexOf(marker);
    if (idx < 0) return output;
    final after = output.substring(idx + marker.length).trim();
    // 也包含标记前的最后一句话（通常是验证结果）
    final before = output.substring(0, idx).trim();
    final lastSentence = before
        .split('\n')
        .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (lastSentence.isNotEmpty && after.isNotEmpty) {
      return '$lastSentence\n$after';
    }
    return after.isNotEmpty ? after : lastSentence;
  }

  /// 简单的无进展检测：两次输出相似度 > 80%
  bool _isStalledOutput(String prev, String current) {
    if (prev.isEmpty || current.isEmpty) return false;
    // 比较前 500 字符
    final a = prev.length > 500 ? prev.substring(0, 500) : prev;
    final b = current.length > 500 ? current.substring(0, 500) : current;
    if (a == b) return true;
    // 简单 Jaccard: 按行比较
    final setA = a.split('\n').toSet();
    final setB = b.split('\n').toSet();
    if (setA.isEmpty || setB.isEmpty) return false;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union > 0 && (intersection / union) > 0.8;
  }
}

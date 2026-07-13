import 'dart:async';
import 'dart:convert';
import '../llm/llm_client.dart';
import '../agent/agent_hook.dart';
import '../agent/message_pipeline.dart';
import '../agent/transformers/context_compactor.dart';
import '../isolate/compute_service.dart';
import '../logger/app_logger.dart';
import 'executor.dart';

/// 解析 DeepSeek DSML 格式的工具调用标记。
///
/// DeepSeek 有时不通过标准 tool_calls 协议返回，而是将内部 DSML 标记
/// 作为文本内容输出。此解析器从文本中提取这些标记并转换为标准 [ToolCall]。
class _DsmlParser {
  // 匹配完整的 DSML tool_calls 块
  static final _blockRe = RegExp(
    r'<(?:｜｜DSML｜|︱DSML︱|DSML\|)tool_calls>([\s\S]*?)</(?:｜｜DSML｜|︱DSML︱|DSML\|)tool_calls>',
  );
  // 匹配单个 invoke 块
  static final _invokeRe = RegExp(
    r'<(?:｜｜DSML｜|︱DSML︱|DSML\|)invoke\s+name="([^"]+)">([\s\S]*?)</(?:｜｜DSML｜|︱DSML︱|DSML\|)(?:｜invoke|invoke)>',
  );
  // 匹配 parameter
  static final _paramRe = RegExp(
    r'<(?:｜｜DSML｜｜|︱DSML︱︱|DSML\|\|)parameter\s+name="([^"]+)">([\s\S]*?)</(?:｜｜DSML｜｜|︱DSML︱︱|DSML\|\|)parameter>',
  );

  /// 检测文本中是否含有 DSML 工具调用标记
  static bool hasDsml(String text) => _blockRe.hasMatch(text);

  /// 从文本中解析 DSML 工具调用，返回 (清理后的文本, 工具调用列表)
  static (String cleanedContent, List<ToolCall> toolCalls) parse(String text) {
    final toolCalls = <ToolCall>[];
    var cleaned = text;
    var callIndex = 0;

    for (final block in _blockRe.allMatches(text)) {
      final blockContent = block.group(1) ?? '';
      cleaned = cleaned.replaceFirst(block.group(0)!, '');

      for (final invoke in _invokeRe.allMatches(blockContent)) {
        final funcName = invoke.group(1) ?? '';
        final invokeBody = invoke.group(2) ?? '';
        final args = <String, dynamic>{};

        for (final param in _paramRe.allMatches(invokeBody)) {
          final key = param.group(1) ?? '';
          final value = param.group(2) ?? '';
          // 尝试解析为数字/bool，否则保持字符串
          args[key] = _parseValue(value);
        }

        toolCalls.add(
          ToolCall(
            id: 'dsml_call_${callIndex++}',
            name: funcName,
            arguments: args,
          ),
        );
      }
    }

    return (cleaned.trim(), toolCalls);
  }

  static dynamic _parseValue(String value) {
    final trimmed = value.trim();
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) return asDouble;
    // 尝试解析 JSON 对象/数组
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {}
    }
    return trimmed;
  }
}

/// Agent 事件 (驱动 UI 更新)
sealed class AgentEvent {}

class AgentToken extends AgentEvent {
  final String text;
  AgentToken(this.text);
}

/// 模型内部推理 token。与最终正文分开，避免 reasoning-only 响应被当作
/// 已完成的 assistant 正文写入历史。
class AgentReasoningToken extends AgentEvent {
  final String text;
  AgentReasoningToken(this.text);
}

class AgentToolStart extends AgentEvent {
  final String name;
  final Map<String, dynamic> args;
  AgentToolStart(this.name, this.args);
}

class AgentToolResult extends AgentEvent {
  final String toolCallId;
  final String result;
  AgentToolResult(this.toolCallId, this.result);
}

class AgentDone extends AgentEvent {
  final String content;
  AgentDone(this.content);
}

class AgentError extends AgentEvent {
  final String message;
  AgentError(this.message);
}

/// 单次 chat() 调用内，"LLM返回tool_calls → 执行 → 再问LLM"这个内层循环
/// 达到轮次上限仍未收到最终回复(无tool_calls的回复)时触发。
///
/// 这与 AutonomousLoop.maxIterations(多轮"Loop模式"的外层熔断，管的是
/// "调用几次 chat()")是完全不同粒度的保护——此事件管的是单次 chat()
/// 内部可能无限转圈的情况(例如模型反复调用同一个工具、或工具结果又
/// 诱导它继续调用另一个工具，一直不收敛到最终文本回复)。
class AgentLoopLimitReached extends AgentEvent {
  /// 触发熔断时已完成的 tool_call 轮次数
  final int rounds;
  AgentLoopLimitReached(this.rounds);
}

/// ToolShell Agent 循环 - Dart 原生实现 (流式版)
///
/// 所有轮次均使用 [LlmClient.chatStreamFull] 进行流式调用：
/// - 有 tool_calls → 执行工具后继续循环
/// - 无 tool_calls (最终回复) → 逐 token yield [AgentToken]，结束时 yield [AgentDone]
class AgentLoop {
  final LlmClient llm;
  final Executor executor;
  final List<Map<String, dynamic>> tools;
  final List<Map<String, dynamic>> messages;
  final MessagePipeline messagePipeline;
  final List<AgentHook> hooks;

  /// 单次 chat() 调用内允许的最大 tool_call 轮次数。超过后强制熔断，
  /// yield [AgentLoopLimitReached] 并结束循环，防止 LLM 一直不给最终
  /// 回复(反复调用工具)导致的无限循环。50轮对正常任务足够宽裕——
  /// 真正卡死的场景通常在几轮内就会重复同一模式，50只是防止真的失控。
  final int maxToolCallRounds;

  /// 模型的上下文窗口大小（token 数）。用于对话中压缩的阈值计算。
  /// 0 表示未知，会使用保守默认值 128K。
  final int contextWindow;

  AgentLoop({
    required this.llm,
    required this.executor,
    required this.tools,
    required this.messages,
    this.messagePipeline = const MessagePipeline(),
    this.hooks = const [],
    this.maxToolCallRounds = 50,
    this.contextWindow = 0,
  });

  /// 执行一轮对话 (用户输入 → 多轮 tool_call → 最终回复)
  /// 如果提供了 [contentParts]，则使用多模态格式发送用户消息
  Stream<AgentEvent> chat(
    String userInput, {
    List<Map<String, dynamic>>? contentParts,
  }) async* {
    if (contentParts != null && contentParts.isNotEmpty) {
      messages.add({'role': 'user', 'content': contentParts});
    } else {
      messages.add({'role': 'user', 'content': userInput});
    }

    var round = 0;
    while (true) {
      round++;
      if (round > maxToolCallRounds) {
        AppLogger.instance.log(
          '[AgentLoop] 达到单轮对话最大tool_call轮次上限($maxToolCallRounds)，强制熔断',
        );
        yield AgentLoopLimitReached(maxToolCallRounds);
        return;
      }

      // ─── 消息变换管线：在发送给 LLM 前处理消息列表 ───
      final effectiveMessages = await messagePipeline.process(messages);

      // ─── Hook: onBeforeLlmCall ───
      for (final hook in hooks) {
        await hook.onBeforeLlmCall(effectiveMessages, tools);
      }

      // 流式调用 LLM
      StreamComplete? completed;
      final stopwatch = Stopwatch()..start();
      try {
        await for (final event in llm.chatStreamFull(
          effectiveMessages,
          tools: tools,
        )) {
          switch (event) {
            case ContentToken(text: final text):
              // 实时推送 token 给 UI
              yield AgentToken(text);
            case ReasoningToken(text: final text):
              // 推理 token 与最终正文分开传递；不能作为 AgentDone 的正文兜底。
              yield AgentReasoningToken(text);
            case StreamComplete():
              completed = event;
          }
        }
      } catch (e, stackTrace) {
        stopwatch.stop();
        AppLogger.instance.log('[AgentLoop] LLM 调用失败: $e');
        AppLogger.instance.log('[AgentLoop] StackTrace: $stackTrace');
        yield AgentError('LLM 调用失败: $e');
        messages.removeLast();
        return;
      }
      stopwatch.stop();

      // 流异常结束，未收到 StreamComplete
      if (completed == null) {
        yield AgentError('LLM 流异常终止: 未收到完整响应');
        return;
      }

      // 截断/异常流不能伪装成正常完成。尤其推理模型可能只收到 reasoning，
      // 连接便被代理关闭；此时必须报告错误，不能写入空 assistant 消息。
      if (completed.isTruncated) {
        yield AgentError(
          'LLM 响应被截断（finish_reason=${completed.finishReason}）。'
          '模型尚未完成最终输出，请重试或检查网络、代理超时及上下文长度。',
        );
        return;
      }

      final finishReason = completed.finishReason.toLowerCase();
      const abnormalFinishReasons = {
        'length',
        'max_tokens',
        'content_filter',
        'error',
        'cancelled',
        'stream_incomplete',
      };
      if (abnormalFinishReasons.contains(finishReason)) {
        yield AgentError(
          'LLM 未正常完成响应（finish_reason=${completed.finishReason}）。'
          '请增加输出上限、缩短上下文或重试。',
        );
        return;
      }

      final hasToolCalls =
          completed.toolCalls != null && completed.toolCalls!.isNotEmpty;
      final hasFinalContent = completed.content?.trim().isNotEmpty ?? false;
      final hasReasoning =
          completed.reasoningContent?.trim().isNotEmpty ?? false;
      if (!hasToolCalls && !hasFinalContent && hasReasoning) {
        yield AgentError(
          '模型只返回了推理内容，没有生成最终回答。'
          '这通常表示输出上限不足或流被提前终止，请重试。',
        );
        return;
      }

      // ─── DSML 兼容层：解析 DeepSeek 等模型的文本内嵌工具调用 ───
      if (completed.content != null &&
          completed.content!.isNotEmpty &&
          (completed.toolCalls == null || completed.toolCalls!.isEmpty) &&
          _DsmlParser.hasDsml(completed.content!)) {
        final (cleanedContent, dsmlCalls) = _DsmlParser.parse(
          completed.content!,
        );
        if (dsmlCalls.isNotEmpty) {
          completed = StreamComplete(
            content: cleanedContent.isEmpty ? null : cleanedContent,
            reasoningContent: completed.reasoningContent,
            toolCalls: dsmlCalls,
            finishReason: completed.finishReason,
          );
        }
      }

      // ─── Hook: onAfterLlmCall ───
      for (final hook in hooks) {
        await hook.onAfterLlmCall(
          completed.content,
          completed.toolCalls ?? [],
          stopwatch.elapsedMilliseconds,
        );
      }

      // 追加 assistant 消息到历史
      messages.add(completed.toMessageJson());

      // 无 tool_call → 最终回复已通过 AgentToken 逐步推送
      if (completed.toolCalls == null || completed.toolCalls!.isEmpty) {
        yield AgentDone(completed.content ?? '');
        return;
      }

      // 有 tool_calls → 执行 tool calls
      for (final tc in completed.toolCalls!) {
        yield AgentToolStart(tc.name, tc.arguments);

        final result = await executor.run(tc.name, tc.arguments);
        yield AgentToolResult(tc.id, result);

        messages.add({
          'role': 'tool',
          'tool_call_id': tc.id,
          'content': result,
        });
      }

      // ✅ 对话中压缩检查：每 5 轮检查一次，防止单轮对话内上下文溢出
      if (round % 5 == 0) {
        await _checkAndCompressIfNeeded(round, messages);
      }

      // 循环 → 把工具结果交给 LLM 继续处理
    }
  }

  /// 对话中压缩检查：估算当前 token 数，超过阈值则触发压缩
  Future<void> _checkAndCompressIfNeeded(
    int round,
    List<Map<String, dynamic>> messages,
  ) async {
    final tokens = _estimateTokens(messages);
    final threshold = _getEffectiveThreshold();

    // 未超过阈值，不压缩
    if (tokens <= threshold) {
      return;
    }

    AppLogger.instance.log(
      '[AgentLoop] 工具循环第 $round 轮触发对话中压缩: $tokens tokens > $threshold tokens (${(tokens / (contextWindow > 0 ? contextWindow : 128000) * 100).toStringAsFixed(1)}%)',
    );

    final processed = await messagePipeline.process(messages);

    // 检查是否真的发生了压缩
    if (processed.length < messages.length) {
      final beforeTokens = tokens;
      messages.clear();
      messages.addAll(processed);

      // 重置压缩标记，允许下次再压缩
      for (final transformer in messagePipeline.transformers) {
        if (transformer is ContextCompactor) {
          transformer.resetRound();
        }
      }

      final afterTokens = _estimateTokens(messages);
      final reduction = ((1 - afterTokens / beforeTokens) * 100)
          .toStringAsFixed(1);
      AppLogger.instance.log(
        '[AgentLoop] 压缩完成: ${messages.length} 条消息, $afterTokens tokens (压缩比: $reduction%)',
      );
    } else {
      AppLogger.instance.log('[AgentLoop] 压缩跳过: 消息数量未减少 (可能已是最小保留量)');
    }
  }

  /// 估算消息列表的 token 数
  int _estimateTokens(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final msg in messages) {
      final content = msg['content'];
      if (content is String) {
        total += ComputeService.estimateTokens(content);
      } else if (content is List) {
        // Multimodal content parts
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            total += ComputeService.estimateTokens(
              part['text'] as String? ?? '',
            );
          }
        }
      }
      // tool_calls 参数也算 token
      if (msg['tool_calls'] is List) {
        for (final tc in msg['tool_calls'] as List) {
          final args = tc['function']?['arguments'] as String? ?? '';
          total += ComputeService.estimateTokens(args);
        }
      }
      total += 4; // 每条消息的元数据开销
    }
    return total;
  }

  /// 获取当前的压缩阈值
  int _getEffectiveThreshold() {
    for (final transformer in messagePipeline.transformers) {
      if (transformer is ContextCompactor) {
        return transformer.effectiveThreshold;
      }
    }
    // 默认：128K * 0.60 = 76.8K
    final ctx = contextWindow > 0 ? contextWindow : 128000;
    return (ctx * 0.60).toInt();
  }
}

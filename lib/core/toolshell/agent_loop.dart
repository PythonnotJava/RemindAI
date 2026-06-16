import 'dart:async';
import 'dart:convert';
import '../llm/llm_client.dart';
import '../agent/agent_hook.dart';
import '../agent/message_pipeline.dart';
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

  AgentLoop({
    required this.llm,
    required this.executor,
    required this.tools,
    required this.messages,
    this.messagePipeline = const MessagePipeline(),
    this.hooks = const [],
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

    while (true) {
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
              // 推理/思考 token (DeepSeek等) — 同样推送给 UI 展示
              yield AgentToken(text);
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

      // 循环 → 把工具结果交给 LLM 继续处理
    }
  }
}

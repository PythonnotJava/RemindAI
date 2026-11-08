import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../llm/llm_client.dart';
import '../agent/agent_hook.dart';
import '../agent/message_pipeline.dart';
import '../agent/tool_middleware.dart';
import '../agent/transformers/context_compactor.dart';
import '../isolate/compute_service.dart';
import '../logger/app_logger.dart';
import '../memory/project_config.dart';
import 'autonomy_nudge.dart';
import 'budget.dart';
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

/// 预算心跳：每轮结束把"已用工具轮 / 工具调用 / 时间 / token"推给 UI。
class AgentBudgetTick extends AgentEvent {
  final BudgetSnapshot snapshot;
  AgentBudgetTick(this.snapshot);
}

/// 触到软上限但上一轮有进展 → 原地续预算。
///
/// 这是"内层续预算不消耗外层重规划轮"的落点：不 return、不换轮，
/// 只是把软上限抬高然后继续同一个循环。
class AgentBudgetExtended extends AgentEvent {
  final BudgetSnapshot snapshot;

  /// 本次新批下来的软轮次（0 表示软上限已贴到硬上限）
  final int grantedRounds;
  AgentBudgetExtended(this.snapshot, this.grantedRounds);
}

/// 执行预算耗尽（硬上限，或触软上限且无进展）。
///
/// 与 [AgentLoopLimitReached]（旧的无配置熔断）不同，这里带着完整的
/// [LoopCheckpoint]，调用方可以直接把它渲染成"检查点摘要 + 追加预算入口"。
class AgentBudgetStop extends AgentEvent {
  final BudgetStopReason reason;
  final BudgetSnapshot snapshot;
  final LoopCheckpoint checkpoint;

  /// 停止时是否还在推进（硬上限被迫停下 vs 空转停下，措辞不同）
  final bool hadProgress;

  AgentBudgetStop({
    required this.reason,
    required this.snapshot,
    required this.checkpoint,
    required this.hadProgress,
  });
}

/// HTML 可视化文件生成事件
class AgentHtmlGenerated extends AgentEvent {
  final String path;
  final String? title;
  AgentHtmlGenerated(this.path, {this.title});
}

/// 视频文件生成事件
class AgentVideoGenerated extends AgentEvent {
  final String path;
  final String? thumbnail;
  AgentVideoGenerated(this.path, {this.thumbnail});
}

/// SVG 矢量图生成事件
class AgentSvgGenerated extends AgentEvent {
  final String path;
  AgentSvgGenerated(this.path);
}

/// 画图子 Agent 生成图片事件
class AgentImageGenerated extends AgentEvent {
  final String path;

  /// 可选标题/说明（预留）。
  final String? title;

  AgentImageGenerated(this.path, {this.title});
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

  /// 单次 chat() 调用内允许的最大 tool_call 轮次数。
  ///
  /// 仅在**没有**传入 [budget] 时生效（老路径/服务端路径的保护网）。
  /// 一旦传了 [budget]，轮次由预算的软/硬上限接管：软上限到线先看进展，
  /// 有进展就原地续预算，没进展才停——这样"50 轮"不再是一个随手的硬数字，
  /// 也不会因为内层轮次用完就白白吃掉一次外层重规划。
  final int maxToolCallRounds;

  /// 执行预算（轮次/工具调用/墙钟/token 四维）。null = 旧行为。
  final ExecutionBudget? budget;

  /// 工具级进展追踪器。与 [budget] 配合判断"触软上限时到底有没有进展"。
  final ToolProgressTracker? progressTracker;

  /// 是否允许把同一条回复里的多个 tool_call 并发执行（降低每轮消耗）。
  ///
  /// 只对"不需要权限确认、参数不重复"的一批调用生效；写/删/执行等
  /// 需要用户确认的工具仍然串行，避免并发弹窗与资源竞态。
  final bool parallelToolCalls;

  /// 输出被长度上限截断时的自动自愈次数（续写 / 抬高输出预算重试）。
  ///
  /// 推理模型的 reasoning_content 也计入 max_tokens：思维链一长，正文还没
  /// 开始写预算就没了，finish_reason 直接是 length。旧实现把这种情况当致命
  /// 错误，用户看到的是"刚开始工作就报错"，已生成的推理也全被丢弃。
  final int maxTruncationRecoveries;

  /// 模型的上下文窗口大小（token 数）。用于对话中压缩的阈值计算。
  /// 0 表示未知，会使用保守默认值 128K。
  final int contextWindow;

  /// 触软上限后，需要"连续多少轮没有实质进展"才判定卡死并停止。
  ///
  /// 设为 1 的历史版本把任务停得太早：模型在收尾阶段重跑同一条验证命令
  /// （同参数、同输出）就算"无进展"，"其实已经做完了"也会被掐断。
  /// 现在要求连续 2 轮，给"验证一次 → 收尾/补一步"留出空间。
  static const int _noProgressRoundsToStop = 2;

  AgentLoop({
    required this.llm,
    required this.executor,
    required this.tools,
    required this.messages,
    this.messagePipeline = const MessagePipeline(),
    this.hooks = const [],
    this.maxToolCallRounds = 50,
    this.budget,
    this.progressTracker,
    this.parallelToolCalls = true,
    this.maxTruncationRecoveries = 2,
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

    // ─── 对话开始时重置压缩标志（修复标志卡死问题）───
    // 问题：上次对话可能因为异常（LLM 失败、网络超时、用户中断等）
    // 而未执行 resetRound()，导致 _compactedThisRound 保持 true，
    // 阻止后续所有压缩。新对话开始 = 新的压缩周期，必须重置。
    for (final transformer in messagePipeline.transformers) {
      if (transformer is ContextCompactor) {
        transformer.resetRound();
      }
    }

    // ─── 每次对话是一次独立 run：清零进展追踪器的"本次"统计 ───
    // 追踪器由 AgentContext 持有（会话级缓存），预算却是每次 run 新建的；
    // 不清零就会出现"检查点说 211 次调用、预算说 93/320"的口径打架。
    //
    // 例外：预算已带着"已用调用数"进来，说明这是"追加预算继续"的续跑段，
    // 此时预算本身就是跨续跑的累计口径；再清零追踪器，摘要里的
    // "重复/失败/产物"就被抹掉，只剩一份空统计。
    if ((budget?.usedToolCalls ?? 0) == 0) {
      progressTracker?.resetRun();
    }

    // ─── 轻量级检查：记录是否需要压缩（不阻塞）───
    final tokens = _estimateTokens(messages);
    final threshold = _getEffectiveThreshold();
    if (tokens > threshold) {
      final ctx = contextWindow > 0 ? contextWindow : 128000;
      final ratio = (tokens / ctx * 100).toStringAsFixed(1);
      AppLogger.instance.log(
        '[AgentLoop] 对话开始前检测到超阈值: $tokens > $threshold ($ratio% 上下文), '
        '将在首轮工具调用后压缩',
      );
    }

    var round = 0;
    // 自动模式"只说不做"兜底：每轮对话最多提醒一次（见 autonomy_nudge.dart）。
    var autonomyNudged = false;
    // 连续"无实质进展"的轮数：单轮的验证型重复（重跑同样的测试看结果）
    // 不该直接掐断任务，必须连续多轮才能判定原地打转。
    var consecutiveNoProgress = 0;
    // 局部变量接住预算/追踪器：public 字段无法被类型提升，用局部非空变量
    // 才能在 if (budget != null) 分支里直接访问成员。
    final execBudget = budget;
    final tracker = progressTracker;
    while (true) {
      round++;
      execBudget?.beginRound();
      tracker?.beginRound();

      if (execBudget != null) {
        // ─── 1) 硬上限：与进展无关，到了必停 ───
        final hardReason = execBudget.hardStopReason();
        if (!hardReason.isNone) {
          AppLogger.instance.log(
            '[AgentLoop] 执行预算硬上限: ${hardReason.name} '
            '(轮 $round, 调用 ${execBudget.usedToolCalls}, '
            '用时 ${execBudget.elapsed.inSeconds}s)',
          );
          yield AgentBudgetStop(
            reason: hardReason,
            snapshot: execBudget.snapshot(),
            checkpoint: _buildCheckpoint(),
            hadProgress: tracker?.lastRound?.hasProgress ?? false,
          );
          return;
        }

        // ─── 2) 软上限：不是"停"，而是"检查一次进展" ───
        if (execBudget.softExceeded) {
          final last = tracker?.lastRound;
          final spinning = last?.isSpinning ?? false;
          // 没有追踪器时保守认为"有进展"（只由硬上限兜底）
          final hasProgress = last?.hasProgress ?? true;
          final noProgressSignal = last?.isNoProgress ?? false;

          if (noProgressSignal || !hasProgress) {
            consecutiveNoProgress++;
          } else {
            consecutiveNoProgress = 0;
          }

          // 必须"连续 N 轮"才判定卡死：给收尾/验证留一口气
          if (consecutiveNoProgress >= _noProgressRoundsToStop) {
            final reason = spinning
                ? BudgetStopReason.repeatedOperations
                : BudgetStopReason.noProgress;
            AppLogger.instance.log(
              '[AgentLoop] 触软上限且连续 $consecutiveNoProgress 轮无进展 '
              '(${reason.name})：${last?.summary ?? "无追踪信息"}',
            );
            yield AgentBudgetStop(
              reason: reason,
              snapshot: execBudget.snapshot(),
              checkpoint: _buildCheckpoint(),
              hadProgress: false,
            );
            return;
          }

          // 有进展 → 原地续预算，不消耗外层重规划轮
          final granted = execBudget.grantSoftExtension();
          if (granted <= 0) {
            // 软上限已经贴到硬上限，续不动了：按硬上限收尾
            final reason = execBudget.hardStopReason();
            AppLogger.instance.log('[AgentLoop] 软上限已贴到硬上限，无法继续续预算');
            yield AgentBudgetStop(
              reason: reason.isNone ? BudgetStopReason.hardRounds : reason,
              snapshot: execBudget.snapshot(),
              checkpoint: _buildCheckpoint(),
              hadProgress: true,
            );
            return;
          }
          AppLogger.instance.log(
            '[AgentLoop] 触软上限但有进展，原地续预算 +$granted 轮 '
            '(软上限 ${execBudget.limits.softRounds}/${execBudget.limits.hardRounds})：'
            '${last?.summary ?? "无追踪信息"}',
          );
          yield AgentBudgetExtended(execBudget.snapshot(), granted);
        }
      } else if (round > maxToolCallRounds) {
        AppLogger.instance.log(
          '[AgentLoop] 达到单轮对话最大tool_call轮次上限($maxToolCallRounds)，强制熔断',
        );
        yield AgentLoopLimitReached(maxToolCallRounds);
        return;
      }

      // ─── 对话中压缩检查：第 1 轮后立即检查，之后每 5 轮检查一次 ───
      // 为什么第 1 轮检查？如果对话开始前就超阈值，及时压缩避免溢出
      // 为什么不在对话开始前压缩？避免阻塞用户消息，影响响应速度
      if (round == 1 || round % 5 == 0) {
        await _checkAndCompressIfNeeded(round, messages);
      }

      // ─── 消息变换管线：在发送给 LLM 前处理消息列表 ───
      final effectiveMessages = await messagePipeline.process(messages);

      // ─── 预算：累计本轮上下文 token（估算，用于四维预算里的 token 维度）───
      execBudget?.addTokens(_estimateTokens(effectiveMessages));

      // ─── 发送前最后验证（防御层 3/3）：检查工具调用配对完整性 ───
      final validationError = _validateToolCallPairing(effectiveMessages);
      if (validationError != null) {
        AppLogger.instance.log('[AgentLoop] ⚠️  检测到工具调用配对问题: $validationError');
        AppLogger.instance.log('[AgentLoop] 🔧 自动修复中...');

        // 自动修复：移除所有孤立的 tool_calls
        final fixed = _fixToolCallPairing(effectiveMessages);
        effectiveMessages.clear();
        effectiveMessages.addAll(fixed);

        AppLogger.instance.log(
          '[AgentLoop] ✅ 修复完成: ${messages.length} → ${fixed.length} 条消息',
        );
      }

      // ─── Hook: onBeforeLlmCall ───
      for (final hook in hooks) {
        await hook.onBeforeLlmCall(effectiveMessages, tools);
      }

      // 打印当前使用的模型
      AppLogger.instance.log('[AgentLoop] 调用模型: ${llm.model}');

      // ─── 流式调用 LLM（带"输出预算被推理吃光 / 正文被截断"的自愈）───
      //
      // 推理模型的 reasoning_content 同样计入 max_tokens。思维链一长，
      // 正文还没开始写预算就见底了，服务端直接返回 finish_reason=length。
      // 旧实现把这种情况当致命错误：用户看到"刚开始工作就报错"，
      // 已经生成的长推理也全部丢弃。现在改为：
      //   1) 有正文被截断 → 把已输出内容作为续写前缀，要求"接着写、别重开头"；
      //   2) 一个字正文都没有（预算全给推理）→ 抬高输出预算并压住推理再试；
      //   3) 自愈用尽才报错，且文案要告诉你该改哪个设置。
      var completed = StreamComplete(content: null, finishReason: 'stop');
      var llmAttempt = 0;
      var contextOverflowRetries = 0;
      var attemptMessages = effectiveMessages;
      int? attemptMaxTokens;
      final roundContent = StringBuffer();
      var stopwatch = Stopwatch()..start();

      while (true) {
        StreamComplete? attemptResult;
        stopwatch = Stopwatch()..start();
        try {
          await for (final event in llm.chatStreamFull(
            attemptMessages,
            tools: tools,
            maxTokensOverride: attemptMaxTokens,
          )) {
            switch (event) {
              case ContentToken(text: final text):
                // 续写场景下这里累计的是"整轮"正文（跨多次请求）
                roundContent.write(text);
                yield AgentToken(text);
              case ReasoningToken(text: final text):
                // 推理 token 与最终正文分开传递；不能作为 AgentDone 的正文兜底。
                yield AgentReasoningToken(text);
              case StreamComplete():
                attemptResult = event;
            }
          }
        } catch (e, stackTrace) {
          stopwatch.stop();
          AppLogger.instance.log('[AgentLoop] LLM 调用失败 (模型: ${llm.model}): $e');

          // ─── 上下文超限自适应：学上限 → 收紧阈值 → 立刻压一次 → 重试 ───
          // 静态阈值永远猜不准各家中转的真实上限，这条才是兜底。
          if (contextOverflowRetries < 1 &&
              _looksLikeContextOverflow(e.toString())) {
            final compactor = _findCompactor();
            if (compactor != null) {
              contextOverflowRetries++;
              // 先尝试从报文学出真实上限（多数上游会把数字写在报文里）
              final learned = compactor.learnCapacityFromError(e.toString());
              compactor.tightenThreshold(0.5);
              final processed = await messagePipeline.process(messages);
              if (processed.length < messages.length) {
                messages
                  ..clear()
                  ..addAll(processed);
              }
              compactor.resetRound();
              attemptMessages = messages;
              AppLogger.instance.log(
                '[AgentLoop] 上下文超限 → 已压缩重试 '
                '(${messages.length} 条消息, 估算 ${_estimateTokens(messages)} tokens'
                '${learned == null ? '' : ', 学到上限 $learned'})',
              );
              yield AgentToken(
                '\n\n…（请求超出接入上下文上限，已自动压缩后重试'
                '${learned == null ? '' : '，本模型实际上限约 ${(learned / 1000).round()}K'}）…\n\n',
              );
              continue;
            }
          }

          AppLogger.instance.log('[AgentLoop] StackTrace: $stackTrace');
          yield AgentError('LLM 调用失败: $e');
          if (messages.isNotEmpty) messages.removeLast();
          return;
        }
        stopwatch.stop();

        // 流异常结束，未收到 StreamComplete
        if (attemptResult == null) {
          yield AgentError('LLM 流异常终止: 未收到完整响应');
          return;
        }
        completed = attemptResult;

        // ─── 用上游实测 usage 向上校准容量（模型卡填小/起点猜低时纠正）───
        _findCompactor()?.observeUsage(attemptResult.usage?.promptTokens);

        final attemptReason = completed.finishReason.toLowerCase();
        final lengthStopped =
            attemptReason == 'length' || attemptReason == 'max_tokens';
        // 只有"长度上限"可自愈；流被代理切断(isTruncated/stream_incomplete)
        // 仍按原策略报告，避免把半截结果伪装成完成。
        if (!lengthStopped) break;

        final partialContent = completed.content?.trim() ?? '';
        final reasoningText = completed.reasoningContent?.trim() ?? '';
        AppLogger.instance.log(
          '[AgentLoop] 输出被长度上限截断: reason=$attemptReason, '
          '本次正文=${partialContent.length}字符, 本轮累计=${roundContent.length}字符, '
          '推理=${reasoningText.length}字符, '
          'max_tokens=${attemptMaxTokens ?? llm.outputTokenBudget}',
        );

        if (llmAttempt >= maxTruncationRecoveries) break; // 交给下面的兜底
        llmAttempt++;

        if (roundContent.isNotEmpty || partialContent.isNotEmpty) {
          // 正文写到一半被打断 → 以已输出内容为前缀续写
          final written = roundContent.isNotEmpty
              ? roundContent.toString()
              : partialContent;
          attemptMessages = [
            ...effectiveMessages,
            {'role': 'assistant', 'content': written},
            {
              'role': 'user',
              'content':
                  '【续写】上面的输出因为输出长度上限被截断。请紧接着继续写，'
                  '不要重复已经写过的内容，不要重新开头，也不要解释计划，直接往下写。',
            },
          ];
          yield AgentToken('\n\n…（输出达到长度上限，正在自动续写）…\n\n');
        } else {
          // 一个字正文都没有：预算全被推理吃掉 → 抬高上限并压住推理
          final base = attemptMaxTokens ?? llm.outputTokenBudget;
          final next = math.min(32000, math.max(base * 2, 16000));
          if (next <= base) break; // 已经到顶，没法再加
          attemptMaxTokens = next;
          attemptMessages = [
            ...effectiveMessages,
            {
              'role': 'user',
              'content':
                  '【重要】请直接给出最终结果（完整答案 / 完整代码），'
                  '不要再展开长篇推理或重复分析，直接开始输出内容。',
            },
          ];
          execBudget?.addTokens(_estimateTokens(attemptMessages));
          yield AgentToken('\n\n…（思考占满了输出预算，已把输出上限提到 $next 并重新生成）…\n\n');
        }
      }

      // 自愈后仍无正文、且是长度原因 → 给出可操作的错误（而不是笼统的"请重试"）
      final selfHealReason = completed.finishReason.toLowerCase();
      final healedContent = roundContent.toString().trim();
      final healedHasToolCalls =
          completed.toolCalls != null && completed.toolCalls!.isNotEmpty;

      if ((selfHealReason == 'length' || selfHealReason == 'max_tokens') &&
          healedContent.isEmpty &&
          !healedHasToolCalls) {
        yield AgentError(
          '模型把输出预算全用在了推理（思考）上，没有产出正文：'
          'finish_reason=${completed.finishReason}，'
          '推理约 ${completed.reasoningContent?.length ?? 0} 字符，'
          '输出上限 ${attemptMaxTokens ?? llm.outputTokenBudget} token。\n'
          '建议：① 在该模型卡把「最大输出 Token」调大（推理模型建议 32000 起）；'
          '② 换用非推理模型；③ 或把任务拆成更小的几步。',
        );
        return;
      }

      // 流被代理/CDN 中途切断（无 [DONE]）：保持原来的严格策略——
      // 半截结果不能伪装成正常完成，必须报告错误。
      if (completed.isTruncated) {
        yield AgentError(
          'LLM 响应被截断（finish_reason=${completed.finishReason}）。'
          '模型尚未完成最终输出，请重试或检查网络、代理超时及上下文长度。',
        );
        return;
      }

      final finishReason = completed.finishReason.toLowerCase();
      const abnormalFinishReasons = {'content_filter', 'error', 'cancelled'};
      if (abnormalFinishReasons.contains(finishReason)) {
        yield AgentError(
          'LLM 未正常完成响应（finish_reason=${completed.finishReason}）。'
          '这通常由内容审核拦截、上游报错或请求被取消导致，请调整提问后重试。',
        );
        return;
      }

      // 自愈过程中累积的整轮正文要覆盖到 completed 上，
      // 否则写回历史/渲染气泡时只剩最后一段。
      final needsRebuild = llmAttempt > 0 && roundContent.isNotEmpty;
      final wasLengthStopped =
          finishReason == 'length' || finishReason == 'max_tokens';
      if (needsRebuild || wasLengthStopped) {
        final buffer = StringBuffer(
          needsRebuild ? roundContent.toString() : (completed.content ?? ''),
        );
        if (wasLengthStopped) {
          buffer.write('\n\n…（已达到输出长度上限，内容可能未结束；可以让我"继续"接着写）');
        }
        completed = StreamComplete(
          content: buffer.isEmpty ? null : buffer.toString(),
          reasoningContent: completed.reasoningContent,
          toolCalls: completed.toolCalls,
          finishReason: wasLengthStopped ? 'stop' : completed.finishReason,
          isTruncated: false,
        );
      }

      final hasToolCalls =
          completed.toolCalls != null && completed.toolCalls!.isNotEmpty;
      final hasFinalContent = completed.content?.trim().isNotEmpty ?? false;
      final hasReasoning =
          completed.reasoningContent?.trim().isNotEmpty ?? false;
      if (!hasToolCalls && !hasFinalContent && hasReasoning) {
        yield AgentError(
          '模型只返回了推理内容，没有生成最终回答。'
          '通常是「最大输出 Token」太小、思维链把预算吃光了：'
          '请到模型卡把它调大（推理模型建议 32000 起），或换用非推理模型。',
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

      // ✅ 对话中压缩检查：在添加新消息前检查，避免压缩刚添加的消息
      if (round % 5 == 0) {
        await _checkAndCompressIfNeeded(round, messages);
      }

      // 追加 assistant 消息到历史
      messages.add(completed.toMessageJson());

      // 无 tool_call → 最终回复已通过 AgentToken 逐步推送
      if (completed.toolCalls == null || completed.toolCalls!.isEmpty) {
        // 自动模式兜底：首轮就"只说不做"时，注入提醒并再给一轮机会。
        // 只在 round == 1（还没执行过任何工具）、auto 模式、且用户像是下了
        // 目标型指令时触发；每轮对话最多一次，避免死循环。
        if (!autonomyNudged &&
            round == 1 &&
            tools.isNotEmpty &&
            executor.permissionMode == PermissionMode.auto &&
            looksActionableGoal(lastUserText(messages))) {
          autonomyNudged = true;
          AppLogger.instance.log(
            '[AgentLoop] auto 模式首轮零工具调用，注入自主执行提醒并继续',
          );
          messages.add({'role': 'user', 'content': kAutonomyNudgePrompt});
          continue;
        }

        // 本轮没有工具调用：也要结算一次进展，否则"只说话不干活"的轮次
        // 会沿用上一轮的进展结论，导致空转判定失效。
        tracker?.endRound();
        yield AgentDone(completed.content ?? '');
        return;
      }

      // 有 tool_calls → 执行 tool calls
      //
      // 降低每轮消耗的关键：同一条回复里的多个互不依赖的 tool_call 应当并发
      // 执行，一轮 ≠ 一次调用。只有"需要权限确认"或"参数完全重复"的批次
      // 退回串行，避免并发弹窗与同文件竞态。
      final toolCalls = completed.toolCalls!;
      final canParallel =
          parallelToolCalls &&
          toolCalls.length > 1 &&
          _canRunInParallel(toolCalls);

      if (canParallel) {
        for (final tc in toolCalls) {
          yield AgentToolStart(tc.name, tc.arguments);
        }
        final results = await Future.wait(toolCalls.map(_runToolSafely));
        for (var i = 0; i < toolCalls.length; i++) {
          final tc = toolCalls[i];
          final result = results[i];
          yield AgentToolResult(tc.id, result);
          messages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'content': result,
          });
          execBudget?.recordToolCalls(_toolCallWeight(tc.name, tc.arguments));
          for (final visualEvent in _visualEvents(tc.name, result)) {
            yield visualEvent;
          }
        }
      } else {
        for (final tc in toolCalls) {
          yield AgentToolStart(tc.name, tc.arguments);

          // 串行路径同样走 _runToolSafely：让 hook 拦截/改写与异常兜底
          // 对"需要确认的工具"也生效（并发路径本就经过它）。
          final result = await _runToolSafely(tc);
          yield AgentToolResult(tc.id, result);

          messages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'content': result,
          });
          execBudget?.recordToolCalls(_toolCallWeight(tc.name, tc.arguments));
          for (final visualEvent in _visualEvents(tc.name, result)) {
            yield visualEvent;
          }
        }
      }

      // ─── 本轮进展结算：给"触软上限时是否有进展"提供确定性证据 ───
      final progress = tracker?.endRound();
      if (progress != null) {
        AppLogger.instance.log('[AgentLoop] 第 $round 轮进展: ${progress.summary}');
      }
      if (execBudget != null) {
        yield AgentBudgetTick(execBudget.snapshot());
      }

      // 循环 → 把工具结果交给 LLM 继续处理
    }
  }

  /// 安全执行单个工具调用：异常也转成结构化错误，避免并发时整批丢失。
  ///
  /// 这里同时是 [AgentHook.onBeforeToolCall] / [AgentHook.onAfterToolResult]
  /// 的唯一接线点（此前这两个钩子只有声明、没有任何调用点，看起来能拦
  /// 实际上拦不住）。钩子默认全是 no-op，所以不注册钩子时行为不变。
  Future<String> _runToolSafely(ToolCall tc) async {
    try {
      // ─── 调用前：允许钩子审查甚至拦截 ───
      for (final hook in hooks) {
        bool allowed = true;
        try {
          allowed = await hook.onBeforeToolCall(tc.name, tc.arguments);
        } catch (e) {
          // 钩子自己出错不应该把整个工具链拖垮：记日志 + 放行
          AppLogger.instance.log('[AgentLoop] onBeforeToolCall 钩子异常(已放行): $e');
        }
        if (!allowed) {
          AppLogger.instance.log('[AgentLoop] 工具调用被 hook 拦截: ${tc.name}');
          return jsonEncode({
            'status': 'error',
            'code': 'HOOK_BLOCKED',
            'detail': '工具调用 ${tc.name} 被 hook 拦截，未执行',
          });
        }
      }

      var result = await executor.run(tc.name, tc.arguments);

      // ─── 调用后：允许钩子改写结果（返回 null 表示不改）───
      for (final hook in hooks) {
        try {
          final replaced = await hook.onAfterToolResult(tc.name, result);
          if (replaced != null) result = replaced;
        } catch (e) {
          AppLogger.instance.log('[AgentLoop] onAfterToolResult 钩子异常(已忽略): $e');
        }
      }
      return result;
    } catch (e) {
      return jsonEncode({
        'status': 'error',
        'code': 'TOOL_EXCEPTION',
        'detail': e.toString(),
      });
    }
  }

  /// 一批 tool_call 能否并发执行。
  ///
  /// 判据（保守）：
  /// 1. 都不需要用户确认（[kApprovalRequiredTools]）；
  /// 2. 不含嵌套的 toolshell_run_parallel（批内再并行只会更难解释）；
  /// 3. 没有完全相同的 (工具名, 参数) 组合（同目标并发是竞态）。
  bool _canRunInParallel(List<ToolCall> calls) {
    final seen = <String>{};
    for (final tc in calls) {
      if (kApprovalRequiredTools.contains(tc.name)) return false;
      if (tc.name == 'toolshell_run_parallel') return false;
      final key = '${tc.name}\u0000${jsonEncode(tc.arguments)}';
      if (!seen.add(key)) return false;
    }
    return true;
  }

  /// 单次 tool_call 在预算里折算成几次"工具调用"。
  ///
  /// `toolshell_run_parallel` 一次带 N 个子调用，按 N 计，
  /// 否则用并行换来的收益会在预算统计里被低估。
  int _toolCallWeight(String name, Map<String, dynamic> args) {
    if (name == 'toolshell_run_parallel') {
      final calls = args['calls'];
      if (calls is List && calls.isNotEmpty) return calls.length;
    }
    return 1;
  }

  /// 工具执行后的可视化事件（HTML/视频/SVG/图片）。
  Iterable<AgentEvent> _visualEvents(String name, String result) sync* {
    // 检测可视化输出（仅针对 Python 执行）
    if (name == 'toolshell_run_python') {
      try {
        final resultJson = jsonDecode(result) as Map<String, dynamic>;

        // HTML 文件
        final htmlFiles = resultJson['html_files'];
        if (htmlFiles is List && htmlFiles.isNotEmpty) {
          for (final htmlPath in htmlFiles) {
            if (htmlPath is String) {
              yield AgentHtmlGenerated(htmlPath);
            }
          }
        }

        // 视频文件
        final videos = resultJson['videos'];
        if (videos is List && videos.isNotEmpty) {
          for (final videoPath in videos) {
            if (videoPath is String) {
              yield AgentVideoGenerated(videoPath);
            }
          }
        }

        // SVG 文件
        final svgFiles = resultJson['svg_files'];
        if (svgFiles is List && svgFiles.isNotEmpty) {
          for (final svgPath in svgFiles) {
            if (svgPath is String) {
              yield AgentSvgGenerated(svgPath);
            }
          }
        }
      } catch (_) {
        // JSON 解析失败或字段不存在，跳过
      }
    }

    // 画图子 Agent 生成图片 → 让 UI 实时展示
    if (name == 'image_generate') {
      try {
        final resultJson = jsonDecode(result);
        if (resultJson is Map) {
          final imagePath = resultJson['image_path'];
          if (imagePath is String && imagePath.isNotEmpty) {
            yield AgentImageGenerated(imagePath);
          }
        }
      } catch (_) {
        // 解析失败（通常是错误 JSON），跳过
      }
    }

    // 并行调用中夹带的画图结果（toolshell_run_parallel 的子结果）
    if (name == 'toolshell_run_parallel') {
      try {
        final root = jsonDecode(result);
        final results = root is Map ? root['results'] : null;
        if (results is List) {
          for (final item in results) {
            if (item is! Map || item['tool'] != 'image_generate') continue;
            final nested = item['result'];
            if (nested is! Map) continue;
            final imagePath = nested['image_path'];
            if (imagePath is String && imagePath.isNotEmpty) {
              yield AgentImageGenerated(imagePath);
            }
          }
        }
      } catch (_) {
        // 忽略非 JSON 结果
      }
    }
  }

  /// 构造检查点（预算耗尽时"说人话"用）。
  LoopCheckpoint _buildCheckpoint() {
    final b = budget;
    final usedRounds = b?.usedRounds ?? 0;
    final elapsed = b?.elapsed ?? Duration.zero;
    final soft = b?.limits.softRounds ?? 0;
    final hard = b?.limits.hardRounds ?? 0;
    final extensions = b?.softExtensions ?? 0;
    final tracker = progressTracker;
    if (tracker == null) {
      return LoopCheckpoint(
        roundsUsed: usedRounds,
        toolCalls: b?.usedToolCalls ?? 0,
        elapsed: elapsed,
        softRounds: soft,
        hardRounds: hard,
        softExtensions: extensions,
      );
    }
    return tracker.checkpoint(
      roundsUsed: usedRounds,
      elapsed: elapsed,
      // 用预算口径覆盖：两个计数必须说同一个数（历史 bug：211 vs 93）
      toolCallsOverride: b?.usedToolCalls,
      softRounds: soft,
      hardRounds: hard,
      softExtensions: extensions,
    );
  }

  /// 上游错误是否属于"上下文超限"（各家措辞不同，只能宽匹配）
  static bool _looksLikeContextOverflow(String raw) {
    final text = raw.toLowerCase();
    const markers = [
      'context_length_exceeded',
      'maximum context',
      'context length',
      'context window',
      'too many tokens',
      'input is too long',
      'prompt is too long',
      'string_above_max_length',
      'exceeds the maximum',
      'reduce the length',
      '超出上下文',
      '上下文过长',
      '超过最大长度',
    ];
    return markers.any(text.contains);
  }

  /// 从消息管线里找出压缩器（超限后收紧阈值用）
  ContextCompactor? _findCompactor() {
    for (final transformer in messagePipeline.transformers) {
      if (transformer is ContextCompactor) return transformer;
    }
    return null;
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
    // 默认：可用输入空间的 60%
    // 可用输入 = contextWindow - maxOutputTokens (12.8K)
    // 例如：128K - 12.8K = 115.2K → 115.2K * 0.60 = 69.1K
    final ctx = contextWindow > 0 ? contextWindow : 128000;
    final availableInput = ctx - 12800;
    return (availableInput * 0.60).toInt();
  }

  // ─── 工具调用配对验证（防御层 3/3）───────────────────────────

  /// 验证消息列表中的工具调用配对完整性
  ///
  /// 检查所有 assistant 消息的 tool_calls 是否都有对应的 tool 结果。
  /// 返回 null 表示验证通过，否则返回错误描述。
  ///
  /// 这是发送给 LLM 前的最后一道防线，确保即使压缩逻辑有漏洞，
  /// 也不会发送无效的消息给 API（导致 HTTP 400）。
  String? _validateToolCallPairing(List<Map<String, dynamic>> messages) {
    final pendingToolCalls = <String, String>{}; // tool_call_id → tool_name

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];

      if (msg['role'] == 'assistant' && msg['tool_calls'] != null) {
        final toolCalls = msg['tool_calls'] as List;
        for (final tc in toolCalls) {
          final id = tc['id'] as String?;
          final name = tc['function']?['name'] as String? ?? 'unknown';
          if (id != null) {
            pendingToolCalls[id] = name;
          }
        }
      } else if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        if (toolCallId != null) {
          pendingToolCalls.remove(toolCallId);
        }
      }
    }

    if (pendingToolCalls.isNotEmpty) {
      final examples = pendingToolCalls.values.take(3).join(', ');
      return '缺少 ${pendingToolCalls.length} 个工具调用结果: $examples';
    }

    return null;
  }

  /// 修复工具调用配对不完整的问题
  ///
  /// 策略：从 assistant 消息中移除没有对应 tool 结果的 tool_calls。
  /// 这比删除整个 assistant 消息更安全，保留了消息的文本内容。
  ///
  /// 两遍扫描：
  /// 1. 收集所有存在的 tool results（有效的 tool_call_id 集合）
  /// 2. 过滤 assistant 消息的 tool_calls，只保留有对应结果的
  List<Map<String, dynamic>> _fixToolCallPairing(
    List<Map<String, dynamic>> messages,
  ) {
    final fixed = <Map<String, dynamic>>[];
    final availableResults = <String>{}; // 所有可用的 tool_call_id

    // 第一遍：收集所有存在的 tool results
    for (final msg in messages) {
      if (msg['role'] == 'tool') {
        final toolCallId = msg['tool_call_id'] as String?;
        if (toolCallId != null) {
          availableResults.add(toolCallId);
        }
      }
    }

    // 第二遍：过滤 assistant 消息的 tool_calls
    for (final msg in messages) {
      if (msg['role'] == 'assistant' && msg['tool_calls'] != null) {
        final toolCalls = msg['tool_calls'] as List;
        final validCalls = toolCalls.where((tc) {
          final id = tc['id'] as String?;
          return id != null && availableResults.contains(id);
        }).toList();

        if (validCalls.isEmpty) {
          // 所有 tool_calls 都孤立，删除
          final cleaned = Map<String, dynamic>.from(msg);
          cleaned.remove('tool_calls');
          final content = cleaned['content'];
          if (content == null ||
              (content is String && content.trim().isEmpty) ||
              (content is List && content.isEmpty)) {
            cleaned['content'] = '(tool calls removed)';
          }
          fixed.add(cleaned);
        } else if (validCalls.length < toolCalls.length) {
          // 部分孤立，只保留有结果的
          final cleaned = Map<String, dynamic>.from(msg);
          cleaned['tool_calls'] = validCalls;
          fixed.add(cleaned);

          final removedCount = toolCalls.length - validCalls.length;
          AppLogger.instance.log(
            '[AgentLoop] 🔧 移除 $removedCount 个孤立的 tool_calls',
          );
        } else {
          // 全部有效
          fixed.add(msg);
        }
      } else {
        fixed.add(msg);
      }
    }

    return fixed;
  }
}

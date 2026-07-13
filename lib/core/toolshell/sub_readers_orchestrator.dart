import 'dart:async';
import 'dart:convert';

import '../isolate/compute_service.dart';
import '../llm/llm_client.dart';
import '../pet/pet_economy.dart';
import 'agent_loop.dart';
import 'executor.dart';

/// 单个只读子任务的定义（来自规划阶段）
class SubReaderTask {
  final String id;

  /// 该子任务负责的范围（用于展示 + 引导子 Agent 不越界重复读取其他子任务的内容）
  final String scope;

  /// 交给子 Agent 执行的具体指令
  final String instruction;

  SubReaderTask({
    required this.id,
    required this.scope,
    required this.instruction,
  });
}

/// 单个子任务的执行结果
class SubReaderResult {
  final SubReaderTask task;
  final String content;
  final bool success;
  final String? error;

  SubReaderResult({
    required this.task,
    required this.content,
    required this.success,
    this.error,
  });
}

/// `/sub-readers` 编排过程中的事件流，供 UI 逐步展示进度
sealed class SubReadersEvent {}

/// 规划完成：已知晓要派生多少个子 Agent、各自负责什么范围
class SubReadersPlanned extends SubReadersEvent {
  final List<SubReaderTask> tasks;
  SubReadersPlanned(this.tasks);
}

/// 某个子 Agent 开始执行
class SubReaderStarted extends SubReadersEvent {
  final String taskId;
  SubReaderStarted(this.taskId);
}

/// 某个子 Agent 执行完成（成功或失败）
class SubReaderFinished extends SubReadersEvent {
  final String taskId;
  final String preview;
  final bool success;
  SubReaderFinished(this.taskId, this.preview, this.success);
}

/// 所有子 Agent 完成后，主模型已完成综合汇总
class SubReadersMerged extends SubReadersEvent {
  final String finalContent;
  final List<SubReaderResult> results;
  SubReadersMerged(this.finalContent, this.results);
}

/// 编排过程中出现不可恢复的错误（规划失败 / 合并失败）
class SubReadersError extends SubReadersEvent {
  final String message;
  SubReadersError(this.message);
}

/// `/sub-readers` 编排器 — 只读并行理解任务的核心逻辑。
///
/// 三阶段流程：
/// 1. **规划 (plan)**：用主模型做一次纯文本调用，把用户的理解需求拆解为
///    1~[maxSubtasks] 个范围不重叠的只读子任务。任务量由模型自行判断，
///    不强行拆分小任务。
/// 2. **并行执行 (run)**：为每个子任务各自创建独立的 [LlmClient] + 只读
///    [Executor] + 全新的 [AgentLoop]（各自独立的 messages 历史，互不干扰），
///    通过 [Future.wait] 并行跑完。因为执行器是只读的（不能写/删/执行任何东西），
///    多个子 Agent 同时指向同一个 projectRoot 不存在冲突风险。
/// 3. **合并 (merge)**：把所有子任务的产出连同原始需求一起交回主模型，
///    产出一份综合、去重、有逻辑结构的最终理解，而不是简单拼接。
///
/// 本类不依赖 Flutter/Riverpod，纯 Dart 逻辑，便于单元测试
/// （用 fake [LlmClient] 和 fake [Executor] 驱动）。
class SubReadersOrchestrator {
  /// 创建一个新的 LlmClient 实例（每次调用应返回独立实例，指向同一模型配置）
  final LlmClient Function() createLlm;

  /// 创建一个新的只读 Executor 实例（每个子任务独立一份，互不共享可变状态）
  final Executor Function() createReadOnlyExecutor;

  /// 提供给子 Agent 的工具定义（应仅包含只读工具，由调用方过滤好后传入）
  final List<Map<String, dynamic>> readOnlyTools;

  /// 最多派生的子任务数量上限，防止模型规划出过多子任务导致成本失控
  final int maxSubtasks;

  SubReadersOrchestrator({
    required this.createLlm,
    required this.createReadOnlyExecutor,
    required this.readOnlyTools,
    this.maxSubtasks = 6,
  });

  /// 执行完整的三阶段流程，逐步 yield 进度事件。
  Stream<SubReadersEvent> run(String description) async* {
    List<SubReaderTask> tasks;
    try {
      tasks = await plan(description);
    } catch (e) {
      yield SubReadersError('任务规划失败: $e');
      return;
    }

    if (tasks.isEmpty) {
      yield SubReadersError('未能规划出任何子任务');
      return;
    }

    yield SubReadersPlanned(tasks);

    // ─── 并行执行所有子任务，通过 controller 把并发进度转成事件流 ───
    final resultsMap = <String, SubReaderResult>{};
    final controller = StreamController<SubReadersEvent>();

    final futures = tasks.map((task) async {
      controller.add(SubReaderStarted(task.id));
      try {
        final content = await runSubtask(task);
        final result = SubReaderResult(
          task: task,
          content: content,
          success: true,
        );
        resultsMap[task.id] = result;
        controller.add(SubReaderFinished(task.id, _preview(content), true));
      } catch (e) {
        final result = SubReaderResult(
          task: task,
          content: '',
          success: false,
          error: e.toString(),
        );
        resultsMap[task.id] = result;
        controller.add(SubReaderFinished(task.id, '执行失败: $e', false));
      }
    }).toList();

    unawaited(Future.wait(futures).then((_) => controller.close()));
    yield* controller.stream;

    final orderedResults = tasks.map((t) => resultsMap[t.id]!).toList();

    try {
      final merged = await merge(description, orderedResults);
      yield SubReadersMerged(merged, orderedResults);
    } catch (e) {
      // 合并失败时降级：直接拼接子任务结果返回，不至于整个 /sub-readers 报废
      final fallback = StringBuffer();
      fallback.writeln('> 合并阶段因网络/模型异常未能完成，以下为各子任务的原始产出：\n');
      for (final r in orderedResults) {
        fallback.writeln('## ${r.task.scope}');
        if (r.success) {
          fallback.writeln(r.content.isEmpty ? '(无输出)' : r.content);
        } else {
          fallback.writeln('执行失败: ${r.error}');
        }
        fallback.writeln();
      }
      yield SubReadersMerged(fallback.toString(), orderedResults);
    }
  }

  // ─── 阶段 1：规划 ─────────────────────────────────────────

  /// 把用户的理解需求拆解为范围不重叠的只读子任务。
  ///
  /// 若模型输出无法解析为合法 JSON，降级为单任务（把整个描述原样交给
  /// 一个子 Agent），保证 `/sub-readers` 在任何情况下都不会因为规划失败
  /// 而彻底不可用。
  Future<List<SubReaderTask>> plan(String description) async {
    final llm = createLlm();
    final planPrompt = [
      {'role': 'system', 'content': _planningSystemPrompt},
      {'role': 'user', 'content': description},
    ];
    final response = await llm.chat(planPrompt);

    final raw = response.content?.trim() ?? '';
    _recordTokenUsage(planPrompt, raw);
    final tasks = _parsePlan(raw);

    if (tasks.isEmpty) {
      return [
        SubReaderTask(id: 'task_1', scope: '整体', instruction: description),
      ];
    }

    return tasks.take(maxSubtasks).toList();
  }

  static const _planningSystemPrompt =
      '你是一个任务分解规划器。用户希望并行、只读地理解/分析一批内容'
      '（可能是多篇文章、一个大型项目的多个模块等）。\n\n'
      '请将其拆解为互不重叠的独立子任务，每个子任务交给一个只读子 Agent 负责'
      '（该子 Agent 只能读文件、搜索文件、召回记忆，不能写/删/执行任何东西）。\n\n'
      '规则：\n'
      '- 子任务数量控制在 1~6 个之间，按任务规模自行判断，不要为了凑数强行拆分。\n'
      '- 如果任务本身很小（比如只理解一个文件/一篇文章），返回 1 个子任务即可。\n'
      '- 每个子任务必须有清晰、不重叠的范围（scope），避免多个子任务重复读同一批内容。\n'
      '- instruction 字段要给子 Agent 具体、可执行的指令（比如要读哪些文件/目录、'
      '关注什么问题），子 Agent 看不到用户的原始描述，只看得到你写的 instruction。\n'
      '- 只输出 JSON 数组，不要任何解释文字、不要代码块标记，格式如下：\n'
      '[{"scope": "简要范围描述", "instruction": "给子 Agent 的具体指令"}, ...]';

  /// 解析规划阶段的模型输出为任务列表。容忍模型输出中夹带 markdown 代码块。
  List<SubReaderTask> _parsePlan(String raw) {
    final jsonText = _extractJsonArray(raw);
    if (jsonText == null) return [];

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! List) return [];

      final tasks = <SubReaderTask>[];
      for (var i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is! Map) continue;
        final scope = item['scope']?.toString().trim();
        final instruction = item['instruction']?.toString().trim();
        if (instruction == null || instruction.isEmpty) continue;
        tasks.add(
          SubReaderTask(
            id: 'task_${i + 1}',
            scope: (scope == null || scope.isEmpty) ? '子任务${i + 1}' : scope,
            instruction: instruction,
          ),
        );
      }
      return tasks;
    } catch (_) {
      return [];
    }
  }

  /// 从模型输出中提取 JSON 数组文本（兼容 ```json ... ``` 代码块包裹）
  String? _extractJsonArray(String raw) {
    var text = raw.trim();
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fenceMatch != null) text = fenceMatch.group(1)!.trim();

    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  // ─── 阶段 2：并行执行单个子任务 ─────────────────────────────

  /// 用独立的 LlmClient + 只读 Executor + 全新 AgentLoop 跑完一个子任务，
  /// 返回该子 Agent 的最终回复文本。
  Future<String> runSubtask(SubReaderTask task) async {
    final llm = createLlm();
    final executor = createReadOnlyExecutor();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _subAgentSystemPrompt(task)},
    ];
    final loop = AgentLoop(
      llm: llm,
      executor: executor,
      tools: readOnlyTools,
      messages: messages,
    );

    // 子 Agent 是独立的真实 LLM 调用链，主聊天窗口的 token 计数不会覆盖到，
    // 这里单独估算并上报，避免 totalTokensSpent 系统性偏低。
    var tokens = ComputeService.estimateTokens(_subAgentSystemPrompt(task));
    tokens += ComputeService.estimateTokens(task.instruction);

    final buffer = StringBuffer();
    try {
      await for (final event in loop.chat(task.instruction)) {
        switch (event) {
          case AgentDone(content: final content):
            tokens += ComputeService.estimateTokens(content);
            return content.isNotEmpty ? content : buffer.toString();
          case AgentError(message: final msg):
            throw Exception(msg);
          case AgentReasoningToken(text: final text):
            tokens += ComputeService.estimateTokens(text);
          case AgentToken(text: final text):
            tokens += ComputeService.estimateTokens(text);
            buffer.write(text);
          case AgentToolStart():
          case AgentToolResult():
            break;
          case AgentLoopLimitReached(rounds: final rounds):
            throw Exception('子 Agent 单轮 tool_call 轮次达到上限($rounds)，未能收敛');
        }
      }
      return buffer.toString();
    } finally {
      if (tokens > 0) PetEconomy.instance.rewardForTokens(tokens);
    }
  }

  String _subAgentSystemPrompt(SubReaderTask task) =>
      '你是一个只读分析子 Agent，负责以下范围: ${task.scope}\n\n'
      '你只能使用只读工具（读文件、搜索、召回记忆），不能写文件、删除、执行命令，'
      '任何非只读操作都会被拒绝。请专注在你负责的范围内完成分析，'
      '给出简洁、有信息密度的总结，供后续汇总使用。';

  /// 结果预览（供 UI/日志展示，避免把完整长文本塞进事件里）
  String _preview(String content) =>
      content.length > 60 ? '${content.substring(0, 60)}...' : content;

  // ─── 阶段 3：合并 ─────────────────────────────────────────

  static const _mergeSystemPrompt =
      '你收到了若干个只读子 Agent 并行完成的分析产出。请基于这些产出，'
      '针对用户的原始需求，给出一份连贯、结构化、去重的最终理解总结。\n\n'
      '要求：\n'
      '- 不要简单拼接子任务的输出，要真正综合、提炼、指出彼此的关联。\n'
      '- 如果某个子任务执行失败，在总结中说明该部分缺失，不要编造内容。\n'
      '- 使用清晰的分段/要点结构，方便用户快速理解全局。';

  /// 把所有子任务结果连同原始需求一起交回主模型，产出最终综合理解。
  ///
  /// 为避免合并阶段 payload 过大导致连接断开，每个子任务结果会被截断到
  /// [_mergeMaxCharsPerResult] 字符以内。
  Future<String> merge(
    String description,
    List<SubReaderResult> results,
  ) async {
    final llm = createLlm();
    final buffer = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('### 子任务 ${i + 1} (范围: ${r.task.scope})');
      if (r.success) {
        if (r.content.isEmpty) {
          buffer.writeln('(无输出)');
        } else if (r.content.length > _mergeMaxCharsPerResult) {
          buffer.writeln(r.content.substring(0, _mergeMaxCharsPerResult));
          buffer.writeln('... (内容过长已截断)');
        } else {
          buffer.writeln(r.content);
        }
      } else {
        buffer.writeln('该子任务执行失败: ${r.error}');
      }
      buffer.writeln();
    }

    final mergePrompt = [
      {'role': 'system', 'content': _mergeSystemPrompt},
      {'role': 'user', 'content': '原始需求：$description\n\n${buffer.toString()}'},
    ];
    final response = await llm.chat(mergePrompt);

    final merged = response.content?.trim();
    _recordTokenUsage(mergePrompt, merged ?? '');
    return (merged == null || merged.isEmpty) ? buffer.toString() : merged;
  }

  /// 把规划/合并阶段的估算 token 计入宠物经济统计（子任务执行阶段在
  /// [runSubtask] 内单独统计，因为它走的是流式 AgentLoop 而非一次性 chat）。
  void _recordTokenUsage(List<Map<String, dynamic>> prompt, String result) {
    var tokens = 0;
    for (final msg in prompt) {
      final content = msg['content'];
      if (content is String) {
        tokens += ComputeService.estimateTokens(content);
      }
    }
    tokens += ComputeService.estimateTokens(result);
    if (tokens > 0) {
      PetEconomy.instance.rewardForTokens(tokens);
    }
  }

  /// 合并阶段每个子任务结果的最大字符数（约 3000 token）。
  static const _mergeMaxCharsPerResult = 6000;
}

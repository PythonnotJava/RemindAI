import '../../isolate/compute_service.dart';
import '../../llm/llm_client.dart';
import '../../logger/app_logger.dart';
import '../../memory/memory_manager.dart';
import '../../pet/pet_economy.dart';
import '../agent_hook.dart';

/// 记忆存储钩子 — Agent 回复完成后自动提取值得记住的信息并存储
class MemoryStoreHook extends AgentHook {
  final MemoryManager manager;
  final String collection;
  final LlmClient llm;
  final bool useQdrant;

  /// 当前对话的消息历史引用 (用于找到 user input)
  final List<Map<String, dynamic>> messages;

  MemoryStoreHook({
    required this.manager,
    required this.collection,
    required this.llm,
    required this.messages,
    this.useQdrant = false,
  });

  @override
  Future<void> onAgentDone(String content, List<ToolCall> toolCalls) async {
    AppLogger.instance.log(
      '[Memory] MemoryStoreHook.onAgentDone, content=${content.length}字符',
    );

    // 获取本轮用户输入
    String userInput = '';
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'user') {
        final c = messages[i]['content'];
        userInput = c is String ? c : c.toString();
        break;
      }
    }

    if (userInput.isEmpty || content.isEmpty) {
      AppLogger.instance.log(
        '[Memory] 跳过: userInput为空=${userInput.isEmpty}, '
        'content为空=${content.isEmpty}',
      );
      return;
    }

    // 短对话不存
    if (content.length < 50) {
      AppLogger.instance.log('[Memory] 跳过: 内容太短 (${content.length}<50字符)');
      return;
    }

    AppLogger.instance.log(
      '[Memory] 进入提取流程, user=${userInput.length}字符, '
      'assistant=${content.length}字符, collection=$collection',
    );

    // 异步执行，不阻塞
    _extractAndStore(userInput, content);
  }

  Future<void> _extractAndStore(
    String userInput,
    String assistantContent,
  ) async {
    try {
      final extractPrompt = [
        {
          'role': 'system',
          'content':
              '你是一个记忆提取器。分析下面的对话，判断是否包含值得长期记住的信息'
              '（如：用户偏好、技术决策、项目约定、重要结论、配置信息等）。\n\n'
              '如果有，输出一条简洁的记忆摘要（一两句话，方便日后语义检索）。\n'
              '如果没有值得记住的信息（普通闲聊、一次性问答），只输出: SKIP',
        },
        {'role': 'user', 'content': '用户: $userInput\n\n助手: $assistantContent'},
      ];

      final response = await llm.chat(extractPrompt);
      final result = response.content?.trim() ?? '';
      AppLogger.instance.log(
        '[Memory] LLM提取结果: '
        '"${result.substring(0, result.length.clamp(0, 80))}"',
      );

      // 记忆提取也是一次真实的 LLM 调用，计入宠物经济的 token 统计，
      // 避免这条旁路消耗完全不计入成就进度。
      _recordTokenUsage(extractPrompt, result);

      if (result.isEmpty || result.toUpperCase().startsWith('SKIP')) {
        AppLogger.instance.log('[Memory] 跳过存储: LLM判断为SKIP');
        return;
      }

      await manager.store(
        text: result,
        collectionName: collection,
        useQdrant: useQdrant,
        metadata: {
          'source': 'auto_store',
          'user_query': userInput.length > 100
              ? '${userInput.substring(0, 100)}...'
              : userInput,
        },
      );
      AppLogger.instance.log(
        '[Memory] ✓ 已存入记忆: collection=$collection, '
        'useQdrant=$useQdrant, length=${result.length}字符',
      );
    } catch (e, stack) {
      AppLogger.instance.log('[Memory] ✗ 存储异常: $e');
      AppLogger.instance.log('[Memory] Stack: $stack');
    }
  }

  /// 把本次记忆提取请求的估算 token 计入宠物经济统计。
  /// 记忆提取是后台旁路的真实 LLM 调用，主聊天窗口的 token 计数
  /// (chat_provider._currentTokenCount) 不会覆盖到这部分消耗，
  /// 因此在这里单独估算并上报，避免 totalTokensSpent 系统性偏低。
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
}

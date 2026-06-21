import 'dart:convert';

import '../llm/llm_client.dart';

/// Anthropic Messages API ↔ 内部 OpenAI 风格 的协议翻译器 (纯代理模式)。
///
/// 与聚合 [ServerSession] 截然不同:
/// - **不跑内部 AgentLoop, 不执行任何工具**;
/// - 原样把客户端 (CherryStudio Agent) 携带的 tools 交给底层模型;
/// - 把模型返回的 tool_calls 翻译回 Anthropic `tool_use` 块, 由客户端自己执行。
///
/// 这样 RemindAI 在 Claude 协议下退化为"任意模型伪装成 Claude"的协议适配器,
/// 让 CherryStudio Agent 能驱动 Kimi/GPT/Gemini 等非 Anthropic 模型。
class AnthropicProxy {
  /// Anthropic content (字符串 或 block 数组) → 纯文本。
  static String blocksToText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final b in content) {
        if (b is Map && b['type'] == 'text') {
          parts.add(b['text']?.toString() ?? '');
        }
      }
      return parts.join('\n');
    }
    return content?.toString() ?? '';
  }

  /// Anthropic tools → OpenAI function tools。无工具返回 null。
  static List<Map<String, dynamic>>? convertTools(dynamic tools) {
    if (tools is! List || tools.isEmpty) return null;
    final out = <Map<String, dynamic>>[];
    for (final t in tools) {
      if (t is! Map) continue;
      final name = t['name']?.toString();
      if (name == null || name.isEmpty) continue;
      out.add({
        'type': 'function',
        'function': {
          'name': name,
          'description': t['description']?.toString() ?? '',
          'parameters':
              t['input_schema'] ??
              {'type': 'object', 'properties': <String, dynamic>{}},
        },
      });
    }
    return out.isEmpty ? null : out;
  }

  // PLACEHOLDER_CONVERT_MESSAGES

  /// Anthropic messages 历史 → OpenAI 风格 messages。
  ///
  /// 关键: CherryStudio Agent 每轮会把含 `tool_use` / `tool_result` 块的完整
  /// 历史发回来。必须双向还原:
  /// - assistant 的 `tool_use` 块 → OpenAI `tool_calls`
  /// - user 的 `tool_result` 块 → 独立的 `{role:'tool', tool_call_id, content}` 消息
  /// 否则模型看不到上一轮工具执行结果, 会重复发起调用或答非所问。
  static List<Map<String, dynamic>> convertMessages(
    List rawMessages, {
    String? systemText,
  }) {
    final out = <Map<String, dynamic>>[];
    if (systemText != null && systemText.isNotEmpty) {
      out.add({'role': 'system', 'content': systemText});
    }

    for (final raw in rawMessages) {
      if (raw is! Map) continue;
      final role = raw['role']?.toString() ?? 'user';
      final content = raw['content'];

      // 纯字符串内容
      if (content is String) {
        out.add({'role': role, 'content': content});
        continue;
      }
      if (content is! List) {
        out.add({'role': role, 'content': blocksToText(content)});
        continue;
      }

      if (role == 'assistant') {
        // 抽出 text 与 tool_use
        final textParts = <String>[];
        final toolCalls = <Map<String, dynamic>>[];
        for (final b in content) {
          if (b is! Map) continue;
          switch (b['type']) {
            case 'text':
              textParts.add(b['text']?.toString() ?? '');
            case 'tool_use':
              toolCalls.add({
                'id': b['id']?.toString() ?? '',
                'type': 'function',
                'function': {
                  'name': b['name']?.toString() ?? '',
                  'arguments': jsonEncode(b['input'] ?? <String, dynamic>{}),
                },
              });
          }
        }
        final msg = <String, dynamic>{'role': 'assistant'};
        final text = textParts.join('\n').trim();
        msg['content'] = text.isEmpty ? null : text;
        if (toolCalls.isNotEmpty) msg['tool_calls'] = toolCalls;
        out.add(msg);
        continue;
      }

      // user (或其他): 可能含 tool_result 块 + text 块
      final userTextParts = <String>[];
      final toolMsgs = <Map<String, dynamic>>[];
      for (final b in content) {
        if (b is! Map) continue;
        switch (b['type']) {
          case 'text':
            userTextParts.add(b['text']?.toString() ?? '');
          case 'tool_result':
            toolMsgs.add({
              'role': 'tool',
              'tool_call_id': b['tool_use_id']?.toString() ?? '',
              'content': blocksToText(b['content']),
            });
        }
      }
      // tool 结果消息必须紧随触发它的 assistant 之后
      out.addAll(toolMsgs);
      final ut = userTextParts.join('\n').trim();
      if (ut.isNotEmpty) out.add({'role': 'user', 'content': ut});
    }

    return out;
  }

  // PLACEHOLDER_KIMI

  /// 解析 Kimi K2 (Moonshot) 文本内嵌工具调用标记。
  ///
  /// 当中转端未正确解析 Kimi 专有 token 时, 模型会把工具调用作为正文输出, 形如:
  /// `<|tool_calls_section_begin|><|tool_call_begin|>functions.Bash:0`
  /// `<|tool_call_argument_begin|>{"command":"..."}<|tool_call_end|>`
  /// `<|tool_calls_section_end|>`
  /// 本解析器从正文抽取这些调用并转为标准 [ToolCall]。
  static final _kimiSectionRe = RegExp(
    r'<\|tool_calls_section_begin\|>([\s\S]*?)<\|tool_calls_section_end\|>',
  );
  static final _kimiCallRe = RegExp(
    r'<\|tool_call_begin\|>\s*([^\s<]+)\s*<\|tool_call_argument_begin\|>([\s\S]*?)<\|tool_call_end\|>',
  );

  static bool hasKimiToolCalls(String text) => _kimiSectionRe.hasMatch(text);

  /// 返回 (清理后的正文, 解析出的工具调用)。
  static (String, List<ToolCall>) parseKimiToolCalls(String text) {
    final calls = <ToolCall>[];
    var cleaned = text;
    var idx = 0;

    for (final section in _kimiSectionRe.allMatches(text)) {
      cleaned = cleaned.replaceFirst(section.group(0)!, '');
      final body = section.group(1) ?? '';
      for (final call in _kimiCallRe.allMatches(body)) {
        // 名字形如 "functions.Bash:0" → 取 Bash
        var rawName = call.group(1) ?? '';
        rawName = rawName.split(':').first; // 去掉序号后缀
        if (rawName.contains('.')) rawName = rawName.split('.').last;
        final argStr = call.group(2)?.trim() ?? '{}';
        Map<String, dynamic> args;
        try {
          args = jsonDecode(argStr) as Map<String, dynamic>;
        } catch (_) {
          args = {};
        }
        calls.add(
          ToolCall(
            id: 'kimi_call_${idx++}_${DateTime.now().microsecondsSinceEpoch}',
            name: rawName,
            arguments: args,
          ),
        );
      }
    }
    return (cleaned.trim(), calls);
  }
}

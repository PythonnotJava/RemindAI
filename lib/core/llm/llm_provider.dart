/// LLM 协议类型 — 决定使用哪个客户端实现与请求/响应翻译。
enum LlmProvider {
  /// OpenAI 兼容 (/chat/completions, SSE delta)。覆盖绝大多数厂商与网关。
  openai,

  /// Anthropic 原生 (/v1/messages, event-stream)。
  anthropic,

  /// Google Gemini 原生 (generateContent / streamGenerateContent)。
  gemini,
}

extension LlmProviderX on LlmProvider {
  /// 持久化用的稳定标识。
  String get id => switch (this) {
    LlmProvider.openai => 'openai',
    LlmProvider.anthropic => 'anthropic',
    LlmProvider.gemini => 'gemini',
  };

  /// UI 展示名。
  String get label => switch (this) {
    LlmProvider.openai => 'OpenAI 兼容',
    LlmProvider.anthropic => 'Anthropic (Claude)',
    LlmProvider.gemini => 'Google Gemini',
  };

  /// 导入对话框里的 Base URL 占位示例。
  String get baseUrlHint => switch (this) {
    LlmProvider.openai => 'https://api.openai.com/v1',
    LlmProvider.anthropic => 'https://api.anthropic.com/v1/messages',
    LlmProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta',
  };

  static LlmProvider fromId(String? id) {
    switch (id) {
      case 'anthropic':
        return LlmProvider.anthropic;
      case 'gemini':
        return LlmProvider.gemini;
      case 'openai':
      default:
        return LlmProvider.openai;
    }
  }
}

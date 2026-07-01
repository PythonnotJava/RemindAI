import 'dart:convert';

/// JSON 序列化/反序列化任务 — 在 Isolate 中执行以避免大对话阻塞 UI。
///
/// 适用场景:
/// - 长对话 (>100条消息) 的保存/加载
/// - 大型 JSON 配置文件的解析
/// - 批量数据导出

/// 将 Map/List 编码为 JSON 字符串（顶层函数，可传入 Isolate）
String jsonEncodeTask(dynamic data) {
  return jsonEncode(data);
}

/// 将 JSON 字符串解码为 Map/List（顶层函数，可传入 Isolate）
dynamic jsonDecodeTask(String jsonStr) {
  return jsonDecode(jsonStr);
}

/// 带格式化的 JSON 编码（用于导出可读性好的文件）
String jsonEncodePrettyTask(dynamic data) {
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// 批量 JSON 解码（多个 JSON 字符串 → 多个对象）
List<dynamic> jsonDecodeBatchTask(List<String> jsonStrings) {
  return jsonStrings.map((s) => jsonDecode(s)).toList();
}

/// 对话消息列表序列化参数
class ConversationEncodeParam {
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic>? metadata;

  ConversationEncodeParam({required this.messages, this.metadata});
}

/// 对话序列化为 JSON 字符串
String conversationEncodeTask(ConversationEncodeParam param) {
  final data = <String, dynamic>{
    'messages': param.messages,
    if (param.metadata != null) 'metadata': param.metadata,
    'exportedAt': DateTime.now().toIso8601String(),
  };
  return jsonEncode(data);
}

/// 对话 JSON 字符串反序列化
Map<String, dynamic> conversationDecodeTask(String jsonStr) {
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;
  return data;
}

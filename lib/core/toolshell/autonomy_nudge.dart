/// 自动模式下的"只说不做"兜底。
///
/// 背景：auto 模式在权限层面是完全放开的（没有权限中间件、没有命令白名单），
/// 但模型偶尔仍然只输出"你可以这样操作：1) … 2) …"就收尾。系统提示能降低
/// 这个概率，但不能保证。所以在 loop 层加一道兜底：本轮对话第一次 LLM 调用
/// 就零工具调用收尾时，注入一条提醒并再跑一轮。
///
/// 约束（避免把正常问答变成"强行动手"）：
/// - 只在 auto 模式；
/// - 只在本轮第一轮（还没执行过任何工具）；
/// - 每轮对话最多提醒 1 次；
/// - 只有用户消息看起来是"目标型指令"才提醒。
library;

/// 注入给模型的提醒内容。
const String kAutonomyNudgePrompt = '''【系统提醒】你上一轮只输出了文字，没有调用任何工具。

当前是 auto 模式，用户已经授权你直接执行：
- 立刻调用工具把目标做完（该装就装、该跑就跑、该改就改），不要把"你可以在终端执行 X"当交付；
- 不要重复上一轮的解释，也不要问"要不要我继续"；
- 只有不可逆丢数据、缺少只有用户才能提供的东西（密码/验证码/手机上人工点"允许"）、
  或需要花钱/对外发消息时，才停下来问；
- 做完用一两句话汇报结果和证据（退出码、关键输出、产物路径）。''';

/// 目标型指令的动作词（中文）。
const List<String> _actionVerbsZh = <String>[
  '安装',
  '装到',
  '装一下',
  '部署',
  '运行',
  '跑一下',
  '跑一遍',
  '跑起来',
  '执行',
  '编译',
  '构建',
  '打包',
  '下载',
  '上传',
  '启动',
  '重启',
  '修改',
  '修复',
  '创建',
  '新建',
  '删除',
  '清理',
  '截图',
  '调试',
  '连接',
  '刷机',
  '配置',
  '设置',
  '迁移',
  '备份',
  '测试',
  '推到',
  '拉取',
  '生成',
  '转换',
  '导出',
  '导入',
  '抓取',
  '监控',
  '监听',
  '帮我做',
  '帮我改',
  '帮我装',
  '帮我跑',
  '搞定',
  '换成',
  '改成',
  '加到',
  '去掉',
  '查一下',
  '看一下日志',
];

/// 目标型指令的动作词（英文，小写匹配）。
const List<String> _actionVerbsEn = <String>[
  'install',
  'deploy',
  'build',
  'compile',
  'run ',
  'start ',
  'restart',
  'fix ',
  'create ',
  'delete',
  'download',
  'upload',
  'screenshot',
  'debug',
  'connect',
  'configure',
  'setup',
  'migrate',
  'backup',
  'test ',
  'generate',
  'export ',
  'import ',
  'logcat',
  'adb ',
  'apk',
  'git ',
  'npm ',
  'pip ',
];

/// 寒暄/纯致谢：即使很短也不该触发"动手"提醒。
const List<String> _chitchatPrefixes = <String>[
  '你好',
  '您好',
  '谢谢',
  '多谢',
  '在吗',
  'hello',
  'hi',
  'thanks',
  'thank you',
  '早上好',
  '晚上好',
];

/// 判断用户这条消息是否像"要我动手做事"的目标型指令。
///
/// 保守启发式：宁可漏判（不提醒），也不要把"这个函数什么意思"变成强行执行。
bool looksActionableGoal(String userText) {
  final text = userText.trim().toLowerCase();
  if (text.length < 6) return false;

  final hasAction =
      _actionVerbsZh.any(text.contains) || _actionVerbsEn.any(text.contains);
  if (!hasAction) return false;

  // 以寒暄开头且没有第二句实质内容时，视为闲聊
  for (final prefix in _chitchatPrefixes) {
    if (text.startsWith(prefix)) {
      final rest = text.substring(prefix.length).trim();
      if (rest.length < 6) return false;
    }
  }
  return true;
}

/// 从消息历史里取最后一条 user 文本（多模态 content 取其中的文本段）。
String lastUserText(List<Map<String, dynamic>> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message['role'] != 'user') continue;
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
      return buffer.toString();
    }
    return '';
  }
  return '';
}

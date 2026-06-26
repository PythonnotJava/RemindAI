// Slash 命令 — 预设提示词模板
//
// Slash 命令的本质是"把一段固定意图的指令模板化"：
// 用户点击命令按钮，命令文本被插入输入框；用户补充描述后发送。
// 发送时调用 [parseSlashCommand] 解析输入文本，决定如何处理：
// - 输入不以任何已注册命令开头（或命令已被用户删除）→ 按普通消息发送
// - 命中命令但描述为空 → 阻止发送并提示用户补充描述
// - 命中命令且有描述 → 展开为发给模型的完整指令后发送

/// 单个 Slash 命令定义
class SlashCommand {
  /// 触发词，含前导斜杠，如 `/skill-cti`
  final String command;

  /// 命令标题（命令菜单主文案）
  final String title;

  /// 命令说明（命令菜单副标题）
  final String subtitle;

  /// 是否仅在工作目录模式可用（纯对话模式下不可用）
  final bool requiresWorkspace;

  /// 是否必须提供描述。为 true 时，命令后无描述将阻止发送并提示补充；
  /// 为 false 时，无描述也可直接发送（命令自身即完整意图）。
  final bool requiresDescription;

  /// 把"命令 + 用户描述"展开为发给模型的完整指令
  final String Function(String description) expand;

  const SlashCommand({
    required this.command,
    required this.title,
    required this.subtitle,
    required this.requiresWorkspace,
    required this.expand,
    this.requiresDescription = true,
  });
}

/// 已注册的 Slash 命令表
const List<SlashCommand> kSlashCommands = [
  SlashCommand(
    command: '/skill-cti',
    title: '/skill-cti',
    subtitle: '创建·测试·安装一个全局技能',
    requiresWorkspace: true,
    expand: _expandSkillCti,
  ),
  SlashCommand(
    command: '/skill-temp',
    title: '/skill-temp',
    subtitle: '在当前工作目录创建项目级技能（不装全局）',
    requiresWorkspace: true,
    expand: _expandSkillTemp,
  ),
];

/// 解析结果
sealed class SlashParseResult {
  const SlashParseResult();
}

/// 普通消息：未命中任何命令（含命令被删除的情况），按原文发送
class PlainMessage extends SlashParseResult {
  final String text;
  const PlainMessage(this.text);
}

/// 命中命令但缺少描述：阻止发送，提示用户补充
class SlashNeedsDescription extends SlashParseResult {
  final SlashCommand command;
  const SlashNeedsDescription(this.command);
}

/// 命中命令且有描述：已展开为完整指令
class SlashExpanded extends SlashParseResult {
  final SlashCommand command;
  final String expandedText;
  const SlashExpanded(this.command, this.expandedText);
}

/// 解析输入文本。
///
/// 命令必须位于文本开头才会被识别；命令后须以空白分隔描述。
/// 这样保证用户删除命令前缀时自动退化为普通消息。
SlashParseResult parseSlashCommand(String rawText) {
  final text = rawText.trim();
  for (final cmd in kSlashCommands) {
    final isExact = text == cmd.command;
    final hasArg =
        text.startsWith('${cmd.command} ') ||
        text.startsWith('${cmd.command}\n');
    if (isExact || hasArg) {
      final description = text.substring(cmd.command.length).trim();
      if (description.isEmpty && cmd.requiresDescription) {
        return SlashNeedsDescription(cmd);
      }
      return SlashExpanded(cmd, cmd.expand(description));
    }
  }
  return PlainMessage(text);
}

/// `/skill-cti` 展开模板：创建·测试·安装到全局技能库
String _expandSkillCti(String description) =>
    '请执行 /skill-cti 工作流（创建·测试·安装到全局），目标是产出一个**全局可复用**的技能。\n'
    '\n'
    '技能需求描述：\n'
    '$description\n'
    '\n'
    '请严格按以下三步闭环执行：\n'
    '\n'
    '1. **创建 (Create)**：在工作目录下的 staging 目录 '
    '`.toolshell/_staging/<技能名>/` 搭建技能骨架，用 toolshell_write 写入 `SKILL.md`'
    '（必需，写清用途/触发条件/使用指南）；若技能需要自定义工具，'
    '再按 OpenAI function 格式写 `tools.json`（可选）。'
    '注意必须用 `.toolshell/_staging/` 而非 `.toolshell/skills/`，'
    '后者会被扫描成项目技能导致装到全局后双重加载。\n'
    '\n'
    '2. **测试 (Test)**：安装到全局之前必须自测——校验 SKILL.md 内容完整、'
    'tools.json（若有）为合法 JSON；若含可执行逻辑，用 toolshell_run_python / '
    'toolshell_run_js / toolshell_exec 跑一个最小用例验证。'
    '自测失败先修正再重测，不要带着已知问题安装。\n'
    '\n'
    '3. **安装到全局 (Install)**：自测通过后，调用 '
    'toolshell_install_skill(source_dir="<staging 技能目录绝对路径>", name="<技能名>")，'
    '把临时技能提升为全局技能（落在 Skills/ 目录，出现在技能页，由我自行开关，'
    '可在任意工作目录复用）。安装成功后 staging 目录会被自动清理。'
    '安装成功后告知我技能名、用途，并提示可在技能页管理与开关。\n';

/// `/skill-temp` 展开模板：在当前工作目录创建项目级技能，不装全局
String _expandSkillTemp(String description) =>
    '请执行 /skill-temp 工作流，在**当前工作目录**创建一个**项目级技能**'
    '（仅本工作目录生效、恒定激活、跟随工作目录），**不要**装到全局技能库。\n'
    '\n'
    '技能需求描述：\n'
    '$description\n'
    '\n'
    '请按以下步骤执行：\n'
    '\n'
    '1. 在 `.toolshell/skills/<技能名>/` 下，用 toolshell_write 写入 `SKILL.md`'
    '（必需，写清技能用途、触发条件、使用指南）；若技能需要自定义工具，'
    '再按 OpenAI function 格式写 `tools.json`（可选）。\n'
    '\n'
    '2. 若技能含可执行逻辑，用 toolshell_run_python / toolshell_run_js / '
    'toolshell_exec 跑一个最小用例自测，失败则修正后重测。\n'
    '\n'
    '3. **不要**调用 toolshell_install_skill——该技能就留在工作目录里。'
    '完成后告知我：技能已建为项目级技能，仅在当前工作目录生效、下一轮上下文构建时'
    '自动加载；如需提升为全局可复用技能，可用 /skill-cti。\n';

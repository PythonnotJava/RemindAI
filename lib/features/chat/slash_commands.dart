// Slash 命令 — 预设提示词模板 / 编排动作
//
// Slash 命令分两类：
// 1. 模板类（默认）：把"命令 + 用户描述"展开为一段完整指令，
//    再作为普通消息发给当前 AgentLoop，由主模型顺序处理。
// 2. 动作类（[isAction] = true）：不发消息给主模型，而是触发一段独立的
//    编排逻辑（如 `/sub-readers` 派生多个只读子 Agent 并行处理）。
//
// 发送时调用 [parseSlashCommand] 解析输入文本，决定如何处理：
// - 输入不以任何已注册命令开头（或命令已被用户删除）→ 按普通消息发送
// - 命中命令但描述为空 → 阻止发送并提示用户补充描述
// - 命中模板类命令且有描述 → 展开为发给模型的完整指令后发送
// - 命中动作类命令且有描述 → 返回原始描述，交给专属编排逻辑处理

import 'dart:io';

/// 单个 Slash 命令定义
class SlashCommand {
  /// 触发词，含前导斜杠，如 `/skill-cti`
  final String command;

  /// 命令标题（命令菜单主文案）
  final String title;

  /// 命令说明（命令菜单副标题）
  final String subtitle;

  /// 命令图标 emoji（命令菜单里的圆形头像图案，直接显示在文案前）
  final String emoji;

  /// 是否仅在工作目录模式可用（纯对话模式下不可用）
  final bool requiresWorkspace;

  /// 是否必须提供描述。为 true 时，命令后无描述将阻止发送并提示补充；
  /// 为 false 时，无描述也可直接发送（命令自身即完整意图）。
  final bool requiresDescription;

  /// 把"命令 + 用户描述"展开为发给模型的完整指令。
  /// 动作类命令（[isAction] = true）不使用此字段，可为 null。
  final String Function(String description)? expand;

  /// 是否为动作类命令：不走"展开为消息发给主 Agent"的路径，
  /// 而是由 UI 层触发专属的编排流程（见 [SlashAction]）。
  final bool isAction;

  const SlashCommand({
    required this.command,
    required this.title,
    required this.subtitle,
    required this.requiresWorkspace,
    this.emoji = '✨',
    this.expand,
    this.requiresDescription = true,
    this.isAction = false,
  }) : assert(isAction || expand != null, '模板类命令 (isAction=false) 必须提供 expand');
}

/// 已注册的 Slash 命令表
const List<SlashCommand> kSlashCommands = [
  SlashCommand(
    command: '/skill-cti',
    title: '/skill-cti',
    subtitle: '创建·测试·安装一个全局技能',
    emoji: '🛠️',
    requiresWorkspace: true,
    expand: _expandSkillCti,
  ),
  SlashCommand(
    command: '/skill-temp',
    title: '/skill-temp',
    subtitle: '在当前工作目录创建项目级技能（不装全局）',
    emoji: '🧪',
    requiresWorkspace: true,
    expand: _expandSkillTemp,
  ),
  SlashCommand(
    command: '/sub-readers',
    title: '/sub-readers',
    subtitle: '并行派生多个只读子 Agent 理解大量内容（如多篇文章、大型项目）',
    emoji: '📚',
    requiresWorkspace: true,
    isAction: true,
  ),
  SlashCommand(
    command: '/archify-draw',
    title: '/archify-draw',
    subtitle: '生成架构图·流程图·时序图·数据流图·状态图（自包含 HTML）',
    emoji: '🎨',
    requiresWorkspace: true,
    expand: _expandArchifyDraw,
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

/// 命中动作类命令（[SlashCommand.isAction] = true）且有描述：
/// 不发消息给主 Agent，交给专属编排逻辑处理，[rawDescription] 是原始描述文本。
class SlashAction extends SlashParseResult {
  final SlashCommand command;
  final String rawDescription;
  const SlashAction(this.command, this.rawDescription);
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
      if (cmd.isAction) {
        return SlashAction(cmd, description);
      }
      return SlashExpanded(cmd, cmd.expand!(description));
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

/// 获取内置 archify 脚本包（assets/scripts/archify）的绝对路径。
///
/// 与 paddle_ocr_tool.dart 的 `_getScriptsDir()` 同一套两段式探测：
/// 开发模式下 CWD 就是项目根，直接用相对路径；发布模式下资源被打进
/// `<可执行文件同级目录>/data/flutter_assets/` 下，需要从可执行文件路径推算。
String _archifyScriptsDir() {
  final candidates = [
    'assets/scripts/archify',
    '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/scripts/archify',
  ];
  for (final p in candidates) {
    if (Directory(p).existsSync()) return p;
  }
  return 'assets/scripts/archify';
}

/// `/archify-draw` 展开模板：调用内置 archify 技能生成技术图表 HTML
String _expandArchifyDraw(String description) {
  final scriptsDir = _archifyScriptsDir();
  return '请使用内置的 archify 技能，把下面的描述画成一张专业的技术图表，'
      '产出一个自包含的 HTML 文件（内嵌 SVG + 明暗主题切换 + 一键导出 PNG/JPEG/WebP/SVG）。\n'
      '\n'
      '图表描述：\n'
      '$description\n'
      '\n'
      'archify 技能目录的绝对路径（本机已探测好，直接用）：\n'
      '$scriptsDir\n'
      '\n'
      '请按以下步骤执行：\n'
      '\n'
      '1. **读技能说明**：先用 toolshell_read 读一遍 `$scriptsDir/SKILL.md`，'
      '按里面 "Choosing a Diagram Type" 的对照表，从描述中判断该用哪种图：'
      '`architecture`（系统架构/云资源/服务拓扑/安全边界）、'
      '`workflow`（流程/审批/CI-CD/runbook）、'
      '`sequence`（调用链/请求时序/异步返回）、'
      '`dataflow`（数据管道/ETL/血缘/PII）、'
      '`lifecycle`（状态机/生命周期/终态）。若用户直接贴了 Mermaid 代码，'
      '按 SKILL.md 里 "Mermaid as an Input Dialect" 的映射表转换，不要机械渲染 Mermaid 语法。\n'
      '\n'
      '2. **读 schema 和示例**：读 `$scriptsDir/schemas/<类型>.schema.json` '
      '和 `$scriptsDir/examples/` 下对应类型的完整示例 JSON，照着示例的字段结构写，'
      '不要凭空猜字段名。若该类型有 README（`$scriptsDir/renderers/<类型>/README.md`），'
      '也读一下里面的排版预算和语义类型说明。\n'
      '\n'
      '3. **写 JSON**：在当前工作目录下用 toolshell_write 写一个 `<名称>.<类型>.json`'
      '（如 `release-flow.workflow.json`），字段按 schema 和示例来，'
      '坐标/列号/行号等排版参数按 SKILL.md 里每种类型的 "Layout budget" 小节的约束填写，'
      '避免节点重叠、标签越界等问题。\n'
      '\n'
      '4. **渲染**：用 toolshell_exec 执行'
      '（cwd 设为 `$scriptsDir`，用相对路径引用刚写的 JSON 和目标输出名）：\n'
      '   ```\n'
      '   node renderers/<类型>/render-<类型>.mjs <输入>.json <输出>.html\n'
      '   ```\n'
      '   若报错，错误信息会指出具体是哪个 JSON 路径或哪个排版参数不满足约束'
      '（如节点重叠、标签超宽、列号越界），照着提示修 JSON 后重新渲染，不要改渲染脚本本身。\n'
      '\n'
      '5. **交付**：渲染成功后，把生成的 `.html` 文件路径告诉我，并简要说明图表内容'
      '（选了哪种类型、包含哪些关键节点/流程）。这个 HTML 是完全自包含的，'
      '可以直接用浏览器打开查看，也支持深浅主题切换和图片/SVG 导出。\n';
}

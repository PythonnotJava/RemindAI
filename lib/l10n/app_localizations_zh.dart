// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'RemindAI';

  @override
  String get navChat => '对话';

  @override
  String get navModels => '模型';

  @override
  String get navSkills => '技能';

  @override
  String get navTools => '工具';

  @override
  String get navMultiAgent => '协作';

  @override
  String get navExperts => '专家';

  @override
  String get navMcp => '服务';

  @override
  String get navSettings => '设置';

  @override
  String get navHistory => '历史';

  @override
  String get navMemory => '记忆';

  @override
  String get navLogs => '日志';

  @override
  String get navPet => '宠物';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsAccentColorTitle => '主题色';

  @override
  String get settingsAccentColorPurple => '紫色';

  @override
  String get settingsAccentColorGreen => '护眼';

  @override
  String get settingsAccentColorBlue => '蓝色';

  @override
  String get settingsAccentColorCyan => '青色';

  @override
  String get settingsNotifyOnBlur => '失焦时系统通知';

  @override
  String get settingsNotifyOnBlurDesc => '窗口不在前台时，对话完成后弹出系统通知';

  @override
  String get settingsEnterAction => '回车行为';

  @override
  String get settingsEnterSend => '发送';

  @override
  String get settingsEnterNewline => '换行';

  @override
  String get settingsEnterSendHint => 'Enter 直接发送';

  @override
  String get settingsEnterNewlineHint => 'Enter 换行，按钮发送';

  @override
  String get settingsStorage => '存储设置';

  @override
  String get settingsDatabasePath => 'SQLite 数据库路径';

  @override
  String get settingsHistoryPath => '对话历史记录路径';

  @override
  String get settingsSkillsPath => '技能 (Skills) 存放目录';

  @override
  String get settingsLogsPath => '日志存放目录';

  @override
  String get settingsToolPaths => '工具路径设置';

  @override
  String get settingsPandocPath => 'Pandoc 可执行文件路径';

  @override
  String get settingsPandocNotDetected => '（未检测到）';

  @override
  String get settingsQdrant => '向量数据库 (Qdrant)';

  @override
  String get settingsEmbedding => '嵌入式模型';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsFont => '字体设置';

  @override
  String get settingsUiFont => '界面字体';

  @override
  String get settingsUiFontDesc => '控制导航、设置等非对话区域的字体';

  @override
  String get settingsUiFontSize => '界面字号';

  @override
  String get settingsChatFont => '交互字体';

  @override
  String get settingsChatFontDesc => '控制对话和多Agent协作区域的字体';

  @override
  String get settingsChatFontSize => '交互字号';

  @override
  String get settingsFontDefault => '默认';

  @override
  String get settingsFontPreview => '字体预览 AaBbCc 你好世界 123';

  @override
  String get settingsCustomFont => '自定义字体';

  @override
  String get settingsCustomFontDesc =>
      '导入本地 .ttf/.otf 字体文件，存放于 .RemindAI/fonts/ 目录';

  @override
  String get settingsCustomFontImport => '导入字体';

  @override
  String get settingsCustomFontPick => '选择字体文件 (.ttf / .otf)';

  @override
  String get settingsCustomFontImported => '字体导入成功';

  @override
  String get settingsChange => '修改';

  @override
  String get settingsMigrating => '正在迁移数据...';

  @override
  String get settingsMigratingHint => '请勿关闭应用';

  @override
  String get settingsPickDbTitle => '选择数据库保存位置';

  @override
  String get settingsPickHistoryTitle => '选择历史记录保存目录';

  @override
  String get settingsPickSkillsTitle => '选择技能存放目录';

  @override
  String get settingsPickLogsTitle => '选择日志存放目录';

  @override
  String get settingsPickPandocTitle => '选择 Pandoc 可执行文件';

  @override
  String get aboutDescription =>
      '您的个人桌面AI工作台。运行工具、安装技能、连接MCP服务器、构建持久内存——所有模型，尽在一个界面。';

  @override
  String get aboutGithub => 'GitHub';

  @override
  String get aboutLicense => '开源许可';

  @override
  String get aboutPoweredBy => 'Powered by';

  @override
  String get trayShow => '显示窗口';

  @override
  String get trayExit => '退出';

  @override
  String get dialogCloseTitle => '关闭窗口';

  @override
  String get dialogCloseContent => '是否最小化到系统托盘？';

  @override
  String get dialogCloseExit => '退出程序';

  @override
  String get dialogCloseMinimize => '最小化到托盘';

  @override
  String get chatSelectModel => '请先在「模型」页面添加并选择一个模型卡片';

  @override
  String get chatComplete => 'RemindAI 对话完成';

  @override
  String get chatCompleteBody => '助手已完成回复';

  @override
  String get chatNoModel => '未选择模型';

  @override
  String get chatLoading => '加载中...';

  @override
  String get chatLoadFailed => '加载失败';

  @override
  String chatLoadFailedWithError(String error) {
    return '加载失败: $error';
  }

  @override
  String get chatExport => '导出对话';

  @override
  String get chatClear => '清空对话';

  @override
  String get chatNew => '新建对话';

  @override
  String get chatNewWorkspace => '新建工作目录';

  @override
  String get chatNeedConfig => '需要配置 API 地址、密钥和模型名称';

  @override
  String get chatStartConversation => '开始对话';

  @override
  String get chatSupportsTools => '支持文件操作、Shell 命令、记忆存储';

  @override
  String get chatCreateWorkspace => '创建工作目录';

  @override
  String get chatAttachments => '附件';

  @override
  String get chatSlashCommands => '命令';

  @override
  String get chatSlashRequiresWorkspace => '需先打开工作目录';

  @override
  String chatSlashNeedsDescription(String command) {
    return '请在 $command 后补充描述再发送';
  }

  @override
  String get chatInterruptHint => '输入新消息可中断当前响应...';

  @override
  String get chatInputHint => '输入消息...';

  @override
  String get chatStopGenerate => '停止生成';

  @override
  String get chatInterruptAndSend => '中断并发送';

  @override
  String get chatSkillManage => '技能管理';

  @override
  String get chatNoSkills => '暂无已安装的技能';

  @override
  String get chatViewSkillMd => '查看 SKILL.md';

  @override
  String get chatUninstall => '卸载';

  @override
  String get chatClose => '关闭';

  @override
  String get chatUninstallSkill => '卸载技能';

  @override
  String chatUninstallSkillConfirm(String name) {
    return '确定要卸载「$name」吗？此操作不可撤销。';
  }

  @override
  String chatUninstalled(String name) {
    return '已卸载：$name';
  }

  @override
  String get chatDisconnect => '断开';

  @override
  String get chatConnect => '连接';

  @override
  String get chatConnected => '已连接';

  @override
  String get chatConnecting => '连接中...';

  @override
  String get chatConnectFailed => '连接失败';

  @override
  String get chatNotConnected => '未连接';

  @override
  String get chatUninstallMcp => '卸载 MCP 服务';

  @override
  String chatUninstallMcpConfirm(String name) {
    return '确定要卸载「$name」吗？';
  }

  @override
  String get chatWorkingDir => '工作目录';

  @override
  String get chatSelectWorkingDir => '选择工作目录';

  @override
  String get chatMemory => '记忆';

  @override
  String get chatMemoryEnabled => '记忆已启用，点击调整';

  @override
  String get chatEmbeddingNotConfigured => '嵌入式模型未配置';

  @override
  String get chatEmbeddingNotConfiguredHint => '请先在「设置 → 嵌入式模型」中配置嵌入模型';

  @override
  String get chatMemorySettings => '记忆设置';

  @override
  String get chatEnableRecall => '启用记忆召回';

  @override
  String get chatEnableRecallDesc => '发消息前自动检索相关记忆';

  @override
  String get chatEnableStore => '启用记忆存储';

  @override
  String get chatEnableStoreDesc => '对话结束后自动提取并存储记忆';

  @override
  String get chatEnableQdrant => '启用 Qdrant 向量检索';

  @override
  String get chatEnableQdrantDesc => '使用向量数据库进行语义召回';

  @override
  String get chatEnableSqlite => '存入 SQLite 作为长期记忆';

  @override
  String get chatEnableSqliteDesc => '将记忆持久化到本地数据库';

  @override
  String get chatEnvironment => '环境';

  @override
  String get chatEnvConfigured => '已指定运行环境，点击调整';

  @override
  String get chatEnvHint => '指定 Python / npm 解释器';

  @override
  String get chatEnvTitle => '运行环境';

  @override
  String get chatEnvSessionScope => '本次对话生效';

  @override
  String get chatEnvDesc => '指定后，项目中的 python/pip、npm/npx/node 命令会优先使用此处选择的版本';

  @override
  String get chatEnvPythonHint => '例如 python.exe / venv/Scripts/python.exe';

  @override
  String get chatEnvSelectNpm => '选择 npm / node 可执行文件';

  @override
  String get chatEnvSelectFile => '选择可执行文件';

  @override
  String get chatEnvClear => '清除';

  @override
  String get chatEnvSelect => '选择';

  @override
  String get chatPermAlways => '始终';

  @override
  String get chatPermAllow => '允许';

  @override
  String get chatPermDeny => '拒绝';

  @override
  String get toolCallWrite => '写入文件';

  @override
  String get toolCallDelete => '删除文件';

  @override
  String get toolCallExec => '执行命令';

  @override
  String get msgEdit => '编辑';

  @override
  String get msgRegenerate => '重新生成';

  @override
  String get msgCopy => '复制';

  @override
  String get msgCopied => '已复制到剪贴板';

  @override
  String get msgExport => '导出';

  @override
  String get msgDelete => '删除';

  @override
  String get msgThinking => '思考中...';

  @override
  String get msgInterrupted => '已中断';

  @override
  String get toolCardArgs => '参数';

  @override
  String get toolCardResult => '结果';

  @override
  String get toolCardExecuting => '执行中';

  @override
  String get toolCardDone => '完成';

  @override
  String get toolCardError => '错误';

  @override
  String get historyTitle => '历史对话';

  @override
  String get historyClearAll => '清空所有对话';

  @override
  String get historyEmpty => '暂无历史对话';

  @override
  String get historyEmptyHint => '开始一段新对话后，将会在这里显示';

  @override
  String get historyDeleteTitle => '删除对话';

  @override
  String historyDeleteConfirm(String title) {
    return '确定要删除「$title」吗？此操作不可撤销。';
  }

  @override
  String get historyClearAllTitle => '清空所有对话';

  @override
  String get historyClearAllConfirm => '确定要删除所有历史对话吗？此操作不可撤销。';

  @override
  String get historyClearBtn => '清空';

  @override
  String get historyUntitled => '未命名对话';

  @override
  String get historyJustNow => '刚刚';

  @override
  String get expertsTitle => '领域专家';

  @override
  String get expertsCreate => '创建专家';

  @override
  String get expertsEmpty => '还没有专家';

  @override
  String get expertsCreateFirst => '创建第一个专家';

  @override
  String get expertsDeleteTitle => '删除专家';

  @override
  String expertsDeleteConfirm(String name) {
    return '确定删除「$name」？此操作不可撤销。';
  }

  @override
  String get expertsNameHint => '如：PPT 设计师';

  @override
  String get expertsDescHint => '一句话说明这个专家的能力';

  @override
  String get expertsPromptHint => '定义专家的身份、能力和工作方式...';

  @override
  String get expertsBindSkills => '绑定技能';

  @override
  String get expertsNameRequired => '请输入专家名称';

  @override
  String get expertsPromptRequired => '请输入系统提示词';

  @override
  String get expertsSelectIcon => '选择图标';

  @override
  String get expertsCreate2 => '创建';

  @override
  String get modelsTitle => '模型管理';

  @override
  String get modelsEmpty => '暂无模型卡片';

  @override
  String get modelsEmptyHint => '点击下方按钮添加第一个模型';

  @override
  String get modelsAdd => '添加模型';

  @override
  String get modelsDefault => '默认';

  @override
  String get modelsDeleteTitle => '确认删除';

  @override
  String modelsDeleteConfirm(String name) {
    return '确定要删除模型 \"$name\" 吗？';
  }

  @override
  String get modelsEditTitle => '编辑模型';

  @override
  String get modelsNameHint => '例如: GPT-4o, Claude Sonnet';

  @override
  String get modelsDetectHint => '点击右侧按钮自动检测';

  @override
  String get modelsDetect => '检测可用模型';

  @override
  String get modelsReorderHint => '点击卡片设为默认，长按拖动可调整顺序';

  @override
  String get modelsSearchHint => '输入关键词搜索模型...';

  @override
  String get skillsTitle => '技能管理';

  @override
  String get skillsImport => '导入技能';

  @override
  String skillsImportSuccess(String name, int count) {
    return '导入成功: $name ($count 个工具)';
  }

  @override
  String skillsImportFailed(String detail) {
    return '导入失败：$detail';
  }

  @override
  String skillsImportBatchSummary(int success, int failed) {
    return '导入完成：成功 $success 个，失败 $failed 个';
  }

  @override
  String skillsImportBatchAllOk(int count) {
    return '已成功导入 $count 个技能';
  }

  @override
  String get skillsEmpty => '暂无已安装技能';

  @override
  String get skillsDeleteTitle => '删除技能';

  @override
  String skillsDeleteConfirm(String name) {
    return '确定要删除技能「$name」吗？此操作不可撤销。';
  }

  @override
  String get mcpTitle => 'MCP 服务';

  @override
  String get mcpAdd => '添加 MCP';

  @override
  String get mcpEmpty => '暂无 MCP 服务';

  @override
  String mcpConnectSuccess(int count) {
    return '连接成功，发现 $count 个工具';
  }

  @override
  String get mcpDeleteTitle => '删除 MCP 服务';

  @override
  String mcpDeleteConfirm(String name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get mcpEditTitle => '编辑 MCP 服务';

  @override
  String get mcpAddTitle => '添加 MCP 服务';

  @override
  String get mcpNameHint => '如: filesystem-server';

  @override
  String get mcpCommandHint => '如: npx, python, node';

  @override
  String get mcpArgsHint =>
      '如: -y @modelcontextprotocol/server-filesystem /tmp';

  @override
  String get mcpCwdHint => '如: C:\\Projects\\my-server';

  @override
  String get mcpEnvHint => '如: API_KEY=xxx';

  @override
  String get mcpHeaderHint => '如: Authorization: Bearer xxx';

  @override
  String get mcpAdd2 => '添加';

  @override
  String get memoryTitle => '记忆管理';

  @override
  String get memoryRefresh => '刷新';

  @override
  String get memoryCount => '记忆条数';

  @override
  String get memoryClearTitle => '清空记忆';

  @override
  String memoryClearConfirm(int count) {
    return '确定要删除当前工作目录的全部 $count 条记忆吗？此操作不可恢复。';
  }

  @override
  String get logsTitle => '日志';

  @override
  String get logsRefresh => '刷新';

  @override
  String get logsEmpty => '暂无日志';

  @override
  String get logsContentEmpty => '日志为空';

  @override
  String get logsClearAllTitle => '清空所有日志';

  @override
  String logsClearAllConfirm(int count, String size) {
    return '将删除 $count 个日志文件 ($size)，此操作不可撤销。';
  }

  @override
  String logsClearedCount(int count) {
    return '已清空 $count 个日志文件';
  }

  @override
  String get toolsTitle => '工具箱';

  @override
  String get toolsBack => '返回工具列表';

  @override
  String get toolsSettings => '工具设置';

  @override
  String get toolsEmpty => '暂无可用工具';

  @override
  String toolsSettingsOf(String name) {
    return '$name 设置';
  }

  @override
  String get toolShortcutsName => '截图';

  @override
  String get toolShortcutsDesc => '查看和自定义应用快捷键';

  @override
  String get toolShortcutsCategory => '快捷键';

  @override
  String get shortcutReset => '恢复默认';

  @override
  String get shortcutResetDone => '快捷键已恢复默认';

  @override
  String get shortcutHint => '点击编辑按钮修改快捷键，需至少包含一个修饰键（Ctrl/Shift/Alt）';

  @override
  String get shortcutEdit => '编辑';

  @override
  String shortcutEditTitle(String name) {
    return '修改「$name」快捷键';
  }

  @override
  String get shortcutEditHint => '按下新的组合键';

  @override
  String get shortcutEditWaiting => '等待按键...';

  @override
  String get shortcutCancel => '取消';

  @override
  String get shortcutConfirm => '确认';

  @override
  String get multiAgentTitle => '多Agent协作';

  @override
  String get multiAgentNewAgent => '新Agent';

  @override
  String get multiAgentHQ => '指挥部';

  @override
  String get multiAgentManager => 'Agent管理器';

  @override
  String get multiAgentSwitchDir => '切换工作目录';

  @override
  String get multiAgentSwitchDirConfirm => '确定要切换目录吗？';

  @override
  String get multiAgentNoHistory => '暂无历史记录';

  @override
  String get multiAgentSelectDir => '选择工作目录';

  @override
  String get multiAgentSelectDirTitle => '选择协作工作目录';

  @override
  String get multiAgentOpenDir => '打开目录';

  @override
  String get multiAgentRestoreHistory => '恢复历史工作区';

  @override
  String get multiAgentDirHint => '提示：可选择现有项目目录，或新建空目录';

  @override
  String get multiAgentDeleteHistory => '删除历史记录';

  @override
  String multiAgentDeleteHistoryConfirm(String name) {
    return '确定删除 \"$name\" 的快照？\n此操作不可恢复。';
  }

  @override
  String get multiAgentHistorySection => '历史工作区';

  @override
  String multiAgentHistoryCount(int count) {
    return '$count 条';
  }

  @override
  String get multiAgentNoHistoryShort => '无历史记录';

  @override
  String get multiAgentDeleteRecord => '删除此记录';

  @override
  String get multiAgentActive => '活跃';

  @override
  String get multiAgentHidden => '已隐藏';

  @override
  String get multiAgentSelectFile => '选择要发送的文件';

  @override
  String get multiAgentReady => '就绪';

  @override
  String get multiAgentThinking => '思考中...';

  @override
  String get multiAgentExecutingTool => '执行工具...';

  @override
  String get multiAgentError => '出错';

  @override
  String get multiAgentSendFile => '发送文件';

  @override
  String get multiAgentInputHint => '输入消息… (Ctrl+Enter 发送)';

  @override
  String get multiAgentWaiting => '等待响应...';

  @override
  String get multiAgentRemoved => 'Agent 已被移除';

  @override
  String get multiAgentSelectGlobalFile => '选择要全局分发的文件';

  @override
  String get multiAgentExportRecord => '导出协作记录';

  @override
  String get multiAgentUser => '用户';

  @override
  String get multiAgentSystem => '系统';

  @override
  String get multiAgentTimeline => '时间线';

  @override
  String get multiAgentOverview => '总览';

  @override
  String get multiAgentBroadcastHint => '广播指令… (Ctrl+Enter 发送)';

  @override
  String get multiAgentBroadcast => '广播';

  @override
  String get multiAgentGlobalFile => '全局分发文件';

  @override
  String get multiAgentNoMessages => '暂无消息';

  @override
  String get multiAgentYou => '你';

  @override
  String get multiAgentNoAgents => '尚未创建Agent';

  @override
  String get multiAgentTotalAgents => '总Agent';

  @override
  String get multiAgentTotalMessages => '消息总数';

  @override
  String get multiAgentStatus => 'Agent 状态';

  @override
  String multiAgentMsgCount(int count) {
    return '$count 条消息';
  }

  @override
  String get multiAgentIdle => '空闲';

  @override
  String multiAgentExported(String path) {
    return '已导出到: $path';
  }

  @override
  String multiAgentExportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get createAgentTitle => '创建新 Agent';

  @override
  String get createAgentName => '名称';

  @override
  String get createAgentNameHint => '例如：代码审查员';

  @override
  String get createAgentRole => '角色';

  @override
  String get createAgentModel => '模型';

  @override
  String get createAgentModelFailed => '加载模型失败';

  @override
  String get createAgentSkills => '挂载技能';

  @override
  String get createAgentPermissions => '权限授予';

  @override
  String get createAgentPromptHint => '定义这个Agent的职责和行为...';

  @override
  String get createAgentPromptLabel => '系统提示（可选）';

  @override
  String get createAgentSysDetect => '系统探测';

  @override
  String get createAgentFileCmd => '文件/命令';

  @override
  String get agentBadgeNotConfigured => '未配置';

  @override
  String get agentBadgeModel => '接入模型';

  @override
  String get agentBadgePermissions => '权限';

  @override
  String get agentBadgeNoPermissions => '无特殊权限';

  @override
  String get agentBadgeSkills => '技能';

  @override
  String get agentBadgeNone => '无';

  @override
  String get agentBadgeTools => '工具';

  @override
  String get agentBadgeMsgCount => '消息数';

  @override
  String get agentBadgeStatus => '状态';

  @override
  String get agentBadgeIdle => '空闲';

  @override
  String get agentBadgeThinking => '思考中';

  @override
  String get agentBadgeExecuting => '执行工具';

  @override
  String get agentBadgeError => '出错';

  @override
  String get agentBadgeSystemPrompt => '系统设定';

  @override
  String get agentBadgeNotExist => 'Agent 不存在';

  @override
  String get agentRoleCommander => '总指挥';

  @override
  String get agentRoleWorker => '工作者';

  @override
  String get agentRoleReviewer => '审查员';

  @override
  String get agentRoleResearcher => '研究员';

  @override
  String get agentRoleCoder => '编码员';

  @override
  String get agentRoleCustom => '自定义';

  @override
  String get agentPermRead => '读文件';

  @override
  String get agentPermWrite => '写文件';

  @override
  String get agentPermDelete => '删文件';

  @override
  String get agentPermExec => '执行命令';

  @override
  String get agentPermNetwork => '网络';

  @override
  String get wsDialogTitle => '新建工作目录';

  @override
  String get wsDialogDesc => '创建一个带有项目配置的工作目录，自动生成 memory.json';

  @override
  String get wsDialogLocation => '目录位置';

  @override
  String get wsDialogSelectParent => '选择父目录...';

  @override
  String get wsDialogFolderName => '文件夹名称';

  @override
  String get wsDialogFolderHint => '例如: my_project';

  @override
  String get wsDialogConfig => '项目配置 (memory.json)';

  @override
  String get wsDialogPermMode => '权限模式';

  @override
  String get wsDialogPermAuto => '自动执行 (auto)';

  @override
  String get wsDialogPermNormal => '操作需确认 (normal)';

  @override
  String get wsDialogEmbeddings => '向量记忆 (embeddings)';

  @override
  String get wsDialogEmbeddingsHint => '需先在设置中配置嵌入模型';

  @override
  String get wsDialogAutoStore => '自动存储记忆';

  @override
  String get wsDialogAutoStoreDesc => '重要信息自动存入长期记忆';

  @override
  String get wsDialogAutoRecall => '自动召回记忆';

  @override
  String get wsDialogAutoRecallDesc => '对话时语义匹配召回相关记忆';

  @override
  String get wsDialogEmbConn => '嵌入模型连接';

  @override
  String get wsDialogTesting => '测试中...';

  @override
  String get wsDialogTestConn => '测试连接';

  @override
  String get wsDialogCreating => '创建中...';

  @override
  String get wsDialogCreateBtn => '创建并切换';

  @override
  String get wsDialogSelectParentTitle => '选择父目录';

  @override
  String get wsDialogEmbNotConfigured => '未配置嵌入模型，请在设置中填写';

  @override
  String wsDialogCreated(String name) {
    return '工作目录已创建: $name';
  }

  @override
  String wsDialogCreateFailed(String error) {
    return '创建失败: $error';
  }

  @override
  String get embEditorTitle => '编辑嵌入模型';

  @override
  String get embEditorAddTitle => '新增嵌入模型';

  @override
  String get embEditorNameHint => '例如: OpenAI Large';

  @override
  String get embEditorEnableQdrant => '启用 Qdrant 向量检索';

  @override
  String get embEditorEnableSqlite => '存入 SQLite 作为长期记忆';

  @override
  String get embEditorTestConn => '测试连接';

  @override
  String get embEditorFillRequired => '请填写 Base URL、API Key 和 Model';

  @override
  String get embEditorConnSuccess => '连接成功';

  @override
  String get embEditorConnAbnormal => '连接成功，但响应格式异常';

  @override
  String get embEditorTimeout => '请求超时';

  @override
  String get embEditorUnknownError => '未知错误';

  @override
  String get embSectionHint => '配置一个或多个嵌入式模型，点击卡片设为默认（选中项用于记忆向量化）';

  @override
  String get embSectionDeleteTitle => '删除嵌入模型';

  @override
  String embSectionDeleteConfirm(String name) {
    return '确定删除 \"$name\" 吗？';
  }

  @override
  String get embSectionDefault => '默认';

  @override
  String get embSectionAdd => '新增嵌入模型';

  @override
  String get qdrantSelectExe => '选择 Qdrant 可执行文件';

  @override
  String get qdrantDetection => '可执行文件检测';

  @override
  String get qdrantRedetect => '重新检测';

  @override
  String get qdrantNotFound => '未找到 qdrant 可执行文件';

  @override
  String get qdrantNotFoundHint =>
      '请手动指定 qdrant 可执行文件，或前往 qdrant.tech 下载后加入系统 PATH。';

  @override
  String get qdrantChangePath => '更换路径';

  @override
  String get qdrantManualSelect => '手动指定';

  @override
  String get qdrantAutoDetect => '恢复自动检测';

  @override
  String get exportFormatTitle => '选择导出格式';

  @override
  String exportExporting(String format) {
    return '正在导出 $format...';
  }

  @override
  String exportSuccess(String path) {
    return '已导出到: $path';
  }

  @override
  String get exportFallbackMd => '是否改为导出 Markdown (.md) 格式？内容完全相同，不会丢失。';

  @override
  String get exportFallbackBtn => '导出为 Markdown';

  @override
  String exportFailed(String format) {
    return '$format 导出失败';
  }

  @override
  String get exportSaveTitle => '保存导出文件';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonCopy => '复制';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonError => '错误';

  @override
  String get commonRetry => '重试';

  @override
  String get commonEmpty => '暂无内容';

  @override
  String get commonClose => '关闭';

  @override
  String get commonClear => '清空';

  @override
  String get commonSelect => '选择';

  @override
  String get commonSwitch => '切换';

  @override
  String get commonAdd => '添加';

  @override
  String commonErrorWithMsg(String msg) {
    return '错误: $msg';
  }

  @override
  String get attachOpenWith => '用系统程序打开';

  @override
  String attachFileNotExist(String path) {
    return '文件不存在：$path';
  }

  @override
  String get imgSaveAs => '另存为…';

  @override
  String get imgCopyPath => '复制路径';

  @override
  String get imgOpenExternal => '在文件夹中显示';

  @override
  String get imgSaved => '图片已保存';

  @override
  String get imgPathCopied => '路径已复制';

  @override
  String get codeSource => '源代码';

  @override
  String get codePreview => '预览';

  @override
  String get scrollUp => '向上滚动（长按持续）';

  @override
  String get scrollDown => '向下滚动（长按持续）';

  @override
  String get permissionDenied => '用户拒绝了操作';

  @override
  String get memoryEmbNotConfigured => '尚未配置嵌入模型\n请前往设置页配置 Embedding 模型后启用向量记忆';

  @override
  String get memoryQdrantNotRunning => 'Qdrant 向量数据库未运行\n请检查 Qdrant 服务状态';

  @override
  String get memoryEmptyHint => '当前工作目录暂无记忆\n对话中产生值得记住的信息时会自动存入';

  @override
  String get memoryQdrantStopped => '未运行';

  @override
  String get memoryContentEmpty => '(空)';

  @override
  String get memorySourceAuto => '自动';

  @override
  String memoryFromQuery(String query) {
    return '来自: $query';
  }

  @override
  String historyMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String historyHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String historyDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String historyDateFormat(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get mcpEmptyHint => '点击下方按钮添加 MCP 服务器配置';

  @override
  String get mcpReorderHint => '点击卡片编辑，长按拖动可调整顺序';

  @override
  String get mcpDisconnect => '断开';

  @override
  String get mcpTestConnection => '测试连接';

  @override
  String mcpConnectFailedWithDetail(String detail) {
    return '连接失败: $detail';
  }

  @override
  String get mcpFormName => '名称';

  @override
  String get mcpFormNameRequired => '请输入名称';

  @override
  String get mcpFormCommand => '命令';

  @override
  String get mcpFormCommandRequired => '请输入命令';

  @override
  String get mcpFormArgs => '参数 (空格分隔)';

  @override
  String get mcpFormCwd => '工作目录 (可选)';

  @override
  String get mcpFormEnv => '环境变量 (每行 KEY=VALUE)';

  @override
  String get mcpFormUrl => 'URL';

  @override
  String get mcpFormUrlRequired => '请输入 URL';

  @override
  String get mcpFormHeaders => '请求头 (每行 Key: Value)';

  @override
  String get mcpSseHint => '如: http://localhost:3000/sse';

  @override
  String get mcpStreamableHint => '如: http://localhost:3000/mcp';

  @override
  String get skillsEmptyHint => '点击下方按钮导入 ZIP 技能包';

  @override
  String get skillsReorderHint => '开关控制启用状态，长按拖动可调整顺序';

  @override
  String get skillsMarketTitle => '推荐技能市场';

  @override
  String get skillsMarketHint => '从以下第三方市场发现并下载技能包（ZIP），再用下方导入功能加载到本应用。';

  @override
  String get skillsMarketSkillsMp => '聚合多来源的技能市场';

  @override
  String get skillsMarketClaudSkills => 'Claude 技能分享社区';

  @override
  String get skillsMarketSkillsSh => '开源技能索引与命令行工具';

  @override
  String skillsMarketOpenFailed(String url) {
    return '无法打开链接：$url';
  }

  @override
  String get skillsBuiltin => '内置';

  @override
  String skillsToolCount(int count) {
    return '$count 个工具';
  }

  @override
  String get skillsNoDesc => '无描述';

  @override
  String get skillsViewMd => '查看 SKILL.md';

  @override
  String get skillsEditDesc => '编辑描述';

  @override
  String get skillsEditDescTitle => '编辑技能描述';

  @override
  String get skillsEditDescHint => '为该技能填写一段描述（仅用于展示）';

  @override
  String get servicesTitle => '服务';

  @override
  String get servicesSkillsTab => '技能';

  @override
  String get servicesToolchainTab => '工具链';

  @override
  String get toolchainDescription =>
      '以下是推荐的命令行工具。检测以系统环境变量 PATH 可寻为准 —— 只要工具已加入 PATH，模型即可在工具外壳中调用。为避免无谓的性能开销，默认不自动检测，点击下方按钮手动探测。';

  @override
  String get toolchainDetect => '检测工具';

  @override
  String get toolchainDetecting => '检测中';

  @override
  String toolchainSummary(int found, int total) {
    return '已找到 $found / $total 个';
  }

  @override
  String get toolchainInstall => '获取';

  @override
  String toolchainOpenFailed(String url) {
    return '无法打开链接：$url';
  }

  @override
  String get toolchainGroupRuntime => '运行时';

  @override
  String get toolchainGroupPkg => '包管理器';

  @override
  String get toolchainGroupVcs => '版本控制';

  @override
  String get toolchainGroupDoc => '文档排版';

  @override
  String get toolchainGroupMedia => '多媒体';

  @override
  String get toolchainGroupNet => '网络';

  @override
  String get toolchainDescNode => 'JavaScript / TypeScript 运行时，执行 JS 脚本与构建工具';

  @override
  String get toolchainDescBun => '高性能 JS/TS 运行时，自带打包与包管理，启动极快';

  @override
  String get toolchainDescPython => 'Python 解释器，运行数据处理、绘图与自动化脚本';

  @override
  String get toolchainDescDeno => '安全的 JS/TS 运行时，原生支持 TypeScript';

  @override
  String get toolchainDescNpm => 'Node 默认包管理器';

  @override
  String get toolchainDescPnpm => '快速、节省磁盘的 Node 包管理器';

  @override
  String get toolchainDescYarn => '另一款流行的 Node 包管理器';

  @override
  String get toolchainDescPip => 'Python 包安装器，安装第三方库';

  @override
  String get toolchainDescUv => '极速 Python 包与项目管理器（Rust 实现）';

  @override
  String get toolchainDescGit => '分布式版本控制，克隆与管理代码仓库';

  @override
  String get toolchainDescPandoc => '万能文档转换器，Markdown / Word / PDF 互转';

  @override
  String get toolchainDescPdftotext => 'Poppler 工具集，从 PDF 提取文本（附件 PDF 解析依赖它）';

  @override
  String get toolchainDescXelatex => 'LaTeX 排版引擎，生成高质量 PDF';

  @override
  String get toolchainDescTypst => '现代排版系统，编译速度快，语法简洁';

  @override
  String get toolchainDescFfmpeg => '音视频处理，转码、剪辑与格式转换';

  @override
  String get toolchainDescMagick => 'ImageMagick，图片格式转换与批量处理';

  @override
  String get toolchainDescCurl => '命令行 HTTP 客户端，请求接口与下载文件';

  @override
  String get toolchainDescWget => '命令行下载工具，递归抓取网络资源';

  @override
  String get expertEditorEdit => '编辑专家';

  @override
  String get expertEditorCreate => '创建专家';

  @override
  String get expertEditorName => '专家名称';

  @override
  String get expertEditorCategory => '分类';

  @override
  String get expertEditorDesc => '简要描述';

  @override
  String get expertEditorPrompt => '系统提示词 (System Prompt)';

  @override
  String get expertCategoryTech => '技术';

  @override
  String get expertCategoryAnalysis => '分析';

  @override
  String get expertCategoryOffice => '办公';

  @override
  String get expertCategoryCreative => '创意';

  @override
  String get expertCategoryCustom => '自定义';

  @override
  String get vplToolName => '可视化编程';

  @override
  String get vplToolDesc => '节点式流程编辑器，拖拽构建程序逻辑';

  @override
  String get vplToolCategory => '开发';

  @override
  String get vplSave => '保存 VPL 项目';

  @override
  String get vplDefaultFilename => '未命名.vpl.json';

  @override
  String vplSaved(String path) {
    return '已保存: $path';
  }

  @override
  String vplSaveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String get vplOpen => '打开 VPL 项目';

  @override
  String vplOpened(String path) {
    return '已打开: $path';
  }

  @override
  String vplOpenFailed(String error) {
    return '打开失败: $error';
  }

  @override
  String get vplExportCode => '导出代码';

  @override
  String get vplExportJson => 'JSON (可重新导入)';

  @override
  String get vplCopyPython => '复制 Python 到剪贴板';

  @override
  String get vplCopied => '已复制到剪贴板';

  @override
  String vplExported(String path) {
    return '已导出: $path';
  }

  @override
  String vplCodePreview(String lang) {
    return '$lang 代码预览';
  }

  @override
  String get vplUnsavedTitle => '未保存的更改';

  @override
  String get vplUnsavedContent => '当前项目有未保存的修改，是否保存？';

  @override
  String get vplDontSave => '不保存';

  @override
  String get vplNewProject => '新项目';

  @override
  String get vplBtnNew => '新建';

  @override
  String get vplBtnOpen => '打开';

  @override
  String get vplBtnSave => '保存';

  @override
  String get vplBtnExport => '导出';

  @override
  String get vplBtnFitCanvas => '适应画布';

  @override
  String get vplBtnSelectAll => '全选';

  @override
  String get vplBtnDeleteSelected => '删除选中';

  @override
  String get vplStatusReady => '就绪';

  @override
  String vplStatusNodes(int count, int edges) {
    return '节点: $count  连线: $edges';
  }

  @override
  String get vplCatFlow => '流程控制';

  @override
  String get vplCatData => '数据';

  @override
  String get vplCatMath => '运算';

  @override
  String get vplCatIO => '输入输出';

  @override
  String get vplCatFunc => '函数';

  @override
  String get vplCatOther => '其他';

  @override
  String get vplNodeStart => '开始';

  @override
  String get vplNodeEnd => '结束';

  @override
  String get vplNodeCondition => '条件';

  @override
  String get vplNodeLoop => '循环';

  @override
  String get vplNodeVariable => '变量';

  @override
  String get vplNodeConstant => '常量';

  @override
  String get vplNodeList => '列表';

  @override
  String get vplNodeDict => '字典';

  @override
  String get vplNodeMath => '数学运算';

  @override
  String get vplNodeCompare => '比较运算';

  @override
  String get vplNodeLogic => '逻辑运算';

  @override
  String get vplNodeString => '字符串';

  @override
  String get vplNodeOutput => '输出';

  @override
  String get vplNodeInput => '输入';

  @override
  String get vplNodeReadFile => '读文件';

  @override
  String get vplNodeWriteFile => '写文件';

  @override
  String get vplNodeFuncDef => '函数定义';

  @override
  String get vplNodeFuncCall => '函数调用';

  @override
  String get vplNodeReturn => '返回';

  @override
  String get vplNodeComment => '注释';

  @override
  String vplPropTitle(String name) {
    return '$name 属性';
  }

  @override
  String get vplPropName => '名称';

  @override
  String get vplPropValue => '值';

  @override
  String get vplPropOperator => '运算符';

  @override
  String get vplPropResultVar => '结果变量名';

  @override
  String get vplPropIndexVar => '索引变量名';

  @override
  String get vplPropPromptText => '提示文本';

  @override
  String get vplPropVarName => '变量名';

  @override
  String get vplPropParamList => '参数列表';

  @override
  String get vplPropCallArgs => '调用参数';

  @override
  String get vplPropContent => '内容';

  @override
  String get vplPropFilePath => '文件路径';

  @override
  String get vplDefaultPrompt => '\"请输入: \"';

  @override
  String get vplPortCondition => '条件';

  @override
  String get vplPortCount => '次数';

  @override
  String get vplPortBody => '循环体';

  @override
  String get vplPortIndex => '索引';

  @override
  String get vplPortDone => '完成';

  @override
  String get vplPortAssign => '赋值';

  @override
  String get vplPortValue => '值';

  @override
  String get vplPortElement => '元素';

  @override
  String get vplPortList => '列表';

  @override
  String get vplPortLength => '长度';

  @override
  String get vplPortKey => '键';

  @override
  String get vplPortDict => '字典';

  @override
  String get vplPortResult => '结果';

  @override
  String get vplPortInput => '输入';

  @override
  String get vplPortParam => '参数';

  @override
  String get vplPortPrompt => '提示';

  @override
  String get vplPortPath => '路径';

  @override
  String get vplPortContent => '内容';

  @override
  String get vplPortReturn => '返回';

  @override
  String get fcToolName => '流程图';

  @override
  String get fcToolDesc => '可视化流程图编辑，支持导出 Mermaid 语法';

  @override
  String get fcToolCategory => '开发';

  @override
  String get siyuToolName => '思宇';

  @override
  String get siyuToolDesc => '富文本文档编辑器，支持图片、格式、导出';

  @override
  String get siyuToolCategory => '创作';

  @override
  String get siyuPickLocation => '选择项目存放位置';

  @override
  String get siyuNewProject => '新建项目';

  @override
  String get siyuProjectName => '项目名称';

  @override
  String get siyuDefaultName => '新文档';

  @override
  String siyuFolderExists(String name) {
    return '文件夹已存在: $name';
  }

  @override
  String siyuSaved(String name) {
    return '$name · 已保存';
  }

  @override
  String siyuSaveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String get siyuPickImage => '选择图片';

  @override
  String get siyuExportTitle => '导出文档';

  @override
  String get siyuExportTxt => '纯文本 (.txt)';

  @override
  String get siyuExportSaveTitle => '导出文档';

  @override
  String siyuExported(String path) {
    return '已导出: $path';
  }

  @override
  String get siyuPlaceholder => '开始书写...';

  @override
  String get siyuWelcomeTitle => '思宇';

  @override
  String get siyuWelcomeDesc => '富文本文档编辑器';

  @override
  String get siyuBtnNewProject => '新建项目';

  @override
  String get siyuBtnSave => '保存';

  @override
  String get siyuBtnInsertImage => '插入图片';

  @override
  String get siyuBtnExport => '导出';

  @override
  String get siyuStatusReady => '就绪';

  @override
  String siyuImageNotFound(String path) {
    return '图片不存在: $path';
  }

  @override
  String get siyuImageLoading => '图片加载中...';

  @override
  String get formulaOcrName => '公式 OCR';

  @override
  String get formulaOcrDesc => '图片识别文字与数学公式 (Pix2Text)';

  @override
  String get formulaOcrModeTextFormula => '文字+公式';

  @override
  String get formulaOcrModeText => '纯文字';

  @override
  String get formulaOcrModeFormula => '纯公式';

  @override
  String get formulaOcrPickImage => '选择要识别的图片';

  @override
  String get formulaOcrNeedApiKey => '请先在设置中配置 API Key';

  @override
  String get formulaOcrNeedImage => '请先上传图片';

  @override
  String formulaOcrFailed(String error) {
    return '识别失败: $error';
  }

  @override
  String get formulaOcrExportMd => '导出 Markdown';

  @override
  String formulaOcrExported(String path) {
    return '已导出: $path';
  }

  @override
  String get formulaOcrPandocMissing => 'Pandoc 未配置';

  @override
  String get formulaOcrPandocHint =>
      '导出 Word 需要 Pandoc，当前未检测到。\n是否降级为导出 Markdown？\n\n（可在 设置 → 工具路径 中配置 Pandoc）';

  @override
  String get formulaOcrExportMdBtn => '导出 MD';

  @override
  String get formulaOcrExportWord => '导出 Word';

  @override
  String formulaOcrPandocFailed(String error) {
    return 'Pandoc 转换失败: $error';
  }

  @override
  String formulaOcrExportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get formulaOcrSectionImage => '图片';

  @override
  String get formulaOcrUploadImage => '上传图片';

  @override
  String get formulaOcrSectionMode => '识别模式';

  @override
  String get formulaOcrRecognizing => '识别中...';

  @override
  String get formulaOcrStartRecognize => '开始识别';

  @override
  String get formulaOcrSectionResult => '识别结果';

  @override
  String get formulaOcrCopy => '复制';

  @override
  String get formulaOcrResultPlaceholder => '识别结果将在此处显示';

  @override
  String get formulaOcrCopied => '已复制到剪贴板';

  @override
  String get formulaOcrSubmitFailed => '提交任务失败';

  @override
  String get formulaOcrRecognizeFailed => '识别失败';

  @override
  String get formulaOcrTimeout => '识别超时，请稍后重试';

  @override
  String get formulaOcrSaveConfig => '保存配置';

  @override
  String get formulaOcrRegisterKey => '注册获取 Key';

  @override
  String get formulaOcrFreeQuota => '每日免费 10,000 字符额度';

  @override
  String get formulaOcrCategory => 'AI';

  @override
  String get paddleOcrName => 'PaddleOCR';

  @override
  String get paddleOcrDesc => '通用 OCR 与文档解析 (PaddleOCR 官方 API)';

  @override
  String get paddleOcrCategory => 'AI';

  @override
  String get paddleOcrModeOcr => 'OCR 识别';

  @override
  String get paddleOcrModeDoc => '文档解析';

  @override
  String get paddleOcrModeOcrDesc => 'PP-OCRv6 · 通用文字识别';

  @override
  String get paddleOcrModeDocDesc => 'PaddleOCR-VL · Markdown 输出';

  @override
  String get paddleOcrPickFile => '选择图片或 PDF 文件';

  @override
  String get paddleOcrNeedPython => '请先在设置中配置 Python 路径';

  @override
  String get paddleOcrNeedToken => '请先在设置中配置 Access Token';

  @override
  String get paddleOcrNeedFile => '请先选择文件';

  @override
  String get paddleOcrSubmitting => '正在提交任务...';

  @override
  String get paddleOcrCalling => '正在调用 PaddleOCR API...';

  @override
  String paddleOcrExecFailed(String error) {
    return '执行失败: $error';
  }

  @override
  String get paddleOcrNoResult => '未返回识别结果';

  @override
  String paddleOcrError(String error) {
    return '执行出错: $error';
  }

  @override
  String get paddleOcrSectionInput => '输入文件';

  @override
  String get paddleOcrSelectFile => '选择图片或 PDF';

  @override
  String get paddleOcrSectionMode => '任务模式';

  @override
  String get paddleOcrProcessing => '处理中...';

  @override
  String get paddleOcrStart => '开始识别';

  @override
  String get paddleOcrModelOcr => 'OCR 模型';

  @override
  String get paddleOcrModelDoc => '解析模型';

  @override
  String get paddleOcrAdvanced => '高级选项';

  @override
  String get paddleOcrRotateCorrect => '文档方向矫正';

  @override
  String get paddleOcrUnwarp => '扭曲矫正';

  @override
  String get paddleOcrChartRecognize => '图表识别';

  @override
  String get paddleOcrResultDoc => '文档解析结果 (Markdown)';

  @override
  String get paddleOcrResultOcr => 'OCR 识别结果';

  @override
  String get paddleOcrResultPlaceholder => '识别结果将在此处显示';

  @override
  String get paddleOcrFileHint => '支持图片 (PNG/JPG/BMP/TIFF) 和 PDF 文件';

  @override
  String get paddleOcrSaveConfig => '保存配置';

  @override
  String get paddleOcrTesting => '测试中...';

  @override
  String get paddleOcrTestConn => '测试连接';

  @override
  String get paddleOcrGetToken => '获取 Token';

  @override
  String get paddleOcrApiDesc => 'PaddleOCR 官网免费 API，支持通用 OCR 与文档解析';

  @override
  String get imageGenName => 'Gemini 画图';

  @override
  String get imageGenDesc => '文生图 / 图改图';

  @override
  String get imageGenCategory => '创作';

  @override
  String get imageGenQuality1k => '1K 快速';

  @override
  String get imageGenQuality2k => '2K 推荐';

  @override
  String get imageGenQuality4k => '4K 超清';

  @override
  String get imageGenNeedConfig => '请先在设置中配置 API 地址和 Key';

  @override
  String get imageGenNeedInput => '请输入描述文字或上传参考图';

  @override
  String imageGenFailed(String error) {
    return '生成失败: $error';
  }

  @override
  String get imageGenPickRef => '选择参考图片';

  @override
  String get imageGenExportTitle => '导出图片';

  @override
  String imageGenExported(String path) {
    return '已导出: $path';
  }

  @override
  String get imageGenSectionDesc => '描述';

  @override
  String get imageGenDescHint => '描述你想生成的图片...';

  @override
  String get imageGenSectionRef => '参考图（可选）';

  @override
  String get imageGenUploadRef => '上传参考图';

  @override
  String get imageGenSectionQuality => '画质';

  @override
  String get imageGenSectionRatio => '宽高比';

  @override
  String get imageGenGenerating => '生成中...';

  @override
  String get imageGenGenerate => '生成图片';

  @override
  String get imageGenExportPng => '导出 PNG';

  @override
  String get imageGenPlaceholder => '生成的图片将在此处预览';

  @override
  String get imageGenTimeout => '请求超时，请稍后重试';

  @override
  String get imageGenSaveConfig => '保存配置';

  @override
  String get imageGenTestConn => '测试连接';

  @override
  String get imageGenTesting => '测试中...';

  @override
  String get modelNameFallback => '未命名模型';

  @override
  String get fcShapeRect => '矩形';

  @override
  String get fcShapeRoundRect => '圆角矩形';

  @override
  String get fcShapeDiamond => '菱形';

  @override
  String get fcShapeCircle => '圆形';

  @override
  String get fcShapeParallelogram => '平行四边形';

  @override
  String get fcShapeHexagon => '六边形';

  @override
  String get fcShapeDatabase => '数据库';

  @override
  String get fcShapeCapsule => '胶囊形';

  @override
  String get fcArrowSingle => '单向箭头';

  @override
  String get fcArrowDouble => '双向箭头';

  @override
  String get fcArrowNone => '无箭头';

  @override
  String get fcLineSolid => '实线';

  @override
  String get fcLineDashed => '虚线';

  @override
  String get fcLineDotted => '点线';

  @override
  String get fcUnsavedTitle => '未保存的更改';

  @override
  String get fcUnsavedContent => '当前流程图有未保存的修改，是否保存？';

  @override
  String get fcDontSave => '不保存';

  @override
  String get fcSaveTitle => '保存流程图';

  @override
  String get fcDefaultFilename => '未命名.fc.json';

  @override
  String fcSaved(String path) {
    return '已保存: $path';
  }

  @override
  String fcSaveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String get fcOpenTitle => '打开流程图';

  @override
  String fcOpened(String path) {
    return '已打开: $path';
  }

  @override
  String fcOpenFailed(String error) {
    return '打开失败: $error';
  }

  @override
  String get fcNewChart => '新建流程图';

  @override
  String get fcCanvasNotReady => '画布未就绪';

  @override
  String get fcImageFailed => '图片生成失败';

  @override
  String get fcExportPng => '导出流程图为 PNG';

  @override
  String fcExported(String path) {
    return '已导出: $path';
  }

  @override
  String fcExportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get fcBtnNew => '新建';

  @override
  String get fcBtnOpen => '打开';

  @override
  String get fcBtnSave => '保存';

  @override
  String get fcBtnExportImage => '导出图片';

  @override
  String get fcBtnHideGrid => '隐藏网格';

  @override
  String get fcBtnShowGrid => '显示网格';

  @override
  String get fcBtnFitCanvas => '适应画布';

  @override
  String get fcBtnSelectAll => '全选';

  @override
  String get fcBtnDeleteSelected => '删除选中';

  @override
  String get fcStatusReady => '就绪 · 点击左侧形状添加节点，从端口拖线连接';

  @override
  String fcStatusNodes(int count, int edges) {
    return '节点: $count';
  }

  @override
  String get fcCustomColor => '自定义颜色';

  @override
  String get fcClickToAdd => '点击添加到画布';

  @override
  String get fcNodeColor => '节点颜色';

  @override
  String get fcHelpText =>
      '操作提示:\n• 点击形状直接添加节点\n• 双击节点编辑文字/样式\n• 从节点边缘拖线连接\n• 滚轮缩放，拖拽画布';

  @override
  String get fcEditNode => '编辑节点';

  @override
  String get fcTextContent => '文本内容';

  @override
  String get servicesSearchTab => '搜索';

  @override
  String get searchDescription =>
      '配置 AI 搜索服务后，可在对话中让模型自动调用联网搜索获取最新信息。选择一个服务并填入 API Key 即可启用。';

  @override
  String get searchBaidu => '百度智能搜索';

  @override
  String get searchTavilyHint => '免费 1000 次/月，支持 AI 摘要';

  @override
  String get searchBraveHint => '免费 2000 次/月，隐私友好';

  @override
  String get searchBaiduHint => '百度千帆智能搜索 API';

  @override
  String get searchConfigured => '已配置';

  @override
  String get searchApiKeyHint => '输入 API Key';

  @override
  String get searchSave => '保存';

  @override
  String get chatSearch => '搜索';

  @override
  String get chatSearchActive => '搜索已启用';

  @override
  String get chatSearchHint => '启用联网搜索';

  @override
  String get chatSearchTitle => '搜索引擎';

  @override
  String get chatSearchOff => '关闭';

  @override
  String get chatSearchOffDesc => '不使用联网搜索';

  @override
  String get chatSearchReady => '已就绪，可选择';

  @override
  String get chatSearchNotConfigured => '未配置 API Key，请前往服务页设置';

  @override
  String get searchTestConnection => '测试连接';

  @override
  String get searchTesting => '测试中...';

  @override
  String get searchTestSuccess => '连接成功，API Key 有效';

  @override
  String get petCatGray => '灰色小猫';

  @override
  String get petCatOrange => '橘色小猫';

  @override
  String get petCatWhite => '白色小猫';

  @override
  String get petTitle => '宠物设置';

  @override
  String get petShow => '显示';

  @override
  String get petSkinSection => '精灵皮肤';

  @override
  String get petModelSection => '宠物模型 (AI)';

  @override
  String get petModelHint => '选择宠物使用的 AI 模型';

  @override
  String petModelLoadFailed(String error) {
    return '加载模型失败: $error';
  }

  @override
  String get petTtsSection => '语音合成';

  @override
  String get petTtsSystem => '系统';

  @override
  String get petTtsVolcano => '火山';

  @override
  String get petTtsAppId => 'AppID';

  @override
  String get petTtsAppIdHint => 'App ID';

  @override
  String get petTtsToken => 'Token';

  @override
  String get petTtsTokenHint => 'Access Token';

  @override
  String get petTtsVoiceType => '音色';

  @override
  String get petTtsVoiceTypeHint => 'voice_type (克隆音色 ID)';

  @override
  String get petTtsSave => '保存配置';

  @override
  String get petTtsSaved => '火山 TTS 配置已保存';

  @override
  String get petTtsReady => '✅ 配置完整';

  @override
  String get petTtsIncomplete => '⚠️ 请填写三项必填';

  @override
  String petTtsSpeedLabel(int value) {
    return '语速($value)';
  }

  @override
  String petTtsLoudnessLabel(int value) {
    return '音量($value)';
  }

  @override
  String get petTtsCredentialHint =>
      '凭证获取: 火山引擎控制台 → 语音合成 → 音色克隆\n参考: github.com/Radiant303/astrbot_plugin_clonetts';

  @override
  String get petBehaviorSection => '回复行为';

  @override
  String petTtsThresholdLabel(int value) {
    return '语音阈值($value字)';
  }

  @override
  String petTtsThresholdHint(int value) {
    return '≤$value字语音，超出文本气泡';
  }

  @override
  String petBubbleDismissLabel(int value) {
    return '气泡倒计时(${value}s)';
  }

  @override
  String get petBubbleDismissManual => '手动关闭气泡';

  @override
  String petBubbleDismissAuto(int value) {
    return '$value秒后自动关闭气泡';
  }

  @override
  String get petCommandSection => '自定义右键指令';

  @override
  String get petCommandHint => '添加自定义指令后会出现在右键菜单中';

  @override
  String get petCommandAdd => '添加指令';

  @override
  String get petCommandAddTitle => '添加自定义指令';

  @override
  String get petCommandEditTitle => '编辑指令';

  @override
  String get petCommandNameLabel => '指令名称';

  @override
  String get petCommandNameHint => '例如：帮我优化';

  @override
  String get petCommandPromptLabel => '系统提示词';

  @override
  String get petCommandPromptHint => '例如：请帮我优化以下代码，提升性能和可读性：';

  @override
  String get petTestSection => '测试';

  @override
  String get petTestShort => '短语音';

  @override
  String get petTestLong => '长文本';

  @override
  String get petDebugEvents => '事件';

  @override
  String get petDebugAnimations => '动画';

  @override
  String get petDebugState => '状态';

  @override
  String get petBubbleThinking => '小猫思考中...';

  @override
  String get petBubbleTitle => '小猫说';

  @override
  String get petBubbleGenerating => '正在生成回答...';

  @override
  String get petBubbleClose => '关闭';

  @override
  String get petBubbleFeedAll => '投喂全文给小猫';

  @override
  String petBubbleFeedFollow(String label) {
    return '追问: $label';
  }

  @override
  String petBubbleFeedSelected(String label) {
    return '投喂小猫: $label';
  }

  @override
  String get petNoModel => '喵~ 我还没有绑定模型，请在宠物设置中选择一个模型。';

  @override
  String petError(String error) {
    return '喵呜...出错了: $error';
  }

  @override
  String get petContextHide => '隐藏宠物';

  @override
  String get petTestShortText => '你好呀主人！';

  @override
  String get petTestLongText =>
      '主人你好，Flutter中Widget是不可变的，每次状态变化都会创建新的Widget树，这就是setState触发rebuild的原因。';

  @override
  String get petPageTitle => '宠物';

  @override
  String get petTabSettings => '设置';

  @override
  String get petTabShop => '商店';

  @override
  String get petTabAchievements => '成就';

  @override
  String get petShopTitle => '商品';

  @override
  String get petInventoryTitle => '背包';

  @override
  String get petInventoryEmpty => '空空如也~';

  @override
  String get petStatusTitle => '状态';

  @override
  String get petStatusSatiety => '饱腹度';

  @override
  String get petStatusHappiness => '心情值';

  @override
  String get petStatusDecayHint => '每小时饱腹 -5、心情 -3\n投喂食物可恢复';

  @override
  String get petShopBuy => '购买';

  @override
  String petShopBought(String name) {
    return '购买了 $name！';
  }

  @override
  String get petShopNoCoins => '宠物币不足~';

  @override
  String petShopSatiety(int value) {
    return '饱腹+$value';
  }

  @override
  String petShopHappiness(int value) {
    return '心情+$value';
  }

  @override
  String petShopEffect(String effect) {
    return '特效: $effect';
  }

  @override
  String get petAchievementsTitle => '成就';

  @override
  String petAchievementsProgress(int unlocked, int total) {
    return '$unlocked / $total';
  }

  @override
  String get petFeedTitle => '投喂小猫';

  @override
  String get petFeedButton => '投喂';

  @override
  String get petFeedButtonEmpty => '投喂 (背包空)';

  @override
  String get petFeedEmpty => '背包空空如也~ 去商店买点食物吧！';

  @override
  String petFeedStat(int quantity, int satiety, int happiness) {
    return 'x$quantity  饱腹+$satiety 心情+$happiness';
  }

  @override
  String get petFeedClose => '关闭';

  @override
  String petCoinReward(int amount) {
    return '+$amount 宠物币~';
  }

  @override
  String get petFoodBanana => '香蕉';

  @override
  String get petFoodBananaDesc => '软糯香甜，猫猫也爱';

  @override
  String get petFoodApple => '苹果';

  @override
  String get petFoodAppleDesc => '一天一苹果，猫猫不找我';

  @override
  String get petFoodPurpleGrape => '紫葡萄';

  @override
  String get petFoodPurpleGrapeDesc => '颗颗饱满的甜蜜';

  @override
  String get petFoodGreenGrape => '绿葡萄';

  @override
  String get petFoodGreenGrapeDesc => '清爽酸甜，开胃小食';

  @override
  String get petFoodPineapple => '菠萝';

  @override
  String get petFoodPineappleDesc => '热带风味，酸甜爆汁';

  @override
  String get petFoodKiwi => '猕猴桃';

  @override
  String get petFoodKiwiDesc => '维C满满的小绿球';

  @override
  String get petFoodCherry => '樱桃';

  @override
  String get petFoodCherryDesc => '小巧精致，猫猫当玩具拍';

  @override
  String get petFoodStrawberry => '草莓';

  @override
  String get petFoodStrawberryDesc => '红彤彤的快乐果实';

  @override
  String get petFoodCarrot => '胡萝卜';

  @override
  String get petFoodCarrotDesc => '对眼睛好，虽然猫不在乎';

  @override
  String get petFoodTomato => '番茄';

  @override
  String get petFoodTomatoDesc => '水灵灵的新鲜番茄';

  @override
  String get petFoodEggplant => '茄子';

  @override
  String get petFoodEggplantDesc => '紫色的健康蔬菜';

  @override
  String get petFoodPumpkin => '南瓜';

  @override
  String get petFoodPumpkinDesc => '大大的南瓜，够吃好久';

  @override
  String get petFoodBroccoli => '花菜';

  @override
  String get petFoodBroccoliDesc => '像一棵小树，营养丰富';

  @override
  String get petFoodGarlic => '洋蒜';

  @override
  String get petFoodGarlicDesc => '猫猫闻了打喷嚏';

  @override
  String get petFoodPepper => '辣椒';

  @override
  String get petFoodPepperDesc => '呼~辣到跳起来！';

  @override
  String get petFoodMushroom => '蘑菇';

  @override
  String get petFoodMushroomDesc => '鲜美的菌菇，猫猫意外喜欢';

  @override
  String get petFoodHam => '火腿';

  @override
  String get petFoodHamDesc => '浓郁肉香，猫猫口水直流';

  @override
  String get petFoodChicken => '鸡腿';

  @override
  String get petFoodChickenDesc => '外焦里嫩的大鸡腿';

  @override
  String get petFoodFish => '鱼';

  @override
  String get petFoodFishDesc => '猫猫的最爱！没有之一';

  @override
  String get petFoodLobster => '大龙虾';

  @override
  String get petFoodLobsterDesc => '顶级海鲜盛宴，猫猫疯狂';

  @override
  String get petAchieveFirstCoin => '第一桶金';

  @override
  String get petAchieveFirstCoinDesc => '获得第一枚宠物币';

  @override
  String get petAchieveRich100 => '小有积蓄';

  @override
  String get petAchieveRich100Desc => '累计获得 100 宠物币';

  @override
  String get petAchieveRich500 => '小富翁';

  @override
  String get petAchieveRich500Desc => '累计获得 500 宠物币';

  @override
  String get petAchieveRich2000 => '宠物大亨';

  @override
  String get petAchieveRich2000Desc => '累计获得 2000 宠物币';

  @override
  String get petAchieveFirstFeed => '初次投喂';

  @override
  String get petAchieveFirstFeedDesc => '第一次喂食小猫';

  @override
  String get petAchieveFeed10 => '尽职铲屎官';

  @override
  String get petAchieveFeed10Desc => '累计投喂 10 次';

  @override
  String get petAchieveFeed50 => '猫奴认证';

  @override
  String get petAchieveFeed50Desc => '累计投喂 50 次';

  @override
  String get petAchieveFullBelly => '吃撑了';

  @override
  String get petAchieveFullBellyDesc => '饱腹度达到 100';

  @override
  String get petAchieveHappyMax => '快乐猫猫';

  @override
  String get petAchieveHappyMaxDesc => '心情值达到 100';

  @override
  String get petAchieveShopper => '购物达人';

  @override
  String get petAchieveShopperDesc => '在商店购买 20 次';

  @override
  String get petAchieveChat1m => '话痨';

  @override
  String get petAchieveChat1mDesc => '累计消耗 100万 tokens';

  @override
  String get petAchieveChat50m => '深度用户';

  @override
  String get petAchieveChat50mDesc => '累计消耗 5000万 tokens';

  @override
  String get petAchieveChat100m => 'AI 重度依赖';

  @override
  String get petAchieveChat100mDesc => '累计消耗 1亿 tokens';

  @override
  String get servicesServerTab => '服务器';

  @override
  String get serverTitle => '服务器';

  @override
  String get serverApiServiceTitle => '对外 API 服务';

  @override
  String get serverApiServiceDesc =>
      '把本机配置的模型、技能、MCP、记忆与搜索能力以标准协议对外提供。默认仅本机可访问，必须配置访问令牌；开放到局域网前请确认安全设置。';

  @override
  String get apiServerTitle => '对外 API 服务';

  @override
  String apiServerRunningPort(Object port) {
    return '运行中 · 端口 $port';
  }

  @override
  String get apiServerStopped => '已停止';

  @override
  String get apiServerIntro =>
      '以 OpenAI / Anthropic 兼容接口对外提供聚合能力 (模型/技能/MCP/记忆/搜索)。默认仅本机可访问 (127.0.0.1)，必须配置访问令牌。';

  @override
  String get apiServerPort => '端口';

  @override
  String get apiServerToken => '访问令牌 (Bearer Token)';

  @override
  String get apiServerTokenRandom => '随机生成';

  @override
  String get apiServerTokenShow => '显示令牌';

  @override
  String get apiServerTokenHide => '隐藏令牌';

  @override
  String get apiServerTestInBrowser => '浏览器测试';

  @override
  String apiServerTestInBrowserFailed(Object url) {
    return '无法打开浏览器: $url';
  }

  @override
  String get apiServerSaveRestart => '保存端口/令牌并重启服务';

  @override
  String get apiServerProtocolTitle => '协议端点';

  @override
  String get apiServerProtocolHint =>
      '按需开放三种对外端点，互不影响。令牌同时支持 Bearer 与 x-api-key 头。';

  @override
  String get apiServerOpenAiAggTitle => 'OpenAI 聚合';

  @override
  String get apiServerOpenAiAggDesc =>
      '跑 RemindAI 自己的 Agent (技能/MCP/记忆/搜索)，以 OpenAI 兼容格式输出。适合通用 OpenAI 客户端接入。';

  @override
  String get apiServerClaudeAggTitle => 'Claude 聚合';

  @override
  String get apiServerClaudeAggDesc =>
      '同样跑 RemindAI 聚合 Agent，但以 Anthropic 协议输出。让仅认 Claude 协议的客户端也能调用本服务的完整聚合能力，工具在服务端内部执行。';

  @override
  String get apiServerClaudeProxyTitle => 'Claude 纯代理';

  @override
  String get apiServerClaudeProxyDesc =>
      '纯协议转换：透传客户端 (如 CherryStudio Agent) 携带的工具与任务给所选模型，由客户端自己执行工具 (不挂载本服务的技能/MCP/记忆)。适合用 Kimi/GPT/Gemini 驱动 CherryStudio 的 Agent 能力。';

  @override
  String get apiServerModelsTitle => '可用模型';

  @override
  String get apiServerModelsHint => '勾选对外开放的模型卡；全部不选 = 开放所有模型卡，客户端可任选';

  @override
  String get apiServerModelsEmpty => '尚未配置任何模型卡';

  @override
  String get apiServerModelsAllOpen => '未限制：当前开放全部模型卡';

  @override
  String get apiServerMemoryTitle => '记忆';

  @override
  String get apiServerMemoryHint => '独立 = 与主程序记忆物理隔离；共享 = 读写主程序记忆 (谨慎)';

  @override
  String get apiServerMemoryNone => '不挂载';

  @override
  String get apiServerMemoryIsolated => '独立记忆';

  @override
  String get apiServerMemoryShared => '共享主记忆';

  @override
  String get apiServerSearchTitle => '联网搜索';

  @override
  String get apiServerSearchHint => '需在搜索设置中配置对应引擎的 API Key';

  @override
  String get apiServerSearchOff => '关闭';

  @override
  String get apiServerSkillsTitle => '技能';

  @override
  String get apiServerSkillsHint => '勾选后对外提供该技能的工具与提示词';

  @override
  String get apiServerSkillsEmpty => '暂无可用技能';

  @override
  String get apiServerMcpTitle => 'MCP 服务';

  @override
  String get apiServerMcpHint => '仅已连接的 MCP 才会对外生效 (灰色表示未连接)';

  @override
  String get apiServerMcpEmpty => '暂无 MCP 服务';

  @override
  String get apiServerBindAllTitle => '允许局域网访问 (0.0.0.0)';

  @override
  String get apiServerBindAllDesc =>
      '开启后同网络的其他设备可调用本服务，等于把你的模型/记忆/工具暴露到局域网。请确保令牌足够强。';

  @override
  String get apiServerBindAllConfirmTitle => '确认暴露到局域网?';

  @override
  String get apiServerBindAllConfirmBody =>
      '开启后，与本机处于同一网络的任何设备都能通过令牌访问该服务，调用你配置的模型、记忆与工具。仅在受信任的网络中开启。';

  @override
  String get apiServerBindAllConfirmCancel => '取消';

  @override
  String get apiServerBindAllConfirmOk => '我已了解风险';

  @override
  String get apiServerIpWhitelistTitle => 'IP 白名单';

  @override
  String get apiServerIpWhitelistHint =>
      '留空 = 不限制 (同网络任意设备可访问)；填写后仅列表内地址可访问 (本机始终放行)';

  @override
  String get apiServerIpWhitelistEmpty => '未配置任何 IP，当前对局域网全部开放';

  @override
  String get apiServerIpWhitelistInputHint => '192.168.1.5 或 192.168.1.0/24';

  @override
  String get apiServerIpWhitelistAdd => '添加';

  @override
  String get apiServerIpWhitelistInvalid =>
      '格式无效，请输入 IPv4 或 CIDR (如 192.168.1.0/24)';

  @override
  String apiServerLoadFailed(Object error) {
    return '加载失败: $error';
  }

  @override
  String trayServerOn(Object port) {
    return '对外服务器 · 运行中 (端口 $port)';
  }

  @override
  String get trayServerOff => '对外服务器 · 已停止';

  @override
  String get trayServerNeedConfig => '对外服务器 (需先配置令牌)';

  @override
  String trayOnlineOn(Object port) {
    return '在线服务 · 运行中 (端口 $port)';
  }

  @override
  String get trayOnlineOff => '在线服务 · 已停止';

  @override
  String get servicesOnlineTab => '在线服务';

  @override
  String get olsTitle => '在线服务';

  @override
  String get olsIntro => '局域网内共享 AI 对话服务。白名单用户通过浏览器访问即可使用。';

  @override
  String olsRunningPort(Object port) {
    return '运行中 :$port';
  }

  @override
  String get olsStopped => '已停止';

  @override
  String get olsControl => '服务控制';

  @override
  String get olsPort => '端口';

  @override
  String get olsMaxConn => '最大连接';

  @override
  String get olsPause => '拉闸';

  @override
  String get olsResume => '恢复';

  @override
  String get olsPauseHint => '停止接受新连接，已在线用户不受影响';

  @override
  String get olsOnlineUsers => '在线用户';

  @override
  String get olsNoUsers => '暂无在线用户';

  @override
  String get olsBusy => '处理中';

  @override
  String get olsKick => '踢出';

  @override
  String get olsWhitelist => '白名单';

  @override
  String get olsWhitelistHint => '(空=允许所有局域网 IP)';

  @override
  String get olsWhitelistAdd => '添加';

  @override
  String get olsWhitelistEdit => '编辑白名单';

  @override
  String get olsWhitelistAddTitle => '添加白名单';

  @override
  String get olsWhitelistEditTitle => '编辑白名单';

  @override
  String get olsWhitelistIp => 'IP 地址';

  @override
  String get olsWhitelistIpHint => '192.168.1.5 或 192.168.1.0/24';

  @override
  String get olsWhitelistNickname => '昵称';

  @override
  String get olsWhitelistModels => '模型 (不选=全部可用)';

  @override
  String get olsWhitelistMcp => 'MCP 服务';

  @override
  String get olsWhitelistSkill => '技能';

  @override
  String get olsWhitelistSearch => '联网搜索';

  @override
  String get olsWhitelistSearchOff => '关闭';

  @override
  String get olsWhitelistSearchTavily => 'Tavily';

  @override
  String get olsWhitelistSearchBrave => 'Brave';

  @override
  String get olsWhitelistSearchBaidu => '百度千帆';

  @override
  String get olsAllModels => '全部模型';

  @override
  String olsNModels(Object n) {
    return '$n个模型';
  }

  @override
  String get olsRemove => '移除';

  @override
  String get olsCancel => '取消';

  @override
  String get olsSave => '保存';

  @override
  String get olsOpenBrowser => '浏览器打开';

  @override
  String olsUserSessionInfo(String ip, Object minutes, Object msgCount) {
    return '$ip · $minutes分钟 · $msgCount条消息';
  }

  @override
  String get olsWhitelistEmpty => '未设置白名单，所有局域网 IP 均可连接';

  @override
  String get olsNicknameHint => '用户名称';

  @override
  String get chatLoopTitle => 'Loop 模式';

  @override
  String get chatLoopDesc => '开启后，AI 将自主迭代执行任务：计划 → 执行 → 验证 → 修复，直到完成或达到最大轮次。';

  @override
  String get chatLoopHint => '开启 Loop 自治模式';

  @override
  String get chatLoopEnabled => 'Loop 模式已开启';

  @override
  String get chatLoopRunning => 'Loop 正在运行中...';

  @override
  String get chatLoopMaxIter => '最大轮次';

  @override
  String get chatLoopAutoApproveHint => 'Loop 模式下工具操作将自动执行，无需逐次确认。';
}

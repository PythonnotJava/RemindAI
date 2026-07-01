// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RemindAI';

  @override
  String get navChat => 'Chat';

  @override
  String get navModels => 'Models';

  @override
  String get navSkills => 'Skills';

  @override
  String get navTools => 'Tools';

  @override
  String get navMultiAgent => 'Collab';

  @override
  String get navExperts => 'Experts';

  @override
  String get navMcp => 'Services';

  @override
  String get navSettings => 'Settings';

  @override
  String get navHistory => 'History';

  @override
  String get navMemory => 'Memory';

  @override
  String get navLogs => 'Logs';

  @override
  String get navPet => 'Pet';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsAccentColorTitle => 'Accent Color';

  @override
  String get settingsAccentColorPurple => 'Purple';

  @override
  String get settingsAccentColorGreen => 'Eye Care';

  @override
  String get settingsAccentColorBlue => 'Blue';

  @override
  String get settingsAccentColorCyan => 'Cyan';

  @override
  String get settingsNotifyOnBlur => 'Notify when unfocused';

  @override
  String get settingsNotifyOnBlurDesc =>
      'Show system notification when conversation completes while window is in background';

  @override
  String get settingsEnterAction => 'Enter Key Behavior';

  @override
  String get settingsEnterSend => 'Send';

  @override
  String get settingsEnterNewline => 'New Line';

  @override
  String get settingsEnterSendHint => 'Enter sends directly';

  @override
  String get settingsEnterNewlineHint => 'Enter newlines, button sends';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsDatabasePath => 'SQLite database path';

  @override
  String get settingsHistoryPath => 'Chat history path';

  @override
  String get settingsSkillsPath => 'Skills directory';

  @override
  String get settingsLogsPath => 'Logs directory';

  @override
  String get settingsToolPaths => 'Tool paths';

  @override
  String get settingsPandocPath => 'Pandoc executable path';

  @override
  String get settingsPandocNotDetected => '(Not detected)';

  @override
  String get settingsQdrant => 'Vector database (Qdrant)';

  @override
  String get settingsEmbedding => 'Embedding models';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsFont => 'Font Settings';

  @override
  String get settingsUiFont => 'UI Font';

  @override
  String get settingsUiFontDesc =>
      'Controls font in navigation, settings, and non-chat areas';

  @override
  String get settingsUiFontSize => 'UI Font Size';

  @override
  String get settingsChatFont => 'Chat Font';

  @override
  String get settingsChatFontDesc =>
      'Controls font in conversations and multi-agent collaboration';

  @override
  String get settingsChatFontSize => 'Chat Font Size';

  @override
  String get settingsFontDefault => 'Default';

  @override
  String get settingsFontPreview => 'Font Preview AaBbCc Hello World 123';

  @override
  String get settingsCustomFont => 'Custom Fonts';

  @override
  String get settingsCustomFontDesc =>
      'Import local .ttf/.otf font files, stored in .RemindAI/fonts/';

  @override
  String get settingsCustomFontImport => 'Import Font';

  @override
  String get settingsCustomFontPick => 'Select font files (.ttf / .otf)';

  @override
  String get settingsCustomFontImported => 'Font imported successfully';

  @override
  String get settingsChange => 'Change';

  @override
  String get settingsMigrating => 'Migrating data...';

  @override
  String get settingsMigratingHint => 'Please do not close the app';

  @override
  String get settingsPickDbTitle => 'Select database location';

  @override
  String get settingsPickHistoryTitle => 'Select history directory';

  @override
  String get settingsPickSkillsTitle => 'Select skills directory';

  @override
  String get settingsPickLogsTitle => 'Select logs directory';

  @override
  String get settingsPickPandocTitle => 'Select Pandoc executable';

  @override
  String get aboutDescription =>
      'Your personal AI workbench on desktop. Execute tools, install skills, connect MCP servers, build persistent memory — all models, one interface.';

  @override
  String get aboutGithub => 'GitHub';

  @override
  String get aboutLicense => 'Licenses';

  @override
  String get aboutPoweredBy => 'Powered by';

  @override
  String get trayShow => 'Show window';

  @override
  String get trayExit => 'Exit';

  @override
  String get dialogCloseTitle => 'Close window';

  @override
  String get dialogCloseContent => 'Minimize to system tray?';

  @override
  String get dialogCloseExit => 'Exit';

  @override
  String get dialogCloseMinimize => 'Minimize to tray';

  @override
  String get chatSelectModel =>
      'Please add and select a model card in the Models page first';

  @override
  String get chatComplete => 'RemindAI conversation complete';

  @override
  String get chatCompleteBody => 'Assistant has finished responding';

  @override
  String get chatNoModel => 'No model selected';

  @override
  String get chatLoading => 'Loading...';

  @override
  String get chatLoadFailed => 'Load failed';

  @override
  String chatLoadFailedWithError(String error) {
    return 'Load failed: $error';
  }

  @override
  String get chatExport => 'Export conversation';

  @override
  String get chatClear => 'Clear conversation';

  @override
  String get chatNew => 'New conversation';

  @override
  String get chatNewWorkspace => 'New workspace';

  @override
  String get chatNeedConfig =>
      'API URL, key, and model name must be configured';

  @override
  String get chatStartConversation => 'Start conversation';

  @override
  String get chatSupportsTools =>
      'Supports file operations, shell commands, memory storage';

  @override
  String get chatCreateWorkspace => 'Create workspace';

  @override
  String get chatAttachments => 'Attachments';

  @override
  String get chatSlashCommands => 'Commands';

  @override
  String get chatSlashRequiresWorkspace => 'Open a workspace first';

  @override
  String chatSlashNeedsDescription(String command) {
    return 'Add a description after $command before sending';
  }

  @override
  String get chatInterruptHint =>
      'Type a new message to interrupt current response...';

  @override
  String get chatInputHint => 'Type a message...';

  @override
  String get chatStopGenerate => 'Stop generating';

  @override
  String get chatInterruptAndSend => 'Interrupt & send';

  @override
  String get chatSkillManage => 'Manage skills';

  @override
  String get chatNoSkills => 'No skills installed';

  @override
  String get chatViewSkillMd => 'View SKILL.md';

  @override
  String get chatUninstall => 'Uninstall';

  @override
  String get chatClose => 'Close';

  @override
  String get chatUninstallSkill => 'Uninstall skill';

  @override
  String chatUninstallSkillConfirm(String name) {
    return 'Uninstall \"$name\"? This cannot be undone.';
  }

  @override
  String chatUninstalled(String name) {
    return 'Uninstalled: $name';
  }

  @override
  String get chatDisconnect => 'Disconnect';

  @override
  String get chatConnect => 'Connect';

  @override
  String get chatConnected => 'Connected';

  @override
  String get chatConnecting => 'Connecting...';

  @override
  String get chatConnectFailed => 'Connection failed';

  @override
  String get chatNotConnected => 'Not connected';

  @override
  String get chatUninstallMcp => 'Uninstall MCP service';

  @override
  String chatUninstallMcpConfirm(String name) {
    return 'Uninstall \"$name\"?';
  }

  @override
  String get chatWorkingDir => 'Working directory';

  @override
  String get chatSelectWorkingDir => 'Select working directory';

  @override
  String get chatMemory => 'Memory';

  @override
  String get chatMemoryEnabled => 'Memory enabled, tap to adjust';

  @override
  String get chatEmbeddingNotConfigured => 'Embedding model not configured';

  @override
  String get chatEmbeddingNotConfiguredHint =>
      'Please configure an embedding model in Settings → Embedding Models';

  @override
  String get chatMemorySettings => 'Memory settings';

  @override
  String get chatEnableRecall => 'Enable memory recall';

  @override
  String get chatEnableRecallDesc =>
      'Auto-retrieve relevant memories before sending';

  @override
  String get chatEnableStore => 'Enable memory storage';

  @override
  String get chatEnableStoreDesc =>
      'Auto-extract and store memories after conversation';

  @override
  String get chatEnableQdrant => 'Enable Qdrant vector search';

  @override
  String get chatEnableQdrantDesc => 'Use vector database for semantic recall';

  @override
  String get chatEnableSqlite => 'Store in SQLite as long-term memory';

  @override
  String get chatEnableSqliteDesc => 'Persist memories to local database';

  @override
  String get chatEnvironment => 'Environment';

  @override
  String get chatEnvConfigured =>
      'Runtime environment configured, tap to adjust';

  @override
  String get chatEnvHint => 'Specify Python / npm interpreter';

  @override
  String get chatEnvTitle => 'Runtime environment';

  @override
  String get chatEnvSessionScope => 'Applies to this session';

  @override
  String get chatEnvDesc =>
      'When specified, python/pip and npm/npx/node commands will use the selected versions';

  @override
  String get chatEnvPythonHint => 'e.g. python.exe / venv/Scripts/python.exe';

  @override
  String get chatEnvSelectNpm => 'Select npm / node executable';

  @override
  String get chatEnvSelectFile => 'Select executable';

  @override
  String get chatEnvClear => 'Clear';

  @override
  String get chatEnvSelect => 'Select';

  @override
  String get chatPermAlways => 'Always';

  @override
  String get chatPermAllow => 'Allow';

  @override
  String get chatPermDeny => 'Deny';

  @override
  String get toolCallWrite => 'Write file';

  @override
  String get toolCallDelete => 'Delete file';

  @override
  String get toolCallExec => 'Execute command';

  @override
  String get msgEdit => 'Edit';

  @override
  String get msgRegenerate => 'Regenerate';

  @override
  String get msgCopy => 'Copy';

  @override
  String get msgCopied => 'Copied to clipboard';

  @override
  String get msgExport => 'Export';

  @override
  String get msgDelete => 'Delete';

  @override
  String get msgThinking => 'Thinking...';

  @override
  String get msgInterrupted => 'Interrupted';

  @override
  String get toolCardArgs => 'Arguments';

  @override
  String get toolCardResult => 'Result';

  @override
  String get toolCardExecuting => 'Executing';

  @override
  String get toolCardDone => 'Done';

  @override
  String get toolCardError => 'Error';

  @override
  String get historyTitle => 'History';

  @override
  String get historyClearAll => 'Clear all conversations';

  @override
  String get historyEmpty => 'No conversations yet';

  @override
  String get historyEmptyHint =>
      'Start a new conversation and it will appear here';

  @override
  String get historyDeleteTitle => 'Delete conversation';

  @override
  String historyDeleteConfirm(String title) {
    return 'Delete \"$title\"? This cannot be undone.';
  }

  @override
  String get historyClearAllTitle => 'Clear all conversations';

  @override
  String get historyClearAllConfirm =>
      'Delete all conversations? This cannot be undone.';

  @override
  String get historyClearBtn => 'Clear';

  @override
  String get historyUntitled => 'Untitled conversation';

  @override
  String get historyJustNow => 'Just now';

  @override
  String get expertsTitle => 'Domain Experts';

  @override
  String get expertsCreate => 'Create expert';

  @override
  String get expertsEmpty => 'No experts yet';

  @override
  String get expertsCreateFirst => 'Create your first expert';

  @override
  String get expertsDeleteTitle => 'Delete expert';

  @override
  String expertsDeleteConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get expertsNameHint => 'e.g. PPT Designer';

  @override
  String get expertsDescHint =>
      'One-line description of this expert\'s capability';

  @override
  String get expertsPromptHint =>
      'Define the expert\'s identity, capabilities, and workflow...';

  @override
  String get expertsBindSkills => 'Bind skills';

  @override
  String get expertsNameRequired => 'Please enter expert name';

  @override
  String get expertsPromptRequired => 'Please enter system prompt';

  @override
  String get expertsSelectIcon => 'Select icon';

  @override
  String get expertsCreate2 => 'Create';

  @override
  String get modelsTitle => 'Model Management';

  @override
  String get modelsEmpty => 'No model cards';

  @override
  String get modelsEmptyHint => 'Tap the button below to add your first model';

  @override
  String get modelsAdd => 'Add model';

  @override
  String get modelsDefault => 'Default';

  @override
  String get modelsDeleteTitle => 'Confirm deletion';

  @override
  String modelsDeleteConfirm(String name) {
    return 'Delete model \"$name\"?';
  }

  @override
  String get modelsEditTitle => 'Edit model';

  @override
  String get modelsNameHint => 'e.g. GPT-4o, Claude Sonnet';

  @override
  String get modelsDetectHint => 'Tap the button to auto-detect';

  @override
  String get modelsDetect => 'Detect available models';

  @override
  String get modelsReorderHint =>
      'Tap card to set default, long press to reorder';

  @override
  String get modelsSearchHint => 'Type to search models...';

  @override
  String get skillsTitle => 'Skill Management';

  @override
  String get skillsImport => 'Import skill';

  @override
  String skillsImportSuccess(String name, int count) {
    return 'Imported: $name ($count tools)';
  }

  @override
  String skillsImportFailed(String detail) {
    return 'Import failed: $detail';
  }

  @override
  String get skillsEmpty => 'No skills installed';

  @override
  String get skillsDeleteTitle => 'Delete skill';

  @override
  String skillsDeleteConfirm(String name) {
    return 'Delete skill \"$name\"? This cannot be undone.';
  }

  @override
  String get mcpTitle => 'MCP Services';

  @override
  String get mcpAdd => 'Add MCP';

  @override
  String get mcpEmpty => 'No MCP services';

  @override
  String mcpConnectSuccess(int count) {
    return 'Connected, found $count tools';
  }

  @override
  String get mcpDeleteTitle => 'Delete MCP service';

  @override
  String mcpDeleteConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get mcpEditTitle => 'Edit MCP service';

  @override
  String get mcpAddTitle => 'Add MCP service';

  @override
  String get mcpNameHint => 'e.g. filesystem-server';

  @override
  String get mcpCommandHint => 'e.g. npx, python, node';

  @override
  String get mcpArgsHint =>
      'e.g. -y @modelcontextprotocol/server-filesystem /tmp';

  @override
  String get mcpCwdHint => 'e.g. C:\\Projects\\my-server';

  @override
  String get mcpEnvHint => 'e.g. API_KEY=xxx';

  @override
  String get mcpHeaderHint => 'e.g. Authorization: Bearer xxx';

  @override
  String get mcpAdd2 => 'Add';

  @override
  String get memoryTitle => 'Memory Management';

  @override
  String get memoryRefresh => 'Refresh';

  @override
  String get memoryCount => 'Memory entries';

  @override
  String get memoryClearTitle => 'Clear memory';

  @override
  String memoryClearConfirm(int count) {
    return 'Delete all $count memories in this workspace? This cannot be recovered.';
  }

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsRefresh => 'Refresh';

  @override
  String get logsEmpty => 'No logs';

  @override
  String get logsContentEmpty => 'Log is empty';

  @override
  String get logsClearAllTitle => 'Clear all logs';

  @override
  String logsClearAllConfirm(int count, String size) {
    return 'This will delete $count log files ($size). This cannot be undone.';
  }

  @override
  String logsClearedCount(int count) {
    return 'Cleared $count log files';
  }

  @override
  String get toolsTitle => 'Toolbox';

  @override
  String get toolsBack => 'Back to tool list';

  @override
  String get toolsSettings => 'Tool settings';

  @override
  String get toolsEmpty => 'No tools available';

  @override
  String toolsSettingsOf(String name) {
    return '$name settings';
  }

  @override
  String get toolShortcutsName => 'Screenshot';

  @override
  String get toolShortcutsDesc => 'View and customize keyboard shortcuts';

  @override
  String get toolShortcutsCategory => 'Shortcuts';

  @override
  String get shortcutReset => 'Reset to defaults';

  @override
  String get shortcutResetDone => 'Shortcuts reset to defaults';

  @override
  String get shortcutHint =>
      'Click the edit button to change a shortcut. At least one modifier key (Ctrl/Shift/Alt) is required.';

  @override
  String get shortcutEdit => 'Edit';

  @override
  String shortcutEditTitle(String name) {
    return 'Change \"$name\" shortcut';
  }

  @override
  String get shortcutEditHint => 'Press a new key combination';

  @override
  String get shortcutEditWaiting => 'Waiting for input...';

  @override
  String get shortcutCancel => 'Cancel';

  @override
  String get shortcutConfirm => 'Confirm';

  @override
  String get multiAgentTitle => 'Multi-Agent Collaboration';

  @override
  String get multiAgentNewAgent => 'New Agent';

  @override
  String get multiAgentHQ => 'Command Center';

  @override
  String get multiAgentManager => 'Agent Manager';

  @override
  String get multiAgentSwitchDir => 'Switch directory';

  @override
  String get multiAgentSwitchDirConfirm => 'Switch working directory?';

  @override
  String get multiAgentNoHistory => 'No history';

  @override
  String get multiAgentSelectDir => 'Select directory';

  @override
  String get multiAgentSelectDirTitle => 'Select collaboration directory';

  @override
  String get multiAgentOpenDir => 'Open directory';

  @override
  String get multiAgentRestoreHistory => 'Restore workspace';

  @override
  String get multiAgentDirHint =>
      'Tip: Select an existing project directory or create a new one';

  @override
  String get multiAgentDeleteHistory => 'Delete history';

  @override
  String multiAgentDeleteHistoryConfirm(String name) {
    return 'Delete snapshot for \"$name\"?\nThis cannot be recovered.';
  }

  @override
  String get multiAgentHistorySection => 'Workspace history';

  @override
  String multiAgentHistoryCount(int count) {
    return '$count entries';
  }

  @override
  String get multiAgentNoHistoryShort => 'No history';

  @override
  String get multiAgentDeleteRecord => 'Delete this record';

  @override
  String get multiAgentActive => 'Active';

  @override
  String get multiAgentHidden => 'Hidden';

  @override
  String get multiAgentSelectFile => 'Select files to send';

  @override
  String get multiAgentReady => 'Ready';

  @override
  String get multiAgentThinking => 'Thinking...';

  @override
  String get multiAgentExecutingTool => 'Executing tool...';

  @override
  String get multiAgentError => 'Error';

  @override
  String get multiAgentSendFile => 'Send file';

  @override
  String get multiAgentInputHint => 'Type a message… (Ctrl+Enter to send)';

  @override
  String get multiAgentWaiting => 'Waiting for response...';

  @override
  String get multiAgentRemoved => 'Agent has been removed';

  @override
  String get multiAgentSelectGlobalFile =>
      'Select files for global distribution';

  @override
  String get multiAgentExportRecord => 'Export collaboration record';

  @override
  String get multiAgentUser => 'User';

  @override
  String get multiAgentSystem => 'System';

  @override
  String get multiAgentTimeline => 'Timeline';

  @override
  String get multiAgentOverview => 'Overview';

  @override
  String get multiAgentBroadcastHint =>
      'Broadcast command… (Ctrl+Enter to send)';

  @override
  String get multiAgentBroadcast => 'Broadcast';

  @override
  String get multiAgentGlobalFile => 'Distribute files globally';

  @override
  String get multiAgentNoMessages => 'No messages yet';

  @override
  String get multiAgentYou => 'You';

  @override
  String get multiAgentNoAgents => 'No agents created yet';

  @override
  String get multiAgentTotalAgents => 'Total agents';

  @override
  String get multiAgentTotalMessages => 'Total messages';

  @override
  String get multiAgentStatus => 'Agent status';

  @override
  String multiAgentMsgCount(int count) {
    return '$count messages';
  }

  @override
  String get multiAgentIdle => 'Idle';

  @override
  String multiAgentExported(String path) {
    return 'Exported to: $path';
  }

  @override
  String multiAgentExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get createAgentTitle => 'Create New Agent';

  @override
  String get createAgentName => 'Name';

  @override
  String get createAgentNameHint => 'e.g. Code Reviewer';

  @override
  String get createAgentRole => 'Role';

  @override
  String get createAgentModel => 'Model';

  @override
  String get createAgentModelFailed => 'Failed to load models';

  @override
  String get createAgentSkills => 'Mount skills';

  @override
  String get createAgentPermissions => 'Grant permissions';

  @override
  String get createAgentPromptHint =>
      'Define this agent\'s responsibilities and behavior...';

  @override
  String get createAgentPromptLabel => 'System prompt (optional)';

  @override
  String get createAgentSysDetect => 'System detection';

  @override
  String get createAgentFileCmd => 'File/Command';

  @override
  String get agentBadgeNotConfigured => 'Not configured';

  @override
  String get agentBadgeModel => 'Model';

  @override
  String get agentBadgePermissions => 'Permissions';

  @override
  String get agentBadgeNoPermissions => 'No special permissions';

  @override
  String get agentBadgeSkills => 'Skills';

  @override
  String get agentBadgeNone => 'None';

  @override
  String get agentBadgeTools => 'Tools';

  @override
  String get agentBadgeMsgCount => 'Messages';

  @override
  String get agentBadgeStatus => 'Status';

  @override
  String get agentBadgeIdle => 'Idle';

  @override
  String get agentBadgeThinking => 'Thinking';

  @override
  String get agentBadgeExecuting => 'Executing tool';

  @override
  String get agentBadgeError => 'Error';

  @override
  String get agentBadgeSystemPrompt => 'System prompt';

  @override
  String get agentBadgeNotExist => 'Agent does not exist';

  @override
  String get agentRoleCommander => 'Commander';

  @override
  String get agentRoleWorker => 'Worker';

  @override
  String get agentRoleReviewer => 'Reviewer';

  @override
  String get agentRoleResearcher => 'Researcher';

  @override
  String get agentRoleCoder => 'Coder';

  @override
  String get agentRoleCustom => 'Custom';

  @override
  String get agentPermRead => 'Read file';

  @override
  String get agentPermWrite => 'Write file';

  @override
  String get agentPermDelete => 'Delete file';

  @override
  String get agentPermExec => 'Execute command';

  @override
  String get agentPermNetwork => 'Network';

  @override
  String get wsDialogTitle => 'New Workspace';

  @override
  String get wsDialogDesc =>
      'Create a workspace with project config, auto-generates memory.json';

  @override
  String get wsDialogLocation => 'Directory location';

  @override
  String get wsDialogSelectParent => 'Select parent directory...';

  @override
  String get wsDialogFolderName => 'Folder name';

  @override
  String get wsDialogFolderHint => 'e.g. my_project';

  @override
  String get wsDialogConfig => 'Project config (memory.json)';

  @override
  String get wsDialogPermMode => 'Permission mode';

  @override
  String get wsDialogPermAuto => 'Auto-execute (auto)';

  @override
  String get wsDialogPermNormal => 'Require confirmation (normal)';

  @override
  String get wsDialogEmbeddings => 'Vector memory (embeddings)';

  @override
  String get wsDialogEmbeddingsHint =>
      'Configure embedding model in settings first';

  @override
  String get wsDialogAutoStore => 'Auto-store memory';

  @override
  String get wsDialogAutoStoreDesc =>
      'Important info auto-saved to long-term memory';

  @override
  String get wsDialogAutoRecall => 'Auto-recall memory';

  @override
  String get wsDialogAutoRecallDesc =>
      'Semantically match and recall relevant memories';

  @override
  String get wsDialogEmbConn => 'Embedding model connection';

  @override
  String get wsDialogTesting => 'Testing...';

  @override
  String get wsDialogTestConn => 'Test connection';

  @override
  String get wsDialogCreating => 'Creating...';

  @override
  String get wsDialogCreateBtn => 'Create & switch';

  @override
  String get wsDialogSelectParentTitle => 'Select parent directory';

  @override
  String get wsDialogEmbNotConfigured =>
      'Embedding model not configured, please set up in settings';

  @override
  String wsDialogCreated(String name) {
    return 'Workspace created: $name';
  }

  @override
  String wsDialogCreateFailed(String error) {
    return 'Creation failed: $error';
  }

  @override
  String get embEditorTitle => 'Edit Embedding Model';

  @override
  String get embEditorAddTitle => 'Add Embedding Model';

  @override
  String get embEditorNameHint => 'e.g. OpenAI Large';

  @override
  String get embEditorEnableQdrant => 'Enable Qdrant vector search';

  @override
  String get embEditorEnableSqlite => 'Store in SQLite as long-term memory';

  @override
  String get embEditorTestConn => 'Test connection';

  @override
  String get embEditorFillRequired =>
      'Please fill in Base URL, API Key, and Model';

  @override
  String get embEditorConnSuccess => 'Connection successful';

  @override
  String get embEditorConnAbnormal =>
      'Connected, but response format is abnormal';

  @override
  String get embEditorTimeout => 'Request timeout';

  @override
  String get embEditorUnknownError => 'Unknown error';

  @override
  String get embSectionHint =>
      'Configure one or more embedding models. Tap a card to set as default (selected model is used for memory vectorization)';

  @override
  String get embSectionDeleteTitle => 'Delete embedding model';

  @override
  String embSectionDeleteConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get embSectionDefault => 'Default';

  @override
  String get embSectionAdd => 'Add embedding model';

  @override
  String get qdrantSelectExe => 'Select Qdrant executable';

  @override
  String get qdrantDetection => 'Executable detection';

  @override
  String get qdrantRedetect => 'Re-detect';

  @override
  String get qdrantNotFound => 'Qdrant executable not found';

  @override
  String get qdrantNotFoundHint =>
      'Please manually specify the qdrant executable, or download from qdrant.tech and add to system PATH.';

  @override
  String get qdrantChangePath => 'Change path';

  @override
  String get qdrantManualSelect => 'Manual select';

  @override
  String get qdrantAutoDetect => 'Restore auto-detect';

  @override
  String get exportFormatTitle => 'Select export format';

  @override
  String exportExporting(String format) {
    return 'Exporting $format...';
  }

  @override
  String exportSuccess(String path) {
    return 'Exported to: $path';
  }

  @override
  String get exportFallbackMd =>
      'Export as Markdown (.md) instead? Content is identical.';

  @override
  String get exportFallbackBtn => 'Export as Markdown';

  @override
  String exportFailed(String format) {
    return '$format export failed';
  }

  @override
  String get exportSaveTitle => 'Save export file';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonError => 'Error';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonEmpty => 'No content';

  @override
  String get commonClose => 'Close';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonSwitch => 'Switch';

  @override
  String get commonAdd => 'Add';

  @override
  String commonErrorWithMsg(String msg) {
    return 'Error: $msg';
  }

  @override
  String get attachOpenWith => 'Open with system app';

  @override
  String attachFileNotExist(String path) {
    return 'File does not exist: $path';
  }

  @override
  String get imgSaveAs => 'Save As…';

  @override
  String get imgCopyPath => 'Copy Path';

  @override
  String get imgOpenExternal => 'Show in Folder';

  @override
  String get imgSaved => 'Image saved';

  @override
  String get imgPathCopied => 'Path copied';

  @override
  String get codeSource => 'Source';

  @override
  String get codePreview => 'Preview';

  @override
  String get scrollUp => 'Scroll up (hold to continue)';

  @override
  String get scrollDown => 'Scroll down (hold to continue)';

  @override
  String get permissionDenied => 'User denied the operation';

  @override
  String get memoryEmbNotConfigured =>
      'Embedding model not configured\nPlease configure an Embedding model in Settings to enable vector memory';

  @override
  String get memoryQdrantNotRunning =>
      'Qdrant vector database is not running\nPlease check the Qdrant service status';

  @override
  String get memoryEmptyHint =>
      'No memories in this workspace yet\nNoteworthy info from conversations will be stored automatically';

  @override
  String get memoryQdrantStopped => 'Not running';

  @override
  String get memoryContentEmpty => '(empty)';

  @override
  String get memorySourceAuto => 'Auto';

  @override
  String memoryFromQuery(String query) {
    return 'From: $query';
  }

  @override
  String historyMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String historyHoursAgo(int hours) {
    return '$hours hr ago';
  }

  @override
  String historyDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String historyDateFormat(int month, int day) {
    return '$month/$day';
  }

  @override
  String get mcpEmptyHint => 'Tap the button below to add an MCP server';

  @override
  String get mcpReorderHint => 'Tap card to edit, long press to reorder';

  @override
  String get mcpDisconnect => 'Disconnect';

  @override
  String get mcpTestConnection => 'Test connection';

  @override
  String mcpConnectFailedWithDetail(String detail) {
    return 'Connection failed: $detail';
  }

  @override
  String get mcpFormName => 'Name';

  @override
  String get mcpFormNameRequired => 'Please enter a name';

  @override
  String get mcpFormCommand => 'Command';

  @override
  String get mcpFormCommandRequired => 'Please enter a command';

  @override
  String get mcpFormArgs => 'Arguments (space-separated)';

  @override
  String get mcpFormCwd => 'Working directory (optional)';

  @override
  String get mcpFormEnv => 'Environment variables (KEY=VALUE per line)';

  @override
  String get mcpFormUrl => 'URL';

  @override
  String get mcpFormUrlRequired => 'Please enter a URL';

  @override
  String get mcpFormHeaders => 'Headers (Key: Value per line)';

  @override
  String get mcpSseHint => 'e.g. http://localhost:3000/sse';

  @override
  String get mcpStreamableHint => 'e.g. http://localhost:3000/mcp';

  @override
  String get skillsEmptyHint =>
      'Tap the button below to import a ZIP skill package';

  @override
  String get skillsReorderHint =>
      'Toggle to enable/disable, long press to reorder';

  @override
  String get skillsMarketTitle => 'Recommended Skill Markets';

  @override
  String get skillsMarketHint =>
      'Discover and download skill packs (ZIP) from these third-party markets, then load them via the import button below.';

  @override
  String get skillsMarketSkillsMp =>
      'Skill market aggregating multiple sources';

  @override
  String get skillsMarketClaudSkills => 'Claude skill sharing community';

  @override
  String get skillsMarketSkillsSh => 'Open-source skill index and CLI';

  @override
  String skillsMarketOpenFailed(String url) {
    return 'Could not open link: $url';
  }

  @override
  String get skillsBuiltin => 'Built-in';

  @override
  String skillsToolCount(int count) {
    return '$count tools';
  }

  @override
  String get skillsNoDesc => 'No description';

  @override
  String get skillsViewMd => 'View SKILL.md';

  @override
  String get skillsEditDesc => 'Edit description';

  @override
  String get skillsEditDescTitle => 'Edit skill description';

  @override
  String get skillsEditDescHint =>
      'Write a description for this skill (display only)';

  @override
  String get servicesTitle => 'Services';

  @override
  String get servicesSkillsTab => 'Skills';

  @override
  String get servicesToolchainTab => 'Toolchain';

  @override
  String get toolchainDescription =>
      'Recommended command-line tools below. Detection relies on your system PATH — once a tool is on PATH, the model can call it from the tool shell. To avoid needless overhead, nothing is checked automatically; click the button below to probe manually.';

  @override
  String get toolchainDetect => 'Detect Tools';

  @override
  String get toolchainDetecting => 'Detecting';

  @override
  String toolchainSummary(int found, int total) {
    return 'Found $found / $total';
  }

  @override
  String get toolchainInstall => 'Get';

  @override
  String toolchainOpenFailed(String url) {
    return 'Could not open link: $url';
  }

  @override
  String get toolchainGroupRuntime => 'Runtimes';

  @override
  String get toolchainGroupPkg => 'Package Managers';

  @override
  String get toolchainGroupVcs => 'Version Control';

  @override
  String get toolchainGroupDoc => 'Documents';

  @override
  String get toolchainGroupMedia => 'Media';

  @override
  String get toolchainGroupNet => 'Network';

  @override
  String get toolchainDescNode =>
      'JavaScript / TypeScript runtime for scripts and build tools';

  @override
  String get toolchainDescBun =>
      'Fast JS/TS runtime with bundler and package manager built in';

  @override
  String get toolchainDescPython =>
      'Python interpreter for data, plotting and automation scripts';

  @override
  String get toolchainDescDeno =>
      'Secure JS/TS runtime with native TypeScript support';

  @override
  String get toolchainDescNpm => 'Default package manager for Node';

  @override
  String get toolchainDescPnpm => 'Fast, disk-efficient Node package manager';

  @override
  String get toolchainDescYarn => 'Another popular Node package manager';

  @override
  String get toolchainDescPip =>
      'Python package installer for third-party libraries';

  @override
  String get toolchainDescUv =>
      'Blazing-fast Python package and project manager (in Rust)';

  @override
  String get toolchainDescGit =>
      'Distributed version control to clone and manage repos';

  @override
  String get toolchainDescPandoc =>
      'Universal document converter: Markdown / Word / PDF';

  @override
  String get toolchainDescPdftotext =>
      'Poppler tools to extract text from PDF (used for PDF attachments)';

  @override
  String get toolchainDescXelatex =>
      'LaTeX typesetting engine for high-quality PDFs';

  @override
  String get toolchainDescTypst =>
      'Modern typesetting system, fast compile, clean syntax';

  @override
  String get toolchainDescFfmpeg =>
      'Audio/video processing: transcode, trim, convert';

  @override
  String get toolchainDescMagick =>
      'ImageMagick for image conversion and batch processing';

  @override
  String get toolchainDescCurl =>
      'Command-line HTTP client for requests and downloads';

  @override
  String get toolchainDescWget =>
      'Command-line downloader for fetching web resources';

  @override
  String get expertEditorEdit => 'Edit Expert';

  @override
  String get expertEditorCreate => 'Create Expert';

  @override
  String get expertEditorName => 'Expert name';

  @override
  String get expertEditorCategory => 'Category';

  @override
  String get expertEditorDesc => 'Brief description';

  @override
  String get expertEditorPrompt => 'System Prompt';

  @override
  String get expertCategoryTech => 'Tech';

  @override
  String get expertCategoryAnalysis => 'Analysis';

  @override
  String get expertCategoryOffice => 'Office';

  @override
  String get expertCategoryCreative => 'Creative';

  @override
  String get expertCategoryCustom => 'Custom';

  @override
  String get vplToolName => 'Visual Programming';

  @override
  String get vplToolDesc =>
      'Node-based flow editor, drag and drop to build logic';

  @override
  String get vplToolCategory => 'Development';

  @override
  String get vplSave => 'Save VPL project';

  @override
  String get vplDefaultFilename => 'Untitled.vpl.json';

  @override
  String vplSaved(String path) {
    return 'Saved: $path';
  }

  @override
  String vplSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get vplOpen => 'Open VPL project';

  @override
  String vplOpened(String path) {
    return 'Opened: $path';
  }

  @override
  String vplOpenFailed(String error) {
    return 'Open failed: $error';
  }

  @override
  String get vplExportCode => 'Export code';

  @override
  String get vplExportJson => 'JSON (re-importable)';

  @override
  String get vplCopyPython => 'Copy Python to clipboard';

  @override
  String get vplCopied => 'Copied to clipboard';

  @override
  String vplExported(String path) {
    return 'Exported: $path';
  }

  @override
  String vplCodePreview(String lang) {
    return '$lang code preview';
  }

  @override
  String get vplUnsavedTitle => 'Unsaved changes';

  @override
  String get vplUnsavedContent => 'This project has unsaved changes. Save now?';

  @override
  String get vplDontSave => 'Don\'t save';

  @override
  String get vplNewProject => 'New project';

  @override
  String get vplBtnNew => 'New';

  @override
  String get vplBtnOpen => 'Open';

  @override
  String get vplBtnSave => 'Save';

  @override
  String get vplBtnExport => 'Export';

  @override
  String get vplBtnFitCanvas => 'Fit canvas';

  @override
  String get vplBtnSelectAll => 'Select all';

  @override
  String get vplBtnDeleteSelected => 'Delete selected';

  @override
  String get vplStatusReady => 'Ready';

  @override
  String vplStatusNodes(int count, int edges) {
    return 'Nodes: $count  Edges: $edges';
  }

  @override
  String get vplCatFlow => 'Flow Control';

  @override
  String get vplCatData => 'Data';

  @override
  String get vplCatMath => 'Math';

  @override
  String get vplCatIO => 'Input/Output';

  @override
  String get vplCatFunc => 'Functions';

  @override
  String get vplCatOther => 'Other';

  @override
  String get vplNodeStart => 'Start';

  @override
  String get vplNodeEnd => 'End';

  @override
  String get vplNodeCondition => 'Condition';

  @override
  String get vplNodeLoop => 'Loop';

  @override
  String get vplNodeVariable => 'Variable';

  @override
  String get vplNodeConstant => 'Constant';

  @override
  String get vplNodeList => 'List';

  @override
  String get vplNodeDict => 'Dictionary';

  @override
  String get vplNodeMath => 'Math';

  @override
  String get vplNodeCompare => 'Compare';

  @override
  String get vplNodeLogic => 'Logic';

  @override
  String get vplNodeString => 'String';

  @override
  String get vplNodeOutput => 'Output';

  @override
  String get vplNodeInput => 'Input';

  @override
  String get vplNodeReadFile => 'Read File';

  @override
  String get vplNodeWriteFile => 'Write File';

  @override
  String get vplNodeFuncDef => 'Function Def';

  @override
  String get vplNodeFuncCall => 'Function Call';

  @override
  String get vplNodeReturn => 'Return';

  @override
  String get vplNodeComment => 'Comment';

  @override
  String vplPropTitle(String name) {
    return '$name Properties';
  }

  @override
  String get vplPropName => 'Name';

  @override
  String get vplPropValue => 'Value';

  @override
  String get vplPropOperator => 'Operator';

  @override
  String get vplPropResultVar => 'Result variable';

  @override
  String get vplPropIndexVar => 'Index variable';

  @override
  String get vplPropPromptText => 'Prompt text';

  @override
  String get vplPropVarName => 'Variable name';

  @override
  String get vplPropParamList => 'Parameter list';

  @override
  String get vplPropCallArgs => 'Call arguments';

  @override
  String get vplPropContent => 'Content';

  @override
  String get vplPropFilePath => 'File path';

  @override
  String get vplDefaultPrompt => '\"Enter: \"';

  @override
  String get vplPortCondition => 'Condition';

  @override
  String get vplPortCount => 'Count';

  @override
  String get vplPortBody => 'Body';

  @override
  String get vplPortIndex => 'Index';

  @override
  String get vplPortDone => 'Done';

  @override
  String get vplPortAssign => 'Assign';

  @override
  String get vplPortValue => 'Value';

  @override
  String get vplPortElement => 'Element';

  @override
  String get vplPortList => 'List';

  @override
  String get vplPortLength => 'Length';

  @override
  String get vplPortKey => 'Key';

  @override
  String get vplPortDict => 'Dict';

  @override
  String get vplPortResult => 'Result';

  @override
  String get vplPortInput => 'Input';

  @override
  String get vplPortParam => 'Param';

  @override
  String get vplPortPrompt => 'Prompt';

  @override
  String get vplPortPath => 'Path';

  @override
  String get vplPortContent => 'Content';

  @override
  String get vplPortReturn => 'Return';

  @override
  String get fcToolName => 'Flowchart';

  @override
  String get fcToolDesc => 'Visual flowchart editor, supports Mermaid export';

  @override
  String get fcToolCategory => 'Development';

  @override
  String get siyuToolName => 'LostYu';

  @override
  String get siyuToolDesc =>
      'Rich text editor with images, formatting, and export';

  @override
  String get siyuToolCategory => 'Creative';

  @override
  String get siyuPickLocation => 'Select project location';

  @override
  String get siyuNewProject => 'New project';

  @override
  String get siyuProjectName => 'Project name';

  @override
  String get siyuDefaultName => 'New Document';

  @override
  String siyuFolderExists(String name) {
    return 'Folder already exists: $name';
  }

  @override
  String siyuSaved(String name) {
    return '$name · Saved';
  }

  @override
  String siyuSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get siyuPickImage => 'Select image';

  @override
  String get siyuExportTitle => 'Export document';

  @override
  String get siyuExportTxt => 'Plain text (.txt)';

  @override
  String get siyuExportSaveTitle => 'Export document';

  @override
  String siyuExported(String path) {
    return 'Exported: $path';
  }

  @override
  String get siyuPlaceholder => 'Start writing...';

  @override
  String get siyuWelcomeTitle => 'LostYu';

  @override
  String get siyuWelcomeDesc => 'Rich text document editor';

  @override
  String get siyuBtnNewProject => 'New project';

  @override
  String get siyuBtnSave => 'Save';

  @override
  String get siyuBtnInsertImage => 'Insert image';

  @override
  String get siyuBtnExport => 'Export';

  @override
  String get siyuStatusReady => 'Ready';

  @override
  String siyuImageNotFound(String path) {
    return 'Image not found: $path';
  }

  @override
  String get siyuImageLoading => 'Loading image...';

  @override
  String get formulaOcrName => 'Formula OCR';

  @override
  String get formulaOcrDesc =>
      'Recognize text and math formulas from images (Pix2Text)';

  @override
  String get formulaOcrModeTextFormula => 'Text+Formula';

  @override
  String get formulaOcrModeText => 'Text only';

  @override
  String get formulaOcrModeFormula => 'Formula only';

  @override
  String get formulaOcrPickImage => 'Select image to recognize';

  @override
  String get formulaOcrNeedApiKey =>
      'Please configure API Key in settings first';

  @override
  String get formulaOcrNeedImage => 'Please upload an image first';

  @override
  String formulaOcrFailed(String error) {
    return 'Recognition failed: $error';
  }

  @override
  String get formulaOcrExportMd => 'Export Markdown';

  @override
  String formulaOcrExported(String path) {
    return 'Exported: $path';
  }

  @override
  String get formulaOcrPandocMissing => 'Pandoc not configured';

  @override
  String get formulaOcrPandocHint =>
      'Word export requires Pandoc, which is not detected.\nExport as Markdown instead?\n\n(Configure Pandoc in Settings → Tool Paths)';

  @override
  String get formulaOcrExportMdBtn => 'Export MD';

  @override
  String get formulaOcrExportWord => 'Export Word';

  @override
  String formulaOcrPandocFailed(String error) {
    return 'Pandoc conversion failed: $error';
  }

  @override
  String formulaOcrExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get formulaOcrSectionImage => 'Image';

  @override
  String get formulaOcrUploadImage => 'Upload image';

  @override
  String get formulaOcrSectionMode => 'Recognition mode';

  @override
  String get formulaOcrRecognizing => 'Recognizing...';

  @override
  String get formulaOcrStartRecognize => 'Start recognition';

  @override
  String get formulaOcrSectionResult => 'Result';

  @override
  String get formulaOcrCopy => 'Copy';

  @override
  String get formulaOcrResultPlaceholder =>
      'Recognition results will appear here';

  @override
  String get formulaOcrCopied => 'Copied to clipboard';

  @override
  String get formulaOcrSubmitFailed => 'Failed to submit task';

  @override
  String get formulaOcrRecognizeFailed => 'Recognition failed';

  @override
  String get formulaOcrTimeout =>
      'Recognition timed out, please try again later';

  @override
  String get formulaOcrSaveConfig => 'Save config';

  @override
  String get formulaOcrRegisterKey => 'Register for Key';

  @override
  String get formulaOcrFreeQuota => '10,000 free characters per day';

  @override
  String get formulaOcrCategory => 'AI';

  @override
  String get paddleOcrName => 'PaddleOCR';

  @override
  String get paddleOcrDesc =>
      'Universal OCR and document parsing (PaddleOCR API)';

  @override
  String get paddleOcrCategory => 'AI';

  @override
  String get paddleOcrModeOcr => 'OCR Recognition';

  @override
  String get paddleOcrModeDoc => 'Document Parsing';

  @override
  String get paddleOcrModeOcrDesc => 'PP-OCRv6 · General text recognition';

  @override
  String get paddleOcrModeDocDesc => 'PaddleOCR-VL · Markdown output';

  @override
  String get paddleOcrPickFile => 'Select image or PDF file';

  @override
  String get paddleOcrNeedPython =>
      'Please configure Python path in settings first';

  @override
  String get paddleOcrNeedToken =>
      'Please configure Access Token in settings first';

  @override
  String get paddleOcrNeedFile => 'Please select a file first';

  @override
  String get paddleOcrSubmitting => 'Submitting task...';

  @override
  String get paddleOcrCalling => 'Calling PaddleOCR API...';

  @override
  String paddleOcrExecFailed(String error) {
    return 'Execution failed: $error';
  }

  @override
  String get paddleOcrNoResult => 'No recognition result returned';

  @override
  String paddleOcrError(String error) {
    return 'Execution error: $error';
  }

  @override
  String get paddleOcrSectionInput => 'Input file';

  @override
  String get paddleOcrSelectFile => 'Select image or PDF';

  @override
  String get paddleOcrSectionMode => 'Task mode';

  @override
  String get paddleOcrProcessing => 'Processing...';

  @override
  String get paddleOcrStart => 'Start recognition';

  @override
  String get paddleOcrModelOcr => 'OCR model';

  @override
  String get paddleOcrModelDoc => 'Parsing model';

  @override
  String get paddleOcrAdvanced => 'Advanced options';

  @override
  String get paddleOcrRotateCorrect => 'Document orientation correction';

  @override
  String get paddleOcrUnwarp => 'Distortion correction';

  @override
  String get paddleOcrChartRecognize => 'Chart recognition';

  @override
  String get paddleOcrResultDoc => 'Document parsing result (Markdown)';

  @override
  String get paddleOcrResultOcr => 'OCR recognition result';

  @override
  String get paddleOcrResultPlaceholder =>
      'Recognition results will appear here';

  @override
  String get paddleOcrFileHint =>
      'Supports images (PNG/JPG/BMP/TIFF) and PDF files';

  @override
  String get paddleOcrSaveConfig => 'Save config';

  @override
  String get paddleOcrTesting => 'Testing...';

  @override
  String get paddleOcrTestConn => 'Test connection';

  @override
  String get paddleOcrGetToken => 'Get Token';

  @override
  String get paddleOcrApiDesc =>
      'PaddleOCR official free API for OCR and document parsing';

  @override
  String get imageGenName => 'Gemini Image Gen';

  @override
  String get imageGenDesc => 'Text-to-image / Image editing';

  @override
  String get imageGenCategory => 'Creative';

  @override
  String get imageGenQuality1k => '1K Fast';

  @override
  String get imageGenQuality2k => '2K Recommended';

  @override
  String get imageGenQuality4k => '4K Ultra';

  @override
  String get imageGenNeedConfig =>
      'Please configure API URL and Key in settings first';

  @override
  String get imageGenNeedInput =>
      'Please enter a description or upload a reference image';

  @override
  String imageGenFailed(String error) {
    return 'Generation failed: $error';
  }

  @override
  String get imageGenPickRef => 'Select reference image';

  @override
  String get imageGenExportTitle => 'Export image';

  @override
  String imageGenExported(String path) {
    return 'Exported: $path';
  }

  @override
  String get imageGenSectionDesc => 'Description';

  @override
  String get imageGenDescHint => 'Describe the image you want to generate...';

  @override
  String get imageGenSectionRef => 'Reference image (optional)';

  @override
  String get imageGenUploadRef => 'Upload reference';

  @override
  String get imageGenSectionQuality => 'Quality';

  @override
  String get imageGenSectionRatio => 'Aspect ratio';

  @override
  String get imageGenGenerating => 'Generating...';

  @override
  String get imageGenGenerate => 'Generate image';

  @override
  String get imageGenExportPng => 'Export PNG';

  @override
  String get imageGenPlaceholder => 'Generated image will preview here';

  @override
  String get imageGenTimeout => 'Request timed out, please try again later';

  @override
  String get imageGenSaveConfig => 'Save config';

  @override
  String get imageGenTestConn => 'Test connection';

  @override
  String get imageGenTesting => 'Testing...';

  @override
  String get modelNameFallback => 'Unnamed model';

  @override
  String get fcShapeRect => 'Rectangle';

  @override
  String get fcShapeRoundRect => 'Rounded Rectangle';

  @override
  String get fcShapeDiamond => 'Diamond';

  @override
  String get fcShapeCircle => 'Circle';

  @override
  String get fcShapeParallelogram => 'Parallelogram';

  @override
  String get fcShapeHexagon => 'Hexagon';

  @override
  String get fcShapeDatabase => 'Database';

  @override
  String get fcShapeCapsule => 'Capsule';

  @override
  String get fcArrowSingle => 'Single arrow';

  @override
  String get fcArrowDouble => 'Double arrow';

  @override
  String get fcArrowNone => 'No arrow';

  @override
  String get fcLineSolid => 'Solid';

  @override
  String get fcLineDashed => 'Dashed';

  @override
  String get fcLineDotted => 'Dotted';

  @override
  String get fcUnsavedTitle => 'Unsaved changes';

  @override
  String get fcUnsavedContent =>
      'This flowchart has unsaved changes. Save now?';

  @override
  String get fcDontSave => 'Don\'t save';

  @override
  String get fcSaveTitle => 'Save flowchart';

  @override
  String get fcDefaultFilename => 'Untitled.fc.json';

  @override
  String fcSaved(String path) {
    return 'Saved: $path';
  }

  @override
  String fcSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get fcOpenTitle => 'Open flowchart';

  @override
  String fcOpened(String path) {
    return 'Opened: $path';
  }

  @override
  String fcOpenFailed(String error) {
    return 'Open failed: $error';
  }

  @override
  String get fcNewChart => 'New flowchart';

  @override
  String get fcCanvasNotReady => 'Canvas not ready';

  @override
  String get fcImageFailed => 'Image generation failed';

  @override
  String get fcExportPng => 'Export flowchart as PNG';

  @override
  String fcExported(String path) {
    return 'Exported: $path';
  }

  @override
  String fcExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get fcBtnNew => 'New';

  @override
  String get fcBtnOpen => 'Open';

  @override
  String get fcBtnSave => 'Save';

  @override
  String get fcBtnExportImage => 'Export image';

  @override
  String get fcBtnHideGrid => 'Hide grid';

  @override
  String get fcBtnShowGrid => 'Show grid';

  @override
  String get fcBtnFitCanvas => 'Fit canvas';

  @override
  String get fcBtnSelectAll => 'Select all';

  @override
  String get fcBtnDeleteSelected => 'Delete selected';

  @override
  String get fcStatusReady =>
      'Ready · Click shapes to add nodes, drag from ports to connect';

  @override
  String fcStatusNodes(int count, int edges) {
    return 'Nodes: $count  Edges: $edges';
  }

  @override
  String get fcCustomColor => 'Custom color';

  @override
  String get fcClickToAdd => 'Click to add to canvas';

  @override
  String get fcNodeColor => 'Node color';

  @override
  String get fcHelpText =>
      'Tips:\n• Click a shape to add a node\n• Double-click node to edit text/style\n• Drag from node edge to connect\n• Scroll to zoom, drag to pan';

  @override
  String get fcEditNode => 'Edit node';

  @override
  String get fcTextContent => 'Text content';

  @override
  String get servicesSearchTab => 'Search';

  @override
  String get searchDescription =>
      'Configure AI search services to let models automatically search the web for up-to-date information during conversations. Select a service and enter an API Key to enable.';

  @override
  String get searchBaidu => 'Baidu AI Search';

  @override
  String get searchTavilyHint =>
      '1000 free queries/month, AI summaries included';

  @override
  String get searchBraveHint => '2000 free queries/month, privacy-focused';

  @override
  String get searchBaiduHint => 'Baidu Qianfan Intelligent Search API';

  @override
  String get searchConfigured => 'Configured';

  @override
  String get searchApiKeyHint => 'Enter API Key';

  @override
  String get searchSave => 'Save';

  @override
  String get chatSearch => 'Search';

  @override
  String get chatSearchActive => 'Search enabled';

  @override
  String get chatSearchHint => 'Enable web search';

  @override
  String get chatSearchTitle => 'Search Engine';

  @override
  String get chatSearchOff => 'Off';

  @override
  String get chatSearchOffDesc => 'Do not use web search';

  @override
  String get chatSearchReady => 'Ready to use';

  @override
  String get chatSearchNotConfigured =>
      'API Key not configured, go to Services to set up';

  @override
  String get searchTestConnection => 'Test Connection';

  @override
  String get searchTesting => 'Testing...';

  @override
  String get searchTestSuccess => 'Connected successfully, API Key is valid';

  @override
  String get petCatGray => 'Gray Kitty';

  @override
  String get petCatOrange => 'Orange Kitty';

  @override
  String get petCatWhite => 'White Kitty';

  @override
  String get petTitle => 'Pet Settings';

  @override
  String get petShow => 'Show';

  @override
  String get petSkinSection => 'Sprite Skin';

  @override
  String get petModelSection => 'Pet Model (AI)';

  @override
  String get petModelHint => 'Select AI model for pet';

  @override
  String petModelLoadFailed(String error) {
    return 'Failed to load models: $error';
  }

  @override
  String get petTtsSection => 'Text-to-Speech';

  @override
  String get petTtsSystem => 'System';

  @override
  String get petTtsVolcano => 'Volcano';

  @override
  String get petTtsAppId => 'AppID';

  @override
  String get petTtsAppIdHint => 'App ID';

  @override
  String get petTtsToken => 'Token';

  @override
  String get petTtsTokenHint => 'Access Token';

  @override
  String get petTtsVoiceType => 'Voice';

  @override
  String get petTtsVoiceTypeHint => 'voice_type (cloned voice ID)';

  @override
  String get petTtsSave => 'Save Config';

  @override
  String get petTtsSaved => 'Volcano TTS config saved';

  @override
  String get petTtsReady => '✅ Config complete';

  @override
  String get petTtsIncomplete => '⚠️ Please fill all 3 required fields';

  @override
  String petTtsSpeedLabel(int value) {
    return 'Speed($value)';
  }

  @override
  String petTtsLoudnessLabel(int value) {
    return 'Volume($value)';
  }

  @override
  String get petTtsCredentialHint =>
      'Get credentials: Volcano Engine Console → TTS → Voice Clone\nRef: github.com/Radiant303/astrbot_plugin_clonetts';

  @override
  String get petBehaviorSection => 'Reply Behavior';

  @override
  String petTtsThresholdLabel(int value) {
    return 'TTS threshold($value chars)';
  }

  @override
  String petTtsThresholdHint(int value) {
    return '≤$value chars → voice, longer → text bubble';
  }

  @override
  String petBubbleDismissLabel(int value) {
    return 'Bubble timeout(${value}s)';
  }

  @override
  String get petBubbleDismissManual => 'Manual close';

  @override
  String petBubbleDismissAuto(int value) {
    return 'Auto-close after ${value}s';
  }

  @override
  String get petCommandSection => 'Custom Commands';

  @override
  String get petCommandHint =>
      'Custom commands will appear in the right-click menu';

  @override
  String get petCommandAdd => 'Add Command';

  @override
  String get petCommandAddTitle => 'Add Custom Command';

  @override
  String get petCommandEditTitle => 'Edit Command';

  @override
  String get petCommandNameLabel => 'Command Name';

  @override
  String get petCommandNameHint => 'e.g. Optimize this';

  @override
  String get petCommandPromptLabel => 'System Prompt';

  @override
  String get petCommandPromptHint =>
      'e.g. Please optimize the following code for performance and readability:';

  @override
  String get petTestSection => 'Test';

  @override
  String get petTestShort => 'Short voice';

  @override
  String get petTestLong => 'Long text';

  @override
  String get petDebugEvents => 'Events';

  @override
  String get petDebugAnimations => 'Animations';

  @override
  String get petDebugState => 'State';

  @override
  String get petBubbleThinking => 'Kitty is thinking...';

  @override
  String get petBubbleTitle => 'Kitty says';

  @override
  String get petBubbleGenerating => 'Generating reply...';

  @override
  String get petBubbleClose => 'Close';

  @override
  String get petBubbleFeedAll => 'Feed full text to kitty';

  @override
  String petBubbleFeedFollow(String label) {
    return 'Ask: $label';
  }

  @override
  String petBubbleFeedSelected(String label) {
    return 'Ask kitty: $label';
  }

  @override
  String get petNoModel =>
      'Meow~ No model bound yet, please select one in Pet Settings.';

  @override
  String petError(String error) {
    return 'Meow... error: $error';
  }

  @override
  String get petContextHide => 'Hide Pet';

  @override
  String get petTestShortText => 'Hello master!';

  @override
  String get petTestLongText =>
      'Hi master, in Flutter Widgets are immutable. Every state change creates a new Widget tree, which is why setState triggers a rebuild.';

  @override
  String get petPageTitle => 'Pet';

  @override
  String get petTabSettings => 'Settings';

  @override
  String get petTabShop => 'Shop';

  @override
  String get petTabAchievements => 'Achievements';

  @override
  String get petShopTitle => 'Items';

  @override
  String get petInventoryTitle => 'Inventory';

  @override
  String get petInventoryEmpty => 'Nothing here~';

  @override
  String get petStatusTitle => 'Status';

  @override
  String get petStatusSatiety => 'Satiety';

  @override
  String get petStatusHappiness => 'Happiness';

  @override
  String get petStatusDecayHint =>
      'Satiety -5/hr, Happiness -3/hr\nFeed to restore';

  @override
  String get petShopBuy => 'Buy';

  @override
  String petShopBought(String name) {
    return 'Bought $name!';
  }

  @override
  String get petShopNoCoins => 'Not enough coins~';

  @override
  String petShopSatiety(int value) {
    return 'Satiety+$value';
  }

  @override
  String petShopHappiness(int value) {
    return 'Happiness+$value';
  }

  @override
  String petShopEffect(String effect) {
    return 'Effect: $effect';
  }

  @override
  String get petAchievementsTitle => 'Achievements';

  @override
  String petAchievementsProgress(int unlocked, int total) {
    return '$unlocked / $total';
  }

  @override
  String get petFeedTitle => 'Feed Kitty';

  @override
  String get petFeedButton => 'Feed';

  @override
  String get petFeedButtonEmpty => 'Feed (empty bag)';

  @override
  String get petFeedEmpty => 'Bag is empty~ Buy some food in the shop!';

  @override
  String petFeedStat(int quantity, int satiety, int happiness) {
    return 'x$quantity  Satiety+$satiety Happiness+$happiness';
  }

  @override
  String get petFeedClose => 'Close';

  @override
  String petCoinReward(int amount) {
    return '+$amount Pet Coins~';
  }

  @override
  String get petFoodBanana => 'Banana';

  @override
  String get petFoodBananaDesc => 'Soft and sweet, kitty loves it';

  @override
  String get petFoodApple => 'Apple';

  @override
  String get petFoodAppleDesc => 'An apple a day keeps kitty at play';

  @override
  String get petFoodPurpleGrape => 'Purple Grape';

  @override
  String get petFoodPurpleGrapeDesc => 'Plump and sweet clusters';

  @override
  String get petFoodGreenGrape => 'Green Grape';

  @override
  String get petFoodGreenGrapeDesc => 'Refreshingly tangy appetizer';

  @override
  String get petFoodPineapple => 'Pineapple';

  @override
  String get petFoodPineappleDesc => 'Tropical flavor, juicy burst';

  @override
  String get petFoodKiwi => 'Kiwi';

  @override
  String get petFoodKiwiDesc => 'Little green ball packed with vitamin C';

  @override
  String get petFoodCherry => 'Cherry';

  @override
  String get petFoodCherryDesc => 'Tiny and cute, kitty bats it around';

  @override
  String get petFoodStrawberry => 'Strawberry';

  @override
  String get petFoodStrawberryDesc => 'Red and happy little fruit';

  @override
  String get petFoodCarrot => 'Carrot';

  @override
  String get petFoodCarrotDesc => 'Good for eyes, not that kitty cares';

  @override
  String get petFoodTomato => 'Tomato';

  @override
  String get petFoodTomatoDesc => 'Fresh and juicy tomato';

  @override
  String get petFoodEggplant => 'Eggplant';

  @override
  String get petFoodEggplantDesc => 'Purple healthy veggie';

  @override
  String get petFoodPumpkin => 'Pumpkin';

  @override
  String get petFoodPumpkinDesc => 'Big pumpkin, lasts a while';

  @override
  String get petFoodBroccoli => 'Broccoli';

  @override
  String get petFoodBroccoliDesc => 'Like a little tree, full of nutrients';

  @override
  String get petFoodGarlic => 'Garlic';

  @override
  String get petFoodGarlicDesc => 'Kitty sneezes at the smell';

  @override
  String get petFoodPepper => 'Pepper';

  @override
  String get petFoodPepperDesc => 'Whew~ spicy jump!';

  @override
  String get petFoodMushroom => 'Mushroom';

  @override
  String get petFoodMushroomDesc => 'Savory fungi, kitty surprisingly likes it';

  @override
  String get petFoodHam => 'Ham';

  @override
  String get petFoodHamDesc => 'Rich meaty aroma, kitty drools';

  @override
  String get petFoodChicken => 'Chicken Leg';

  @override
  String get petFoodChickenDesc => 'Crispy outside, juicy inside';

  @override
  String get petFoodFish => 'Fish';

  @override
  String get petFoodFishDesc => 'Kitty\'s absolute favorite!';

  @override
  String get petFoodLobster => 'Lobster';

  @override
  String get petFoodLobsterDesc => 'Premium seafood feast, kitty goes wild';

  @override
  String get petAchieveFirstCoin => 'First Coin';

  @override
  String get petAchieveFirstCoinDesc => 'Earned your first pet coin';

  @override
  String get petAchieveRich100 => 'Savings Started';

  @override
  String get petAchieveRich100Desc => 'Earned 100 pet coins total';

  @override
  String get petAchieveRich500 => 'Little Rich';

  @override
  String get petAchieveRich500Desc => 'Earned 500 pet coins total';

  @override
  String get petAchieveRich2000 => 'Pet Tycoon';

  @override
  String get petAchieveRich2000Desc => 'Earned 2000 pet coins total';

  @override
  String get petAchieveFirstFeed => 'First Feeding';

  @override
  String get petAchieveFirstFeedDesc => 'Fed kitty for the first time';

  @override
  String get petAchieveFeed10 => 'Dutiful Owner';

  @override
  String get petAchieveFeed10Desc => 'Fed kitty 10 times';

  @override
  String get petAchieveFeed50 => 'Cat Servant';

  @override
  String get petAchieveFeed50Desc => 'Fed kitty 50 times';

  @override
  String get petAchieveFullBelly => 'Stuffed';

  @override
  String get petAchieveFullBellyDesc => 'Satiety reached 100';

  @override
  String get petAchieveHappyMax => 'Happy Kitty';

  @override
  String get petAchieveHappyMaxDesc => 'Happiness reached 100';

  @override
  String get petAchieveShopper => 'Shopaholic';

  @override
  String get petAchieveShopperDesc => 'Made 20 purchases in the shop';

  @override
  String get petAchieveChat1m => 'Chatterbox';

  @override
  String get petAchieveChat1mDesc => 'Consumed 1 million tokens';

  @override
  String get petAchieveChat50m => 'Power User';

  @override
  String get petAchieveChat50mDesc => 'Consumed 50 million tokens';

  @override
  String get petAchieveChat100m => 'AI Addict';

  @override
  String get petAchieveChat100mDesc => 'Consumed 100 million tokens';

  @override
  String get servicesServerTab => 'Server';

  @override
  String get serverTitle => 'Server';

  @override
  String get serverApiServiceTitle => 'External API Service';

  @override
  String get serverApiServiceDesc =>
      'Expose your locally configured models, skills, MCP, memory and search via standard protocols. Local-only by default; an access token is required. Review the security settings before opening to the LAN.';

  @override
  String get apiServerTitle => 'External API Service';

  @override
  String apiServerRunningPort(Object port) {
    return 'Running · port $port';
  }

  @override
  String get apiServerStopped => 'Stopped';

  @override
  String get apiServerIntro =>
      'Expose aggregated capabilities (model/skill/MCP/memory/search) via OpenAI / Anthropic compatible APIs. Local-only by default (127.0.0.1); an access token is required.';

  @override
  String get apiServerPort => 'Port';

  @override
  String get apiServerToken => 'Access Token (Bearer Token)';

  @override
  String get apiServerTokenRandom => 'Generate random';

  @override
  String get apiServerTokenShow => 'Show token';

  @override
  String get apiServerTokenHide => 'Hide token';

  @override
  String get apiServerTestInBrowser => 'Test in browser';

  @override
  String apiServerTestInBrowserFailed(Object url) {
    return 'Failed to open browser: $url';
  }

  @override
  String get apiServerSaveRestart => 'Save port/token and restart service';

  @override
  String get apiServerProtocolTitle => 'Protocol Endpoints';

  @override
  String get apiServerProtocolHint =>
      'Enable any of the three endpoints independently. The token works with both Bearer and x-api-key headers.';

  @override
  String get apiServerOpenAiAggTitle => 'OpenAI Aggregate';

  @override
  String get apiServerOpenAiAggDesc =>
      'Runs RemindAI\'s own Agent (skill/MCP/memory/search) and outputs in OpenAI-compatible format. Good for generic OpenAI clients.';

  @override
  String get apiServerClaudeAggTitle => 'Claude Aggregate';

  @override
  String get apiServerClaudeAggDesc =>
      'Also runs RemindAI\'s aggregate Agent but outputs in the Anthropic protocol, letting Claude-only clients use the full aggregated capability. Tools run inside the server.';

  @override
  String get apiServerClaudeProxyTitle => 'Claude Pure Proxy';

  @override
  String get apiServerClaudeProxyDesc =>
      'Pure protocol conversion: passes the tools and tasks carried by the client (e.g. CherryStudio Agent) to the selected model; the client executes the tools itself (this service\'s skills/MCP/memory are not mounted). Ideal for driving CherryStudio\'s Agent with Kimi/GPT/Gemini.';

  @override
  String get apiServerModelsTitle => 'Available Models';

  @override
  String get apiServerModelsHint =>
      'Check the model cards to expose; none selected = expose all model cards, client can choose any';

  @override
  String get apiServerModelsEmpty => 'No model cards configured yet';

  @override
  String get apiServerModelsAllOpen =>
      'Unrestricted: all model cards are currently exposed';

  @override
  String get apiServerMemoryTitle => 'Memory';

  @override
  String get apiServerMemoryHint =>
      'Isolated = physically separated from the main app\'s memory; Shared = reads/writes the main app\'s memory (use with care)';

  @override
  String get apiServerMemoryNone => 'None';

  @override
  String get apiServerMemoryIsolated => 'Isolated';

  @override
  String get apiServerMemoryShared => 'Shared';

  @override
  String get apiServerSearchTitle => 'Web Search';

  @override
  String get apiServerSearchHint =>
      'Configure the engine\'s API key in Search settings first';

  @override
  String get apiServerSearchOff => 'Off';

  @override
  String get apiServerSkillsTitle => 'Skills';

  @override
  String get apiServerSkillsHint =>
      'Selected skills expose their tools and prompts externally';

  @override
  String get apiServerSkillsEmpty => 'No skills available';

  @override
  String get apiServerMcpTitle => 'MCP Services';

  @override
  String get apiServerMcpHint =>
      'Only connected MCP servers take effect externally (grey = not connected)';

  @override
  String get apiServerMcpEmpty => 'No MCP services';

  @override
  String get apiServerBindAllTitle => 'Allow LAN access (0.0.0.0)';

  @override
  String get apiServerBindAllDesc =>
      'When enabled, other devices on the same network can call this service, effectively exposing your models/memory/tools to the LAN. Make sure the token is strong.';

  @override
  String get apiServerBindAllConfirmTitle => 'Expose to the LAN?';

  @override
  String get apiServerBindAllConfirmBody =>
      'Once enabled, any device on the same network can access this service with the token and call your configured models, memory and tools. Only enable on trusted networks.';

  @override
  String get apiServerBindAllConfirmCancel => 'Cancel';

  @override
  String get apiServerBindAllConfirmOk => 'I understand the risk';

  @override
  String get apiServerIpWhitelistTitle => 'IP Allowlist';

  @override
  String get apiServerIpWhitelistHint =>
      'Empty = unrestricted (any device on the network can access); when set, only listed addresses are allowed (localhost always allowed)';

  @override
  String get apiServerIpWhitelistEmpty =>
      'No IPs configured; currently open to the entire LAN';

  @override
  String get apiServerIpWhitelistInputHint => '192.168.1.5 or 192.168.1.0/24';

  @override
  String get apiServerIpWhitelistAdd => 'Add';

  @override
  String get apiServerIpWhitelistInvalid =>
      'Invalid format. Enter an IPv4 or CIDR (e.g. 192.168.1.0/24)';

  @override
  String apiServerLoadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String trayServerOn(Object port) {
    return 'API Server · Running (port $port)';
  }

  @override
  String get trayServerOff => 'API Server · Stopped';

  @override
  String get trayServerNeedConfig => 'API Server (configure token first)';

  @override
  String trayOnlineOn(Object port) {
    return 'Online Service · Running (port $port)';
  }

  @override
  String get trayOnlineOff => 'Online Service · Stopped';

  @override
  String get servicesOnlineTab => 'Online';

  @override
  String get olsTitle => 'Online Service';

  @override
  String get olsIntro =>
      'Share AI chat service across LAN. Whitelisted users can access via browser.';

  @override
  String olsRunningPort(Object port) {
    return 'Running :$port';
  }

  @override
  String get olsStopped => 'Stopped';

  @override
  String get olsControl => 'Service Control';

  @override
  String get olsPort => 'Port';

  @override
  String get olsMaxConn => 'Max Connections';

  @override
  String get olsPause => 'Pause';

  @override
  String get olsResume => 'Resume';

  @override
  String get olsPauseHint =>
      'Stop accepting new connections; online users unaffected';

  @override
  String get olsOnlineUsers => 'Online Users';

  @override
  String get olsNoUsers => 'No users online';

  @override
  String get olsBusy => 'Busy';

  @override
  String get olsKick => 'Kick';

  @override
  String get olsWhitelist => 'Whitelist';

  @override
  String get olsWhitelistHint => '(empty = allow all LAN IPs)';

  @override
  String get olsWhitelistAdd => 'Add';

  @override
  String get olsWhitelistEdit => 'Edit whitelist';

  @override
  String get olsWhitelistAddTitle => 'Add to Whitelist';

  @override
  String get olsWhitelistEditTitle => 'Edit Whitelist';

  @override
  String get olsWhitelistIp => 'IP Address';

  @override
  String get olsWhitelistIpHint => '192.168.1.5 or 192.168.1.0/24';

  @override
  String get olsWhitelistNickname => 'Nickname';

  @override
  String get olsWhitelistModels => 'Models (none = all available)';

  @override
  String get olsWhitelistMcp => 'MCP Servers';

  @override
  String get olsWhitelistSkill => 'Skills';

  @override
  String get olsWhitelistSearch => 'Web Search';

  @override
  String get olsWhitelistSearchOff => 'Off';

  @override
  String get olsWhitelistSearchTavily => 'Tavily';

  @override
  String get olsWhitelistSearchBrave => 'Brave';

  @override
  String get olsWhitelistSearchBaidu => 'Baidu Qianfan';

  @override
  String get olsAllModels => 'All models';

  @override
  String olsNModels(Object n) {
    return '$n models';
  }

  @override
  String get olsRemove => 'Remove';

  @override
  String get olsCancel => 'Cancel';

  @override
  String get olsSave => 'Save';

  @override
  String get olsOpenBrowser => 'Open in Browser';

  @override
  String olsUserSessionInfo(String ip, Object minutes, Object msgCount) {
    return '$ip · $minutes min · $msgCount messages';
  }

  @override
  String get olsWhitelistEmpty => 'No whitelist set; all LAN IPs can connect';

  @override
  String get olsNicknameHint => 'Username';

  @override
  String get chatLoopTitle => 'Loop Mode';

  @override
  String get chatLoopDesc =>
      'When enabled, AI will autonomously iterate: plan → execute → verify → fix, until done or max iterations reached.';

  @override
  String get chatLoopHint => 'Enable Loop autonomous mode';

  @override
  String get chatLoopEnabled => 'Loop mode enabled';

  @override
  String get chatLoopRunning => 'Loop running...';

  @override
  String get chatLoopMaxIter => 'Max iterations';

  @override
  String get chatLoopAutoApproveHint =>
      'In Loop mode, tool operations execute automatically without per-action confirmation.';
}

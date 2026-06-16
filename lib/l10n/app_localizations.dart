import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'RemindAI'**
  String get appTitle;

  /// No description provided for @navChat.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get navChat;

  /// No description provided for @navModels.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get navModels;

  /// No description provided for @navSkills.
  ///
  /// In zh, this message translates to:
  /// **'技能'**
  String get navSkills;

  /// No description provided for @navTools.
  ///
  /// In zh, this message translates to:
  /// **'工具'**
  String get navTools;

  /// No description provided for @navMultiAgent.
  ///
  /// In zh, this message translates to:
  /// **'协作'**
  String get navMultiAgent;

  /// No description provided for @navExperts.
  ///
  /// In zh, this message translates to:
  /// **'专家'**
  String get navExperts;

  /// No description provided for @navMcp.
  ///
  /// In zh, this message translates to:
  /// **'服务'**
  String get navMcp;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @navHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史'**
  String get navHistory;

  /// No description provided for @navMemory.
  ///
  /// In zh, this message translates to:
  /// **'记忆'**
  String get navMemory;

  /// No description provided for @navLogs.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get navLogs;

  /// No description provided for @navPet.
  ///
  /// In zh, this message translates to:
  /// **'宠物'**
  String get navPet;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsTheme;

  /// No description provided for @settingsNotifyOnBlur.
  ///
  /// In zh, this message translates to:
  /// **'失焦时系统通知'**
  String get settingsNotifyOnBlur;

  /// No description provided for @settingsNotifyOnBlurDesc.
  ///
  /// In zh, this message translates to:
  /// **'窗口不在前台时，对话完成后弹出系统通知'**
  String get settingsNotifyOnBlurDesc;

  /// No description provided for @settingsStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储设置'**
  String get settingsStorage;

  /// No description provided for @settingsDatabasePath.
  ///
  /// In zh, this message translates to:
  /// **'SQLite 数据库路径'**
  String get settingsDatabasePath;

  /// No description provided for @settingsHistoryPath.
  ///
  /// In zh, this message translates to:
  /// **'对话历史记录路径'**
  String get settingsHistoryPath;

  /// No description provided for @settingsSkillsPath.
  ///
  /// In zh, this message translates to:
  /// **'技能 (Skills) 存放目录'**
  String get settingsSkillsPath;

  /// No description provided for @settingsLogsPath.
  ///
  /// In zh, this message translates to:
  /// **'日志存放目录'**
  String get settingsLogsPath;

  /// No description provided for @settingsToolPaths.
  ///
  /// In zh, this message translates to:
  /// **'工具路径设置'**
  String get settingsToolPaths;

  /// No description provided for @settingsPandocPath.
  ///
  /// In zh, this message translates to:
  /// **'Pandoc 可执行文件路径'**
  String get settingsPandocPath;

  /// No description provided for @settingsPandocNotDetected.
  ///
  /// In zh, this message translates to:
  /// **'（未检测到）'**
  String get settingsPandocNotDetected;

  /// No description provided for @settingsQdrant.
  ///
  /// In zh, this message translates to:
  /// **'向量数据库 (Qdrant)'**
  String get settingsQdrant;

  /// No description provided for @settingsEmbedding.
  ///
  /// In zh, this message translates to:
  /// **'嵌入式模型'**
  String get settingsEmbedding;

  /// No description provided for @settingsAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsFont.
  ///
  /// In zh, this message translates to:
  /// **'字体设置'**
  String get settingsFont;

  /// No description provided for @settingsUiFont.
  ///
  /// In zh, this message translates to:
  /// **'界面字体'**
  String get settingsUiFont;

  /// No description provided for @settingsUiFontDesc.
  ///
  /// In zh, this message translates to:
  /// **'控制导航、设置等非对话区域的字体'**
  String get settingsUiFontDesc;

  /// No description provided for @settingsUiFontSize.
  ///
  /// In zh, this message translates to:
  /// **'界面字号'**
  String get settingsUiFontSize;

  /// No description provided for @settingsChatFont.
  ///
  /// In zh, this message translates to:
  /// **'交互字体'**
  String get settingsChatFont;

  /// No description provided for @settingsChatFontDesc.
  ///
  /// In zh, this message translates to:
  /// **'控制对话和多Agent协作区域的字体'**
  String get settingsChatFontDesc;

  /// No description provided for @settingsChatFontSize.
  ///
  /// In zh, this message translates to:
  /// **'交互字号'**
  String get settingsChatFontSize;

  /// No description provided for @settingsFontDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get settingsFontDefault;

  /// No description provided for @settingsFontPreview.
  ///
  /// In zh, this message translates to:
  /// **'字体预览 AaBbCc 你好世界 123'**
  String get settingsFontPreview;

  /// No description provided for @settingsCustomFont.
  ///
  /// In zh, this message translates to:
  /// **'自定义字体'**
  String get settingsCustomFont;

  /// No description provided for @settingsCustomFontDesc.
  ///
  /// In zh, this message translates to:
  /// **'导入本地 .ttf/.otf 字体文件，存放于 .RemindAI/fonts/ 目录'**
  String get settingsCustomFontDesc;

  /// No description provided for @settingsCustomFontImport.
  ///
  /// In zh, this message translates to:
  /// **'导入字体'**
  String get settingsCustomFontImport;

  /// No description provided for @settingsCustomFontPick.
  ///
  /// In zh, this message translates to:
  /// **'选择字体文件 (.ttf / .otf)'**
  String get settingsCustomFontPick;

  /// No description provided for @settingsCustomFontImported.
  ///
  /// In zh, this message translates to:
  /// **'字体导入成功'**
  String get settingsCustomFontImported;

  /// No description provided for @settingsChange.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get settingsChange;

  /// No description provided for @settingsMigrating.
  ///
  /// In zh, this message translates to:
  /// **'正在迁移数据...'**
  String get settingsMigrating;

  /// No description provided for @settingsMigratingHint.
  ///
  /// In zh, this message translates to:
  /// **'请勿关闭应用'**
  String get settingsMigratingHint;

  /// No description provided for @settingsPickDbTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择数据库保存位置'**
  String get settingsPickDbTitle;

  /// No description provided for @settingsPickHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择历史记录保存目录'**
  String get settingsPickHistoryTitle;

  /// No description provided for @settingsPickSkillsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择技能存放目录'**
  String get settingsPickSkillsTitle;

  /// No description provided for @settingsPickLogsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择日志存放目录'**
  String get settingsPickLogsTitle;

  /// No description provided for @settingsPickPandocTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择 Pandoc 可执行文件'**
  String get settingsPickPandocTitle;

  /// No description provided for @aboutDescription.
  ///
  /// In zh, this message translates to:
  /// **'您的个人桌面AI工作台。运行工具、安装技能、连接MCP服务器、构建持久内存——所有模型，尽在一个界面。'**
  String get aboutDescription;

  /// No description provided for @aboutGithub.
  ///
  /// In zh, this message translates to:
  /// **'GitHub'**
  String get aboutGithub;

  /// No description provided for @aboutLicense.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get aboutLicense;

  /// No description provided for @aboutPoweredBy.
  ///
  /// In zh, this message translates to:
  /// **'Powered by'**
  String get aboutPoweredBy;

  /// No description provided for @trayShow.
  ///
  /// In zh, this message translates to:
  /// **'显示窗口'**
  String get trayShow;

  /// No description provided for @trayExit.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get trayExit;

  /// No description provided for @dialogCloseTitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口'**
  String get dialogCloseTitle;

  /// No description provided for @dialogCloseContent.
  ///
  /// In zh, this message translates to:
  /// **'是否最小化到系统托盘？'**
  String get dialogCloseContent;

  /// No description provided for @dialogCloseExit.
  ///
  /// In zh, this message translates to:
  /// **'退出程序'**
  String get dialogCloseExit;

  /// No description provided for @dialogCloseMinimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化到托盘'**
  String get dialogCloseMinimize;

  /// No description provided for @chatSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'请先在「模型」页面添加并选择一个模型卡片'**
  String get chatSelectModel;

  /// No description provided for @chatComplete.
  ///
  /// In zh, this message translates to:
  /// **'RemindAI 对话完成'**
  String get chatComplete;

  /// No description provided for @chatCompleteBody.
  ///
  /// In zh, this message translates to:
  /// **'助手已完成回复'**
  String get chatCompleteBody;

  /// No description provided for @chatNoModel.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get chatNoModel;

  /// No description provided for @chatLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get chatLoading;

  /// No description provided for @chatLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get chatLoadFailed;

  /// No description provided for @chatLoadFailedWithError.
  ///
  /// In zh, this message translates to:
  /// **'加载失败: {error}'**
  String chatLoadFailedWithError(String error);

  /// No description provided for @chatExport.
  ///
  /// In zh, this message translates to:
  /// **'导出对话'**
  String get chatExport;

  /// No description provided for @chatClear.
  ///
  /// In zh, this message translates to:
  /// **'清空对话'**
  String get chatClear;

  /// No description provided for @chatNew.
  ///
  /// In zh, this message translates to:
  /// **'新建对话'**
  String get chatNew;

  /// No description provided for @chatNewWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'新建工作目录'**
  String get chatNewWorkspace;

  /// No description provided for @chatNeedConfig.
  ///
  /// In zh, this message translates to:
  /// **'需要配置 API 地址、密钥和模型名称'**
  String get chatNeedConfig;

  /// No description provided for @chatStartConversation.
  ///
  /// In zh, this message translates to:
  /// **'开始对话'**
  String get chatStartConversation;

  /// No description provided for @chatSupportsTools.
  ///
  /// In zh, this message translates to:
  /// **'支持文件操作、Shell 命令、记忆存储'**
  String get chatSupportsTools;

  /// No description provided for @chatCreateWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'创建工作目录'**
  String get chatCreateWorkspace;

  /// No description provided for @chatAttachments.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get chatAttachments;

  /// No description provided for @chatInterruptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入新消息可中断当前响应...'**
  String get chatInterruptHint;

  /// No description provided for @chatInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入消息...'**
  String get chatInputHint;

  /// No description provided for @chatStopGenerate.
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get chatStopGenerate;

  /// No description provided for @chatInterruptAndSend.
  ///
  /// In zh, this message translates to:
  /// **'中断并发送'**
  String get chatInterruptAndSend;

  /// No description provided for @chatSkillManage.
  ///
  /// In zh, this message translates to:
  /// **'技能管理'**
  String get chatSkillManage;

  /// No description provided for @chatNoSkills.
  ///
  /// In zh, this message translates to:
  /// **'暂无已安装的技能'**
  String get chatNoSkills;

  /// No description provided for @chatViewSkillMd.
  ///
  /// In zh, this message translates to:
  /// **'查看 SKILL.md'**
  String get chatViewSkillMd;

  /// No description provided for @chatUninstall.
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get chatUninstall;

  /// No description provided for @chatClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get chatClose;

  /// No description provided for @chatUninstallSkill.
  ///
  /// In zh, this message translates to:
  /// **'卸载技能'**
  String get chatUninstallSkill;

  /// No description provided for @chatUninstallSkillConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要卸载「{name}」吗？此操作不可撤销。'**
  String chatUninstallSkillConfirm(String name);

  /// No description provided for @chatUninstalled.
  ///
  /// In zh, this message translates to:
  /// **'已卸载：{name}'**
  String chatUninstalled(String name);

  /// No description provided for @chatDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'断开'**
  String get chatDisconnect;

  /// No description provided for @chatConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get chatConnect;

  /// No description provided for @chatConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get chatConnected;

  /// No description provided for @chatConnecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中...'**
  String get chatConnecting;

  /// No description provided for @chatConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get chatConnectFailed;

  /// No description provided for @chatNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get chatNotConnected;

  /// No description provided for @chatUninstallMcp.
  ///
  /// In zh, this message translates to:
  /// **'卸载 MCP 服务'**
  String get chatUninstallMcp;

  /// No description provided for @chatUninstallMcpConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要卸载「{name}」吗？'**
  String chatUninstallMcpConfirm(String name);

  /// No description provided for @chatWorkingDir.
  ///
  /// In zh, this message translates to:
  /// **'工作目录'**
  String get chatWorkingDir;

  /// No description provided for @chatSelectWorkingDir.
  ///
  /// In zh, this message translates to:
  /// **'选择工作目录'**
  String get chatSelectWorkingDir;

  /// No description provided for @chatMemory.
  ///
  /// In zh, this message translates to:
  /// **'记忆'**
  String get chatMemory;

  /// No description provided for @chatMemoryEnabled.
  ///
  /// In zh, this message translates to:
  /// **'记忆已启用，点击调整'**
  String get chatMemoryEnabled;

  /// No description provided for @chatEmbeddingNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'嵌入式模型未配置'**
  String get chatEmbeddingNotConfigured;

  /// No description provided for @chatEmbeddingNotConfiguredHint.
  ///
  /// In zh, this message translates to:
  /// **'请先在「设置 → 嵌入式模型」中配置嵌入模型'**
  String get chatEmbeddingNotConfiguredHint;

  /// No description provided for @chatMemorySettings.
  ///
  /// In zh, this message translates to:
  /// **'记忆设置'**
  String get chatMemorySettings;

  /// No description provided for @chatEnableRecall.
  ///
  /// In zh, this message translates to:
  /// **'启用记忆召回'**
  String get chatEnableRecall;

  /// No description provided for @chatEnableRecallDesc.
  ///
  /// In zh, this message translates to:
  /// **'发消息前自动检索相关记忆'**
  String get chatEnableRecallDesc;

  /// No description provided for @chatEnableStore.
  ///
  /// In zh, this message translates to:
  /// **'启用记忆存储'**
  String get chatEnableStore;

  /// No description provided for @chatEnableStoreDesc.
  ///
  /// In zh, this message translates to:
  /// **'对话结束后自动提取并存储记忆'**
  String get chatEnableStoreDesc;

  /// No description provided for @chatEnableQdrant.
  ///
  /// In zh, this message translates to:
  /// **'启用 Qdrant 向量检索'**
  String get chatEnableQdrant;

  /// No description provided for @chatEnableQdrantDesc.
  ///
  /// In zh, this message translates to:
  /// **'使用向量数据库进行语义召回'**
  String get chatEnableQdrantDesc;

  /// No description provided for @chatEnableSqlite.
  ///
  /// In zh, this message translates to:
  /// **'存入 SQLite 作为长期记忆'**
  String get chatEnableSqlite;

  /// No description provided for @chatEnableSqliteDesc.
  ///
  /// In zh, this message translates to:
  /// **'将记忆持久化到本地数据库'**
  String get chatEnableSqliteDesc;

  /// No description provided for @chatEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'环境'**
  String get chatEnvironment;

  /// No description provided for @chatEnvConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已指定运行环境，点击调整'**
  String get chatEnvConfigured;

  /// No description provided for @chatEnvHint.
  ///
  /// In zh, this message translates to:
  /// **'指定 Python / npm 解释器'**
  String get chatEnvHint;

  /// No description provided for @chatEnvTitle.
  ///
  /// In zh, this message translates to:
  /// **'运行环境'**
  String get chatEnvTitle;

  /// No description provided for @chatEnvSessionScope.
  ///
  /// In zh, this message translates to:
  /// **'本次对话生效'**
  String get chatEnvSessionScope;

  /// No description provided for @chatEnvDesc.
  ///
  /// In zh, this message translates to:
  /// **'指定后，项目中的 python/pip、npm/npx/node 命令会优先使用此处选择的版本'**
  String get chatEnvDesc;

  /// No description provided for @chatEnvPythonHint.
  ///
  /// In zh, this message translates to:
  /// **'例如 python.exe / venv/Scripts/python.exe'**
  String get chatEnvPythonHint;

  /// No description provided for @chatEnvSelectNpm.
  ///
  /// In zh, this message translates to:
  /// **'选择 npm / node 可执行文件'**
  String get chatEnvSelectNpm;

  /// No description provided for @chatEnvSelectFile.
  ///
  /// In zh, this message translates to:
  /// **'选择可执行文件'**
  String get chatEnvSelectFile;

  /// No description provided for @chatEnvClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get chatEnvClear;

  /// No description provided for @chatEnvSelect.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get chatEnvSelect;

  /// No description provided for @chatPermAlways.
  ///
  /// In zh, this message translates to:
  /// **'始终'**
  String get chatPermAlways;

  /// No description provided for @chatPermAllow.
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get chatPermAllow;

  /// No description provided for @chatPermDeny.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get chatPermDeny;

  /// No description provided for @toolCallWrite.
  ///
  /// In zh, this message translates to:
  /// **'写入文件'**
  String get toolCallWrite;

  /// No description provided for @toolCallDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除文件'**
  String get toolCallDelete;

  /// No description provided for @toolCallExec.
  ///
  /// In zh, this message translates to:
  /// **'执行命令'**
  String get toolCallExec;

  /// No description provided for @msgEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get msgEdit;

  /// No description provided for @msgRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get msgRegenerate;

  /// No description provided for @msgCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get msgCopy;

  /// No description provided for @msgCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get msgCopied;

  /// No description provided for @msgExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get msgExport;

  /// No description provided for @msgDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get msgDelete;

  /// No description provided for @msgThinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中...'**
  String get msgThinking;

  /// No description provided for @toolCardArgs.
  ///
  /// In zh, this message translates to:
  /// **'参数'**
  String get toolCardArgs;

  /// No description provided for @toolCardResult.
  ///
  /// In zh, this message translates to:
  /// **'结果'**
  String get toolCardResult;

  /// No description provided for @toolCardExecuting.
  ///
  /// In zh, this message translates to:
  /// **'执行中'**
  String get toolCardExecuting;

  /// No description provided for @toolCardDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get toolCardDone;

  /// No description provided for @toolCardError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get toolCardError;

  /// No description provided for @historyTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史对话'**
  String get historyTitle;

  /// No description provided for @historyClearAll.
  ///
  /// In zh, this message translates to:
  /// **'清空所有对话'**
  String get historyClearAll;

  /// No description provided for @historyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史对话'**
  String get historyEmpty;

  /// No description provided for @historyEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'开始一段新对话后，将会在这里显示'**
  String get historyEmptyHint;

  /// No description provided for @historyDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除对话'**
  String get historyDeleteTitle;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除「{title}」吗？此操作不可撤销。'**
  String historyDeleteConfirm(String title);

  /// No description provided for @historyClearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空所有对话'**
  String get historyClearAllTitle;

  /// No description provided for @historyClearAllConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除所有历史对话吗？此操作不可撤销。'**
  String get historyClearAllConfirm;

  /// No description provided for @historyClearBtn.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get historyClearBtn;

  /// No description provided for @historyUntitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名对话'**
  String get historyUntitled;

  /// No description provided for @historyJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get historyJustNow;

  /// No description provided for @expertsTitle.
  ///
  /// In zh, this message translates to:
  /// **'领域专家'**
  String get expertsTitle;

  /// No description provided for @expertsCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建专家'**
  String get expertsCreate;

  /// No description provided for @expertsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有专家'**
  String get expertsEmpty;

  /// No description provided for @expertsCreateFirst.
  ///
  /// In zh, this message translates to:
  /// **'创建第一个专家'**
  String get expertsCreateFirst;

  /// No description provided for @expertsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除专家'**
  String get expertsDeleteTitle;

  /// No description provided for @expertsDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？此操作不可撤销。'**
  String expertsDeleteConfirm(String name);

  /// No description provided for @expertsNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如：PPT 设计师'**
  String get expertsNameHint;

  /// No description provided for @expertsDescHint.
  ///
  /// In zh, this message translates to:
  /// **'一句话说明这个专家的能力'**
  String get expertsDescHint;

  /// No description provided for @expertsPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'定义专家的身份、能力和工作方式...'**
  String get expertsPromptHint;

  /// No description provided for @expertsBindSkills.
  ///
  /// In zh, this message translates to:
  /// **'绑定技能'**
  String get expertsBindSkills;

  /// No description provided for @expertsNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入专家名称'**
  String get expertsNameRequired;

  /// No description provided for @expertsPromptRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入系统提示词'**
  String get expertsPromptRequired;

  /// No description provided for @expertsSelectIcon.
  ///
  /// In zh, this message translates to:
  /// **'选择图标'**
  String get expertsSelectIcon;

  /// No description provided for @expertsCreate2.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get expertsCreate2;

  /// No description provided for @modelsTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型管理'**
  String get modelsTitle;

  /// No description provided for @modelsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无模型卡片'**
  String get modelsEmpty;

  /// No description provided for @modelsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮添加第一个模型'**
  String get modelsEmptyHint;

  /// No description provided for @modelsAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get modelsAdd;

  /// No description provided for @modelsDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get modelsDefault;

  /// No description provided for @modelsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get modelsDeleteTitle;

  /// No description provided for @modelsDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除模型 \"{name}\" 吗？'**
  String modelsDeleteConfirm(String name);

  /// No description provided for @modelsEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑模型'**
  String get modelsEditTitle;

  /// No description provided for @modelsNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: GPT-4o, Claude Sonnet'**
  String get modelsNameHint;

  /// No description provided for @modelsDetectHint.
  ///
  /// In zh, this message translates to:
  /// **'点击右侧按钮自动检测'**
  String get modelsDetectHint;

  /// No description provided for @modelsDetect.
  ///
  /// In zh, this message translates to:
  /// **'检测可用模型'**
  String get modelsDetect;

  /// No description provided for @modelsReorderHint.
  ///
  /// In zh, this message translates to:
  /// **'点击卡片设为默认，长按拖动可调整顺序'**
  String get modelsReorderHint;

  /// No description provided for @modelsSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词搜索模型...'**
  String get modelsSearchHint;

  /// No description provided for @skillsTitle.
  ///
  /// In zh, this message translates to:
  /// **'技能管理'**
  String get skillsTitle;

  /// No description provided for @skillsImport.
  ///
  /// In zh, this message translates to:
  /// **'导入技能'**
  String get skillsImport;

  /// No description provided for @skillsImportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'导入成功: {name} ({count} 个工具)'**
  String skillsImportSuccess(String name, int count);

  /// No description provided for @skillsImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败：{detail}'**
  String skillsImportFailed(String detail);

  /// No description provided for @skillsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无已安装技能'**
  String get skillsEmpty;

  /// No description provided for @skillsDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除技能'**
  String get skillsDeleteTitle;

  /// No description provided for @skillsDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除技能「{name}」吗？此操作不可撤销。'**
  String skillsDeleteConfirm(String name);

  /// No description provided for @mcpTitle.
  ///
  /// In zh, this message translates to:
  /// **'MCP 服务'**
  String get mcpTitle;

  /// No description provided for @mcpAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加 MCP'**
  String get mcpAdd;

  /// No description provided for @mcpEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无 MCP 服务'**
  String get mcpEmpty;

  /// No description provided for @mcpConnectSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，发现 {count} 个工具'**
  String mcpConnectSuccess(int count);

  /// No description provided for @mcpDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 MCP 服务'**
  String get mcpDeleteTitle;

  /// No description provided for @mcpDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除「{name}」吗？'**
  String mcpDeleteConfirm(String name);

  /// No description provided for @mcpEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 MCP 服务'**
  String get mcpEditTitle;

  /// No description provided for @mcpAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 MCP 服务'**
  String get mcpAddTitle;

  /// No description provided for @mcpNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如: filesystem-server'**
  String get mcpNameHint;

  /// No description provided for @mcpCommandHint.
  ///
  /// In zh, this message translates to:
  /// **'如: npx, python, node'**
  String get mcpCommandHint;

  /// No description provided for @mcpArgsHint.
  ///
  /// In zh, this message translates to:
  /// **'如: -y @modelcontextprotocol/server-filesystem /tmp'**
  String get mcpArgsHint;

  /// No description provided for @mcpCwdHint.
  ///
  /// In zh, this message translates to:
  /// **'如: C:\\Projects\\my-server'**
  String get mcpCwdHint;

  /// No description provided for @mcpEnvHint.
  ///
  /// In zh, this message translates to:
  /// **'如: API_KEY=xxx'**
  String get mcpEnvHint;

  /// No description provided for @mcpHeaderHint.
  ///
  /// In zh, this message translates to:
  /// **'如: Authorization: Bearer xxx'**
  String get mcpHeaderHint;

  /// No description provided for @mcpAdd2.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get mcpAdd2;

  /// No description provided for @memoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'记忆管理'**
  String get memoryTitle;

  /// No description provided for @memoryRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get memoryRefresh;

  /// No description provided for @memoryCount.
  ///
  /// In zh, this message translates to:
  /// **'记忆条数'**
  String get memoryCount;

  /// No description provided for @memoryClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空记忆'**
  String get memoryClearTitle;

  /// No description provided for @memoryClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除当前工作目录的全部 {count} 条记忆吗？此操作不可恢复。'**
  String memoryClearConfirm(int count);

  /// No description provided for @logsTitle.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get logsTitle;

  /// No description provided for @logsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get logsRefresh;

  /// No description provided for @logsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get logsEmpty;

  /// No description provided for @logsContentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'日志为空'**
  String get logsContentEmpty;

  /// No description provided for @logsClearAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空所有日志'**
  String get logsClearAllTitle;

  /// No description provided for @logsClearAllConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将删除 {count} 个日志文件 ({size})，此操作不可撤销。'**
  String logsClearAllConfirm(int count, String size);

  /// No description provided for @logsClearedCount.
  ///
  /// In zh, this message translates to:
  /// **'已清空 {count} 个日志文件'**
  String logsClearedCount(int count);

  /// No description provided for @toolsTitle.
  ///
  /// In zh, this message translates to:
  /// **'工具箱'**
  String get toolsTitle;

  /// No description provided for @toolsBack.
  ///
  /// In zh, this message translates to:
  /// **'返回工具列表'**
  String get toolsBack;

  /// No description provided for @toolsSettings.
  ///
  /// In zh, this message translates to:
  /// **'工具设置'**
  String get toolsSettings;

  /// No description provided for @toolsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用工具'**
  String get toolsEmpty;

  /// No description provided for @toolsSettingsOf.
  ///
  /// In zh, this message translates to:
  /// **'{name} 设置'**
  String toolsSettingsOf(String name);

  /// No description provided for @toolShortcutsName.
  ///
  /// In zh, this message translates to:
  /// **'截图'**
  String get toolShortcutsName;

  /// No description provided for @toolShortcutsDesc.
  ///
  /// In zh, this message translates to:
  /// **'查看和自定义应用快捷键'**
  String get toolShortcutsDesc;

  /// No description provided for @toolShortcutsCategory.
  ///
  /// In zh, this message translates to:
  /// **'快捷键'**
  String get toolShortcutsCategory;

  /// No description provided for @shortcutReset.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get shortcutReset;

  /// No description provided for @shortcutResetDone.
  ///
  /// In zh, this message translates to:
  /// **'快捷键已恢复默认'**
  String get shortcutResetDone;

  /// No description provided for @shortcutHint.
  ///
  /// In zh, this message translates to:
  /// **'点击编辑按钮修改快捷键，需至少包含一个修饰键（Ctrl/Shift/Alt）'**
  String get shortcutHint;

  /// No description provided for @shortcutEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get shortcutEdit;

  /// No description provided for @shortcutEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'修改「{name}」快捷键'**
  String shortcutEditTitle(String name);

  /// No description provided for @shortcutEditHint.
  ///
  /// In zh, this message translates to:
  /// **'按下新的组合键'**
  String get shortcutEditHint;

  /// No description provided for @shortcutEditWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待按键...'**
  String get shortcutEditWaiting;

  /// No description provided for @shortcutCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get shortcutCancel;

  /// No description provided for @shortcutConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get shortcutConfirm;

  /// No description provided for @multiAgentTitle.
  ///
  /// In zh, this message translates to:
  /// **'多Agent协作'**
  String get multiAgentTitle;

  /// No description provided for @multiAgentNewAgent.
  ///
  /// In zh, this message translates to:
  /// **'新Agent'**
  String get multiAgentNewAgent;

  /// No description provided for @multiAgentHQ.
  ///
  /// In zh, this message translates to:
  /// **'指挥部'**
  String get multiAgentHQ;

  /// No description provided for @multiAgentManager.
  ///
  /// In zh, this message translates to:
  /// **'Agent管理器'**
  String get multiAgentManager;

  /// No description provided for @multiAgentSwitchDir.
  ///
  /// In zh, this message translates to:
  /// **'切换工作目录'**
  String get multiAgentSwitchDir;

  /// No description provided for @multiAgentSwitchDirConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要切换目录吗？'**
  String get multiAgentSwitchDirConfirm;

  /// No description provided for @multiAgentNoHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史记录'**
  String get multiAgentNoHistory;

  /// No description provided for @multiAgentSelectDir.
  ///
  /// In zh, this message translates to:
  /// **'选择工作目录'**
  String get multiAgentSelectDir;

  /// No description provided for @multiAgentSelectDirTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择协作工作目录'**
  String get multiAgentSelectDirTitle;

  /// No description provided for @multiAgentOpenDir.
  ///
  /// In zh, this message translates to:
  /// **'打开目录'**
  String get multiAgentOpenDir;

  /// No description provided for @multiAgentRestoreHistory.
  ///
  /// In zh, this message translates to:
  /// **'恢复历史工作区'**
  String get multiAgentRestoreHistory;

  /// No description provided for @multiAgentDirHint.
  ///
  /// In zh, this message translates to:
  /// **'提示：可选择现有项目目录，或新建空目录'**
  String get multiAgentDirHint;

  /// No description provided for @multiAgentDeleteHistory.
  ///
  /// In zh, this message translates to:
  /// **'删除历史记录'**
  String get multiAgentDeleteHistory;

  /// No description provided for @multiAgentDeleteHistoryConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 \"{name}\" 的快照？\n此操作不可恢复。'**
  String multiAgentDeleteHistoryConfirm(String name);

  /// No description provided for @multiAgentHistorySection.
  ///
  /// In zh, this message translates to:
  /// **'历史工作区'**
  String get multiAgentHistorySection;

  /// No description provided for @multiAgentHistoryCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String multiAgentHistoryCount(int count);

  /// No description provided for @multiAgentNoHistoryShort.
  ///
  /// In zh, this message translates to:
  /// **'无历史记录'**
  String get multiAgentNoHistoryShort;

  /// No description provided for @multiAgentDeleteRecord.
  ///
  /// In zh, this message translates to:
  /// **'删除此记录'**
  String get multiAgentDeleteRecord;

  /// No description provided for @multiAgentActive.
  ///
  /// In zh, this message translates to:
  /// **'活跃'**
  String get multiAgentActive;

  /// No description provided for @multiAgentHidden.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏'**
  String get multiAgentHidden;

  /// No description provided for @multiAgentSelectFile.
  ///
  /// In zh, this message translates to:
  /// **'选择要发送的文件'**
  String get multiAgentSelectFile;

  /// No description provided for @multiAgentReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get multiAgentReady;

  /// No description provided for @multiAgentThinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中...'**
  String get multiAgentThinking;

  /// No description provided for @multiAgentExecutingTool.
  ///
  /// In zh, this message translates to:
  /// **'执行工具...'**
  String get multiAgentExecutingTool;

  /// No description provided for @multiAgentError.
  ///
  /// In zh, this message translates to:
  /// **'出错'**
  String get multiAgentError;

  /// No description provided for @multiAgentSendFile.
  ///
  /// In zh, this message translates to:
  /// **'发送文件'**
  String get multiAgentSendFile;

  /// No description provided for @multiAgentInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入消息… (Ctrl+Enter 发送)'**
  String get multiAgentInputHint;

  /// No description provided for @multiAgentWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待响应...'**
  String get multiAgentWaiting;

  /// No description provided for @multiAgentRemoved.
  ///
  /// In zh, this message translates to:
  /// **'Agent 已被移除'**
  String get multiAgentRemoved;

  /// No description provided for @multiAgentSelectGlobalFile.
  ///
  /// In zh, this message translates to:
  /// **'选择要全局分发的文件'**
  String get multiAgentSelectGlobalFile;

  /// No description provided for @multiAgentExportRecord.
  ///
  /// In zh, this message translates to:
  /// **'导出协作记录'**
  String get multiAgentExportRecord;

  /// No description provided for @multiAgentUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get multiAgentUser;

  /// No description provided for @multiAgentSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get multiAgentSystem;

  /// No description provided for @multiAgentTimeline.
  ///
  /// In zh, this message translates to:
  /// **'时间线'**
  String get multiAgentTimeline;

  /// No description provided for @multiAgentOverview.
  ///
  /// In zh, this message translates to:
  /// **'总览'**
  String get multiAgentOverview;

  /// No description provided for @multiAgentBroadcastHint.
  ///
  /// In zh, this message translates to:
  /// **'广播指令… (Ctrl+Enter 发送)'**
  String get multiAgentBroadcastHint;

  /// No description provided for @multiAgentBroadcast.
  ///
  /// In zh, this message translates to:
  /// **'广播'**
  String get multiAgentBroadcast;

  /// No description provided for @multiAgentGlobalFile.
  ///
  /// In zh, this message translates to:
  /// **'全局分发文件'**
  String get multiAgentGlobalFile;

  /// No description provided for @multiAgentNoMessages.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get multiAgentNoMessages;

  /// No description provided for @multiAgentYou.
  ///
  /// In zh, this message translates to:
  /// **'你'**
  String get multiAgentYou;

  /// No description provided for @multiAgentNoAgents.
  ///
  /// In zh, this message translates to:
  /// **'尚未创建Agent'**
  String get multiAgentNoAgents;

  /// No description provided for @multiAgentTotalAgents.
  ///
  /// In zh, this message translates to:
  /// **'总Agent'**
  String get multiAgentTotalAgents;

  /// No description provided for @multiAgentTotalMessages.
  ///
  /// In zh, this message translates to:
  /// **'消息总数'**
  String get multiAgentTotalMessages;

  /// No description provided for @multiAgentStatus.
  ///
  /// In zh, this message translates to:
  /// **'Agent 状态'**
  String get multiAgentStatus;

  /// No description provided for @multiAgentMsgCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息'**
  String multiAgentMsgCount(int count);

  /// No description provided for @multiAgentIdle.
  ///
  /// In zh, this message translates to:
  /// **'空闲'**
  String get multiAgentIdle;

  /// No description provided for @multiAgentExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出到: {path}'**
  String multiAgentExported(String path);

  /// No description provided for @multiAgentExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败: {error}'**
  String multiAgentExportFailed(String error);

  /// No description provided for @createAgentTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建新 Agent'**
  String get createAgentTitle;

  /// No description provided for @createAgentName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get createAgentName;

  /// No description provided for @createAgentNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：代码审查员'**
  String get createAgentNameHint;

  /// No description provided for @createAgentRole.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get createAgentRole;

  /// No description provided for @createAgentModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get createAgentModel;

  /// No description provided for @createAgentModelFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载模型失败'**
  String get createAgentModelFailed;

  /// No description provided for @createAgentSkills.
  ///
  /// In zh, this message translates to:
  /// **'挂载技能'**
  String get createAgentSkills;

  /// No description provided for @createAgentPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限授予'**
  String get createAgentPermissions;

  /// No description provided for @createAgentPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'定义这个Agent的职责和行为...'**
  String get createAgentPromptHint;

  /// No description provided for @createAgentPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'系统提示（可选）'**
  String get createAgentPromptLabel;

  /// No description provided for @createAgentSysDetect.
  ///
  /// In zh, this message translates to:
  /// **'系统探测'**
  String get createAgentSysDetect;

  /// No description provided for @createAgentFileCmd.
  ///
  /// In zh, this message translates to:
  /// **'文件/命令'**
  String get createAgentFileCmd;

  /// No description provided for @agentBadgeNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get agentBadgeNotConfigured;

  /// No description provided for @agentBadgeModel.
  ///
  /// In zh, this message translates to:
  /// **'接入模型'**
  String get agentBadgeModel;

  /// No description provided for @agentBadgePermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get agentBadgePermissions;

  /// No description provided for @agentBadgeNoPermissions.
  ///
  /// In zh, this message translates to:
  /// **'无特殊权限'**
  String get agentBadgeNoPermissions;

  /// No description provided for @agentBadgeSkills.
  ///
  /// In zh, this message translates to:
  /// **'技能'**
  String get agentBadgeSkills;

  /// No description provided for @agentBadgeNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get agentBadgeNone;

  /// No description provided for @agentBadgeTools.
  ///
  /// In zh, this message translates to:
  /// **'工具'**
  String get agentBadgeTools;

  /// No description provided for @agentBadgeMsgCount.
  ///
  /// In zh, this message translates to:
  /// **'消息数'**
  String get agentBadgeMsgCount;

  /// No description provided for @agentBadgeStatus.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get agentBadgeStatus;

  /// No description provided for @agentBadgeIdle.
  ///
  /// In zh, this message translates to:
  /// **'空闲'**
  String get agentBadgeIdle;

  /// No description provided for @agentBadgeThinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中'**
  String get agentBadgeThinking;

  /// No description provided for @agentBadgeExecuting.
  ///
  /// In zh, this message translates to:
  /// **'执行工具'**
  String get agentBadgeExecuting;

  /// No description provided for @agentBadgeError.
  ///
  /// In zh, this message translates to:
  /// **'出错'**
  String get agentBadgeError;

  /// No description provided for @agentBadgeSystemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统设定'**
  String get agentBadgeSystemPrompt;

  /// No description provided for @agentBadgeNotExist.
  ///
  /// In zh, this message translates to:
  /// **'Agent 不存在'**
  String get agentBadgeNotExist;

  /// No description provided for @agentRoleCommander.
  ///
  /// In zh, this message translates to:
  /// **'总指挥'**
  String get agentRoleCommander;

  /// No description provided for @agentRoleWorker.
  ///
  /// In zh, this message translates to:
  /// **'工作者'**
  String get agentRoleWorker;

  /// No description provided for @agentRoleReviewer.
  ///
  /// In zh, this message translates to:
  /// **'审查员'**
  String get agentRoleReviewer;

  /// No description provided for @agentRoleResearcher.
  ///
  /// In zh, this message translates to:
  /// **'研究员'**
  String get agentRoleResearcher;

  /// No description provided for @agentRoleCoder.
  ///
  /// In zh, this message translates to:
  /// **'编码员'**
  String get agentRoleCoder;

  /// No description provided for @agentRoleCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get agentRoleCustom;

  /// No description provided for @agentPermRead.
  ///
  /// In zh, this message translates to:
  /// **'读文件'**
  String get agentPermRead;

  /// No description provided for @agentPermWrite.
  ///
  /// In zh, this message translates to:
  /// **'写文件'**
  String get agentPermWrite;

  /// No description provided for @agentPermDelete.
  ///
  /// In zh, this message translates to:
  /// **'删文件'**
  String get agentPermDelete;

  /// No description provided for @agentPermExec.
  ///
  /// In zh, this message translates to:
  /// **'执行命令'**
  String get agentPermExec;

  /// No description provided for @agentPermNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络'**
  String get agentPermNetwork;

  /// No description provided for @wsDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建工作目录'**
  String get wsDialogTitle;

  /// No description provided for @wsDialogDesc.
  ///
  /// In zh, this message translates to:
  /// **'创建一个带有项目配置的工作目录，自动生成 memory.json'**
  String get wsDialogDesc;

  /// No description provided for @wsDialogLocation.
  ///
  /// In zh, this message translates to:
  /// **'目录位置'**
  String get wsDialogLocation;

  /// No description provided for @wsDialogSelectParent.
  ///
  /// In zh, this message translates to:
  /// **'选择父目录...'**
  String get wsDialogSelectParent;

  /// No description provided for @wsDialogFolderName.
  ///
  /// In zh, this message translates to:
  /// **'文件夹名称'**
  String get wsDialogFolderName;

  /// No description provided for @wsDialogFolderHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: my_project'**
  String get wsDialogFolderHint;

  /// No description provided for @wsDialogConfig.
  ///
  /// In zh, this message translates to:
  /// **'项目配置 (memory.json)'**
  String get wsDialogConfig;

  /// No description provided for @wsDialogPermMode.
  ///
  /// In zh, this message translates to:
  /// **'权限模式'**
  String get wsDialogPermMode;

  /// No description provided for @wsDialogPermAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动执行 (auto)'**
  String get wsDialogPermAuto;

  /// No description provided for @wsDialogPermNormal.
  ///
  /// In zh, this message translates to:
  /// **'操作需确认 (normal)'**
  String get wsDialogPermNormal;

  /// No description provided for @wsDialogEmbeddings.
  ///
  /// In zh, this message translates to:
  /// **'向量记忆 (embeddings)'**
  String get wsDialogEmbeddings;

  /// No description provided for @wsDialogEmbeddingsHint.
  ///
  /// In zh, this message translates to:
  /// **'需先在设置中配置嵌入模型'**
  String get wsDialogEmbeddingsHint;

  /// No description provided for @wsDialogAutoStore.
  ///
  /// In zh, this message translates to:
  /// **'自动存储记忆'**
  String get wsDialogAutoStore;

  /// No description provided for @wsDialogAutoStoreDesc.
  ///
  /// In zh, this message translates to:
  /// **'重要信息自动存入长期记忆'**
  String get wsDialogAutoStoreDesc;

  /// No description provided for @wsDialogAutoRecall.
  ///
  /// In zh, this message translates to:
  /// **'自动召回记忆'**
  String get wsDialogAutoRecall;

  /// No description provided for @wsDialogAutoRecallDesc.
  ///
  /// In zh, this message translates to:
  /// **'对话时语义匹配召回相关记忆'**
  String get wsDialogAutoRecallDesc;

  /// No description provided for @wsDialogEmbConn.
  ///
  /// In zh, this message translates to:
  /// **'嵌入模型连接'**
  String get wsDialogEmbConn;

  /// No description provided for @wsDialogTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get wsDialogTesting;

  /// No description provided for @wsDialogTestConn.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get wsDialogTestConn;

  /// No description provided for @wsDialogCreating.
  ///
  /// In zh, this message translates to:
  /// **'创建中...'**
  String get wsDialogCreating;

  /// No description provided for @wsDialogCreateBtn.
  ///
  /// In zh, this message translates to:
  /// **'创建并切换'**
  String get wsDialogCreateBtn;

  /// No description provided for @wsDialogSelectParentTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择父目录'**
  String get wsDialogSelectParentTitle;

  /// No description provided for @wsDialogEmbNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置嵌入模型，请在设置中填写'**
  String get wsDialogEmbNotConfigured;

  /// No description provided for @wsDialogCreated.
  ///
  /// In zh, this message translates to:
  /// **'工作目录已创建: {name}'**
  String wsDialogCreated(String name);

  /// No description provided for @wsDialogCreateFailed.
  ///
  /// In zh, this message translates to:
  /// **'创建失败: {error}'**
  String wsDialogCreateFailed(String error);

  /// No description provided for @embEditorTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑嵌入模型'**
  String get embEditorTitle;

  /// No description provided for @embEditorAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增嵌入模型'**
  String get embEditorAddTitle;

  /// No description provided for @embEditorNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如: OpenAI Large'**
  String get embEditorNameHint;

  /// No description provided for @embEditorEnableQdrant.
  ///
  /// In zh, this message translates to:
  /// **'启用 Qdrant 向量检索'**
  String get embEditorEnableQdrant;

  /// No description provided for @embEditorEnableSqlite.
  ///
  /// In zh, this message translates to:
  /// **'存入 SQLite 作为长期记忆'**
  String get embEditorEnableSqlite;

  /// No description provided for @embEditorTestConn.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get embEditorTestConn;

  /// No description provided for @embEditorFillRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写 Base URL、API Key 和 Model'**
  String get embEditorFillRequired;

  /// No description provided for @embEditorConnSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get embEditorConnSuccess;

  /// No description provided for @embEditorConnAbnormal.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，但响应格式异常'**
  String get embEditorConnAbnormal;

  /// No description provided for @embEditorTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时'**
  String get embEditorTimeout;

  /// No description provided for @embEditorUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get embEditorUnknownError;

  /// No description provided for @embSectionHint.
  ///
  /// In zh, this message translates to:
  /// **'配置一个或多个嵌入式模型，点击卡片设为默认（选中项用于记忆向量化）'**
  String get embSectionHint;

  /// No description provided for @embSectionDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除嵌入模型'**
  String get embSectionDeleteTitle;

  /// No description provided for @embSectionDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除 \"{name}\" 吗？'**
  String embSectionDeleteConfirm(String name);

  /// No description provided for @embSectionDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get embSectionDefault;

  /// No description provided for @embSectionAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增嵌入模型'**
  String get embSectionAdd;

  /// No description provided for @qdrantSelectExe.
  ///
  /// In zh, this message translates to:
  /// **'选择 Qdrant 可执行文件'**
  String get qdrantSelectExe;

  /// No description provided for @qdrantDetection.
  ///
  /// In zh, this message translates to:
  /// **'可执行文件检测'**
  String get qdrantDetection;

  /// No description provided for @qdrantRedetect.
  ///
  /// In zh, this message translates to:
  /// **'重新检测'**
  String get qdrantRedetect;

  /// No description provided for @qdrantNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到 qdrant 可执行文件'**
  String get qdrantNotFound;

  /// No description provided for @qdrantNotFoundHint.
  ///
  /// In zh, this message translates to:
  /// **'请手动指定 qdrant 可执行文件，或前往 qdrant.tech 下载后加入系统 PATH。'**
  String get qdrantNotFoundHint;

  /// No description provided for @qdrantChangePath.
  ///
  /// In zh, this message translates to:
  /// **'更换路径'**
  String get qdrantChangePath;

  /// No description provided for @qdrantManualSelect.
  ///
  /// In zh, this message translates to:
  /// **'手动指定'**
  String get qdrantManualSelect;

  /// No description provided for @qdrantAutoDetect.
  ///
  /// In zh, this message translates to:
  /// **'恢复自动检测'**
  String get qdrantAutoDetect;

  /// No description provided for @exportFormatTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择导出格式'**
  String get exportFormatTitle;

  /// No description provided for @exportExporting.
  ///
  /// In zh, this message translates to:
  /// **'正在导出 {format}...'**
  String exportExporting(String format);

  /// No description provided for @exportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已导出到: {path}'**
  String exportSuccess(String path);

  /// No description provided for @exportFallbackMd.
  ///
  /// In zh, this message translates to:
  /// **'是否改为导出 Markdown (.md) 格式？内容完全相同，不会丢失。'**
  String get exportFallbackMd;

  /// No description provided for @exportFallbackBtn.
  ///
  /// In zh, this message translates to:
  /// **'导出为 Markdown'**
  String get exportFallbackBtn;

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'{format} 导出失败'**
  String exportFailed(String format);

  /// No description provided for @exportSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存导出文件'**
  String get exportSaveTitle;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get commonConfirm;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @commonCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get commonCopy;

  /// No description provided for @commonSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get commonSearch;

  /// No description provided for @commonLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get commonLoading;

  /// No description provided for @commonError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get commonError;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get commonEmpty;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get commonClear;

  /// No description provided for @commonSelect.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get commonSelect;

  /// No description provided for @commonSwitch.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get commonSwitch;

  /// No description provided for @commonAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get commonAdd;

  /// No description provided for @commonErrorWithMsg.
  ///
  /// In zh, this message translates to:
  /// **'错误: {msg}'**
  String commonErrorWithMsg(String msg);

  /// No description provided for @attachOpenWith.
  ///
  /// In zh, this message translates to:
  /// **'用系统程序打开'**
  String get attachOpenWith;

  /// No description provided for @attachFileNotExist.
  ///
  /// In zh, this message translates to:
  /// **'文件不存在：{path}'**
  String attachFileNotExist(String path);

  /// No description provided for @scrollUp.
  ///
  /// In zh, this message translates to:
  /// **'向上滚动（长按持续）'**
  String get scrollUp;

  /// No description provided for @scrollDown.
  ///
  /// In zh, this message translates to:
  /// **'向下滚动（长按持续）'**
  String get scrollDown;

  /// No description provided for @permissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'用户拒绝了操作'**
  String get permissionDenied;

  /// No description provided for @memoryEmbNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置嵌入模型\n请前往设置页配置 Embedding 模型后启用向量记忆'**
  String get memoryEmbNotConfigured;

  /// No description provided for @memoryQdrantNotRunning.
  ///
  /// In zh, this message translates to:
  /// **'Qdrant 向量数据库未运行\n请检查 Qdrant 服务状态'**
  String get memoryQdrantNotRunning;

  /// No description provided for @memoryEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'当前工作目录暂无记忆\n对话中产生值得记住的信息时会自动存入'**
  String get memoryEmptyHint;

  /// No description provided for @memoryQdrantStopped.
  ///
  /// In zh, this message translates to:
  /// **'未运行'**
  String get memoryQdrantStopped;

  /// No description provided for @memoryContentEmpty.
  ///
  /// In zh, this message translates to:
  /// **'(空)'**
  String get memoryContentEmpty;

  /// No description provided for @memorySourceAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get memorySourceAuto;

  /// No description provided for @memoryFromQuery.
  ///
  /// In zh, this message translates to:
  /// **'来自: {query}'**
  String memoryFromQuery(String query);

  /// No description provided for @historyMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟前'**
  String historyMinutesAgo(int minutes);

  /// No description provided for @historyHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时前'**
  String historyHoursAgo(int hours);

  /// No description provided for @historyDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天前'**
  String historyDaysAgo(int days);

  /// No description provided for @historyDateFormat.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String historyDateFormat(int month, int day);

  /// No description provided for @mcpEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮添加 MCP 服务器配置'**
  String get mcpEmptyHint;

  /// No description provided for @mcpReorderHint.
  ///
  /// In zh, this message translates to:
  /// **'点击卡片编辑，长按拖动可调整顺序'**
  String get mcpReorderHint;

  /// No description provided for @mcpDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'断开'**
  String get mcpDisconnect;

  /// No description provided for @mcpTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get mcpTestConnection;

  /// No description provided for @mcpConnectFailedWithDetail.
  ///
  /// In zh, this message translates to:
  /// **'连接失败: {detail}'**
  String mcpConnectFailedWithDetail(String detail);

  /// No description provided for @mcpFormName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get mcpFormName;

  /// No description provided for @mcpFormNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入名称'**
  String get mcpFormNameRequired;

  /// No description provided for @mcpFormCommand.
  ///
  /// In zh, this message translates to:
  /// **'命令'**
  String get mcpFormCommand;

  /// No description provided for @mcpFormCommandRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入命令'**
  String get mcpFormCommandRequired;

  /// No description provided for @mcpFormArgs.
  ///
  /// In zh, this message translates to:
  /// **'参数 (空格分隔)'**
  String get mcpFormArgs;

  /// No description provided for @mcpFormCwd.
  ///
  /// In zh, this message translates to:
  /// **'工作目录 (可选)'**
  String get mcpFormCwd;

  /// No description provided for @mcpFormEnv.
  ///
  /// In zh, this message translates to:
  /// **'环境变量 (每行 KEY=VALUE)'**
  String get mcpFormEnv;

  /// No description provided for @mcpFormUrl.
  ///
  /// In zh, this message translates to:
  /// **'URL'**
  String get mcpFormUrl;

  /// No description provided for @mcpFormUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 URL'**
  String get mcpFormUrlRequired;

  /// No description provided for @mcpFormHeaders.
  ///
  /// In zh, this message translates to:
  /// **'请求头 (每行 Key: Value)'**
  String get mcpFormHeaders;

  /// No description provided for @mcpSseHint.
  ///
  /// In zh, this message translates to:
  /// **'如: http://localhost:3000/sse'**
  String get mcpSseHint;

  /// No description provided for @mcpStreamableHint.
  ///
  /// In zh, this message translates to:
  /// **'如: http://localhost:3000/mcp'**
  String get mcpStreamableHint;

  /// No description provided for @skillsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击下方按钮导入 ZIP 技能包'**
  String get skillsEmptyHint;

  /// No description provided for @skillsReorderHint.
  ///
  /// In zh, this message translates to:
  /// **'开关控制启用状态，长按拖动可调整顺序'**
  String get skillsReorderHint;

  /// No description provided for @skillsBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get skillsBuiltin;

  /// No description provided for @skillsToolCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个工具'**
  String skillsToolCount(int count);

  /// No description provided for @servicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务'**
  String get servicesTitle;

  /// No description provided for @servicesSkillsTab.
  ///
  /// In zh, this message translates to:
  /// **'技能'**
  String get servicesSkillsTab;

  /// No description provided for @expertEditorEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑专家'**
  String get expertEditorEdit;

  /// No description provided for @expertEditorCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建专家'**
  String get expertEditorCreate;

  /// No description provided for @expertEditorName.
  ///
  /// In zh, this message translates to:
  /// **'专家名称'**
  String get expertEditorName;

  /// No description provided for @expertEditorCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get expertEditorCategory;

  /// No description provided for @expertEditorDesc.
  ///
  /// In zh, this message translates to:
  /// **'简要描述'**
  String get expertEditorDesc;

  /// No description provided for @expertEditorPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词 (System Prompt)'**
  String get expertEditorPrompt;

  /// No description provided for @expertCategoryTech.
  ///
  /// In zh, this message translates to:
  /// **'技术'**
  String get expertCategoryTech;

  /// No description provided for @expertCategoryAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'分析'**
  String get expertCategoryAnalysis;

  /// No description provided for @expertCategoryOffice.
  ///
  /// In zh, this message translates to:
  /// **'办公'**
  String get expertCategoryOffice;

  /// No description provided for @expertCategoryCreative.
  ///
  /// In zh, this message translates to:
  /// **'创意'**
  String get expertCategoryCreative;

  /// No description provided for @expertCategoryCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get expertCategoryCustom;

  /// No description provided for @vplToolName.
  ///
  /// In zh, this message translates to:
  /// **'可视化编程'**
  String get vplToolName;

  /// No description provided for @vplToolDesc.
  ///
  /// In zh, this message translates to:
  /// **'节点式流程编辑器，拖拽构建程序逻辑'**
  String get vplToolDesc;

  /// No description provided for @vplToolCategory.
  ///
  /// In zh, this message translates to:
  /// **'开发'**
  String get vplToolCategory;

  /// No description provided for @vplSave.
  ///
  /// In zh, this message translates to:
  /// **'保存 VPL 项目'**
  String get vplSave;

  /// No description provided for @vplDefaultFilename.
  ///
  /// In zh, this message translates to:
  /// **'未命名.vpl.json'**
  String get vplDefaultFilename;

  /// No description provided for @vplSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存: {path}'**
  String vplSaved(String path);

  /// No description provided for @vplSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String vplSaveFailed(String error);

  /// No description provided for @vplOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开 VPL 项目'**
  String get vplOpen;

  /// No description provided for @vplOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开: {path}'**
  String vplOpened(String path);

  /// No description provided for @vplOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开失败: {error}'**
  String vplOpenFailed(String error);

  /// No description provided for @vplExportCode.
  ///
  /// In zh, this message translates to:
  /// **'导出代码'**
  String get vplExportCode;

  /// No description provided for @vplExportJson.
  ///
  /// In zh, this message translates to:
  /// **'JSON (可重新导入)'**
  String get vplExportJson;

  /// No description provided for @vplCopyPython.
  ///
  /// In zh, this message translates to:
  /// **'复制 Python 到剪贴板'**
  String get vplCopyPython;

  /// No description provided for @vplCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get vplCopied;

  /// No description provided for @vplExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出: {path}'**
  String vplExported(String path);

  /// No description provided for @vplCodePreview.
  ///
  /// In zh, this message translates to:
  /// **'{lang} 代码预览'**
  String vplCodePreview(String lang);

  /// No description provided for @vplUnsavedTitle.
  ///
  /// In zh, this message translates to:
  /// **'未保存的更改'**
  String get vplUnsavedTitle;

  /// No description provided for @vplUnsavedContent.
  ///
  /// In zh, this message translates to:
  /// **'当前项目有未保存的修改，是否保存？'**
  String get vplUnsavedContent;

  /// No description provided for @vplDontSave.
  ///
  /// In zh, this message translates to:
  /// **'不保存'**
  String get vplDontSave;

  /// No description provided for @vplNewProject.
  ///
  /// In zh, this message translates to:
  /// **'新项目'**
  String get vplNewProject;

  /// No description provided for @vplBtnNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get vplBtnNew;

  /// No description provided for @vplBtnOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get vplBtnOpen;

  /// No description provided for @vplBtnSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get vplBtnSave;

  /// No description provided for @vplBtnExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get vplBtnExport;

  /// No description provided for @vplBtnFitCanvas.
  ///
  /// In zh, this message translates to:
  /// **'适应画布'**
  String get vplBtnFitCanvas;

  /// No description provided for @vplBtnSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get vplBtnSelectAll;

  /// No description provided for @vplBtnDeleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'删除选中'**
  String get vplBtnDeleteSelected;

  /// No description provided for @vplStatusReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get vplStatusReady;

  /// No description provided for @vplStatusNodes.
  ///
  /// In zh, this message translates to:
  /// **'节点: {count}  连线: {edges}'**
  String vplStatusNodes(int count, int edges);

  /// No description provided for @vplCatFlow.
  ///
  /// In zh, this message translates to:
  /// **'流程控制'**
  String get vplCatFlow;

  /// No description provided for @vplCatData.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get vplCatData;

  /// No description provided for @vplCatMath.
  ///
  /// In zh, this message translates to:
  /// **'运算'**
  String get vplCatMath;

  /// No description provided for @vplCatIO.
  ///
  /// In zh, this message translates to:
  /// **'输入输出'**
  String get vplCatIO;

  /// No description provided for @vplCatFunc.
  ///
  /// In zh, this message translates to:
  /// **'函数'**
  String get vplCatFunc;

  /// No description provided for @vplCatOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get vplCatOther;

  /// No description provided for @vplNodeStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get vplNodeStart;

  /// No description provided for @vplNodeEnd.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get vplNodeEnd;

  /// No description provided for @vplNodeCondition.
  ///
  /// In zh, this message translates to:
  /// **'条件'**
  String get vplNodeCondition;

  /// No description provided for @vplNodeLoop.
  ///
  /// In zh, this message translates to:
  /// **'循环'**
  String get vplNodeLoop;

  /// No description provided for @vplNodeVariable.
  ///
  /// In zh, this message translates to:
  /// **'变量'**
  String get vplNodeVariable;

  /// No description provided for @vplNodeConstant.
  ///
  /// In zh, this message translates to:
  /// **'常量'**
  String get vplNodeConstant;

  /// No description provided for @vplNodeList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get vplNodeList;

  /// No description provided for @vplNodeDict.
  ///
  /// In zh, this message translates to:
  /// **'字典'**
  String get vplNodeDict;

  /// No description provided for @vplNodeMath.
  ///
  /// In zh, this message translates to:
  /// **'数学运算'**
  String get vplNodeMath;

  /// No description provided for @vplNodeCompare.
  ///
  /// In zh, this message translates to:
  /// **'比较运算'**
  String get vplNodeCompare;

  /// No description provided for @vplNodeLogic.
  ///
  /// In zh, this message translates to:
  /// **'逻辑运算'**
  String get vplNodeLogic;

  /// No description provided for @vplNodeString.
  ///
  /// In zh, this message translates to:
  /// **'字符串'**
  String get vplNodeString;

  /// No description provided for @vplNodeOutput.
  ///
  /// In zh, this message translates to:
  /// **'输出'**
  String get vplNodeOutput;

  /// No description provided for @vplNodeInput.
  ///
  /// In zh, this message translates to:
  /// **'输入'**
  String get vplNodeInput;

  /// No description provided for @vplNodeReadFile.
  ///
  /// In zh, this message translates to:
  /// **'读文件'**
  String get vplNodeReadFile;

  /// No description provided for @vplNodeWriteFile.
  ///
  /// In zh, this message translates to:
  /// **'写文件'**
  String get vplNodeWriteFile;

  /// No description provided for @vplNodeFuncDef.
  ///
  /// In zh, this message translates to:
  /// **'函数定义'**
  String get vplNodeFuncDef;

  /// No description provided for @vplNodeFuncCall.
  ///
  /// In zh, this message translates to:
  /// **'函数调用'**
  String get vplNodeFuncCall;

  /// No description provided for @vplNodeReturn.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get vplNodeReturn;

  /// No description provided for @vplNodeComment.
  ///
  /// In zh, this message translates to:
  /// **'注释'**
  String get vplNodeComment;

  /// No description provided for @vplPropTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} 属性'**
  String vplPropTitle(String name);

  /// No description provided for @vplPropName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get vplPropName;

  /// No description provided for @vplPropValue.
  ///
  /// In zh, this message translates to:
  /// **'值'**
  String get vplPropValue;

  /// No description provided for @vplPropOperator.
  ///
  /// In zh, this message translates to:
  /// **'运算符'**
  String get vplPropOperator;

  /// No description provided for @vplPropResultVar.
  ///
  /// In zh, this message translates to:
  /// **'结果变量名'**
  String get vplPropResultVar;

  /// No description provided for @vplPropIndexVar.
  ///
  /// In zh, this message translates to:
  /// **'索引变量名'**
  String get vplPropIndexVar;

  /// No description provided for @vplPropPromptText.
  ///
  /// In zh, this message translates to:
  /// **'提示文本'**
  String get vplPropPromptText;

  /// No description provided for @vplPropVarName.
  ///
  /// In zh, this message translates to:
  /// **'变量名'**
  String get vplPropVarName;

  /// No description provided for @vplPropParamList.
  ///
  /// In zh, this message translates to:
  /// **'参数列表'**
  String get vplPropParamList;

  /// No description provided for @vplPropCallArgs.
  ///
  /// In zh, this message translates to:
  /// **'调用参数'**
  String get vplPropCallArgs;

  /// No description provided for @vplPropContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get vplPropContent;

  /// No description provided for @vplPropFilePath.
  ///
  /// In zh, this message translates to:
  /// **'文件路径'**
  String get vplPropFilePath;

  /// No description provided for @vplDefaultPrompt.
  ///
  /// In zh, this message translates to:
  /// **'\"请输入: \"'**
  String get vplDefaultPrompt;

  /// No description provided for @vplPortCondition.
  ///
  /// In zh, this message translates to:
  /// **'条件'**
  String get vplPortCondition;

  /// No description provided for @vplPortCount.
  ///
  /// In zh, this message translates to:
  /// **'次数'**
  String get vplPortCount;

  /// No description provided for @vplPortBody.
  ///
  /// In zh, this message translates to:
  /// **'循环体'**
  String get vplPortBody;

  /// No description provided for @vplPortIndex.
  ///
  /// In zh, this message translates to:
  /// **'索引'**
  String get vplPortIndex;

  /// No description provided for @vplPortDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get vplPortDone;

  /// No description provided for @vplPortAssign.
  ///
  /// In zh, this message translates to:
  /// **'赋值'**
  String get vplPortAssign;

  /// No description provided for @vplPortValue.
  ///
  /// In zh, this message translates to:
  /// **'值'**
  String get vplPortValue;

  /// No description provided for @vplPortElement.
  ///
  /// In zh, this message translates to:
  /// **'元素'**
  String get vplPortElement;

  /// No description provided for @vplPortList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get vplPortList;

  /// No description provided for @vplPortLength.
  ///
  /// In zh, this message translates to:
  /// **'长度'**
  String get vplPortLength;

  /// No description provided for @vplPortKey.
  ///
  /// In zh, this message translates to:
  /// **'键'**
  String get vplPortKey;

  /// No description provided for @vplPortDict.
  ///
  /// In zh, this message translates to:
  /// **'字典'**
  String get vplPortDict;

  /// No description provided for @vplPortResult.
  ///
  /// In zh, this message translates to:
  /// **'结果'**
  String get vplPortResult;

  /// No description provided for @vplPortInput.
  ///
  /// In zh, this message translates to:
  /// **'输入'**
  String get vplPortInput;

  /// No description provided for @vplPortParam.
  ///
  /// In zh, this message translates to:
  /// **'参数'**
  String get vplPortParam;

  /// No description provided for @vplPortPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示'**
  String get vplPortPrompt;

  /// No description provided for @vplPortPath.
  ///
  /// In zh, this message translates to:
  /// **'路径'**
  String get vplPortPath;

  /// No description provided for @vplPortContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get vplPortContent;

  /// No description provided for @vplPortReturn.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get vplPortReturn;

  /// No description provided for @fcToolName.
  ///
  /// In zh, this message translates to:
  /// **'流程图'**
  String get fcToolName;

  /// No description provided for @fcToolDesc.
  ///
  /// In zh, this message translates to:
  /// **'可视化流程图编辑，支持导出 Mermaid 语法'**
  String get fcToolDesc;

  /// No description provided for @fcToolCategory.
  ///
  /// In zh, this message translates to:
  /// **'开发'**
  String get fcToolCategory;

  /// No description provided for @fcShapeRect.
  ///
  /// In zh, this message translates to:
  /// **'矩形'**
  String get fcShapeRect;

  /// No description provided for @fcShapeRoundRect.
  ///
  /// In zh, this message translates to:
  /// **'圆角矩形'**
  String get fcShapeRoundRect;

  /// No description provided for @fcShapeDiamond.
  ///
  /// In zh, this message translates to:
  /// **'菱形'**
  String get fcShapeDiamond;

  /// No description provided for @fcShapeCircle.
  ///
  /// In zh, this message translates to:
  /// **'圆形'**
  String get fcShapeCircle;

  /// No description provided for @fcShapeParallelogram.
  ///
  /// In zh, this message translates to:
  /// **'平行四边形'**
  String get fcShapeParallelogram;

  /// No description provided for @fcShapeHexagon.
  ///
  /// In zh, this message translates to:
  /// **'六边形'**
  String get fcShapeHexagon;

  /// No description provided for @fcShapeDatabase.
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get fcShapeDatabase;

  /// No description provided for @fcShapeCapsule.
  ///
  /// In zh, this message translates to:
  /// **'胶囊形'**
  String get fcShapeCapsule;

  /// No description provided for @fcArrowSingle.
  ///
  /// In zh, this message translates to:
  /// **'单向箭头'**
  String get fcArrowSingle;

  /// No description provided for @fcArrowDouble.
  ///
  /// In zh, this message translates to:
  /// **'双向箭头'**
  String get fcArrowDouble;

  /// No description provided for @fcArrowNone.
  ///
  /// In zh, this message translates to:
  /// **'无箭头'**
  String get fcArrowNone;

  /// No description provided for @fcLineSolid.
  ///
  /// In zh, this message translates to:
  /// **'实线'**
  String get fcLineSolid;

  /// No description provided for @fcLineDashed.
  ///
  /// In zh, this message translates to:
  /// **'虚线'**
  String get fcLineDashed;

  /// No description provided for @fcLineDotted.
  ///
  /// In zh, this message translates to:
  /// **'点线'**
  String get fcLineDotted;

  /// No description provided for @fcUnsavedTitle.
  ///
  /// In zh, this message translates to:
  /// **'未保存的更改'**
  String get fcUnsavedTitle;

  /// No description provided for @fcUnsavedContent.
  ///
  /// In zh, this message translates to:
  /// **'当前流程图有未保存的修改，是否保存？'**
  String get fcUnsavedContent;

  /// No description provided for @fcDontSave.
  ///
  /// In zh, this message translates to:
  /// **'不保存'**
  String get fcDontSave;

  /// No description provided for @fcSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存流程图'**
  String get fcSaveTitle;

  /// No description provided for @fcDefaultFilename.
  ///
  /// In zh, this message translates to:
  /// **'未命名.fc.json'**
  String get fcDefaultFilename;

  /// No description provided for @fcSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存: {path}'**
  String fcSaved(String path);

  /// No description provided for @fcSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String fcSaveFailed(String error);

  /// No description provided for @fcOpenTitle.
  ///
  /// In zh, this message translates to:
  /// **'打开流程图'**
  String get fcOpenTitle;

  /// No description provided for @fcOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开: {path}'**
  String fcOpened(String path);

  /// No description provided for @fcOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'打开失败: {error}'**
  String fcOpenFailed(String error);

  /// No description provided for @fcNewChart.
  ///
  /// In zh, this message translates to:
  /// **'新建流程图'**
  String get fcNewChart;

  /// No description provided for @fcCanvasNotReady.
  ///
  /// In zh, this message translates to:
  /// **'画布未就绪'**
  String get fcCanvasNotReady;

  /// No description provided for @fcImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片生成失败'**
  String get fcImageFailed;

  /// No description provided for @fcExportPng.
  ///
  /// In zh, this message translates to:
  /// **'导出流程图为 PNG'**
  String get fcExportPng;

  /// No description provided for @fcExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出: {path}'**
  String fcExported(String path);

  /// No description provided for @fcExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败: {error}'**
  String fcExportFailed(String error);

  /// No description provided for @fcBtnNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get fcBtnNew;

  /// No description provided for @fcBtnOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get fcBtnOpen;

  /// No description provided for @fcBtnSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get fcBtnSave;

  /// No description provided for @fcBtnExportImage.
  ///
  /// In zh, this message translates to:
  /// **'导出图片'**
  String get fcBtnExportImage;

  /// No description provided for @fcBtnShowGrid.
  ///
  /// In zh, this message translates to:
  /// **'显示网格'**
  String get fcBtnShowGrid;

  /// No description provided for @fcBtnHideGrid.
  ///
  /// In zh, this message translates to:
  /// **'隐藏网格'**
  String get fcBtnHideGrid;

  /// No description provided for @fcBtnFitCanvas.
  ///
  /// In zh, this message translates to:
  /// **'适应画布'**
  String get fcBtnFitCanvas;

  /// No description provided for @fcBtnSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get fcBtnSelectAll;

  /// No description provided for @fcBtnDeleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'删除选中'**
  String get fcBtnDeleteSelected;

  /// No description provided for @fcStatusReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪 · 点击左侧形状添加节点，从端口拖线连接'**
  String get fcStatusReady;

  /// No description provided for @fcStatusNodes.
  ///
  /// In zh, this message translates to:
  /// **'节点: {count}'**
  String fcStatusNodes(int count, int edges);

  /// No description provided for @fcCustomColor.
  ///
  /// In zh, this message translates to:
  /// **'自定义颜色'**
  String get fcCustomColor;

  /// No description provided for @fcClickToAdd.
  ///
  /// In zh, this message translates to:
  /// **'点击添加到画布'**
  String get fcClickToAdd;

  /// No description provided for @fcNodeColor.
  ///
  /// In zh, this message translates to:
  /// **'节点颜色'**
  String get fcNodeColor;

  /// No description provided for @fcHelpText.
  ///
  /// In zh, this message translates to:
  /// **'操作提示:\n• 点击形状直接添加节点\n• 双击节点编辑文字/样式\n• 从节点边缘拖线连接\n• 滚轮缩放，拖拽画布'**
  String get fcHelpText;

  /// No description provided for @fcEditNode.
  ///
  /// In zh, this message translates to:
  /// **'编辑节点'**
  String get fcEditNode;

  /// No description provided for @fcTextContent.
  ///
  /// In zh, this message translates to:
  /// **'文本内容'**
  String get fcTextContent;

  /// No description provided for @siyuToolName.
  ///
  /// In zh, this message translates to:
  /// **'思宇'**
  String get siyuToolName;

  /// No description provided for @siyuToolDesc.
  ///
  /// In zh, this message translates to:
  /// **'富文本文档编辑器，支持图片、格式、导出'**
  String get siyuToolDesc;

  /// No description provided for @siyuToolCategory.
  ///
  /// In zh, this message translates to:
  /// **'创作'**
  String get siyuToolCategory;

  /// No description provided for @siyuPickLocation.
  ///
  /// In zh, this message translates to:
  /// **'选择项目存放位置'**
  String get siyuPickLocation;

  /// No description provided for @siyuNewProject.
  ///
  /// In zh, this message translates to:
  /// **'新建项目'**
  String get siyuNewProject;

  /// No description provided for @siyuProjectName.
  ///
  /// In zh, this message translates to:
  /// **'项目名称'**
  String get siyuProjectName;

  /// No description provided for @siyuDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'新文档'**
  String get siyuDefaultName;

  /// No description provided for @siyuFolderExists.
  ///
  /// In zh, this message translates to:
  /// **'文件夹已存在: {name}'**
  String siyuFolderExists(String name);

  /// No description provided for @siyuSaved.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 已保存'**
  String siyuSaved(String name);

  /// No description provided for @siyuSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String siyuSaveFailed(String error);

  /// No description provided for @siyuPickImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get siyuPickImage;

  /// No description provided for @siyuExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出文档'**
  String get siyuExportTitle;

  /// No description provided for @siyuExportTxt.
  ///
  /// In zh, this message translates to:
  /// **'纯文本 (.txt)'**
  String get siyuExportTxt;

  /// No description provided for @siyuExportSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出文档'**
  String get siyuExportSaveTitle;

  /// No description provided for @siyuExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出: {path}'**
  String siyuExported(String path);

  /// No description provided for @siyuPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'开始书写...'**
  String get siyuPlaceholder;

  /// No description provided for @siyuWelcomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'思宇'**
  String get siyuWelcomeTitle;

  /// No description provided for @siyuWelcomeDesc.
  ///
  /// In zh, this message translates to:
  /// **'富文本文档编辑器'**
  String get siyuWelcomeDesc;

  /// No description provided for @siyuBtnNewProject.
  ///
  /// In zh, this message translates to:
  /// **'新建项目'**
  String get siyuBtnNewProject;

  /// No description provided for @siyuBtnSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get siyuBtnSave;

  /// No description provided for @siyuBtnInsertImage.
  ///
  /// In zh, this message translates to:
  /// **'插入图片'**
  String get siyuBtnInsertImage;

  /// No description provided for @siyuBtnExport.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get siyuBtnExport;

  /// No description provided for @siyuStatusReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get siyuStatusReady;

  /// No description provided for @siyuImageNotFound.
  ///
  /// In zh, this message translates to:
  /// **'图片不存在: {path}'**
  String siyuImageNotFound(String path);

  /// No description provided for @siyuImageLoading.
  ///
  /// In zh, this message translates to:
  /// **'图片加载中...'**
  String get siyuImageLoading;

  /// No description provided for @formulaOcrName.
  ///
  /// In zh, this message translates to:
  /// **'公式 OCR'**
  String get formulaOcrName;

  /// No description provided for @formulaOcrDesc.
  ///
  /// In zh, this message translates to:
  /// **'图片识别文字与数学公式 (Pix2Text)'**
  String get formulaOcrDesc;

  /// No description provided for @formulaOcrModeTextFormula.
  ///
  /// In zh, this message translates to:
  /// **'文字+公式'**
  String get formulaOcrModeTextFormula;

  /// No description provided for @formulaOcrModeText.
  ///
  /// In zh, this message translates to:
  /// **'纯文字'**
  String get formulaOcrModeText;

  /// No description provided for @formulaOcrModeFormula.
  ///
  /// In zh, this message translates to:
  /// **'纯公式'**
  String get formulaOcrModeFormula;

  /// No description provided for @formulaOcrPickImage.
  ///
  /// In zh, this message translates to:
  /// **'选择要识别的图片'**
  String get formulaOcrPickImage;

  /// No description provided for @formulaOcrNeedApiKey.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中配置 API Key'**
  String get formulaOcrNeedApiKey;

  /// No description provided for @formulaOcrNeedImage.
  ///
  /// In zh, this message translates to:
  /// **'请先上传图片'**
  String get formulaOcrNeedImage;

  /// No description provided for @formulaOcrFailed.
  ///
  /// In zh, this message translates to:
  /// **'识别失败: {error}'**
  String formulaOcrFailed(String error);

  /// No description provided for @formulaOcrExportMd.
  ///
  /// In zh, this message translates to:
  /// **'导出 Markdown'**
  String get formulaOcrExportMd;

  /// No description provided for @formulaOcrExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出: {path}'**
  String formulaOcrExported(String path);

  /// No description provided for @formulaOcrPandocMissing.
  ///
  /// In zh, this message translates to:
  /// **'Pandoc 未配置'**
  String get formulaOcrPandocMissing;

  /// No description provided for @formulaOcrPandocHint.
  ///
  /// In zh, this message translates to:
  /// **'导出 Word 需要 Pandoc，当前未检测到。\n是否降级为导出 Markdown？\n\n（可在 设置 → 工具路径 中配置 Pandoc）'**
  String get formulaOcrPandocHint;

  /// No description provided for @formulaOcrExportMdBtn.
  ///
  /// In zh, this message translates to:
  /// **'导出 MD'**
  String get formulaOcrExportMdBtn;

  /// No description provided for @formulaOcrExportWord.
  ///
  /// In zh, this message translates to:
  /// **'导出 Word'**
  String get formulaOcrExportWord;

  /// No description provided for @formulaOcrPandocFailed.
  ///
  /// In zh, this message translates to:
  /// **'Pandoc 转换失败: {error}'**
  String formulaOcrPandocFailed(String error);

  /// No description provided for @formulaOcrExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败: {error}'**
  String formulaOcrExportFailed(String error);

  /// No description provided for @formulaOcrSectionImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get formulaOcrSectionImage;

  /// No description provided for @formulaOcrUploadImage.
  ///
  /// In zh, this message translates to:
  /// **'上传图片'**
  String get formulaOcrUploadImage;

  /// No description provided for @formulaOcrSectionMode.
  ///
  /// In zh, this message translates to:
  /// **'识别模式'**
  String get formulaOcrSectionMode;

  /// No description provided for @formulaOcrRecognizing.
  ///
  /// In zh, this message translates to:
  /// **'识别中...'**
  String get formulaOcrRecognizing;

  /// No description provided for @formulaOcrStartRecognize.
  ///
  /// In zh, this message translates to:
  /// **'开始识别'**
  String get formulaOcrStartRecognize;

  /// No description provided for @formulaOcrSectionResult.
  ///
  /// In zh, this message translates to:
  /// **'识别结果'**
  String get formulaOcrSectionResult;

  /// No description provided for @formulaOcrCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get formulaOcrCopy;

  /// No description provided for @formulaOcrResultPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'识别结果将在此处显示'**
  String get formulaOcrResultPlaceholder;

  /// No description provided for @formulaOcrCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get formulaOcrCopied;

  /// No description provided for @formulaOcrSubmitFailed.
  ///
  /// In zh, this message translates to:
  /// **'提交任务失败'**
  String get formulaOcrSubmitFailed;

  /// No description provided for @formulaOcrRecognizeFailed.
  ///
  /// In zh, this message translates to:
  /// **'识别失败'**
  String get formulaOcrRecognizeFailed;

  /// No description provided for @formulaOcrTimeout.
  ///
  /// In zh, this message translates to:
  /// **'识别超时，请稍后重试'**
  String get formulaOcrTimeout;

  /// No description provided for @formulaOcrSaveConfig.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get formulaOcrSaveConfig;

  /// No description provided for @formulaOcrRegisterKey.
  ///
  /// In zh, this message translates to:
  /// **'注册获取 Key'**
  String get formulaOcrRegisterKey;

  /// No description provided for @formulaOcrFreeQuota.
  ///
  /// In zh, this message translates to:
  /// **'每日免费 10,000 字符额度'**
  String get formulaOcrFreeQuota;

  /// No description provided for @formulaOcrCategory.
  ///
  /// In zh, this message translates to:
  /// **'AI'**
  String get formulaOcrCategory;

  /// No description provided for @paddleOcrName.
  ///
  /// In zh, this message translates to:
  /// **'PaddleOCR'**
  String get paddleOcrName;

  /// No description provided for @paddleOcrDesc.
  ///
  /// In zh, this message translates to:
  /// **'通用 OCR 与文档解析 (PaddleOCR 官方 API)'**
  String get paddleOcrDesc;

  /// No description provided for @paddleOcrCategory.
  ///
  /// In zh, this message translates to:
  /// **'AI'**
  String get paddleOcrCategory;

  /// No description provided for @paddleOcrModeOcr.
  ///
  /// In zh, this message translates to:
  /// **'OCR 识别'**
  String get paddleOcrModeOcr;

  /// No description provided for @paddleOcrModeDoc.
  ///
  /// In zh, this message translates to:
  /// **'文档解析'**
  String get paddleOcrModeDoc;

  /// No description provided for @paddleOcrModeOcrDesc.
  ///
  /// In zh, this message translates to:
  /// **'PP-OCRv6 · 通用文字识别'**
  String get paddleOcrModeOcrDesc;

  /// No description provided for @paddleOcrModeDocDesc.
  ///
  /// In zh, this message translates to:
  /// **'PaddleOCR-VL · Markdown 输出'**
  String get paddleOcrModeDocDesc;

  /// No description provided for @paddleOcrPickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择图片或 PDF 文件'**
  String get paddleOcrPickFile;

  /// No description provided for @paddleOcrNeedPython.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中配置 Python 路径'**
  String get paddleOcrNeedPython;

  /// No description provided for @paddleOcrNeedToken.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中配置 Access Token'**
  String get paddleOcrNeedToken;

  /// No description provided for @paddleOcrNeedFile.
  ///
  /// In zh, this message translates to:
  /// **'请先选择文件'**
  String get paddleOcrNeedFile;

  /// No description provided for @paddleOcrSubmitting.
  ///
  /// In zh, this message translates to:
  /// **'正在提交任务...'**
  String get paddleOcrSubmitting;

  /// No description provided for @paddleOcrCalling.
  ///
  /// In zh, this message translates to:
  /// **'正在调用 PaddleOCR API...'**
  String get paddleOcrCalling;

  /// No description provided for @paddleOcrExecFailed.
  ///
  /// In zh, this message translates to:
  /// **'执行失败: {error}'**
  String paddleOcrExecFailed(String error);

  /// No description provided for @paddleOcrNoResult.
  ///
  /// In zh, this message translates to:
  /// **'未返回识别结果'**
  String get paddleOcrNoResult;

  /// No description provided for @paddleOcrError.
  ///
  /// In zh, this message translates to:
  /// **'执行出错: {error}'**
  String paddleOcrError(String error);

  /// No description provided for @paddleOcrSectionInput.
  ///
  /// In zh, this message translates to:
  /// **'输入文件'**
  String get paddleOcrSectionInput;

  /// No description provided for @paddleOcrSelectFile.
  ///
  /// In zh, this message translates to:
  /// **'选择图片或 PDF'**
  String get paddleOcrSelectFile;

  /// No description provided for @paddleOcrSectionMode.
  ///
  /// In zh, this message translates to:
  /// **'任务模式'**
  String get paddleOcrSectionMode;

  /// No description provided for @paddleOcrProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中...'**
  String get paddleOcrProcessing;

  /// No description provided for @paddleOcrStart.
  ///
  /// In zh, this message translates to:
  /// **'开始识别'**
  String get paddleOcrStart;

  /// No description provided for @paddleOcrModelOcr.
  ///
  /// In zh, this message translates to:
  /// **'OCR 模型'**
  String get paddleOcrModelOcr;

  /// No description provided for @paddleOcrModelDoc.
  ///
  /// In zh, this message translates to:
  /// **'解析模型'**
  String get paddleOcrModelDoc;

  /// No description provided for @paddleOcrAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'高级选项'**
  String get paddleOcrAdvanced;

  /// No description provided for @paddleOcrRotateCorrect.
  ///
  /// In zh, this message translates to:
  /// **'文档方向矫正'**
  String get paddleOcrRotateCorrect;

  /// No description provided for @paddleOcrUnwarp.
  ///
  /// In zh, this message translates to:
  /// **'扭曲矫正'**
  String get paddleOcrUnwarp;

  /// No description provided for @paddleOcrChartRecognize.
  ///
  /// In zh, this message translates to:
  /// **'图表识别'**
  String get paddleOcrChartRecognize;

  /// No description provided for @paddleOcrResultDoc.
  ///
  /// In zh, this message translates to:
  /// **'文档解析结果 (Markdown)'**
  String get paddleOcrResultDoc;

  /// No description provided for @paddleOcrResultOcr.
  ///
  /// In zh, this message translates to:
  /// **'OCR 识别结果'**
  String get paddleOcrResultOcr;

  /// No description provided for @paddleOcrResultPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'识别结果将在此处显示'**
  String get paddleOcrResultPlaceholder;

  /// No description provided for @paddleOcrFileHint.
  ///
  /// In zh, this message translates to:
  /// **'支持图片 (PNG/JPG/BMP/TIFF) 和 PDF 文件'**
  String get paddleOcrFileHint;

  /// No description provided for @paddleOcrSaveConfig.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get paddleOcrSaveConfig;

  /// No description provided for @paddleOcrTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get paddleOcrTesting;

  /// No description provided for @paddleOcrTestConn.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get paddleOcrTestConn;

  /// No description provided for @paddleOcrGetToken.
  ///
  /// In zh, this message translates to:
  /// **'获取 Token'**
  String get paddleOcrGetToken;

  /// No description provided for @paddleOcrApiDesc.
  ///
  /// In zh, this message translates to:
  /// **'PaddleOCR 官网免费 API，支持通用 OCR 与文档解析'**
  String get paddleOcrApiDesc;

  /// No description provided for @imageGenName.
  ///
  /// In zh, this message translates to:
  /// **'Gemini 画图'**
  String get imageGenName;

  /// No description provided for @imageGenDesc.
  ///
  /// In zh, this message translates to:
  /// **'文生图 / 图改图'**
  String get imageGenDesc;

  /// No description provided for @imageGenCategory.
  ///
  /// In zh, this message translates to:
  /// **'创作'**
  String get imageGenCategory;

  /// No description provided for @imageGenQuality1k.
  ///
  /// In zh, this message translates to:
  /// **'1K 快速'**
  String get imageGenQuality1k;

  /// No description provided for @imageGenQuality2k.
  ///
  /// In zh, this message translates to:
  /// **'2K 推荐'**
  String get imageGenQuality2k;

  /// No description provided for @imageGenQuality4k.
  ///
  /// In zh, this message translates to:
  /// **'4K 超清'**
  String get imageGenQuality4k;

  /// No description provided for @imageGenNeedConfig.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中配置 API 地址和 Key'**
  String get imageGenNeedConfig;

  /// No description provided for @imageGenNeedInput.
  ///
  /// In zh, this message translates to:
  /// **'请输入描述文字或上传参考图'**
  String get imageGenNeedInput;

  /// No description provided for @imageGenFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败: {error}'**
  String imageGenFailed(String error);

  /// No description provided for @imageGenPickRef.
  ///
  /// In zh, this message translates to:
  /// **'选择参考图片'**
  String get imageGenPickRef;

  /// No description provided for @imageGenExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出图片'**
  String get imageGenExportTitle;

  /// No description provided for @imageGenExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出: {path}'**
  String imageGenExported(String path);

  /// No description provided for @imageGenSectionDesc.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get imageGenSectionDesc;

  /// No description provided for @imageGenDescHint.
  ///
  /// In zh, this message translates to:
  /// **'描述你想生成的图片...'**
  String get imageGenDescHint;

  /// No description provided for @imageGenSectionRef.
  ///
  /// In zh, this message translates to:
  /// **'参考图（可选）'**
  String get imageGenSectionRef;

  /// No description provided for @imageGenUploadRef.
  ///
  /// In zh, this message translates to:
  /// **'上传参考图'**
  String get imageGenUploadRef;

  /// No description provided for @imageGenSectionQuality.
  ///
  /// In zh, this message translates to:
  /// **'画质'**
  String get imageGenSectionQuality;

  /// No description provided for @imageGenSectionRatio.
  ///
  /// In zh, this message translates to:
  /// **'宽高比'**
  String get imageGenSectionRatio;

  /// No description provided for @imageGenGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get imageGenGenerating;

  /// No description provided for @imageGenGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get imageGenGenerate;

  /// No description provided for @imageGenExportPng.
  ///
  /// In zh, this message translates to:
  /// **'导出 PNG'**
  String get imageGenExportPng;

  /// No description provided for @imageGenPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'生成的图片将在此处预览'**
  String get imageGenPlaceholder;

  /// No description provided for @imageGenTimeout.
  ///
  /// In zh, this message translates to:
  /// **'请求超时，请稍后重试'**
  String get imageGenTimeout;

  /// No description provided for @imageGenSaveConfig.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get imageGenSaveConfig;

  /// No description provided for @imageGenTestConn.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get imageGenTestConn;

  /// No description provided for @imageGenTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get imageGenTesting;

  /// No description provided for @modelNameFallback.
  ///
  /// In zh, this message translates to:
  /// **'未命名模型'**
  String get modelNameFallback;

  /// No description provided for @servicesSearchTab.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get servicesSearchTab;

  /// No description provided for @searchDescription.
  ///
  /// In zh, this message translates to:
  /// **'配置 AI 搜索服务后，可在对话中让模型自动调用联网搜索获取最新信息。选择一个服务并填入 API Key 即可启用。'**
  String get searchDescription;

  /// No description provided for @searchBaidu.
  ///
  /// In zh, this message translates to:
  /// **'百度智能搜索'**
  String get searchBaidu;

  /// No description provided for @searchTavilyHint.
  ///
  /// In zh, this message translates to:
  /// **'免费 1000 次/月，支持 AI 摘要'**
  String get searchTavilyHint;

  /// No description provided for @searchBraveHint.
  ///
  /// In zh, this message translates to:
  /// **'免费 2000 次/月，隐私友好'**
  String get searchBraveHint;

  /// No description provided for @searchBaiduHint.
  ///
  /// In zh, this message translates to:
  /// **'百度千帆智能搜索 API'**
  String get searchBaiduHint;

  /// No description provided for @searchConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get searchConfigured;

  /// No description provided for @searchApiKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'输入 API Key'**
  String get searchApiKeyHint;

  /// No description provided for @searchSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get searchSave;

  /// No description provided for @chatSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get chatSearch;

  /// No description provided for @chatSearchActive.
  ///
  /// In zh, this message translates to:
  /// **'搜索已启用'**
  String get chatSearchActive;

  /// No description provided for @chatSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'启用联网搜索'**
  String get chatSearchHint;

  /// No description provided for @chatSearchTitle.
  ///
  /// In zh, this message translates to:
  /// **'搜索引擎'**
  String get chatSearchTitle;

  /// No description provided for @chatSearchOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get chatSearchOff;

  /// No description provided for @chatSearchOffDesc.
  ///
  /// In zh, this message translates to:
  /// **'不使用联网搜索'**
  String get chatSearchOffDesc;

  /// No description provided for @chatSearchReady.
  ///
  /// In zh, this message translates to:
  /// **'已就绪，可选择'**
  String get chatSearchReady;

  /// No description provided for @chatSearchNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置 API Key，请前往服务页设置'**
  String get chatSearchNotConfigured;

  /// No description provided for @searchTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get searchTestConnection;

  /// No description provided for @searchTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get searchTesting;

  /// No description provided for @searchTestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，API Key 有效'**
  String get searchTestSuccess;

  /// No description provided for @petCatGray.
  ///
  /// In zh, this message translates to:
  /// **'灰色小猫'**
  String get petCatGray;

  /// No description provided for @petCatOrange.
  ///
  /// In zh, this message translates to:
  /// **'橘色小猫'**
  String get petCatOrange;

  /// No description provided for @petCatWhite.
  ///
  /// In zh, this message translates to:
  /// **'白色小猫'**
  String get petCatWhite;

  /// No description provided for @petTitle.
  ///
  /// In zh, this message translates to:
  /// **'宠物设置'**
  String get petTitle;

  /// No description provided for @petShow.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get petShow;

  /// No description provided for @petSkinSection.
  ///
  /// In zh, this message translates to:
  /// **'精灵皮肤'**
  String get petSkinSection;

  /// No description provided for @petModelSection.
  ///
  /// In zh, this message translates to:
  /// **'宠物模型 (AI)'**
  String get petModelSection;

  /// No description provided for @petModelHint.
  ///
  /// In zh, this message translates to:
  /// **'选择宠物使用的 AI 模型'**
  String get petModelHint;

  /// No description provided for @petModelLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载模型失败: {error}'**
  String petModelLoadFailed(String error);

  /// No description provided for @petTtsSection.
  ///
  /// In zh, this message translates to:
  /// **'语音合成'**
  String get petTtsSection;

  /// No description provided for @petTtsSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get petTtsSystem;

  /// No description provided for @petTtsVolcano.
  ///
  /// In zh, this message translates to:
  /// **'火山'**
  String get petTtsVolcano;

  /// No description provided for @petTtsAppId.
  ///
  /// In zh, this message translates to:
  /// **'AppID'**
  String get petTtsAppId;

  /// No description provided for @petTtsAppIdHint.
  ///
  /// In zh, this message translates to:
  /// **'App ID'**
  String get petTtsAppIdHint;

  /// No description provided for @petTtsToken.
  ///
  /// In zh, this message translates to:
  /// **'Token'**
  String get petTtsToken;

  /// No description provided for @petTtsTokenHint.
  ///
  /// In zh, this message translates to:
  /// **'Access Token'**
  String get petTtsTokenHint;

  /// No description provided for @petTtsVoiceType.
  ///
  /// In zh, this message translates to:
  /// **'音色'**
  String get petTtsVoiceType;

  /// No description provided for @petTtsVoiceTypeHint.
  ///
  /// In zh, this message translates to:
  /// **'voice_type (克隆音色 ID)'**
  String get petTtsVoiceTypeHint;

  /// No description provided for @petTtsSave.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get petTtsSave;

  /// No description provided for @petTtsSaved.
  ///
  /// In zh, this message translates to:
  /// **'火山 TTS 配置已保存'**
  String get petTtsSaved;

  /// No description provided for @petTtsReady.
  ///
  /// In zh, this message translates to:
  /// **'✅ 配置完整'**
  String get petTtsReady;

  /// No description provided for @petTtsIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'⚠️ 请填写三项必填'**
  String get petTtsIncomplete;

  /// No description provided for @petTtsSpeedLabel.
  ///
  /// In zh, this message translates to:
  /// **'语速({value})'**
  String petTtsSpeedLabel(int value);

  /// No description provided for @petTtsLoudnessLabel.
  ///
  /// In zh, this message translates to:
  /// **'音量({value})'**
  String petTtsLoudnessLabel(int value);

  /// No description provided for @petTtsCredentialHint.
  ///
  /// In zh, this message translates to:
  /// **'凭证获取: 火山引擎控制台 → 语音合成 → 音色克隆\n参考: github.com/Radiant303/astrbot_plugin_clonetts'**
  String get petTtsCredentialHint;

  /// No description provided for @petBehaviorSection.
  ///
  /// In zh, this message translates to:
  /// **'回复行为'**
  String get petBehaviorSection;

  /// No description provided for @petTtsThresholdLabel.
  ///
  /// In zh, this message translates to:
  /// **'语音阈值({value}字)'**
  String petTtsThresholdLabel(int value);

  /// No description provided for @petTtsThresholdHint.
  ///
  /// In zh, this message translates to:
  /// **'≤{value}字语音，超出文本气泡'**
  String petTtsThresholdHint(int value);

  /// No description provided for @petBubbleDismissLabel.
  ///
  /// In zh, this message translates to:
  /// **'气泡倒计时({value}s)'**
  String petBubbleDismissLabel(int value);

  /// No description provided for @petBubbleDismissManual.
  ///
  /// In zh, this message translates to:
  /// **'手动关闭气泡'**
  String get petBubbleDismissManual;

  /// No description provided for @petBubbleDismissAuto.
  ///
  /// In zh, this message translates to:
  /// **'{value}秒后自动关闭气泡'**
  String petBubbleDismissAuto(int value);

  /// No description provided for @petCommandSection.
  ///
  /// In zh, this message translates to:
  /// **'自定义右键指令'**
  String get petCommandSection;

  /// No description provided for @petCommandHint.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义指令后会出现在右键菜单中'**
  String get petCommandHint;

  /// No description provided for @petCommandAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加指令'**
  String get petCommandAdd;

  /// No description provided for @petCommandAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义指令'**
  String get petCommandAddTitle;

  /// No description provided for @petCommandEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑指令'**
  String get petCommandEditTitle;

  /// No description provided for @petCommandNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'指令名称'**
  String get petCommandNameLabel;

  /// No description provided for @petCommandNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：帮我优化'**
  String get petCommandNameHint;

  /// No description provided for @petCommandPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词'**
  String get petCommandPromptLabel;

  /// No description provided for @petCommandPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：请帮我优化以下代码，提升性能和可读性：'**
  String get petCommandPromptHint;

  /// No description provided for @petTestSection.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get petTestSection;

  /// No description provided for @petTestShort.
  ///
  /// In zh, this message translates to:
  /// **'短语音'**
  String get petTestShort;

  /// No description provided for @petTestLong.
  ///
  /// In zh, this message translates to:
  /// **'长文本'**
  String get petTestLong;

  /// No description provided for @petDebugEvents.
  ///
  /// In zh, this message translates to:
  /// **'事件'**
  String get petDebugEvents;

  /// No description provided for @petDebugAnimations.
  ///
  /// In zh, this message translates to:
  /// **'动画'**
  String get petDebugAnimations;

  /// No description provided for @petDebugState.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get petDebugState;

  /// No description provided for @petBubbleThinking.
  ///
  /// In zh, this message translates to:
  /// **'小猫思考中...'**
  String get petBubbleThinking;

  /// No description provided for @petBubbleTitle.
  ///
  /// In zh, this message translates to:
  /// **'小猫说'**
  String get petBubbleTitle;

  /// No description provided for @petBubbleGenerating.
  ///
  /// In zh, this message translates to:
  /// **'正在生成回答...'**
  String get petBubbleGenerating;

  /// No description provided for @petBubbleClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get petBubbleClose;

  /// No description provided for @petBubbleFeedAll.
  ///
  /// In zh, this message translates to:
  /// **'投喂全文给小猫'**
  String get petBubbleFeedAll;

  /// No description provided for @petBubbleFeedFollow.
  ///
  /// In zh, this message translates to:
  /// **'追问: {label}'**
  String petBubbleFeedFollow(String label);

  /// No description provided for @petBubbleFeedSelected.
  ///
  /// In zh, this message translates to:
  /// **'投喂小猫: {label}'**
  String petBubbleFeedSelected(String label);

  /// No description provided for @petNoModel.
  ///
  /// In zh, this message translates to:
  /// **'喵~ 我还没有绑定模型，请在宠物设置中选择一个模型。'**
  String get petNoModel;

  /// No description provided for @petError.
  ///
  /// In zh, this message translates to:
  /// **'喵呜...出错了: {error}'**
  String petError(String error);

  /// No description provided for @petContextHide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏宠物'**
  String get petContextHide;

  /// No description provided for @petTestShortText.
  ///
  /// In zh, this message translates to:
  /// **'你好呀主人！'**
  String get petTestShortText;

  /// No description provided for @petTestLongText.
  ///
  /// In zh, this message translates to:
  /// **'主人你好，Flutter中Widget是不可变的，每次状态变化都会创建新的Widget树，这就是setState触发rebuild的原因。'**
  String get petTestLongText;

  /// No description provided for @petPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'宠物'**
  String get petPageTitle;

  /// No description provided for @petTabSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get petTabSettings;

  /// No description provided for @petTabShop.
  ///
  /// In zh, this message translates to:
  /// **'商店'**
  String get petTabShop;

  /// No description provided for @petTabAchievements.
  ///
  /// In zh, this message translates to:
  /// **'成就'**
  String get petTabAchievements;

  /// No description provided for @petShopTitle.
  ///
  /// In zh, this message translates to:
  /// **'商品'**
  String get petShopTitle;

  /// No description provided for @petInventoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'背包'**
  String get petInventoryTitle;

  /// No description provided for @petInventoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'空空如也~'**
  String get petInventoryEmpty;

  /// No description provided for @petStatusTitle.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get petStatusTitle;

  /// No description provided for @petStatusSatiety.
  ///
  /// In zh, this message translates to:
  /// **'饱腹度'**
  String get petStatusSatiety;

  /// No description provided for @petStatusHappiness.
  ///
  /// In zh, this message translates to:
  /// **'心情值'**
  String get petStatusHappiness;

  /// No description provided for @petStatusDecayHint.
  ///
  /// In zh, this message translates to:
  /// **'每小时饱腹 -5、心情 -3\n投喂食物可恢复'**
  String get petStatusDecayHint;

  /// No description provided for @petShopBuy.
  ///
  /// In zh, this message translates to:
  /// **'购买'**
  String get petShopBuy;

  /// No description provided for @petShopBought.
  ///
  /// In zh, this message translates to:
  /// **'购买了 {name}！'**
  String petShopBought(String name);

  /// No description provided for @petShopNoCoins.
  ///
  /// In zh, this message translates to:
  /// **'宠物币不足~'**
  String get petShopNoCoins;

  /// No description provided for @petShopSatiety.
  ///
  /// In zh, this message translates to:
  /// **'饱腹+{value}'**
  String petShopSatiety(int value);

  /// No description provided for @petShopHappiness.
  ///
  /// In zh, this message translates to:
  /// **'心情+{value}'**
  String petShopHappiness(int value);

  /// No description provided for @petShopEffect.
  ///
  /// In zh, this message translates to:
  /// **'特效: {effect}'**
  String petShopEffect(String effect);

  /// No description provided for @petAchievementsTitle.
  ///
  /// In zh, this message translates to:
  /// **'成就'**
  String get petAchievementsTitle;

  /// No description provided for @petAchievementsProgress.
  ///
  /// In zh, this message translates to:
  /// **'{unlocked} / {total}'**
  String petAchievementsProgress(int unlocked, int total);

  /// No description provided for @petFeedTitle.
  ///
  /// In zh, this message translates to:
  /// **'投喂小猫'**
  String get petFeedTitle;

  /// No description provided for @petFeedButton.
  ///
  /// In zh, this message translates to:
  /// **'投喂'**
  String get petFeedButton;

  /// No description provided for @petFeedButtonEmpty.
  ///
  /// In zh, this message translates to:
  /// **'投喂 (背包空)'**
  String get petFeedButtonEmpty;

  /// No description provided for @petFeedEmpty.
  ///
  /// In zh, this message translates to:
  /// **'背包空空如也~ 去商店买点食物吧！'**
  String get petFeedEmpty;

  /// No description provided for @petFeedStat.
  ///
  /// In zh, this message translates to:
  /// **'x{quantity}  饱腹+{satiety} 心情+{happiness}'**
  String petFeedStat(int quantity, int satiety, int happiness);

  /// No description provided for @petFeedClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get petFeedClose;

  /// No description provided for @petCoinReward.
  ///
  /// In zh, this message translates to:
  /// **'+{amount} 宠物币~'**
  String petCoinReward(int amount);

  /// No description provided for @petFoodBanana.
  ///
  /// In zh, this message translates to:
  /// **'香蕉'**
  String get petFoodBanana;

  /// No description provided for @petFoodBananaDesc.
  ///
  /// In zh, this message translates to:
  /// **'软糯香甜，猫猫也爱'**
  String get petFoodBananaDesc;

  /// No description provided for @petFoodApple.
  ///
  /// In zh, this message translates to:
  /// **'苹果'**
  String get petFoodApple;

  /// No description provided for @petFoodAppleDesc.
  ///
  /// In zh, this message translates to:
  /// **'一天一苹果，猫猫不找我'**
  String get petFoodAppleDesc;

  /// No description provided for @petFoodPurpleGrape.
  ///
  /// In zh, this message translates to:
  /// **'紫葡萄'**
  String get petFoodPurpleGrape;

  /// No description provided for @petFoodPurpleGrapeDesc.
  ///
  /// In zh, this message translates to:
  /// **'颗颗饱满的甜蜜'**
  String get petFoodPurpleGrapeDesc;

  /// No description provided for @petFoodGreenGrape.
  ///
  /// In zh, this message translates to:
  /// **'绿葡萄'**
  String get petFoodGreenGrape;

  /// No description provided for @petFoodGreenGrapeDesc.
  ///
  /// In zh, this message translates to:
  /// **'清爽酸甜，开胃小食'**
  String get petFoodGreenGrapeDesc;

  /// No description provided for @petFoodPineapple.
  ///
  /// In zh, this message translates to:
  /// **'菠萝'**
  String get petFoodPineapple;

  /// No description provided for @petFoodPineappleDesc.
  ///
  /// In zh, this message translates to:
  /// **'热带风味，酸甜爆汁'**
  String get petFoodPineappleDesc;

  /// No description provided for @petFoodKiwi.
  ///
  /// In zh, this message translates to:
  /// **'猕猴桃'**
  String get petFoodKiwi;

  /// No description provided for @petFoodKiwiDesc.
  ///
  /// In zh, this message translates to:
  /// **'维C满满的小绿球'**
  String get petFoodKiwiDesc;

  /// No description provided for @petFoodCherry.
  ///
  /// In zh, this message translates to:
  /// **'樱桃'**
  String get petFoodCherry;

  /// No description provided for @petFoodCherryDesc.
  ///
  /// In zh, this message translates to:
  /// **'小巧精致，猫猫当玩具拍'**
  String get petFoodCherryDesc;

  /// No description provided for @petFoodStrawberry.
  ///
  /// In zh, this message translates to:
  /// **'草莓'**
  String get petFoodStrawberry;

  /// No description provided for @petFoodStrawberryDesc.
  ///
  /// In zh, this message translates to:
  /// **'红彤彤的快乐果实'**
  String get petFoodStrawberryDesc;

  /// No description provided for @petFoodCarrot.
  ///
  /// In zh, this message translates to:
  /// **'胡萝卜'**
  String get petFoodCarrot;

  /// No description provided for @petFoodCarrotDesc.
  ///
  /// In zh, this message translates to:
  /// **'对眼睛好，虽然猫不在乎'**
  String get petFoodCarrotDesc;

  /// No description provided for @petFoodTomato.
  ///
  /// In zh, this message translates to:
  /// **'番茄'**
  String get petFoodTomato;

  /// No description provided for @petFoodTomatoDesc.
  ///
  /// In zh, this message translates to:
  /// **'水灵灵的新鲜番茄'**
  String get petFoodTomatoDesc;

  /// No description provided for @petFoodEggplant.
  ///
  /// In zh, this message translates to:
  /// **'茄子'**
  String get petFoodEggplant;

  /// No description provided for @petFoodEggplantDesc.
  ///
  /// In zh, this message translates to:
  /// **'紫色的健康蔬菜'**
  String get petFoodEggplantDesc;

  /// No description provided for @petFoodPumpkin.
  ///
  /// In zh, this message translates to:
  /// **'南瓜'**
  String get petFoodPumpkin;

  /// No description provided for @petFoodPumpkinDesc.
  ///
  /// In zh, this message translates to:
  /// **'大大的南瓜，够吃好久'**
  String get petFoodPumpkinDesc;

  /// No description provided for @petFoodBroccoli.
  ///
  /// In zh, this message translates to:
  /// **'花菜'**
  String get petFoodBroccoli;

  /// No description provided for @petFoodBroccoliDesc.
  ///
  /// In zh, this message translates to:
  /// **'像一棵小树，营养丰富'**
  String get petFoodBroccoliDesc;

  /// No description provided for @petFoodGarlic.
  ///
  /// In zh, this message translates to:
  /// **'洋蒜'**
  String get petFoodGarlic;

  /// No description provided for @petFoodGarlicDesc.
  ///
  /// In zh, this message translates to:
  /// **'猫猫闻了打喷嚏'**
  String get petFoodGarlicDesc;

  /// No description provided for @petFoodPepper.
  ///
  /// In zh, this message translates to:
  /// **'辣椒'**
  String get petFoodPepper;

  /// No description provided for @petFoodPepperDesc.
  ///
  /// In zh, this message translates to:
  /// **'呼~辣到跳起来！'**
  String get petFoodPepperDesc;

  /// No description provided for @petFoodMushroom.
  ///
  /// In zh, this message translates to:
  /// **'蘑菇'**
  String get petFoodMushroom;

  /// No description provided for @petFoodMushroomDesc.
  ///
  /// In zh, this message translates to:
  /// **'鲜美的菌菇，猫猫意外喜欢'**
  String get petFoodMushroomDesc;

  /// No description provided for @petFoodHam.
  ///
  /// In zh, this message translates to:
  /// **'火腿'**
  String get petFoodHam;

  /// No description provided for @petFoodHamDesc.
  ///
  /// In zh, this message translates to:
  /// **'浓郁肉香，猫猫口水直流'**
  String get petFoodHamDesc;

  /// No description provided for @petFoodChicken.
  ///
  /// In zh, this message translates to:
  /// **'鸡腿'**
  String get petFoodChicken;

  /// No description provided for @petFoodChickenDesc.
  ///
  /// In zh, this message translates to:
  /// **'外焦里嫩的大鸡腿'**
  String get petFoodChickenDesc;

  /// No description provided for @petFoodFish.
  ///
  /// In zh, this message translates to:
  /// **'鱼'**
  String get petFoodFish;

  /// No description provided for @petFoodFishDesc.
  ///
  /// In zh, this message translates to:
  /// **'猫猫的最爱！没有之一'**
  String get petFoodFishDesc;

  /// No description provided for @petFoodLobster.
  ///
  /// In zh, this message translates to:
  /// **'大龙虾'**
  String get petFoodLobster;

  /// No description provided for @petFoodLobsterDesc.
  ///
  /// In zh, this message translates to:
  /// **'顶级海鲜盛宴，猫猫疯狂'**
  String get petFoodLobsterDesc;

  /// No description provided for @petAchieveFirstCoin.
  ///
  /// In zh, this message translates to:
  /// **'第一桶金'**
  String get petAchieveFirstCoin;

  /// No description provided for @petAchieveFirstCoinDesc.
  ///
  /// In zh, this message translates to:
  /// **'获得第一枚宠物币'**
  String get petAchieveFirstCoinDesc;

  /// No description provided for @petAchieveRich100.
  ///
  /// In zh, this message translates to:
  /// **'小有积蓄'**
  String get petAchieveRich100;

  /// No description provided for @petAchieveRich100Desc.
  ///
  /// In zh, this message translates to:
  /// **'累计获得 100 宠物币'**
  String get petAchieveRich100Desc;

  /// No description provided for @petAchieveRich500.
  ///
  /// In zh, this message translates to:
  /// **'小富翁'**
  String get petAchieveRich500;

  /// No description provided for @petAchieveRich500Desc.
  ///
  /// In zh, this message translates to:
  /// **'累计获得 500 宠物币'**
  String get petAchieveRich500Desc;

  /// No description provided for @petAchieveRich2000.
  ///
  /// In zh, this message translates to:
  /// **'宠物大亨'**
  String get petAchieveRich2000;

  /// No description provided for @petAchieveRich2000Desc.
  ///
  /// In zh, this message translates to:
  /// **'累计获得 2000 宠物币'**
  String get petAchieveRich2000Desc;

  /// No description provided for @petAchieveFirstFeed.
  ///
  /// In zh, this message translates to:
  /// **'初次投喂'**
  String get petAchieveFirstFeed;

  /// No description provided for @petAchieveFirstFeedDesc.
  ///
  /// In zh, this message translates to:
  /// **'第一次喂食小猫'**
  String get petAchieveFirstFeedDesc;

  /// No description provided for @petAchieveFeed10.
  ///
  /// In zh, this message translates to:
  /// **'尽职铲屎官'**
  String get petAchieveFeed10;

  /// No description provided for @petAchieveFeed10Desc.
  ///
  /// In zh, this message translates to:
  /// **'累计投喂 10 次'**
  String get petAchieveFeed10Desc;

  /// No description provided for @petAchieveFeed50.
  ///
  /// In zh, this message translates to:
  /// **'猫奴认证'**
  String get petAchieveFeed50;

  /// No description provided for @petAchieveFeed50Desc.
  ///
  /// In zh, this message translates to:
  /// **'累计投喂 50 次'**
  String get petAchieveFeed50Desc;

  /// No description provided for @petAchieveFullBelly.
  ///
  /// In zh, this message translates to:
  /// **'吃撑了'**
  String get petAchieveFullBelly;

  /// No description provided for @petAchieveFullBellyDesc.
  ///
  /// In zh, this message translates to:
  /// **'饱腹度达到 100'**
  String get petAchieveFullBellyDesc;

  /// No description provided for @petAchieveHappyMax.
  ///
  /// In zh, this message translates to:
  /// **'快乐猫猫'**
  String get petAchieveHappyMax;

  /// No description provided for @petAchieveHappyMaxDesc.
  ///
  /// In zh, this message translates to:
  /// **'心情值达到 100'**
  String get petAchieveHappyMaxDesc;

  /// No description provided for @petAchieveShopper.
  ///
  /// In zh, this message translates to:
  /// **'购物达人'**
  String get petAchieveShopper;

  /// No description provided for @petAchieveShopperDesc.
  ///
  /// In zh, this message translates to:
  /// **'在商店购买 20 次'**
  String get petAchieveShopperDesc;

  /// No description provided for @petAchieveChat1m.
  ///
  /// In zh, this message translates to:
  /// **'话痨'**
  String get petAchieveChat1m;

  /// No description provided for @petAchieveChat1mDesc.
  ///
  /// In zh, this message translates to:
  /// **'累计消耗 100万 tokens'**
  String get petAchieveChat1mDesc;

  /// No description provided for @petAchieveChat50m.
  ///
  /// In zh, this message translates to:
  /// **'深度用户'**
  String get petAchieveChat50m;

  /// No description provided for @petAchieveChat50mDesc.
  ///
  /// In zh, this message translates to:
  /// **'累计消耗 5000万 tokens'**
  String get petAchieveChat50mDesc;

  /// No description provided for @petAchieveChat100m.
  ///
  /// In zh, this message translates to:
  /// **'AI 重度依赖'**
  String get petAchieveChat100m;

  /// No description provided for @petAchieveChat100mDesc.
  ///
  /// In zh, this message translates to:
  /// **'累计消耗 1亿 tokens'**
  String get petAchieveChat100mDesc;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

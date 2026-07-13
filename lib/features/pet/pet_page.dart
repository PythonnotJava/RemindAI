import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_ext.dart';
import '../../l10n/app_localizations.dart';
import '../../core/isolate/compute_service.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/llm_provider.dart';
import '../../core/pet/pet.dart';
import '../../core/tts/tts_service.dart';
import '../../providers/database_provider.dart';
import 'widgets/floating_pet.dart';
import 'widgets/food_sprite.dart';

/// 宠物标签页 — 设置 + 商店 + 成就
class PetPage extends ConsumerStatefulWidget {
  const PetPage({super.key});

  @override
  ConsumerState<PetPage> createState() => _PetPageState();
}

class _PetPageState extends ConsumerState<PetPage>
    with SingleTickerProviderStateMixin {
  final _controller = FloatingPetController.instance;
  final _chatService = PetChatService.instance;
  final _economy = PetEconomy.instance;
  late List<PetSpriteSheet> _availableSprites;
  int _selectedSpriteIndex = 0;
  late final TabController _tabController;

  // 火山 TTS 配置输入控制器
  late final TextEditingController _volcanoAppIdCtrl;
  late final TextEditingController _volcanoTokenCtrl;
  late final TextEditingController _volcanoVoiceTypeCtrl;

  PetEngine get _engine => _controller.engine;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _availableSprites = PetRegistry.instance.all;
    final currentId = _engine.sprite.id;
    _selectedSpriteIndex = _availableSprites.indexWhere(
      (s) => s.id == currentId,
    );
    if (_selectedSpriteIndex < 0) _selectedSpriteIndex = 0;

    // 初始化火山 TTS 输入框
    final tts = TtsService.instance.config;
    _volcanoAppIdCtrl = TextEditingController(text: tts.volcanoAppId);
    _volcanoTokenCtrl = TextEditingController(text: tts.volcanoToken);
    _volcanoVoiceTypeCtrl = TextEditingController(text: tts.volcanoVoiceType);

    // 监听经济系统变化
    _economy.addListener(_onEconomyChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _volcanoAppIdCtrl.dispose();
    _volcanoTokenCtrl.dispose();
    _volcanoVoiceTypeCtrl.dispose();
    _economy.removeListener(_onEconomyChanged);
    super.dispose();
  }

  void _onEconomyChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = context.s;

    // 注入国际化文本到 service 层
    _chatService.noModelText = s.petNoModel;
    _chatService.formatError = (e) => s.petError(e);
    _chatService.formatCoinReward = (amount) => s.petCoinReward(amount);

    return Column(
      children: [
        // 顶部状态栏：宠物币 + Tab
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              Icon(Icons.pets, size: 22, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                s.petPageTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              // 宠物币显示
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      size: 14,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_economy.coins}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 饱腹度 & 心情
              _buildMiniStat(
                Icons.fastfood,
                _economy.satiety,
                Colors.orange,
                colorScheme,
              ),
              const SizedBox(width: 8),
              _buildMiniStat(
                Icons.favorite,
                _economy.happiness,
                Colors.pink,
                colorScheme,
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: _controller.visibleNotifier,
                builder: (context, visible, _) => Switch(
                  value: visible,
                  onChanged: (_) => _controller.toggleVisibility(),
                ),
              ),
              Text(s.petShow, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        // TabBar
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: s.petTabSettings),
            Tab(text: s.petTabShop),
            Tab(text: s.petTabAchievements),
          ],
        ),
        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildSettings(theme, colorScheme),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _buildDebugPanel(theme, colorScheme),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: _buildShopTab(theme, colorScheme),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: _buildAchievementsTab(theme, colorScheme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(
    IconData icon,
    int value,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(ThemeData theme, ColorScheme colorScheme) {
    final ttsConfig = TtsService.instance.config;
    final s = context.s;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(s.petSkinSection, theme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _availableSprites.length,
              (i) => ChoiceChip(
                label: Text(_spriteName(_availableSprites[i].name, s)),
                selected: i == _selectedSpriteIndex,
                onSelected: (_) => _switchSprite(i),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _section(s.petModelSection, theme),
          _buildModelSelector(theme),
          const SizedBox(height: 20),
          _section(s.petTtsSection, theme),
          _row(
            s.petTtsSection,
            SegmentedButton<TtsEngineType>(
              segments: [
                ButtonSegment(
                  value: TtsEngineType.system,
                  label: Text(s.petTtsSystem),
                ),
                ButtonSegment(
                  value: TtsEngineType.volcano,
                  label: Text(s.petTtsVolcano),
                ),
              ],
              selected: {ttsConfig.engine},
              onSelectionChanged: (v) {
                TtsService.instance.updateConfig(
                  ttsConfig.copyWith(engine: v.first),
                );
                setState(() {});
              },
            ),
            theme,
          ),
          if (ttsConfig.engine == TtsEngineType.volcano) ...[
            _row(
              s.petTtsAppId,
              _ctrlField(_volcanoAppIdCtrl, s.petTtsAppIdHint),
              theme,
            ),
            _row(
              s.petTtsToken,
              _ctrlField(_volcanoTokenCtrl, s.petTtsTokenHint, obscure: true),
              theme,
            ),
            _row(
              s.petTtsVoiceType,
              _ctrlField(_volcanoVoiceTypeCtrl, s.petTtsVoiceTypeHint),
              theme,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(width: 100),
                  FilledButton.icon(
                    onPressed: _saveVolcanoConfig,
                    icon: const Icon(Icons.save, size: 16),
                    label: Text(s.petTtsSave),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    ttsConfig.volcanoReady ? s.petTtsReady : s.petTtsIncomplete,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ttsConfig.volcanoReady
                          ? Colors.green
                          : colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            _row(
              s.petTtsSpeedLabel(ttsConfig.volcanoSpeed),
              Slider(
                value: ttsConfig.volcanoSpeed.toDouble(),
                min: -50,
                max: 100,
                divisions: 150,
                onChanged: (v) {
                  TtsService.instance.updateConfig(
                    ttsConfig.copyWith(volcanoSpeed: v.round()),
                  );
                  setState(() {});
                },
              ),
              theme,
            ),
            _row(
              s.petTtsLoudnessLabel(ttsConfig.volcanoLoudness),
              Slider(
                value: ttsConfig.volcanoLoudness.toDouble(),
                min: -50,
                max: 100,
                divisions: 150,
                onChanged: (v) {
                  TtsService.instance.updateConfig(
                    ttsConfig.copyWith(volcanoLoudness: v.round()),
                  );
                  setState(() {});
                },
              ),
              theme,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 100, bottom: 8),
              child: Text(
                s.petTtsCredentialHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _section(s.petBehaviorSection, theme),
          _row(
            s.petTtsThresholdLabel(_chatService.ttsMaxLength),
            Slider(
              value: _chatService.ttsMaxLength.toDouble(),
              min: 20,
              max: 300,
              divisions: 28,
              onChanged: (v) =>
                  setState(() => _chatService.ttsMaxLength = v.round()),
            ),
            theme,
          ),
          Text(
            '  ${s.petTtsThresholdHint(_chatService.ttsMaxLength)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _row(
            s.petBubbleDismissLabel(_chatService.bubbleDismissSeconds),
            Slider(
              value: _chatService.bubbleDismissSeconds.toDouble(),
              min: 0,
              max: 30,
              divisions: 30,
              onChanged: (v) =>
                  setState(() => _chatService.bubbleDismissSeconds = v.round()),
            ),
            theme,
          ),
          Text(
            '  ${_chatService.bubbleDismissSeconds == 0 ? s.petBubbleDismissManual : s.petBubbleDismissAuto(_chatService.bubbleDismissSeconds)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _section(s.petCommandSection, theme),
          Text(
            '  ${s.petCommandHint}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ..._chatService.customCommands.map(
            (cmd) => _buildCommandTile(cmd, theme, colorScheme),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _showAddCommandDialog(context, theme),
            icon: const Icon(Icons.add, size: 16),
            label: Text(s.petCommandAdd),
          ),
          const SizedBox(height: 20),
          _section(s.petTestSection, theme),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => _controller.petSpeak(s.petTestShortText),
                child: Text(s.petTestShort),
              ),
              FilledButton.tonal(
                onPressed: () =>
                    _controller.petSpeak(s.petTestLongText, emotion: '温柔'),
                child: Text(s.petTestLong),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebugPanel(ThemeData theme, ColorScheme colorScheme) {
    final s = context.s;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.petDebugEvents,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn('Tap', () => _engine.sendEvent(PetEvent.tap)),
                _btn('Double', () => _engine.sendEvent(PetEvent.doubleTap)),
                _btn('Drag', () => _engine.sendEvent(PetEvent.drag)),
                _btn('Wake', () => _engine.sendEvent(PetEvent.voiceWake)),
                _btn('Random', () => _engine.sendEvent(PetEvent.randomTick)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.petDebugAnimations,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _engine.sprite.animations
                  .map((a) => _btn(a.name, () => _engine.playAnimation(a.name)))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text(
              s.petDebugState,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: _engine,
              builder: (context, _) {
                final anim = _engine.currentAnimation;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _info('State', _engine.currentState.name, theme),
                    _info('Anim', anim?.name ?? '-', theme),
                    _info(
                      'Frame',
                      '${_engine.frameIndex}/${anim?.frameCount ?? 0}',
                      theme,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 将精灵 name key 翻译为本地化文本
  String _spriteName(String nameKey, S s) {
    switch (nameKey) {
      case 'petCatGray':
        return s.petCatGray;
      case 'petCatOrange':
        return s.petCatOrange;
      case 'petCatWhite':
        return s.petCatWhite;
      default:
        return nameKey;
    }
  }

  void _switchSprite(int i) {
    setState(() => _selectedSpriteIndex = i);
    _controller.switchSprite(_availableSprites[i]);
  }

  /// 保存火山 TTS 三项密钥配置
  void _saveVolcanoConfig() {
    final current = TtsService.instance.config;
    TtsService.instance.updateConfig(
      current.copyWith(
        volcanoAppId: _volcanoAppIdCtrl.text.trim(),
        volcanoToken: _volcanoTokenCtrl.text.trim(),
        volcanoVoiceType: _volcanoVoiceTypeCtrl.text.trim(),
      ),
    );
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.s.petTtsSaved),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 带 Controller 的输入框（不实时提交，等保存按钮）
  Widget _ctrlField(
    TextEditingController ctrl,
    String hint, {
    bool obscure = false,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12),
    );
  }

  Widget _buildModelSelector(ThemeData theme) {
    final modelsAsync = ref.watch(modelCardsProvider);
    return modelsAsync.when(
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        context.s.petModelLoadFailed(e.toString()),
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      ),
      data: (models) {
        final currentId = _chatService.modelId;
        return DropdownButtonFormField<String>(
          initialValue: models.any((m) => m.id.toString() == currentId)
              ? currentId
              : null,
          decoration: InputDecoration(
            hintText: context.s.petModelHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
          items: models
              .map(
                (m) => DropdownMenuItem(
                  value: m.id.toString(),
                  child: Text(
                    '${m.name} (${m.modelId})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() => _chatService.modelId = v);
            if (v != null) {
              final card = models.firstWhere((m) => m.id.toString() == v);
              _chatService.onGenerate = (prompt) async {
                final client = LlmClient(
                  baseUrl: card.baseUrl,
                  apiKey: card.apiKey,
                  model: card.modelId,
                  provider: LlmProviderX.fromId(card.provider),
                );
                final resp = await client.chat([
                  {'role': 'user', 'content': prompt},
                ]);
                final content = resp.content ?? '';
                // 宠物聊天是独立于主聊天窗口的真实 LLM 调用，主聊天的
                // token 计数不会覆盖到，这里单独估算并计入宠物经济统计。
                final tokens =
                    ComputeService.estimateTokens(prompt) +
                    ComputeService.estimateTokens(content);
                if (tokens > 0) {
                  PetEconomy.instance.rewardForTokens(tokens);
                }
                return content;
              };
            }
          },
        );
      },
    );
  }

  Widget _section(String t, ThemeData th) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
  Widget _row(String l, Widget c, ThemeData th) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(l, style: th.textTheme.bodySmall)),
        Expanded(child: c),
      ],
    ),
  );
  Widget _btn(String l, VoidCallback f) => FilledButton.tonal(
    onPressed: f,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      minimumSize: Size.zero,
      textStyle: const TextStyle(fontSize: 11),
    ),
    child: Text(l),
  );
  Widget _info(String l, String v, ThemeData th) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            l,
            style: th.textTheme.bodySmall?.copyWith(
              color: th.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          v,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    ),
  );

  Widget _buildCommandTile(
    CustomPetCommand cmd,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 16, color: colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cmd.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    cmd.systemPrompt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.edit,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => _showEditCommandDialog(context, cmd, theme),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: context.s.commonEdit,
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 14,
                color: colorScheme.error,
              ),
              onPressed: () {
                _chatService.removeCustomCommand(cmd.id);
                setState(() {});
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: context.s.commonDelete,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCommandDialog(BuildContext context, ThemeData theme) {
    final labelCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    final s = context.s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.petCommandAddTitle),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: s.petCommandNameLabel,
                  hintText: s.petCommandNameHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                decoration: InputDecoration(
                  labelText: s.petCommandPromptLabel,
                  hintText: s.petCommandPromptHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (label.isNotEmpty && prompt.isNotEmpty) {
                _chatService.addCustomCommand(
                  CustomPetCommand(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    label: label,
                    systemPrompt: prompt,
                  ),
                );
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: Text(s.petCommandAdd),
          ),
        ],
      ),
    );
  }

  void _showEditCommandDialog(
    BuildContext context,
    CustomPetCommand cmd,
    ThemeData theme,
  ) {
    final labelCtrl = TextEditingController(text: cmd.label);
    final promptCtrl = TextEditingController(text: cmd.systemPrompt);
    final s = context.s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.petCommandEditTitle),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: s.petCommandNameLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                decoration: InputDecoration(
                  labelText: s.petCommandPromptLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              final prompt = promptCtrl.text.trim();
              if (label.isNotEmpty && prompt.isNotEmpty) {
                _chatService.updateCustomCommand(
                  CustomPetCommand(
                    id: cmd.id,
                    label: label,
                    systemPrompt: prompt,
                  ),
                );
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: Text(s.searchSave),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 商店 Tab
  // ═══════════════════════════════════════════════════════════

  Widget _buildShopTab(ThemeData theme, ColorScheme colorScheme) {
    final s = context.s;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：商品列表
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.petShopTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...PetShop.catalog.map(
                  (item) => _buildShopItem(item, theme, colorScheme),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 右侧：背包
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.petInventoryTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (_economy.inventory.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Center(
                      child: Text(
                        s.petInventoryEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ..._economy.inventory.map((entry) {
                    final item = PetShop.instance.getItem(entry.itemId);
                    if (item == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          FoodSprite(item: item, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            petL10n(s, item.nameKey),
                            style: theme.textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Text(
                            'x${entry.quantity}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  s.petStatusTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildProgressBar(
                  s.petStatusSatiety,
                  _economy.satiety,
                  Colors.orange,
                  theme,
                ),
                const SizedBox(height: 6),
                _buildProgressBar(
                  s.petStatusHappiness,
                  _economy.happiness,
                  Colors.pink,
                  theme,
                ),
                const SizedBox(height: 12),
                Text(
                  s.petStatusDecayHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShopItem(
    PetFoodItem item,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final s = context.s;
    final canAfford = _economy.coins >= item.price;
    final name = petL10n(s, item.nameKey);
    final desc = petL10n(s, item.descKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            FoodSprite(item: item, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.petShopSatiety(item.satietyRestore)}  ${s.petShopHappiness(item.happinessBoost)}${item.specialEffect != null ? "  ${s.petShopEffect(item.specialEffect!)}" : ""}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      size: 12,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${item.price}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                FilledButton.tonal(
                  onPressed: canAfford ? () => _buyItem(item) : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: Text(s.petShopBuy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buyItem(PetFoodItem item) async {
    final s = context.s;
    final success = await _economy.buyItem(item.id);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.petShopBought(petL10n(s, item.nameKey))),
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.petShopNoCoins),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _buildProgressBar(
    String label,
    int value,
    Color color,
    ThemeData theme,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100.0,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 25,
          child: Text(
            '$value',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 成就 Tab
  // ═══════════════════════════════════════════════════════════

  Widget _buildAchievementsTab(ThemeData theme, ColorScheme colorScheme) {
    final s = context.s;
    final unlocked = _economy.unlockedAchievements;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                s.petAchievementsTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                s.petAchievementsProgress(
                  unlocked.length,
                  allAchievements.length,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: allAchievements
                .map(
                  (a) => _buildAchievementCard(
                    a,
                    unlocked.contains(a.id),
                    theme,
                    colorScheme,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard(
    PetAchievement achievement,
    bool unlocked,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                achievement.icon,
                style: TextStyle(
                  fontSize: 22,
                  color: unlocked ? null : Colors.grey,
                ),
              ),
              const Spacer(),
              if (unlocked)
                Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            petL10n(context.s, achievement.nameKey),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: unlocked
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            petL10n(context.s, achievement.descKey),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: unlocked
                  ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

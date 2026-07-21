import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../core/db/tables/model_cards.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/llm/llm_provider.dart';
import '../../providers/database_provider.dart';
import '../../widgets/reorderable_card_grid.dart';
import '../../widgets/model_logo.dart';
import 'model_card_tile_optimized.dart';

/// 模型检测结果：id + 上下文窗口大小 (0=未知)
class _DetectedModel {
  final String id;
  final int contextWindow;
  const _DetectedModel(this.id, [this.contextWindow = 0]);
}

class ModelCardsPage extends ConsumerStatefulWidget {
  const ModelCardsPage({super.key});

  @override
  ConsumerState<ModelCardsPage> createState() => _ModelCardsPageState();
}

class _ModelCardsPageState extends ConsumerState<ModelCardsPage> {
  /// 是否处于排序模式（拖拽可用）
  bool _reorderMode = false;

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(modelCardsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.modelsTitle),
        actions: [
          // 排序模式切换
          if (cardsAsync.valueOrNull != null &&
              cardsAsync.valueOrNull!.length > 1)
            IconButton(
              icon: Icon(_reorderMode ? Icons.done : Icons.swap_vert),
              tooltip: _reorderMode ? '完成排序' : '拖拽排序',
              onPressed: () => setState(() => _reorderMode = !_reorderMode),
            ),
        ],
      ),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text(context.s.commonErrorWithMsg(err.toString()))),
        data: (cards) {
          if (cards.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.smart_toy_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(context.s.modelsEmpty, style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    context.s.modelsEmptyHint,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text(context.s.modelsAdd),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_reorderMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.s.modelsReorderHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                // 排序模式：带拖拽的重排网格
                // 普通模式：轻量 Wrap，点击即切换默认，无拖拽开销
                if (_reorderMode)
                  ReorderableCardGrid<ModelCard>(
                    items: cards,
                    keyOf: (c) => c.id,
                    onReorder: (reordered) => ref
                        .read(modelCardsProvider.notifier)
                        .reorder(reordered),
                    itemBuilder: (context, card) =>
                        OptimizedModelCardTile(card: card),
                    trailing: _AddModelCard(
                      onTap: () => _showAddDialog(context, ref),
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final card in cards)
                        SizedBox(
                          key: ValueKey(card.id),
                          width: 280,
                          child: OptimizedModelCardTile(card: card),
                        ),
                      SizedBox(
                        width: 280,
                        child: _AddModelCard(
                          onTap: () => _showAddDialog(context, ref),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        tooltip: context.s.modelsAdd,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => ModelCardDialog(
        onSave:
            (
              name,
              baseUrl,
              apiKey,
              modelId,
              logoPath,
              provider,
              contextWindow,
            ) {
              ref
                  .read(modelCardsProvider.notifier)
                  .addCard(
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    modelId: modelId,
                    logoPath: logoPath,
                    provider: provider,
                    contextWindow: contextWindow,
                  );
            },
      ),
    );
  }
}

/// 新增模型卡片 (虚线占位)
class _AddModelCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddModelCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      height: 132,
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 28, color: colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    context.s.modelsAdd,
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 已废弃：旧的卡片组件，现使用 OptimizedModelCardTile

class ModelCardDialog extends StatefulWidget {
  final String? initialName;
  final String? initialBaseUrl;
  final String? initialApiKey;
  final String? initialModelId;
  final String? initialLogoPath;
  final String? initialProvider;
  final int? initialContextWindow;
  final String? cardId; // 用于区分是新建还是编辑
  final void Function(
    String name,
    String baseUrl,
    String apiKey,
    String modelId,
    String logoPath,
    String provider,
    int contextWindow,
  )
  onSave;

  const ModelCardDialog({
    this.initialName,
    this.initialBaseUrl,
    this.initialApiKey,
    this.initialModelId,
    this.initialLogoPath,
    this.initialProvider,
    this.initialContextWindow,
    this.cardId,
    required this.onSave,
    super.key,
  });

  @override
  State<ModelCardDialog> createState() => _ModelCardDialogState();
}

class _ModelCardDialogState extends State<ModelCardDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _obscureKey = true;

  // logo 路径 (空表示未设置)
  String _logoPath = '';

  // 协议类型
  LlmProvider _provider = LlmProvider.openai;

  // 模型检测相关
  List<_DetectedModel> _availableModels = [];
  String? _selectedModel;
  bool _testing = false;
  String? _testError;

  // 上下文窗口大小
  int _contextWindow = 0;
  late final TextEditingController _contextWindowCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _urlCtrl = TextEditingController(text: widget.initialBaseUrl ?? '');
    _keyCtrl = TextEditingController(text: widget.initialApiKey ?? '');
    _logoPath = widget.initialLogoPath ?? '';
    _provider = LlmProviderX.fromId(widget.initialProvider);
    _selectedModel = widget.initialModelId;
    _contextWindow = widget.initialContextWindow ?? 0;
    _contextWindowCtrl = TextEditingController(
      text: _contextWindow > 0 ? _contextWindow.toString() : '',
    );
    if (widget.initialModelId != null && widget.initialModelId!.isNotEmpty) {
      _availableModels = [
        _DetectedModel(widget.initialModelId!, _contextWindow),
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _contextWindowCtrl.dispose();
    super.dispose();
  }

  /// 选择 logo 图片文件 (可为空)。
  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: '选择模型 Logo',
    );
    final path = result?.files.single.path;
    if (path != null) {
      setState(() => _logoPath = path);
    }
  }

  /// 测试连接并检测可用模型
  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();

    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _testError = '请先填写 Base URL 和 API Key';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testError = null;
      _availableModels = [];
    });

    try {
      // 调用 /v1/models 端点检测可用模型
      final dio = Dio(
        BaseOptions(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      // 规范化 URL
      var baseUrl = url;
      while (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      if (baseUrl.endsWith('/chat/completions')) {
        baseUrl = baseUrl.substring(
          0,
          baseUrl.length - '/chat/completions'.length,
        );
      }
      if (baseUrl.endsWith('/v1/messages')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - '/messages'.length);
      }

      final modelsUrl = '$baseUrl/models';
      final response = await dio.get(modelsUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['data'] is List) {
          final models = (data['data'] as List)
              .map((m) {
                if (m is Map) {
                  final id = m['id']?.toString() ?? '';
                  final contextWindow = m['context_window'] as int? ?? 0;
                  return _DetectedModel(id, contextWindow);
                }
                return null;
              })
              .whereType<_DetectedModel>()
              .toList();

          if (models.isEmpty) {
            throw Exception('未检测到可用模型');
          }

          setState(() {
            _availableModels = models;
            _testing = false;
            // 自动选择第一个模型
            if (_selectedModel == null || _selectedModel!.isEmpty) {
              _selectedModel = models.first.id;
              _contextWindow = models.first.contextWindow;
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ 连接成功，检测到 ${models.length} 个模型'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception('响应格式不正确');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      String errorMsg;
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          errorMsg =
              '端点不存在 (404)\n\n'
              '提示：此服务商可能不支持 /v1/models 端点，\n'
              '请手动输入模型 ID';
        } else if (e.response?.statusCode == 401 ||
            e.response?.statusCode == 403) {
          errorMsg = 'API Key 无效或权限不足';
        } else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          errorMsg = '连接超时，请检查网络或 Base URL 是否正确';
        } else if (e.type == DioExceptionType.connectionError) {
          errorMsg =
              '无法连接到服务器\n\n'
              '请检查：\n'
              '1. Base URL 是否正确\n'
              '2. 网络连接是否正常\n'
              '3. 是否需要代理';
        } else {
          errorMsg = e.message ?? e.toString();
        }
      } else {
        errorMsg = e.toString();
      }

      setState(() {
        _testing = false;
        _testError = errorMsg;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ 测试失败: $errorMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName != null;
    return AlertDialog(
      title: Text(isEdit ? context.s.modelsEditTitle : context.s.modelsAdd),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo 选择区
              Row(
                children: [
                  ModelLogo(
                    logoPath: _logoPath,
                    name: _nameCtrl.text,
                    modelId: _selectedModel ?? '',
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logo (可选)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          _logoPath.isEmpty
                              ? '未设置，将按品牌自动识别'
                              : _logoPath.split(RegExp(r'[\\/]')).last,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_logoPath.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: context.s.chatEnvClear,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _logoPath = ''),
                    ),
                  TextButton.icon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(context.s.commonSelect),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 协议类型选择
              DropdownButtonFormField<LlmProvider>(
                initialValue: _provider,
                decoration: InputDecoration(
                  labelText: context.s.modelsProtocolType,
                  helperText: context.s.modelsProtocolHelper,
                ),
                items: LlmProvider.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: (p) {
                  if (p == null) return;
                  setState(() {
                    _provider = p;
                    // 切换协议后清空已检测模型 (避免跨协议串味)
                    _availableModels =
                        _selectedModel != null && _selectedModel!.isNotEmpty
                        ? [_DetectedModel(_selectedModel!)]
                        : [];
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.s.modelsName,
                  hintText: context.s.modelsNameHint,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.s.modelsNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _provider.baseUrlHint,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.s.modelsBaseUrlRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keyCtrl,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.s.modelsApiKeyRequired
                    : null,
              ),
              const SizedBox(height: 16),
              // 测试连接按钮
              OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cable, size: 18),
                label: Text(
                  _testing
                      ? context.s.modelsTestingConnection
                      : context.s.modelsTestConnection,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
              if (_testError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 模型选择区
              _availableModels.isEmpty
                  ? TextFormField(
                      initialValue: _selectedModel,
                      decoration: InputDecoration(
                        labelText: context.s.modelsModelId,
                        hintText: context.s.modelsModelIdHint,
                      ),
                      onChanged: (v) => _selectedModel = v.trim(),
                      validator: (v) {
                        if (_selectedModel == null || _selectedModel!.isEmpty) {
                          return context.s.modelsModelIdRequired;
                        }
                        return null;
                      },
                    )
                  : Autocomplete<_DetectedModel>(
                      displayStringForOption: (m) => m.id,
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        if (query.isEmpty) return _availableModels;
                        return _availableModels.where(
                          (m) => m.id.toLowerCase().contains(query),
                        );
                      },
                      initialValue: _selectedModel != null
                          ? TextEditingValue(text: _selectedModel!)
                          : null,
                      onSelected: (v) => setState(() {
                        _selectedModel = v.id;
                        _contextWindow = v.contextWindow;
                      }),
                      optionsMaxHeight: 240,
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText:
                                    '模型 (${_availableModels.length} 个可用)',
                                hintText: context.s.modelsSearchHint,
                                suffixIcon: const Icon(Icons.search, size: 20),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) => _selectedModel = v.trim(),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? '请选择模型'
                                  : null,
                            );
                          },
                    ),
              const SizedBox(height: 16),
              // 上下文窗口配置
              Tooltip(
                message: context.s.modelsContextWindowTooltip,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.white,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextFormField(
                  controller: _contextWindowCtrl,
                  decoration: InputDecoration(
                    labelText: context.s.modelsContextWindow,
                    hintText: context.s.modelsContextWindowHint,
                    helperText: context.s.modelsContextWindowHelper,
                    suffixIcon: Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    _contextWindow = parsed ?? 0;
                  },
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null; // 允许为空
                    final parsed = int.tryParse(v.trim());
                    if (parsed == null) {
                      return context.s.modelsContextWindowValidNumber;
                    }
                    if (parsed <= 0) {
                      return context.s.modelsContextWindowValidPositive;
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate() &&
                _selectedModel != null &&
                _selectedModel!.isNotEmpty) {
              // 解析上下文窗口：用户输入 > 检测值 > 默认 128K
              int finalContextWindow = _contextWindow;
              if (_contextWindowCtrl.text.trim().isEmpty &&
                  finalContextWindow == 0) {
                finalContextWindow = 128000; // 默认 128K
              }

              widget.onSave(
                _nameCtrl.text.trim(),
                _urlCtrl.text.trim(),
                _keyCtrl.text.trim(),
                _selectedModel!,
                _logoPath,
                _provider.id,
                finalContextWindow,
              );
              Navigator.pop(context);
            }
          },
          child: Text(isEdit ? context.s.commonSave : context.s.modelsAdd),
        ),
      ],
    );
  }
}

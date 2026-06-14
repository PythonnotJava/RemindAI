import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/db/tables/model_cards.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/llm/llm_provider.dart';
import '../../providers/database_provider.dart';
import '../../widgets/reorderable_card_grid.dart';
import '../../widgets/model_logo.dart';

class ModelCardsPage extends ConsumerWidget {
  const ModelCardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(modelCardsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.s.modelsTitle)),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.s.modelsReorderHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ReorderableCardGrid<ModelCard>(
                  items: cards,
                  keyOf: (c) => c.id,
                  onReorder: (reordered) =>
                      ref.read(modelCardsProvider.notifier).reorder(reordered),
                  itemBuilder: (context, card) => _ModelCardTile(card: card),
                  trailing: _AddModelCard(
                    onTap: () => _showAddDialog(context, ref),
                  ),
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
      builder: (ctx) => _ModelCardDialog(
        onSave: (name, baseUrl, apiKey, modelId, logoPath, provider) {
          ref
              .read(modelCardsProvider.notifier)
              .addCard(
                name: name,
                baseUrl: baseUrl,
                apiKey: apiKey,
                modelId: modelId,
                logoPath: logoPath,
                provider: provider,
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

class _ModelCardTile extends ConsumerWidget {
  final ModelCard card;
  const _ModelCardTile({required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maskedUrl = _maskUrl(card.baseUrl);

    return Material(
      color: card.isDefault
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(modelCardsProvider.notifier).setDefault(card.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: card.isDefault ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    card.isDefault
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: card.isDefault
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  ModelLogo(
                    logoPath: card.logoPath,
                    name: card.name,
                    modelId: card.modelId,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      card.name,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (card.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.s.modelsDefault,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _kv(context, 'Model', card.modelId),
              const SizedBox(height: 2),
              _kv(context, 'URL', maskedUrl),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: context.s.commonEdit,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showEditDialog(context, ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: context.s.commonDelete,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            k,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Consolas',
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _maskUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return '${uri.scheme}://${uri.host}/***';
    } catch (_) {
      if (url.length > 20) return '${url.substring(0, 20)}***';
      return url;
    }
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _ModelCardDialog(
        initialName: card.name,
        initialBaseUrl: card.baseUrl,
        initialApiKey: card.apiKey,
        initialModelId: card.modelId,
        initialLogoPath: card.logoPath,
        initialProvider: card.provider,
        onSave: (name, baseUrl, apiKey, modelId, logoPath, provider) {
          final updated = card.copyWith(
            name: name,
            baseUrl: baseUrl,
            apiKey: apiKey,
            modelId: modelId,
            logoPath: logoPath,
            provider: provider,
          );
          ref.read(modelCardsProvider.notifier).updateCard(updated);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.modelsDeleteTitle),
        content: Text(context.s.modelsDeleteConfirm(card.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.s.commonCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(modelCardsProvider.notifier).deleteCard(card.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
  }
}

class _ModelCardDialog extends StatefulWidget {
  final String? initialName;
  final String? initialBaseUrl;
  final String? initialApiKey;
  final String? initialModelId;
  final String? initialLogoPath;
  final String? initialProvider;
  final void Function(
    String name,
    String baseUrl,
    String apiKey,
    String modelId,
    String logoPath,
    String provider,
  )
  onSave;

  const _ModelCardDialog({
    this.initialName,
    this.initialBaseUrl,
    this.initialApiKey,
    this.initialModelId,
    this.initialLogoPath,
    this.initialProvider,
    required this.onSave,
  });

  @override
  State<_ModelCardDialog> createState() => _ModelCardDialogState();
}

class _ModelCardDialogState extends State<_ModelCardDialog> {
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
  List<String> _availableModels = [];
  String? _selectedModel;
  bool _isFetchingModels = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _urlCtrl = TextEditingController(text: widget.initialBaseUrl ?? '');
    _keyCtrl = TextEditingController(text: widget.initialApiKey ?? '');
    _logoPath = widget.initialLogoPath ?? '';
    _provider = LlmProviderX.fromId(widget.initialProvider);
    _selectedModel = widget.initialModelId;
    if (widget.initialModelId != null && widget.initialModelId!.isNotEmpty) {
      _availableModels = [widget.initialModelId!];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  /// 调用各协议的模型列表接口检测可用模型
  Future<void> _fetchModels() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _fetchError = '请先填写 Base URL 和 API Key');
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchError = null;
    });

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final baseUrl = url.endsWith('/')
          ? url.substring(0, url.length - 1)
          : url;

      final List<String> models;
      switch (_provider) {
        case LlmProvider.anthropic:
          models = await _fetchAnthropicModels(dio, baseUrl, key);
          break;
        case LlmProvider.gemini:
          models = await _fetchGeminiModels(dio, baseUrl, key);
          break;
        case LlmProvider.openai:
          models = await _fetchOpenAiModels(dio, baseUrl, key);
          break;
      }

      models.sort();
      setState(() {
        _availableModels = models;
        _isFetchingModels = false;
        if (models.isNotEmpty && _selectedModel == null) {
          _selectedModel = models.first;
        }
        if (models.isEmpty) {
          _fetchError = '接口返回空模型列表';
        }
      });
    } on DioException catch (e) {
      setState(() {
        _isFetchingModels = false;
        _fetchError = e.response?.statusCode != null
            ? 'HTTP ${e.response!.statusCode}'
            : (e.message ?? '网络请求失败');
      });
    } catch (e) {
      setState(() {
        _isFetchingModels = false;
        _fetchError = e.toString();
      });
    }
  }

  /// OpenAI: GET {base}/models, Bearer
  Future<List<String>> _fetchOpenAiModels(
    Dio dio,
    String baseUrl,
    String key,
  ) async {
    final response = await dio.get(
      '$baseUrl/models',
      options: Options(headers: {'Authorization': 'Bearer $key'}),
    );
    final data = response.data;
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((m) => (m['id'] ?? m['name'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } else if (data is List) {
      return data
          .map((m) => (m is Map ? (m['id'] ?? m['name'] ?? '') : m).toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Anthropic: GET {base}/v1/models, x-api-key + anthropic-version
  Future<List<String>> _fetchAnthropicModels(
    Dio dio,
    String baseUrl,
    String key,
  ) async {
    final response = await dio.get(
      '$baseUrl/v1/models',
      options: Options(
        headers: {'x-api-key': key, 'anthropic-version': '2023-06-01'},
      ),
    );
    final data = response.data;
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Gemini: GET {base}/models?key=, 返回 models[].name (去掉 "models/" 前缀)
  Future<List<String>> _fetchGeminiModels(
    Dio dio,
    String baseUrl,
    String key,
  ) async {
    final response = await dio.get(
      '$baseUrl/models',
      queryParameters: {'key': key},
    );
    final data = response.data;
    if (data is Map && data['models'] is List) {
      return (data['models'] as List)
          .map((m) => (m['name'] ?? '').toString())
          .map((n) => n.startsWith('models/') ? n.substring(7) : n)
          .where((id) => id.isNotEmpty)
          .toList();
    }
    return [];
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
                decoration: const InputDecoration(
                  labelText: '协议类型',
                  helperText: '决定请求格式与模型检测方式',
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
                        ? [_selectedModel!]
                        : [];
                    _fetchError = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: '名称',
                  hintText: context.s.modelsNameHint,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _provider.baseUrlHint,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入 Base URL' : null,
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
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入 API Key' : null,
              ),
              const SizedBox(height: 16),
              // 模型选择区
              Row(
                children: [
                  Expanded(
                    child: _availableModels.isEmpty
                        ? TextFormField(
                            initialValue: _selectedModel,
                            decoration: InputDecoration(
                              labelText: '模型 ID',
                              hintText: context.s.modelsDetectHint,
                              errorText: _fetchError,
                            ),
                            onChanged: (v) => _selectedModel = v.trim(),
                            validator: (v) {
                              if (_selectedModel == null ||
                                  _selectedModel!.isEmpty) {
                                return '请选择或输入模型';
                              }
                              return null;
                            },
                          )
                        : DropdownButtonFormField<String>(
                            initialValue:
                                _availableModels.contains(_selectedModel)
                                ? _selectedModel
                                : null,
                            decoration: InputDecoration(
                              labelText: '模型 (${_availableModels.length} 个可用)',
                              errorText: _fetchError,
                            ),
                            items: _availableModels
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      m,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedModel = v),
                            validator: (v) => v == null ? '请选择模型' : null,
                          ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: _isFetchingModels
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton.filledTonal(
                            onPressed: _fetchModels,
                            icon: const Icon(Icons.refresh),
                            tooltip: context.s.modelsDetect,
                          ),
                  ),
                ],
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
              widget.onSave(
                _nameCtrl.text.trim(),
                _urlCtrl.text.trim(),
                _keyCtrl.text.trim(),
                _selectedModel!,
                _logoPath,
                _provider.id,
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

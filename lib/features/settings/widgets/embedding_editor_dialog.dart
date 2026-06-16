import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/settings/app_settings.dart';
import '../../../providers/settings_provider.dart';

/// 嵌入模型新增/编辑弹窗
class EmbeddingEditorDialog extends ConsumerStatefulWidget {
  final EmbeddingConfig? existing;
  const EmbeddingEditorDialog({super.key, this.existing});

  @override
  ConsumerState<EmbeddingEditorDialog> createState() =>
      _EmbeddingEditorDialogState();
}

class _EmbeddingEditorDialogState extends ConsumerState<EmbeddingEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late bool _useQdrant;
  late bool _persistToSqlite;

  bool _obscureApiKey = true;
  bool _testing = false;
  String? _testMessage;
  bool _testSuccess = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameController = TextEditingController(text: c?.name ?? '');
    _baseUrlController = TextEditingController(text: c?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: c?.apiKey ?? '');
    _modelController = TextEditingController(text: c?.model ?? '');
    _useQdrant = c?.useQdrant ?? false;
    _persistToSqlite = c?.persistToSqlite ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }
  // PLACEHOLDER_EDITOR

  Future<void> _testConnection() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = context.s.embEditorFillRequired;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testMessage = null;
    });

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    try {
      final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/embeddings';
      final response = await dio.post(
        url,
        data: {'model': model, 'input': 'test'},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      final embedding = data['data']?[0]?['embedding'];
      if (embedding is List) {
        setState(() {
          _testSuccess = true;
          _testMessage = '连接成功（维度: ${embedding.length}）';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testMessage = context.s.embEditorConnAbnormal;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      String detail;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        detail = context.s.embEditorTimeout;
      } else if (e.response != null) {
        detail = 'HTTP ${e.response?.statusCode}: ${e.response?.data}';
      } else {
        detail = e.message ?? context.s.embEditorUnknownError;
      }
      setState(() {
        _testSuccess = false;
        _testMessage = '连接失败: $detail';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = '连接失败: $e';
      });
    } finally {
      dio.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testMessage = context.s.embEditorFillRequired;
      });
      return;
    }

    setState(() => _saving = true);

    // 生成 id: 编辑沿用原 id，新增用时间戳
    final id =
        widget.existing?.id ??
        'embedding_${DateTime.now().millisecondsSinceEpoch}';

    final config = EmbeddingConfig(
      id: id,
      name: _nameController.text.trim(),
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      useQdrant: _useQdrant,
      persistToSqlite: _persistToSqlite,
    );

    try {
      await ref.read(settingsProvider.notifier).upsertEmbedding(config);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(
        _isEdit ? context.s.embEditorTitle : context.s.embEditorAddTitle,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '名称 (可选)',
                  hintText: context.s.embEditorNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.openai.com/v1',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: _obscureApiKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureApiKey = !_obscureApiKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  hintText: 'text-embedding-3-large',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.s.embEditorEnableQdrant),
                value: _useQdrant,
                onChanged: (v) => setState(() => _useQdrant = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.s.embEditorEnableSqlite),
                value: _persistToSqlite,
                onChanged: (v) => setState(() => _persistToSqlite = v),
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _testMessage!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: _testSuccess ? Colors.green : colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(context.s.commonCancel),
        ),
        FilledButton.tonalIcon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 18),
          label: Text(context.s.embEditorTestConn),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: Text(context.s.commonSave),
        ),
      ],
    );
  }
}

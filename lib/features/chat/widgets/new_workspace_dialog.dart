import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/utils/directory_picker.dart';
import '../../../core/settings/app_settings.dart';
import '../../../providers/settings_provider.dart';
import '../chat_provider.dart';

/// 新建工作目录对话框
///
/// 提供:
/// - 父目录选择 + 文件夹名输入
/// - memory.json 配置 (embeddings, long_term_store, long_term_recall, mode)
/// - 嵌入模型连接测试
/// - 创建并切换工作目录
class NewWorkspaceDialog extends ConsumerStatefulWidget {
  const NewWorkspaceDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const NewWorkspaceDialog(),
    );
  }

  @override
  ConsumerState<NewWorkspaceDialog> createState() => _NewWorkspaceDialogState();
}

class _NewWorkspaceDialogState extends ConsumerState<NewWorkspaceDialog> {
  final _folderNameController = TextEditingController();
  String _parentDir = '';

  // memory.json 配置
  bool _embeddings = false;
  bool _longTermStore = false;
  bool _longTermRecall = false;
  String _mode = 'normal'; // normal | auto

  // 连接测试状态
  _TestStatus _testStatus = _TestStatus.idle;
  String _testMessage = '';

  // 创建状态
  bool _creating = false;

  // 原生目录选择器状态，防止快速重复点击打开多个 IFileDialog
  bool _pickingParentDir = false;

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final embeddingCfg = ref.watch(settingsProvider).valueOrNull?.embedding;
    final hasEmbedding = embeddingCfg?.isConfigured ?? false;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Icon(
                    Icons.create_new_folder,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.s.wsDialogTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.s.wsDialogDesc,
                style: TextStyle(fontSize: 13, color: colorScheme.outline),
              ),
              const SizedBox(height: 20),

              // 可变内容区（受限高度时可滚动，避免溢出）
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 路径选择
                      _buildPathSection(context),
                      const SizedBox(height: 20),

                      // memory.json 配置
                      _buildMemoryConfigSection(context, hasEmbedding),

                      // 连接测试
                      if (_embeddings) ...[
                        const SizedBox(height: 16),
                        _buildTestSection(context, embeddingCfg),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 底部按钮
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 路径区域 ────────────────────────────────────────────

  Widget _buildPathSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fullPath =
        _parentDir.isNotEmpty && _folderNameController.text.isNotEmpty
        ? p.join(_parentDir, _folderNameController.text)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.s.wsDialogLocation,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickingParentDir ? null : _pickParentDir,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _parentDir.isEmpty
                              ? context.s.wsDialogSelectParent
                              : _parentDir,
                          style: TextStyle(
                            fontSize: 13,
                            color: _parentDir.isEmpty
                                ? colorScheme.outline
                                : colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _folderNameController,
          decoration: InputDecoration(
            labelText: context.s.wsDialogFolderName,
            hintText: context.s.wsDialogFolderHint,
            prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (fullPath.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: colorScheme.outline),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '将创建: $fullPath',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── memory.json 配置区域 ─────────────────────────────────

  Widget _buildMemoryConfigSection(BuildContext context, bool hasEmbedding) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.s.wsDialogConfig,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _configSwitch(
                icon: Icons.auto_awesome,
                title: context.s.wsDialogPermMode,
                subtitle: _mode == 'auto'
                    ? context.s.wsDialogPermAuto
                    : context.s.wsDialogPermNormal,
                value: _mode == 'auto',
                onChanged: (v) => setState(() => _mode = v ? 'auto' : 'normal'),
              ),
              const Divider(height: 1, indent: 48),
              _configSwitch(
                icon: Icons.hub,
                title: context.s.wsDialogEmbeddings,
                subtitle: hasEmbedding
                    ? '启用 Qdrant + 嵌入模型存储长期记忆'
                    : context.s.wsDialogEmbeddingsHint,
                value: _embeddings,
                enabled: hasEmbedding,
                onChanged: (v) => setState(() {
                  _embeddings = v;
                  if (!v) {
                    _longTermStore = false;
                    _longTermRecall = false;
                  }
                }),
              ),
              if (_embeddings) ...[
                const Divider(height: 1, indent: 48),
                _configSwitch(
                  icon: Icons.save_alt,
                  title: context.s.wsDialogAutoStore,
                  subtitle: context.s.wsDialogAutoStoreDesc,
                  value: _longTermStore,
                  onChanged: (v) => setState(() => _longTermStore = v),
                ),
                const Divider(height: 1, indent: 48),
                _configSwitch(
                  icon: Icons.manage_search,
                  title: context.s.wsDialogAutoRecall,
                  subtitle: context.s.wsDialogAutoRecallDesc,
                  value: _longTermRecall,
                  onChanged: (v) => setState(() => _longTermRecall = v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _configSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: enabled ? onChanged : null,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  // ─── 连接测试区域 ─────────────────────────────────────────

  Widget _buildTestSection(BuildContext context, EmbeddingConfig? cfg) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _testStatusIcon(colorScheme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.s.wsDialogEmbConn,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (_testMessage.isNotEmpty)
                  Text(
                    _testMessage,
                    style: TextStyle(
                      fontSize: 11,
                      color: _testStatus == _TestStatus.success
                          ? Colors.green.shade700
                          : _testStatus == _TestStatus.error
                          ? colorScheme.error
                          : colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _testStatus == _TestStatus.testing
                ? null
                : () => _runTest(cfg),
            child: Text(
              _testStatus == _TestStatus.testing
                  ? context.s.wsDialogTesting
                  : context.s.wsDialogTestConn,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _testStatusIcon(ColorScheme colorScheme) {
    return switch (_testStatus) {
      _TestStatus.idle => Icon(
        Icons.link,
        size: 20,
        color: colorScheme.outline,
      ),
      _TestStatus.testing => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _TestStatus.success => const Icon(
        Icons.check_circle,
        size: 20,
        color: Colors.green,
      ),
      _TestStatus.error => Icon(
        Icons.error,
        size: 20,
        color: colorScheme.error,
      ),
    };
  }

  // ─── 底部按钮 ─────────────────────────────────────────────

  Widget _buildActions(BuildContext context) {
    final canCreate =
        _parentDir.isNotEmpty &&
        _folderNameController.text.trim().isNotEmpty &&
        !_creating;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: Text(context.s.commonCancel),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: canCreate ? _create : null,
          icon: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.create_new_folder, size: 18),
          label: Text(
            _creating
                ? context.s.wsDialogCreating
                : context.s.wsDialogCreateBtn,
          ),
        ),
      ],
    );
  }

  // ─── 操作逻辑 ─────────────────────────────────────────────

  Future<void> _pickParentDir() async {
    if (_pickingParentDir) return;
    setState(() => _pickingParentDir = true);

    final total = Stopwatch()..start();
    final dialogTitle = context.s.wsDialogSelectParentTitle;
    AppLogger.instance.log('[NewWorkspace] 开始选择父目录: current=$_parentDir');

    try {
      // 异步检查旧父目录，避免 existsSync 在离线盘或网络路径上冻结 UI。
      String? initialDirectory;
      if (_parentDir.isNotEmpty) {
        final exists = await directoryExistsSafely(_parentDir);
        if (exists) {
          initialDirectory = _parentDir;
        } else if (mounted) {
          AppLogger.instance.log('[NewWorkspace] 当前父目录无效或检查超时，清空旧路径');
          setState(() => _parentDir = '');
        }
      }

      final dir = await pickDirectory(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      if (dir != null && mounted) {
        setState(() => _parentDir = dir);
        AppLogger.instance.log('[NewWorkspace] 父目录状态更新完成: path=$dir');
      }
    } finally {
      total.stop();
      AppLogger.instance.log(
        '[NewWorkspace] 父目录选择流程结束: '
        'elapsed=${total.elapsedMilliseconds}ms',
      );
      if (mounted) setState(() => _pickingParentDir = false);
    }
  }

  Future<void> _runTest(EmbeddingConfig? cfg) async {
    if (cfg == null || !cfg.isConfigured) {
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = context.s.wsDialogEmbNotConfigured;
      });
      return;
    }

    setState(() {
      _testStatus = _TestStatus.testing;
      _testMessage = '正在连接 ${cfg.baseUrl}...';
    });

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: cfg.baseUrl,
          headers: {
            'Authorization': 'Bearer ${cfg.apiKey}',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final resp = await dio.post(
        '/embeddings',
        data: {'model': cfg.model, 'input': 'connection test'},
      );

      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final embedding = data['data']?[0]?['embedding'] as List?;
        final dim = embedding?.length ?? 0;
        setState(() {
          _testStatus = _TestStatus.success;
          _testMessage = '连接成功 · 模型: ${cfg.model} · 维度: $dim';
        });
      } else {
        setState(() {
          _testStatus = _TestStatus.error;
          _testMessage = 'HTTP ${resp.statusCode}';
        });
      }
    } on DioException catch (e) {
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = e.message ?? e.type.name;
      });
    } catch (e) {
      setState(() {
        _testStatus = _TestStatus.error;
        _testMessage = e.toString();
      });
    }
  }

  Future<void> _create() async {
    final folderName = _folderNameController.text.trim();
    if (_parentDir.isEmpty || folderName.isEmpty) return;

    final fullPath = p.join(_parentDir, folderName);

    setState(() => _creating = true);

    try {
      // 1. 创建目录
      final dir = Directory(fullPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 2. 写入 memory.json
      final config = {
        'embeddings': _embeddings,
        'long_term_store': _longTermStore,
        'long_term_recall': _longTermRecall,
        'mode': _mode,
      };
      final jsonFile = File(p.join(fullPath, 'memory.json'));
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      // 3. 切换工作目录
      ref.read(workingDirectoryProvider.notifier).state = fullPath;
      await ref
          .read(settingsProvider.notifier)
          .updateWorkingDirectory(fullPath);

      // 4. 新建对话
      ref.read(chatProvider.notifier).newConversation();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.wsDialogCreated(folderName))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.wsDialogCreateFailed(e.toString()))),
        );
      }
    }
  }
}

enum _TestStatus { idle, testing, success, error }

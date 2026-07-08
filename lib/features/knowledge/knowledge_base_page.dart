import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/db/tables/knowledge_base.dart';
import '../../core/l10n/l10n_ext.dart';
import '../../core/settings/app_settings.dart';
import '../../providers/kb_provider.dart';
import '../../providers/settings_provider.dart';

/// 知识库管理页 — 服务页的一个 Tab。
class KnowledgeBasePage extends ConsumerWidget {
  const KnowledgeBasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.servicesKbTab)),
      body: const KnowledgeBasePageBody(),
    );
  }
}

/// 知识库内容体 (可嵌入服务页 TabBarView)
class KnowledgeBasePageBody extends ConsumerWidget {
  const KnowledgeBasePageBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basesAsync = ref.watch(knowledgeBasesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return basesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(context.s.chatLoadFailedWithError(e.toString()))),
      data: (bases) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.s.kbSectionHint,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (bases.isEmpty)
                _EmptyState(onCreate: () => _openEditor(context, ref, null))
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final kb in bases)
                      _KbCard(
                        kb: kb,
                        onEdit: () => _openEditor(context, ref, kb),
                        onDelete: () => _confirmDelete(context, ref, kb),
                        onManage: () => _openDocs(context, ref, kb),
                      ),
                    _AddKbCard(onTap: () => _openEditor(context, ref, null)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    KnowledgeBase? existing,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _KbEditorDialog(existing: existing),
    );
  }

  Future<void> _openDocs(
    BuildContext context,
    WidgetRef ref,
    KnowledgeBase kb,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _KbDocsDialog(kbId: kb.id, kbName: kb.name),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    KnowledgeBase kb,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.kbDeleteTitle),
        content: Text(context.s.kbDeleteConfirm(kb.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(knowledgeBasesProvider.notifier).deleteBase(kb);
    }
  }
}

/// 知识库卡片
class _KbCard extends StatelessWidget {
  final KnowledgeBase kb;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManage;

  const _KbCard({
    required this.kb,
    required this.onEdit,
    required this.onDelete,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 300,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onManage,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kb.name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (kb.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    kb.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.memory, size: 14, color: colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        kb.embeddingDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Consolas',
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (kb.embeddingDimension > 0)
                      Text(
                        context.s.kbDimension(kb.embeddingDimension),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: onManage,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(context.s.kbManageDocs),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: context.s.commonEdit,
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: context.s.commonDelete,
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 新增卡片
class _AddKbCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddKbCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
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
                    context.s.kbCreate,
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

/// 空状态
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(context.s.kbEmpty, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              context.s.kbEmptyHint,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.s.kbCreate),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建/编辑知识库对话框
class _KbEditorDialog extends ConsumerStatefulWidget {
  final KnowledgeBase? existing;
  const _KbEditorDialog({this.existing});

  @override
  ConsumerState<_KbEditorDialog> createState() => _KbEditorDialogState();
}

class _KbEditorDialogState extends ConsumerState<_KbEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  String? _selectedEmbeddingId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    // 编辑模式下嵌入模型不可改，用其快照的 model 名匹配现有配置作展示
    if (!_isEdit) {
      final settings = ref.read(settingsProvider).valueOrNull;
      _selectedEmbeddingId = settings?.selectedEmbeddingId.isNotEmpty == true
          ? settings!.selectedEmbeddingId
          : (settings?.embeddings.isNotEmpty == true
                ? settings!.embeddings.first.id
                : null);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final embeddings = settings?.embeddings ?? const <EmbeddingConfig>[];

    return AlertDialog(
      title: Text(_isEdit ? context.s.kbEditTitle : context.s.kbCreateTitle),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.s.kbNameLabel,
                  hintText: context.s.kbNameHint,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.s.kbNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(
                  labelText: context.s.kbDescLabel,
                  hintText: context.s.kbDescHint,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              if (_isEdit)
                // 编辑模式: 只读展示嵌入模型 (不可改)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.s.kbEmbeddingLabel,
                    helperText: context.s.kbEmbeddingLocked,
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  ),
                  child: Text(widget.existing!.embeddingDisplay),
                )
              else if (embeddings.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    context.s.kbNoEmbeddingConfigured,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmbeddingId,
                  decoration: InputDecoration(
                    labelText: context.s.kbEmbeddingLabel,
                    helperText: context.s.kbEmbeddingLocked,
                    prefixIcon: const Icon(Icons.memory, size: 18),
                  ),
                  items: [
                    for (final e in embeddings)
                      DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          e.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedEmbeddingId = v),
                  validator: (v) => (v == null || v.isEmpty)
                      ? context.s.kbEmbeddingRequired
                      : null,
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
          onPressed: () => _submit(embeddings),
          child: Text(context.s.commonSave),
        ),
      ],
    );
  }

  Future<void> _submit(List<EmbeddingConfig> embeddings) async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(knowledgeBasesProvider.notifier);

    if (_isEdit) {
      await notifier.updateMeta(
        id: widget.existing!.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
    } else {
      final cfg = embeddings.firstWhere((e) => e.id == _selectedEmbeddingId);
      await notifier.createBase(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        embeddingBaseUrl: cfg.baseUrl,
        embeddingApiKey: cfg.apiKey,
        embeddingModel: cfg.model,
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

/// 文档管理对话框
class _KbDocsDialog extends ConsumerStatefulWidget {
  final String kbId;
  final String kbName;
  const _KbDocsDialog({required this.kbId, required this.kbName});

  @override
  ConsumerState<_KbDocsDialog> createState() => _KbDocsDialogState();
}

class _KbDocsDialogState extends ConsumerState<_KbDocsDialog> {
  String get kbId => widget.kbId;
  String get kbName => widget.kbName;

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(kbDocumentsProvider(kbId));
    final progress = ref.watch(kbIndexProgressProvider(kbId));
    final colorScheme = Theme.of(context).colorScheme;

    // 是否有待解析文档 (pending 或 failed)
    final hasPending =
        docsAsync.valueOrNull?.any(
          (d) =>
              d.status == KbDocStatus.pending || d.status == KbDocStatus.failed,
        ) ??
        false;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.s.kbDocsTitle(kbName))),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _importDir(context),
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(context.s.kbImportDir),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _import(context),
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(context.s.kbImportDocs),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (hasPending && !progress.running) ? _startIndex : null,
            icon: progress.running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(
              progress.running ? context.s.kbImporting : context.s.kbStartIndex,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 进度条区域
            if (progress.running || progress.completed > 0) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${progress.completed} / ${progress.total}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              context.s.kbQdrantHint,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: docsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (docs) {
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        context.s.kbDocsEmpty,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return _GroupedDocList(kbId: kbId, docs: docs);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (progress.running)
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check, size: 16),
            label: Text(context.s.kbCloseBackground),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.s.commonClose),
          ),
      ],
    );
  }

  Future<void> _import(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.kbImportPickTitle,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'md',
        'markdown',
        'json',
        'csv',
        'log',
        'yaml',
        'yml',
        'xml',
        'html',
        'htm',
        'pdf',
        'docx',
        'doc',
        'pptx',
        'xlsx',
        'xls',
        'odt',
        'rtf',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    // 仅登记文档 (pending 状态)，不触发解析
    await ref.read(kbDocumentsProvider(kbId).notifier).importFiles(paths);
  }

  /// 导入整个目录: 递归扫描支持的文件类型，批量登记
  Future<void> _importDir(BuildContext context) async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: context.s.kbImportDirPick,
    );
    if (dirPath == null || dirPath.isEmpty) return;

    // 支持的扩展名
    const supportedExts = {
      'txt',
      'md',
      'markdown',
      'json',
      'csv',
      'log',
      'yaml',
      'yml',
      'xml',
      'html',
      'htm',
      'pdf',
      'docx',
      'doc',
      'pptx',
      'xlsx',
      'xls',
      'odt',
      'rtf',
    };

    // 递归扫描目录 (包括所有子目录)
    final dir = Directory(dirPath);
    final files = <({String filename, String sourcePath})>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = p
            .extension(entity.path)
            .replaceFirst('.', '')
            .toLowerCase();
        if (supportedExts.contains(ext)) {
          // filename 用相对路径 (保留子目录层级，避免同名文件冲突)
          final relPath = p.relative(entity.path, from: dirPath);
          files.add((filename: relPath, sourcePath: entity.path));
        }
      }
    }

    if (files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s.kbImportDirEmpty)));
      }
      return;
    }

    // sourceGroup = 文件夹名，UI 分组折叠展示
    final folderName = p.basename(dirPath);
    await ref
        .read(kbDocumentsProvider(kbId).notifier)
        .importDirFiles(files, sourceGroup: folderName);
  }

  /// 一键开始解析 (后台运行，不阻塞对话框交互)
  void _startIndex() {
    ref.read(kbDocumentsProvider(kbId).notifier).indexAllPending();
  }
}

/// 目录树节点
class _TreeNode {
  final String name;
  final String path; // 完整相对路径 (用作展开 key)
  final Map<String, _TreeNode> children = {};
  KbDocument? doc; // 叶子节点才有

  _TreeNode(this.name, this.path);

  int get totalDocs {
    if (doc != null) return 1;
    int n = 0;
    for (final c in children.values) {
      n += c.totalDocs;
    }
    return n;
  }

  int get doneDocs {
    if (doc != null) return doc!.status == KbDocStatus.done ? 1 : 0;
    int n = 0;
    for (final c in children.values) {
      n += c.doneDocs;
    }
    return n;
  }
}

/// 文档目录树 — 按实际目录结构展开/折叠。
class _GroupedDocList extends StatefulWidget {
  final String kbId;
  final List<KbDocument> docs;
  const _GroupedDocList({required this.kbId, required this.docs});

  @override
  State<_GroupedDocList> createState() => _GroupedDocListState();
}

class _GroupedDocListState extends State<_GroupedDocList> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final root = _TreeNode('', '');

    for (final doc in widget.docs) {
      final segments = <String>[];
      if (doc.sourceGroup.isNotEmpty) segments.add(doc.sourceGroup);
      segments.addAll(doc.filename.split(RegExp(r'[/\\]')));

      var current = root;
      final pathBuf = StringBuffer();
      for (var i = 0; i < segments.length - 1; i++) {
        if (pathBuf.isNotEmpty) pathBuf.write('/');
        pathBuf.write(segments[i]);
        final key = segments[i];
        current = current.children.putIfAbsent(
          key,
          () => _TreeNode(key, pathBuf.toString()),
        );
      }
      final leafName = segments.last;
      if (pathBuf.isNotEmpty) pathBuf.write('/');
      pathBuf.write(leafName);
      final leaf = current.children.putIfAbsent(
        leafName,
        () => _TreeNode(leafName, pathBuf.toString()),
      );
      leaf.doc = doc;
    }

    return ListView(children: _buildChildren(root, 0));
  }

  List<Widget> _buildChildren(_TreeNode node, int depth) {
    final sorted = node.children.values.toList()
      ..sort((a, b) {
        final aIsDir = a.doc == null && a.children.isNotEmpty;
        final bIsDir = b.doc == null && b.children.isNotEmpty;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.name.compareTo(b.name);
      });

    final widgets = <Widget>[];
    for (final child in sorted) {
      if (child.doc != null && child.children.isEmpty) {
        widgets.add(_fileTile(child.doc!, depth));
      } else {
        widgets.addAll(_dirTile(child, depth));
      }
    }
    return widgets;
  }

  List<Widget> _dirTile(_TreeNode dirNode, int depth) {
    final colorScheme = Theme.of(context).colorScheme;
    final isExpanded = _expanded.contains(dirNode.path);
    final total = dirNode.totalDocs;
    final done = dirNode.doneDocs;

    final header = InkWell(
      onTap: () => setState(() {
        if (isExpanded) {
          _expanded.remove(dirNode.path);
        } else {
          _expanded.add(dirNode.path);
        }
      }),
      child: Padding(
        padding: EdgeInsets.only(
          left: depth * 20.0 + 4,
          right: 4,
          top: 5,
          bottom: 5,
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dirNode.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              done == total ? '$total ✓' : '$done/$total',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    if (!isExpanded) return [header];
    return [header, ..._buildChildren(dirNode, depth + 1)];
  }

  Widget _fileTile(KbDocument doc, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: _DocTile(kbId: widget.kbId, doc: doc),
    );
  }
}

/// 单份文档条目
class _DocTile extends ConsumerWidget {
  final String kbId;
  final KbDocument doc;
  const _DocTile({required this.kbId, required this.doc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: _statusIcon(context),
      title: Text(
        p.basename(doc.filename),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(_subtitle(context), style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (doc.status == KbDocStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: context.s.kbDocRetry,
              visualDensity: VisualDensity.compact,
              onPressed: () => ref
                  .read(kbDocumentsProvider(kbId).notifier)
                  .retryDocument(doc),
            ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: colorScheme.error,
            ),
            tooltip: context.s.kbDocDelete,
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(BuildContext context) {
    switch (doc.status) {
      case KbDocStatus.indexing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case KbDocStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case KbDocStatus.failed:
        return const Icon(Icons.error_outline, color: Colors.red, size: 20);
      case KbDocStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey, size: 20);
    }
  }

  String _subtitle(BuildContext context) {
    final s = context.s;
    switch (doc.status) {
      case KbDocStatus.indexing:
        return s.kbDocStatusIndexing;
      case KbDocStatus.done:
        return '${s.kbDocStatusDone} · ${s.kbDocChunks(doc.chunkCount)}';
      case KbDocStatus.failed:
        return '${s.kbDocStatusFailed} · ${doc.error}';
      case KbDocStatus.pending:
        return s.kbDocStatusPending;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.s.kbDocDelete),
        content: Text(context.s.kbDocDeleteConfirm(doc.filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(kbDocumentsProvider(kbId).notifier).deleteDocument(doc);
    }
  }
}

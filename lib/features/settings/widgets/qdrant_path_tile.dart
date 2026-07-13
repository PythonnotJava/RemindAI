import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/memory/qdrant_service.dart';
import '../../../providers/settings_provider.dart';

/// Qdrant 可执行文件路径检测/配置卡片
class QdrantPathTile extends ConsumerStatefulWidget {
  final String manualPath;
  const QdrantPathTile({super.key, required this.manualPath});

  @override
  ConsumerState<QdrantPathTile> createState() => _QdrantPathTileState();
}

class _QdrantPathTileState extends ConsumerState<QdrantPathTile> {
  ({String path, String source})? _detected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  @override
  void didUpdateWidget(QdrantPathTile old) {
    super.didUpdateWidget(old);
    if (old.manualPath != widget.manualPath) _detect();
  }

  Future<void> _detect() async {
    setState(() => _loading = true);
    final result = await QdrantService.instance.detectExecutable(
      widget.manualPath,
    );
    if (mounted) {
      setState(() {
        _detected = result;
        _loading = false;
      });
    }
  }
  // PLACEHOLDER_BUILD

  Future<void> _pickManual() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: context.s.qdrantSelectExe,
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await ref.read(settingsProvider.notifier).updateQdrantPath(path);
  }

  Future<void> _clearManual() async {
    await ref.read(settingsProvider.notifier).updateQdrantPath('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final detected = _detected;
    final found = detected != null && detected.path.isNotEmpty;
    final isManual = widget.manualPath.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  found ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: found ? Colors.green : colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  context.s.qdrantDetection,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: context.s.qdrantRedetect,
                    visualDensity: VisualDensity.compact,
                    onPressed: _detect,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // 来源标签
            if (detected != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: found
                      ? colorScheme.secondaryContainer
                      : colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  context.s.qdrantSource(detected.source),
                  style: textTheme.labelSmall?.copyWith(
                    color: found
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 路径
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                found ? detected.path : context.s.qdrantNotFound,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!found) ...[
              const SizedBox(height: 8),
              Text(
                context.s.qdrantNotFoundHint,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pickManual,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(
                    isManual
                        ? context.s.qdrantChangePath
                        : context.s.qdrantManualSelect,
                  ),
                ),
                if (isManual) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _clearManual,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(context.s.qdrantAutoDetect),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.s.qdrantPriority,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

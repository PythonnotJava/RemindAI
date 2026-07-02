import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n/l10n_ext.dart';
import '../../core/logger/app_logger.dart';

/// 把日志内容按行倒序，使最新写入的一行排在最前面（顶部）。
/// 日志文件本身是旧行在前、新行追加在末尾（见 AppLogger.log），
/// 这里只在展示层倒序，不改动底层文件的实际存储顺序。
/// 提取为顶层函数以便单元测试覆盖，不依赖 State/BuildContext。
String reverseLogLines(String content) {
  if (content.isEmpty) return content;
  // 保留末尾可能存在的空行语义：先按换行拆分再整体反转。
  final lines = content.split('\n');
  return lines.reversed.join('\n');
}

/// 日志管理页面 — 查看 / 切换日期 / 清空
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<FileSystemEntity> _logFiles = [];
  String _selectedFileName = '';
  String _content = '';
  bool _loading = true;
  int _totalSize = 0;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final logger = AppLogger.instance;
    final files = await logger.listLogFiles();
    final size = await logger.totalSize();

    String content = '';
    String selected = '';
    if (files.isNotEmpty) {
      selected = p.basename(files.first.path);
      content = await logger.readFile(selected);
    }

    if (!mounted) return;
    setState(() {
      _logFiles = files;
      _selectedFileName = selected;
      _content = content;
      _totalSize = size;
      _loading = false;
    });
  }

  Future<void> _selectFile(String fileName) async {
    final content = await AppLogger.instance.readFile(fileName);
    if (!mounted) return;
    setState(() {
      _selectedFileName = fileName;
      _content = content;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever, size: 32),
        title: Text(context.s.logsClearAllTitle),
        content: Text(
          context.s.logsClearAllConfirm(_logFiles.length, _formattedSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.s.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.s.commonClear),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final count = await AppLogger.instance.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.logsClearedCount(count))),
        );
        _loadFiles();
      }
    }
  }

  String get _formattedSize {
    if (_totalSize <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = _totalSize.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.s.logsTitle),
        actions: [
          Chip(
            avatar: const Icon(Icons.storage, size: 16),
            label: Text(_formattedSize, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.s.logsRefresh,
            onPressed: _loadFiles,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.s.logsClearAllTitle,
            onPressed: _logFiles.isEmpty ? null : _clearAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _logFiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 48,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.s.logsEmpty,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                // 左侧: 日志文件列表
                SizedBox(
                  width: 160,
                  child: ListView.builder(
                    itemCount: _logFiles.length,
                    itemBuilder: (ctx, index) {
                      final name = p.basename(_logFiles[index].path);
                      final isSelected = name == _selectedFileName;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        title: Text(
                          name.replaceAll('.log', ''),
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => _selectFile(name),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                // 右侧: 日志内容
                Expanded(
                  child: _content.isEmpty
                      ? Center(
                          child: Text(
                            context.s.logsContentEmpty,
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        )
                      : SelectableText(
                          // 新日志在前：文件内是旧→新追加写入，这里展示时倒序，
                          // 打开页面即看到最新记录，无需滚动到底部。
                          reverseLogLines(_content),
                          scrollPhysics: const ClampingScrollPhysics(),
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 12,
                            height: 1.5,
                            color: colorScheme.onSurface,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

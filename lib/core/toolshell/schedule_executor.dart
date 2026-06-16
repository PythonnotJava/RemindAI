import 'dart:convert';
import 'dart:io';

/// Schedule 技能工具执行器
/// 解析和操作 SCHEDULE.md 文件
class ScheduleExecutor {
  final String projectRoot;

  ScheduleExecutor({required this.projectRoot});

  /// 统一执行入口
  Future<String> run(String toolName, Map<String, dynamic> args) async {
    try {
      return switch (toolName) {
        'schedule_load' => await _load(args),
        'schedule_add_task' => await _addTask(args),
        'schedule_complete' => await _complete(args),
        'schedule_update' => await _update(args),
        'schedule_delete' => await _delete(args),
        'schedule_review' => await _review(args),
        'schedule_archive' => await _archive(args),
        _ => _err('UNKNOWN_TOOL', toolName),
      };
    } catch (e) {
      return _err('EXCEPTION', e.toString());
    }
  }

  // ─── 路径解析 ─────────────────────────────────────────────

  String _resolvePath(String? path) {
    final filename = path ?? 'SCHEDULE.md';
    if (filename.contains('..')) throw Exception('路径不安全');
    return '$projectRoot/$filename';
  }

  // ─── schedule_load ────────────────────────────────────────

  Future<String> _load(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final file = File(filePath);

    if (!await file.exists()) {
      // 创建模板
      await file.writeAsString(_template());
      return _ok({
        'created': true,
        'tasks': <Map<String, dynamic>>[],
        'message': '已创建 SCHEDULE.md 模板',
      });
    }

    final content = await file.readAsString();
    final tasks = _parseTasks(content);

    final p0 = tasks.where((t) => t['priority'] == 'P0' && !t['done']).length;
    final p1 = tasks.where((t) => t['priority'] == 'P1' && !t['done']).length;
    final p2 = tasks.where((t) => t['priority'] == 'P2' && !t['done']).length;
    final done = tasks.where((t) => t['done']).length;

    return _ok({
      'tasks': tasks,
      'summary': {
        'p0_pending': p0,
        'p1_pending': p1,
        'p2_pending': p2,
        'completed': done,
        'total': tasks.length,
      },
    });
  }

  // ─── schedule_add_task ────────────────────────────────────

  Future<String> _addTask(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final task = args['task'] as String;
    final priority = args['priority'] as String;
    final after = args['after'] as String?;
    final tags = (args['tags'] as List?)?.cast<String>() ?? [];
    final note = args['note'] as String?;

    final file = File(filePath);
    if (!await file.exists()) {
      await file.writeAsString(_template());
    }

    final content = await file.readAsString();
    final lines = content.split('\n');

    // 构建任务行
    final tagStr = tags.isNotEmpty
        ? ' ${tags.map((t) => '`#$t`').join(' ')}'
        : '';
    final noteStr = note != null ? ' — $note' : '';
    final taskLine = '- [ ] $task$tagStr$noteStr';

    // 找到对应优先级区域
    final sectionHeader = _sectionHeader(priority);
    int insertIdx = -1;

    // 查找该优先级的 section
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith(sectionHeader)) {
        // 找到 section，定位插入点
        if (after != null && after.isNotEmpty) {
          // 在 "after" 匹配的任务之后插入
          for (int j = i + 1; j < lines.length; j++) {
            if (lines[j].startsWith('## ')) break; // 到了下一个 section
            if (lines[j].contains(after)) {
              insertIdx = j + 1;
              break;
            }
          }
        }
        if (insertIdx == -1) {
          // 追加到该 section 末尾（下一个 ## 之前）
          int end = i + 1;
          while (end < lines.length && !lines[end].startsWith('## ')) {
            end++;
          }
          // 往回跳过空行
          while (end > i + 1 && lines[end - 1].trim().isEmpty) {
            end--;
          }
          insertIdx = end;
        }
        break;
      }
    }

    if (insertIdx == -1) {
      // section 不存在，在文件末尾前添加
      lines.add('');
      lines.add(sectionHeader);
      lines.add(taskLine);
      insertIdx = lines.length - 1;
    } else {
      lines.insert(insertIdx, taskLine);
    }

    // 更新时间戳
    final updated = _updateTimestamp(lines.join('\n'));
    await file.writeAsString(updated);

    return _ok({
      'added': task,
      'priority': priority,
      'position': insertIdx,
      'tags': tags,
    });
  }

  // ─── schedule_complete ────────────────────────────────────

  Future<String> _complete(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final taskMatch = args['task_match'] as String;
    final summary = args['summary'] as String?;

    final file = File(filePath);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', filePath);

    final content = await file.readAsString();
    final lines = content.split('\n');

    // 查找匹配的任务
    int foundIdx = -1;
    String foundLine = '';
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('- [ ]') && lines[i].contains(taskMatch)) {
        foundIdx = i;
        foundLine = lines[i];
        break;
      }
    }

    if (foundIdx == -1) {
      return _err('TASK_NOT_FOUND', '未找到匹配: $taskMatch');
    }

    // 从原位置删除
    lines.removeAt(foundIdx);

    // 构建完成行
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final originalTask = foundLine.replaceFirst('- [ ] ', '');
    final summaryStr = summary != null ? ' ($summary)' : '';
    final completedLine = '- [x] $originalTask — $dateStr 完成$summaryStr';

    // 找到已完成区域并插入
    int doneIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('## ✅')) {
        doneIdx = i + 1;
        break;
      }
    }

    if (doneIdx == -1) {
      // 创建已完成区域
      lines.add('');
      lines.add('## ✅ 已完成');
      lines.add(completedLine);
    } else {
      lines.insert(doneIdx, completedLine);
    }

    final updated = _updateTimestamp(lines.join('\n'));
    await file.writeAsString(updated);

    return _ok({
      'completed': originalTask,
      'date': dateStr,
      'summary': summary,
    });
  }

  // ─── schedule_update ──────────────────────────────────────

  Future<String> _update(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final taskMatch = args['task_match'] as String;
    final newPriority = args['new_priority'] as String?;
    final newText = args['new_text'] as String?;
    final newNote = args['new_note'] as String?;

    final file = File(filePath);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', filePath);

    final content = await file.readAsString();
    final lines = content.split('\n');

    // 查找匹配的任务
    int foundIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('- [ ]') && lines[i].contains(taskMatch)) {
        foundIdx = i;
        break;
      }
    }

    if (foundIdx == -1) {
      return _err('TASK_NOT_FOUND', '未找到匹配: $taskMatch');
    }

    String taskLine = lines[foundIdx];

    // 更新文本
    if (newText != null) {
      // 保留标签和备注
      final existingNote = taskLine.contains(' — ')
          ? ' — ${taskLine.split(' — ').last}'
          : '';
      taskLine = '- [ ] $newText$existingNote';
    }

    // 更新备注
    if (newNote != null) {
      if (taskLine.contains(' — ')) {
        taskLine = '${taskLine.split(' — ').first} — $newNote';
      } else {
        taskLine = '$taskLine — $newNote';
      }
    }

    // 优先级变更 = 移动到新 section
    if (newPriority != null) {
      lines.removeAt(foundIdx);
      // 重新插入到新优先级区域
      final sectionHeader = _sectionHeader(newPriority);
      int insertIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith(sectionHeader)) {
          int end = i + 1;
          while (end < lines.length && !lines[end].startsWith('## ')) {
            end++;
          }
          while (end > i + 1 && lines[end - 1].trim().isEmpty) {
            end--;
          }
          insertIdx = end;
          break;
        }
      }
      if (insertIdx != -1) {
        lines.insert(insertIdx, taskLine);
      } else {
        lines.add('');
        lines.add(sectionHeader);
        lines.add(taskLine);
      }
    } else {
      lines[foundIdx] = taskLine;
    }

    final updated = _updateTimestamp(lines.join('\n'));
    await file.writeAsString(updated);

    return _ok({
      'updated': taskMatch,
      'new_priority': newPriority,
      'new_text': newText,
      'new_note': newNote,
    });
  }

  // ─── schedule_delete ───────────────────────────────────────

  Future<String> _delete(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final taskMatch = args['task_match'] as String;
    final reason = args['reason'] as String?;

    final file = File(filePath);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', filePath);

    final content = await file.readAsString();
    final lines = content.split('\n');

    // 查找匹配的任务 (待办)
    int foundIdx = -1;
    String foundLine = '';
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('- [ ]') && lines[i].contains(taskMatch)) {
        foundIdx = i;
        foundLine = lines[i];
        break;
      }
    }

    if (foundIdx == -1) {
      return _err('TASK_NOT_FOUND', '未找到匹配: $taskMatch');
    }

    // 直接删除该行
    lines.removeAt(foundIdx);

    final updated = _updateTimestamp(lines.join('\n'));
    await file.writeAsString(updated);

    final taskText = foundLine.replaceFirst(RegExp(r'^- \[[ x]\] '), '').trim();
    return _ok({'deleted': taskText, 'reason': reason});
  }

  // ─── schedule_review ──────────────────────────────────────

  Future<String> _review(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final file = File(filePath);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', filePath);

    final content = await file.readAsString();
    final tasks = _parseTasks(content);

    final pending = tasks.where((t) => !t['done']).toList();
    final done = tasks.where((t) => t['done']).toList();
    final p0 = pending.where((t) => t['priority'] == 'P0').toList();
    final p1 = pending.where((t) => t['priority'] == 'P1').toList();
    final p2 = pending.where((t) => t['priority'] == 'P2').toList();

    // 建议下一步
    String suggestion = '';
    if (p0.isNotEmpty) {
      suggestion = '建议聚焦: ${p0.first['text']}';
    } else if (p1.isNotEmpty) {
      suggestion = '建议聚焦: ${p1.first['text']}';
    } else if (p2.isNotEmpty) {
      suggestion = '所有重要任务已完成，可选做: ${p2.first['text']}';
    } else {
      suggestion = '所有任务已完成！';
    }

    return _ok({
      'summary': {
        'total_pending': pending.length,
        'total_completed': done.length,
        'p0': p0.map((t) => t['text']).toList(),
        'p1': p1.map((t) => t['text']).toList(),
        'p2': p2.map((t) => t['text']).toList(),
        'recent_completed': done.take(3).map((t) => t['text']).toList(),
      },
      'suggestion': suggestion,
    });
  }

  // ─── schedule_archive ─────────────────────────────────────

  Future<String> _archive(Map<String, dynamic> args) async {
    final filePath = _resolvePath(args['path'] as String?);
    final days = args['days'] as int? ?? 7;

    final file = File(filePath);
    if (!await file.exists()) return _err('FILE_NOT_FOUND', filePath);

    final content = await file.readAsString();
    final lines = content.split('\n');
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: days));

    // 找到已完成 section
    int doneStart = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('## ✅')) {
        doneStart = i + 1;
        break;
      }
    }

    if (doneStart == -1) return _ok({'archived': 0, 'message': '无已完成任务'});

    final toArchive = <String>[];
    final toKeep = <int>[];

    for (int i = doneStart; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) break; // 到了下个 section
      if (!lines[i].startsWith('- [x]')) continue;

      // 尝试解析日期
      final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(lines[i]);
      if (dateMatch != null) {
        final date = DateTime.tryParse(dateMatch.group(1)!);
        if (date != null && date.isBefore(cutoff)) {
          toArchive.add(lines[i]);
          toKeep.add(i);
          continue;
        }
      }
      // 没有日期的也保留
    }

    if (toArchive.isEmpty) {
      return _ok({'archived': 0, 'message': '无需归档'});
    }

    // 从主文件删除
    for (int i = toKeep.length - 1; i >= 0; i--) {
      lines.removeAt(toKeep[i]);
    }
    await file.writeAsString(_updateTimestamp(lines.join('\n')));

    // 追加到归档文件
    final archivePath = filePath.replaceAll('.md', '_ARCHIVE.md');
    final archiveFile = File(archivePath);
    final archiveContent = await archiveFile.exists()
        ? await archiveFile.readAsString()
        : '# 计划归档\n\n';
    final newArchive = '$archiveContent${toArchive.join('\n')}\n';
    await archiveFile.writeAsString(newArchive);

    return _ok({'archived': toArchive.length, 'archive_file': archivePath});
  }

  // ─── 辅助方法 ─────────────────────────────────────────────

  /// 解析 SCHEDULE.md 中的所有任务
  List<Map<String, dynamic>> _parseTasks(String content) {
    final tasks = <Map<String, dynamic>>[];
    final lines = content.split('\n');
    String currentPriority = 'P2';

    for (final line in lines) {
      if (line.startsWith('## 🔴')) currentPriority = 'P0';
      if (line.startsWith('## 🟡')) currentPriority = 'P1';
      if (line.startsWith('## 🟢')) currentPriority = 'P2';
      if (line.startsWith('## ✅')) currentPriority = 'done';

      if (line.startsWith('- [ ]') || line.startsWith('- [x]')) {
        final done = line.startsWith('- [x]');
        final text = line.replaceFirst(RegExp(r'^- \[[ x]\] '), '').trim();

        // 提取标签
        final tagMatches = RegExp(r'`#(\w+)`').allMatches(text);
        final tags = tagMatches.map((m) => m.group(1)!).toList();

        tasks.add({
          'text': text,
          'priority': done ? 'done' : currentPriority,
          'done': done,
          'tags': tags,
        });
      }
    }

    return tasks;
  }

  /// 获取优先级对应的 section 标题
  String _sectionHeader(String priority) {
    return switch (priority) {
      'P0' => '## 🔴 P0 - 紧急',
      'P1' => '## 🟡 P1 - 重要',
      'P2' => '## 🟢 P2 - 一般',
      _ => '## 🟢 P2 - 一般',
    };
  }

  /// 更新文件头部时间戳
  String _updateTimestamp(String content) {
    final now = DateTime.now();
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // 替换或插入时间戳行
    final tsRegex = RegExp(r'^> 最后更新:.*$', multiLine: true);
    if (tsRegex.hasMatch(content)) {
      return content.replaceFirst(tsRegex, '> 最后更新: $timeStr');
    } else {
      // 在第一个标题后插入
      final firstLine = content.indexOf('\n');
      if (firstLine != -1) {
        return '${content.substring(0, firstLine + 1)}> 最后更新: $timeStr\n${content.substring(firstLine + 1)}';
      }
      return '> 最后更新: $timeStr\n$content';
    }
  }

  /// SCHEDULE.md 模板
  String _template() {
    final now = DateTime.now();
    final timeStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return '''# 工作计划
> 最后更新: $timeStr

## 🔴 P0 - 紧急

## 🟡 P1 - 重要

## 🟢 P2 - 一般

## ✅ 已完成
''';
  }

  String _ok(Map<String, dynamic> data) =>
      jsonEncode({'status': 'ok', ...data});

  String _err(String code, String detail) =>
      jsonEncode({'status': 'error', 'code': code, 'detail': detail});
}

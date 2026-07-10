import 'dart:io';

class Statistics {
  int files = 0;
  int totalLines = 0;
  int codeLines = 0;
  int commentLines = 0;
  int blankLines = 0;
}

void main(List<String> args) {
  final directory = Directory(args.isEmpty ? '.' : args.first);

  if (!directory.existsSync()) {
    print('目录不存在');
    return;
  }

  final stat = Statistics();

  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    stat.files++;

    bool inBlockComment = false;

    for (final line in entity.readAsLinesSync()) {
      stat.totalLines++;

      final text = line.trim();

      if (text.isEmpty) {
        stat.blankLines++;
        continue;
      }

      if (inBlockComment) {
        stat.commentLines++;
        if (text.contains('*/')) {
          inBlockComment = false;
        }
        continue;
      }

      if (text.startsWith('//')) {
        stat.commentLines++;
        continue;
      }

      if (text.startsWith('/*')) {
        stat.commentLines++;
        if (!text.contains('*/')) {
          inBlockComment = true;
        }
        continue;
      }

      stat.codeLines++;
    }
  }

  print('========== 总计 ==========');
  print('Dart 文件数 : ${stat.files}');
  print('总代码行数 : ${stat.totalLines}');
  print('有效代码行 : ${stat.codeLines}');
  print('注释行数   : ${stat.commentLines}');
  print('空行数     : ${stat.blankLines}');
}

// dart compile exe counter.dart -o counter.exe
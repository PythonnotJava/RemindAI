// import 'dart:io';
//
// void main(List<String> args) async {
//   final rootPath = args.isNotEmpty ? args[0] : '.';
//
//   int totalLines = 0;
//   int blankLines = 0;
//   int commentLines = 0;
//   int codeLines = 0;
//   int fileCount = 0;
//
//   await for (final entity
//       in Directory(rootPath).list(recursive: true, followLinks: false)) {
//     if (entity is! File) continue;
//     if (!entity.path.endsWith('.dart')) continue;
//
//     fileCount++;
//
//     final lines = await entity.readAsLines();
//
//     bool inBlockComment = false;
//
//     for (var line in lines) {
//       totalLines++;
//
//       final text = line.trim();
//
//       if (text.isEmpty) {
//         blankLines++;
//         continue;
//       }
//
//       if (inBlockComment) {
//         commentLines++;
//         if (text.contains('*/')) {
//           inBlockComment = false;
//         }
//         continue;
//       }
//
//       if (text.startsWith('//')) {
//         commentLines++;
//         continue;
//       }
//
//       if (text.startsWith('/*')) {
//         commentLines++;
//         if (!text.contains('*/')) {
//           inBlockComment = true;
//         }
//         continue;
//       }
//
//       codeLines++;
//     }
//   }
//
//   print('统计结果');
//   print('======================');
//   print('Dart文件数 : $fileCount');
//   print('总代码行数 : $totalLines');
//   print('代码行数   : $codeLines');
//   print('注释行数   : $commentLines');
//   if (kDebugMode) {
//     print('空白行数   : $blankLines');
//   }
// }
//

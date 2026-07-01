// 语法高亮任务 — 在 Isolate 中对代码块做 token 化和高亮标注。
//
// 适用场景:
// - 大代码块 (>200行) 的语法高亮
// - 批量代码块高亮（长消息中多个代码块）
//
// 注意: flutter_highlight 的 `highlight()` 依赖 dart:ui (TextSpan)，
// 不能直接在 Isolate 中使用。这里做的是"预 token 化"——将代码分词并标注类型，
// 主 isolate 拿到结果后映射为 TextSpan 颜色即可，避免正则匹配在主线程执行。

/// 代码 token 类型
enum CodeTokenType {
  keyword,
  string,
  comment,
  number,
  punctuation,
  identifier,
  operator,
  type,
  function,
  plain,
}

/// 单个代码 token
class CodeToken {
  final CodeTokenType type;
  final String text;

  CodeToken(this.type, this.text);
}

/// 高亮预处理结果
class HighlightResult {
  final String language;
  final List<CodeToken> tokens;
  final int lineCount;

  HighlightResult({
    required this.language,
    required this.tokens,
    required this.lineCount,
  });
}

/// 高亮任务参数
class HighlightParam {
  final String code;
  final String language;

  HighlightParam({required this.code, required this.language});
}

/// 顶层函数: 代码预 token 化（可传入 Isolate）
///
/// 根据语言进行基础分词+分类，返回 token 列表。
/// 主 isolate 收到后直接映射为 TextSpan，无需再做正则匹配。
HighlightResult highlightPreTokenizeTask(HighlightParam param) {
  final tokens = _tokenize(param.code, param.language);
  return HighlightResult(
    language: param.language,
    tokens: tokens,
    lineCount: param.code.split('\n').length,
  );
}

/// 批量代码高亮
List<HighlightResult> highlightBatchTask(List<HighlightParam> params) {
  return params.map(highlightPreTokenizeTask).toList();
}

// =============================================================================
// 通用 Tokenizer (简化版，覆盖主流语言基础语法)
// =============================================================================

List<CodeToken> _tokenize(String code, String language) {
  final tokens = <CodeToken>[];
  final keywords = _getKeywords(language);
  final typeKeywords = _getTypeKeywords(language);

  int i = 0;
  while (i < code.length) {
    // 跳过空白（保留）
    if (_isWhitespace(code[i])) {
      final start = i;
      while (i < code.length && _isWhitespace(code[i])) {
        i++;
      }
      tokens.add(CodeToken(CodeTokenType.plain, code.substring(start, i)));
      continue;
    }

    // 单行注释
    if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
      final start = i;
      while (i < code.length && code[i] != '\n') {
        i++;
      }
      tokens.add(CodeToken(CodeTokenType.comment, code.substring(start, i)));
      continue;
    }

    // 块注释
    if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
      final start = i;
      i += 2;
      while (i + 1 < code.length && !(code[i] == '*' && code[i + 1] == '/')) {
        i++;
      }
      i += 2;
      tokens.add(CodeToken(CodeTokenType.comment, code.substring(start, i)));
      continue;
    }

    // Python/Shell # 注释
    if (code[i] == '#' &&
        (language == 'python' ||
            language == 'py' ||
            language == 'bash' ||
            language == 'sh' ||
            language == 'yaml')) {
      final start = i;
      while (i < code.length && code[i] != '\n') {
        i++;
      }
      tokens.add(CodeToken(CodeTokenType.comment, code.substring(start, i)));
      continue;
    }

    // 字符串 (单引号/双引号)
    if (code[i] == '"' || code[i] == '\'') {
      final quote = code[i];
      final start = i;
      i++;
      while (i < code.length && code[i] != quote) {
        if (code[i] == '\\') i++; // 跳过转义
        i++;
      }
      if (i < code.length) i++; // 跳过关闭引号
      tokens.add(CodeToken(CodeTokenType.string, code.substring(start, i)));
      continue;
    }

    // 数字
    if (_isDigit(code[i])) {
      final start = i;
      while (i < code.length &&
          (_isDigit(code[i]) ||
              code[i] == '.' ||
              code[i] == 'x' ||
              code[i] == 'X')) {
        i++;
      }
      tokens.add(CodeToken(CodeTokenType.number, code.substring(start, i)));
      continue;
    }

    // 标识符/关键字
    if (_isIdentStart(code[i])) {
      final start = i;
      while (i < code.length && _isIdentChar(code[i])) {
        i++;
      }
      final word = code.substring(start, i);
      if (keywords.contains(word)) {
        tokens.add(CodeToken(CodeTokenType.keyword, word));
      } else if (typeKeywords.contains(word)) {
        tokens.add(CodeToken(CodeTokenType.type, word));
      } else {
        tokens.add(CodeToken(CodeTokenType.identifier, word));
      }
      continue;
    }

    // 运算符
    if (_isOperator(code[i])) {
      tokens.add(CodeToken(CodeTokenType.operator, code[i]));
      i++;
      continue;
    }

    // 标点
    if (_isPunctuation(code[i])) {
      tokens.add(CodeToken(CodeTokenType.punctuation, code[i]));
      i++;
      continue;
    }

    // 其他
    tokens.add(CodeToken(CodeTokenType.plain, code[i]));
    i++;
  }

  return tokens;
}

bool _isWhitespace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
bool _isIdentStart(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      c == '_' ||
      c == '\$';
}

bool _isIdentChar(String c) => _isIdentStart(c) || _isDigit(c);
bool _isOperator(String c) => '+-*/%=<>&|^~!?'.contains(c);
bool _isPunctuation(String c) => '(){}[];:.,@'.contains(c);

Set<String> _getKeywords(String language) {
  switch (language.toLowerCase()) {
    case 'dart':
      return {
        'abstract',
        'as',
        'assert',
        'async',
        'await',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'covariant',
        'default',
        'deferred',
        'do',
        'dynamic',
        'else',
        'enum',
        'export',
        'extends',
        'extension',
        'external',
        'factory',
        'false',
        'final',
        'finally',
        'for',
        'get',
        'hide',
        'if',
        'implements',
        'import',
        'in',
        'interface',
        'is',
        'late',
        'library',
        'mixin',
        'new',
        'null',
        'on',
        'operator',
        'part',
        'required',
        'rethrow',
        'return',
        'sealed',
        'set',
        'show',
        'static',
        'super',
        'switch',
        'sync',
        'this',
        'throw',
        'true',
        'try',
        'typedef',
        'var',
        'void',
        'when',
        'while',
        'with',
        'yield',
      };
    case 'python':
    case 'py':
      return {
        'and',
        'as',
        'assert',
        'async',
        'await',
        'break',
        'class',
        'continue',
        'def',
        'del',
        'elif',
        'else',
        'except',
        'finally',
        'for',
        'from',
        'global',
        'if',
        'import',
        'in',
        'is',
        'lambda',
        'nonlocal',
        'not',
        'or',
        'pass',
        'raise',
        'return',
        'try',
        'while',
        'with',
        'yield',
        'True',
        'False',
        'None',
      };
    case 'javascript':
    case 'js':
    case 'typescript':
    case 'ts':
      return {
        'abstract',
        'arguments',
        'async',
        'await',
        'boolean',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'debugger',
        'default',
        'delete',
        'do',
        'else',
        'enum',
        'export',
        'extends',
        'false',
        'finally',
        'for',
        'function',
        'get',
        'if',
        'implements',
        'import',
        'in',
        'instanceof',
        'interface',
        'let',
        'new',
        'null',
        'of',
        'package',
        'private',
        'protected',
        'public',
        'return',
        'set',
        'static',
        'super',
        'switch',
        'this',
        'throw',
        'true',
        'try',
        'typeof',
        'undefined',
        'var',
        'void',
        'while',
        'with',
        'yield',
      };
    case 'rust':
    case 'rs':
      return {
        'as',
        'async',
        'await',
        'break',
        'const',
        'continue',
        'crate',
        'dyn',
        'else',
        'enum',
        'extern',
        'false',
        'fn',
        'for',
        'if',
        'impl',
        'in',
        'let',
        'loop',
        'match',
        'mod',
        'move',
        'mut',
        'pub',
        'ref',
        'return',
        'self',
        'Self',
        'static',
        'struct',
        'super',
        'trait',
        'true',
        'type',
        'unsafe',
        'use',
        'where',
        'while',
      };
    default:
      return {
        'if',
        'else',
        'for',
        'while',
        'do',
        'switch',
        'case',
        'break',
        'continue',
        'return',
        'class',
        'function',
        'var',
        'const',
        'let',
        'new',
        'this',
        'true',
        'false',
        'null',
        'try',
        'catch',
        'throw',
        'import',
        'export',
        'from',
        'async',
        'await',
      };
  }
}

Set<String> _getTypeKeywords(String language) {
  switch (language.toLowerCase()) {
    case 'dart':
      return {
        'int',
        'double',
        'String',
        'bool',
        'List',
        'Map',
        'Set',
        'Future',
        'Stream',
        'Iterable',
        'Object',
        'Type',
        'Function',
        'num',
        'Never',
        'Null',
        'Duration',
        'DateTime',
        'Uri',
        'File',
        'Directory',
        'Widget',
        'State',
        'BuildContext',
        'Key',
      };
    case 'python':
    case 'py':
      return {
        'int',
        'float',
        'str',
        'bool',
        'list',
        'dict',
        'set',
        'tuple',
        'bytes',
        'type',
        'object',
        'range',
        'complex',
      };
    case 'javascript':
    case 'js':
    case 'typescript':
    case 'ts':
      return {
        'string',
        'number',
        'boolean',
        'object',
        'symbol',
        'bigint',
        'any',
        'unknown',
        'never',
        'void',
        'Array',
        'Promise',
        'Map',
        'Set',
        'Record',
        'Partial',
        'Required',
        'Readonly',
      };
    case 'rust':
    case 'rs':
      return {
        'i8',
        'i16',
        'i32',
        'i64',
        'i128',
        'isize',
        'u8',
        'u16',
        'u32',
        'u64',
        'u128',
        'usize',
        'f32',
        'f64',
        'bool',
        'char',
        'str',
        'String',
        'Vec',
        'Option',
        'Result',
        'Box',
        'Rc',
        'Arc',
      };
    default:
      return {};
  }
}

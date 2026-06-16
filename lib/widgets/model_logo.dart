import 'dart:io';
import 'package:flutter/material.dart';

/// 模型品牌识别 + Logo 展示。
///
/// 优先级：用户导入的 logo 文件 > 品牌色 + 首字母兜底。
/// 不依赖任何外部资源，匹配不到品牌时用名称首字母 + 主题色圆标。
class ModelLogo extends StatelessWidget {
  /// 用户导入的 logo 文件路径，空则走品牌/首字母兜底。
  final String logoPath;

  /// 卡片名称 (兜底首字母来源)。
  final String name;

  /// 模型 ID / baseUrl，用于品牌关键字识别。
  final String modelId;

  final double size;

  const ModelLogo({
    super.key,
    required this.logoPath,
    required this.name,
    required this.modelId,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    // 1. 用户导入的 logo 文件
    if (logoPath.isNotEmpty) {
      final file = File(logoPath);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _fallback(context),
          ),
        );
      }
    }
    // 2. 品牌识别 / 首字母兜底
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final brand = ModelBrand.detect('$name $modelId');
    final color = brand?.color ?? Theme.of(context).colorScheme.primary;
    final letter = (brand?.label ?? _firstLetter(name)).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.46,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _firstLetter(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : t.characters.first;
  }
}

/// 已知模型品牌 (用于兜底配色 + 标识字母)。
class ModelBrand {
  final String label;
  final Color color;

  const ModelBrand(this.label, this.color);

  /// 按关键字匹配品牌，匹配不到返回 null。
  static ModelBrand? detect(String text) {
    final s = text.toLowerCase();
    for (final entry in _rules) {
      for (final kw in entry.keywords) {
        if (s.contains(kw)) return entry.brand;
      }
    }
    return null;
  }

  // 关键字 → 品牌。顺序靠前优先 (更具体的放前面)。
  static final List<_BrandRule> _rules = [
    _BrandRule([
      'claude',
      'anthropic',
    ], const ModelBrand('C', Color(0xFFD97757))),
    _BrandRule([
      'gpt',
      'o1',
      'o3',
      'o4',
      'openai',
      'chatgpt',
      'davinci',
    ], const ModelBrand('AI', Color(0xFF10A37F))),
    _BrandRule([
      'gemini',
      'palm',
      'bard',
    ], const ModelBrand('G', Color(0xFF4285F4))),
    _BrandRule(['deepseek'], const ModelBrand('D', Color(0xFF4D6BFE))),
    _BrandRule([
      'qwen',
      'qwq',
      '通义',
      'tongyi',
    ], const ModelBrand('Q', Color(0xFF615CED))),
    _BrandRule([
      'glm',
      'chatglm',
      '智谱',
      'zhipu',
    ], const ModelBrand('Z', Color(0xFF3859FF))),
    _BrandRule(['minimax', 'abab'], const ModelBrand('M', Color(0xFFE1467C))),
    _BrandRule(['moonshot', 'kimi'], const ModelBrand('K', Color(0xFF16162B))),
    _BrandRule(['grok', 'xai'], const ModelBrand('X', Color(0xFF000000))),
    _BrandRule(['llama', 'meta'], const ModelBrand('L', Color(0xFF0866FF))),
    _BrandRule([
      'mistral',
      'mixtral',
    ], const ModelBrand('M', Color(0xFFFF7000))),
    _BrandRule([
      'yi-',
      '零一',
      '01-ai',
      '01ai',
    ], const ModelBrand('Y', Color(0xFF00A67E))),
    _BrandRule([
      'doubao',
      '豆包',
      'volc',
    ], const ModelBrand('豆', Color(0xFF4254FB))),
    _BrandRule([
      'hunyuan',
      '混元',
      'tencent',
    ], const ModelBrand('混', Color(0xFF0052D9))),
    _BrandRule([
      'ernie',
      '文心',
      'baidu',
      'wenxin',
    ], const ModelBrand('文', Color(0xFF2932E1))),
    _BrandRule([
      'spark',
      '星火',
      'xunfei',
      'iflytek',
    ], const ModelBrand('星', Color(0xFF1E6FFF))),
    _BrandRule([
      'command',
      'cohere',
    ], const ModelBrand('Co', Color(0xFF39594D))),
    _BrandRule([
      'phi-',
      'phi3',
      'phi4',
    ], const ModelBrand('P', Color(0xFF0078D4))),
    _BrandRule(['gemma'], const ModelBrand('Ge', Color(0xFF4285F4))),
  ];
}

class _BrandRule {
  final List<String> keywords;
  final ModelBrand brand;
  const _BrandRule(this.keywords, this.brand);
}

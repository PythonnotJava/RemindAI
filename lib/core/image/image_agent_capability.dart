import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent/agent_capability.dart';
import '../agent/tool_pipeline.dart';
import '../logger/app_logger.dart';
import 'image_agent_service.dart';
import 'session_image_registry.dart';

/// 画图子 Agent 能力。
///
/// 用户在对话输入栏选择一张模型卡作为「子画图 Agent」后，本能力会向 LLM
/// 注册 `image_generate` 工具。模型需要先判断用户意图：
///   - `mode=new`：从零生成一张新图；
///   - `mode=edit`：基于已有图片修改/重绘/风格转换/继续编辑；
///   - `mode=auto`：不确定时使用，框架根据是否提供输入图自动判断。
///
/// 输入图通过 [SessionImageRegistry] 中的稳定 ID（A1/G1…）引用，模型
/// 不需要复制磁盘路径；框架负责把 ID 解析成真实文件。
///
/// 调用顺序：
///   1. 先用用户选择的子画图模型；
///   2. 失败（额度/模型下架/网络/协议不匹配等）自动用当前对话的主模型兜底；
///   3. 都失败才把错误返回给 LLM 和 UI。
class ImageAgentCapability extends AgentCapability {
  /// 子画图模型。null 表示已选模型卡被删除。
  final ImageModelSpec? subCard;

  /// 当前对话主模型，兜底用。
  final ImageModelSpec? mainCard;

  /// 当前工作目录。为空时图片落到 `.RemindAI/generated/images`。
  final String workDir;

  /// 子模型不可用的原因（如已被删除）。
  final String? unavailableReason;

  /// 会话级图片注册表，负责 ID ↔ 路径解析与图片上下文清单。
  final SessionImageRegistry registry;

  ImageAgentCapability({
    required this.subCard,
    required this.mainCard,
    required this.workDir,
    required this.registry,
    this.unavailableReason,
  });

  @override
  String get id => 'image_agent';

  @override
  String get displayName => '画图';

  @override
  bool get isActive => subCard != null || mainCard != null;

  @override
  List<Map<String, dynamic>> get toolDefinitions => [
    {
      'type': 'function',
      'function': {
        'name': 'image_generate',
        'description':
            '生成或修改图片。必须先根据用户意图选择 mode：\n'
            '- new：从零生成一张新图（用户没有提供要修改的图片）。\n'
            '- edit：基于已有图片修改、重绘、风格转换、扩展、继续编辑；'
            '必须通过 input_image_ids 指定输入图。\n'
            '- auto：不确定时使用，框架根据是否提供输入图自动判断。\n'
            '用户上传了图片并说“改成/把这张/基于这张”时，必须用 edit，'
            '不要用 new 重新画。用户说“上一张/刚才那张”时，用 ["last"] '
            '或图片上下文中对应的 G 编号。'
            '用户只是附了图、但明确要画一张全新内容且不要求参考它时，用 new。',
        'parameters': {
          'type': 'object',
          'required': ['prompt'],
          'properties': {
            'prompt': {
              'type': 'string',
              'description': '详细的画面描述或修改要求，包含主体、风格、构图、色彩、光线等。',
            },
            'mode': {
              'type': 'string',
              'enum': ['new', 'edit', 'auto'],
              'description':
                  'new=从零画新图；edit=基于已有图片修改（必须给 input_image_ids）；'
                  'auto=自动判断。默认 auto。',
            },
            'input_image_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  '要作为输入/参考的图片 ID，例如 ["A1"]、["G2"]；'
                  '也支持 ["last"]（最近一张）、["last_generated"]、["last_attachment"]。'
                  '只能使用 [图片上下文] 中列出的 ID，不要编造。',
            },
            'input_image_id': {
              'type': 'string',
              'description': '单张输入图的 ID，等价于 input_image_ids 只传一个元素。',
            },
            'input_image_path': {
              'type': 'string',
              'description': '可选。显式本地图片路径；一般不需要，优先使用 input_image_ids。',
            },
            'aspect_ratio': {
              'type': 'string',
              'enum': ImageAgentService.aspectRatios,
              'description': '图片宽高比，默认 1:1。',
            },
            'quality': {
              'type': 'string',
              'enum': ImageAgentService.qualities,
              'description': '分辨率档位：1k / 2k / 4k，默认 1k。',
            },
          },
        },
      },
    },
  ];

  @override
  Map<String, CustomToolHandler> get toolHandlers => {
    'image_generate': _execute,
  };

  @override
  String? get systemPromptExtension =>
      '# 画图能力\n'
      '当用户要求生成、绘制、修改图片（插画、海报、头像、壁纸、示意图等）时，'
      '必须调用 image_generate 工具，不要只回复文字描述。\n'
      '调用前必须判断意图并选择 mode：\n'
      '- 从零画新图：mode=new，不要传 input_image_ids。\n'
      '- 基于用户上传的图或之前生成的图做修改/重绘/风格转换/继续编辑：'
      'mode=edit，并把图片上下文中的 ID 填进 input_image_ids。\n'
      '- 用户说“参考这张图的风格/构图，画一张新的”时也用 edit，'
      '并在 prompt 里说明是“参考风格重新构图”。\n'
      '- 用户只是附了图、但明确要画全新内容且不要求参考它时，用 new。\n'
      '- 用户说“这张/刚上传的”时用 A 编号；“上一张/刚才生成的”时用 G 编号，'
      '或直接用 ["last"]。\n'
      '- 不要用 new 去“修改”已有图片，也不要编造不存在的 ID。\n'
      '工具成功后会在界面上展示图片，并返回新的 image_id；'
      '用户要求继续改时，用这个 image_id 作为 input_image_ids。';

  Future<String> _execute(Map<String, dynamic> args) async {
    final prompt = (args['prompt'] as String?)?.trim() ?? '';
    if (prompt.isEmpty) {
      return _error('INVALID_ARGS', 'image_generate 缺少必需参数 prompt');
    }

    final mode = _normalizeMode(args['mode']);
    final ids = [
      ..._normalizeIds(args['input_image_ids']),
      ..._normalizeIds(args['input_image_id']),
    ];
    final explicitPath = (args['input_image_path'] as String?)?.trim();

    final paths = <String>[];
    final usedIds = <String>[];

    // 1) 显式路径：既支持真实路径，也兼容模型误把 ID 填进 path 的情况
    if (explicitPath != null && explicitPath.isNotEmpty) {
      final byId = registry.findById(explicitPath);
      if (byId != null) {
        paths.add(byId.path);
        usedIds.add(byId.id);
      } else {
        final resolved = _resolvePath(explicitPath);
        if (!File(resolved).existsSync()) {
          return _error(
            'IMAGE_NOT_FOUND',
            '图片路径不存在：$resolved。'
                '如果这是图片上下文里的图片，请改用 input_image_ids。',
            extra: {'available_image_ids': registry.availableIds},
          );
        }
        paths.add(resolved);
        final id = registry.idForPath(resolved);
        if (id != null) usedIds.add(id);
      }
    }

    // 2) 图片 ID：由注册表解析，模型不需要接触路径。
    //    同时兼容模型把 image_path 误填进 input_image_ids 的情况。
    if (ids.isNotEmpty) {
      final unresolved = <String>[];
      for (final id in ids) {
        final asset = registry.findById(id);
        if (asset != null) {
          if (!asset.exists) {
            return _error(
              'IMAGE_NOT_FOUND',
              '图片 ${asset.id} 的文件已不存在：${asset.path}',
              extra: {'available_image_ids': registry.availableIds},
            );
          }
          paths.add(asset.path);
          usedIds.add(asset.id);
          continue;
        }
        final resolved = _resolvePath(id);
        if (File(resolved).existsSync()) {
          paths.add(resolved);
          final regId = registry.idForPath(resolved);
          if (regId != null) usedIds.add(regId);
          continue;
        }
        unresolved.add(id);
      }
      if (unresolved.isNotEmpty) {
        return _error(
          'IMAGE_REFERENCE',
          '找不到图片 ID: ${unresolved.join(', ')}。'
              '当前可用图片：${registry.availableIds.join(', ')}',
          extra: {'available_image_ids': registry.availableIds},
        );
      }
    }

    // 去重并保持顺序
    final uniquePaths = <String>[];
    for (final path in paths) {
      if (!uniquePaths.contains(path)) uniquePaths.add(path);
    }
    final uniqueIds = <String>[];
    for (final id in usedIds) {
      if (!uniqueIds.contains(id)) uniqueIds.add(id);
    }
    final hasInput = uniquePaths.isNotEmpty;

    // 3) 意图与输入必须自洽，错误提示要能让模型自我纠正
    if (mode == 'new' && hasInput) {
      return _error(
        'INVALID_MODE',
        'mode=new 表示从零画新图，不能携带 input_image_ids/input_image_path。'
            '如果要修改已有图片，请改用 mode=edit。',
        extra: {'input_image_ids': uniqueIds},
      );
    }
    if (mode == 'edit' && !hasInput) {
      return _error(
        'INVALID_MODE',
        'mode=edit 需要输入图片，但本次没有解析到任何图片。'
            '请从图片上下文中选择 ID 填入 input_image_ids。',
        extra: {'available_image_ids': registry.availableIds},
      );
    }
    final effectiveMode = hasInput ? 'edit' : 'new';

    try {
      final outcome = await ImageAgentService.generate(
        prompt: prompt,
        workDir: workDir,
        subCard: subCard,
        mainCard: mainCard,
        aspectRatio: (args['aspect_ratio'] as String?) ?? '1:1',
        quality: (args['quality'] as String?) ?? '1k',
        inputImagePaths: uniquePaths,
        unavailableReason: unavailableReason,
      );

      final imageId = registry.registerGenerated(
        outcome.path,
        prompt: prompt,
        parentIds: uniqueIds,
      );

      // 日志摘要：明确记录这次是子模型生成，还是子模型失败后主模型兜底。
      final inputIdsText = uniqueIds.isEmpty ? '-' : uniqueIds.join(',');
      if (outcome.fallbackUsed) {
        AppLogger.instance.log(
          '[ImageAgent] 子画图模型失败，已使用主模型兜底生成图片: '
          'sub=${subCard?.modelId ?? '(不可用)'}, '
          'main=${outcome.model}, mode=$effectiveMode, '
          'input_ids=$inputIdsText, image_id=$imageId, '
          'prompt="${_logText(prompt, 80)}"',
        );
      } else {
        AppLogger.instance.log(
          '[ImageAgent] 调用子画图模型生成图片: '
          'sub=${outcome.model}, mode=$effectiveMode, '
          'input_ids=$inputIdsText, image_id=$imageId, '
          'prompt="${_logText(prompt, 80)}"',
        );
      }

      return jsonEncode({
        'status': 'ok',
        'mode': effectiveMode,
        'image_id': imageId,
        'image_path': outcome.path,
        'input_image_ids': uniqueIds,
        'model': outcome.model,
        'provider': outcome.provider,
        'fallback_used': outcome.fallbackUsed,
        if (outcome.warning != null) 'warning': outcome.warning,
        'message':
            '图片已生成并保存为 $imageId，界面会自动展示。'
            '请在回复中简要说明已生成，不要输出路径或 base64。'
            '如需继续修改，下一轮使用 mode=edit + input_image_ids:["$imageId"]。',
      });
    } catch (e) {
      AppLogger.instance.log(
        '[ImageAgent] 画图失败: mode=$effectiveMode, '
        'sub=${subCard?.modelId ?? '(不可用)'}, '
        'main=${mainCard?.modelId ?? '(无)'}, '
        'input_ids=${uniqueIds.isEmpty ? '-' : uniqueIds.join(',')}, '
        'error=${_logText(e.toString())}',
      );
      return _error(
        'IMAGE_GEN_FAILED',
        e.toString(),
        extra: {
          'mode': effectiveMode,
          'input_image_ids': uniqueIds,
          'available_image_ids': registry.availableIds,
        },
      );
    }
  }

  String _normalizeMode(dynamic raw) {
    final value = raw is String ? raw.trim().toLowerCase() : '';
    if (value == 'new' || value == 'edit' || value == 'auto') return value;
    return 'auto';
  }

  List<String> _normalizeIds(dynamic raw) {
    final result = <String>[];
    void add(dynamic value) {
      if (value is! String) return;
      final text = value.trim();
      if (text.isEmpty) return;
      // 兼容模型偶尔把数组序列化成字符串
      if (text.startsWith('[') && text.endsWith(']')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is String && item.trim().isNotEmpty) {
                result.add(item.trim());
              }
            }
            return;
          }
        } catch (_) {}
      }
      // 兼容 "A1, G1" 这种写法
      if (text.contains(',')) {
        for (final part in text.split(',')) {
          if (part.trim().isNotEmpty) result.add(part.trim());
        }
        return;
      }
      result.add(text);
    }

    if (raw is String) {
      add(raw);
    } else if (raw is List) {
      for (final item in raw) {
        add(item);
      }
    }
    return result;
  }

  String _resolvePath(String value) {
    final trimmed = value.trim();
    if (p.isAbsolute(trimmed)) return p.normalize(trimmed);
    if (workDir.trim().isEmpty) return p.normalize(trimmed);
    return p.normalize(p.join(workDir, trimmed));
  }

  /// 日志用：压成单行并截断。
  String _logText(String text, [int max = 300]) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length <= max ? single : '${single.substring(0, max)}…';
  }

  String _error(String code, String detail, {Map<String, dynamic>? extra}) {
    return jsonEncode({
      'status': 'error',
      'code': code,
      'detail': detail,
      ...?extra,
    });
  }
}

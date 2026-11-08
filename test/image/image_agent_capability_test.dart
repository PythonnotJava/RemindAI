import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/image/image_agent_capability.dart';
import 'package:remind_ai/core/image/image_agent_service.dart';
import 'package:remind_ai/core/image/session_image_registry.dart';
import 'package:remind_ai/core/models/file_attachment.dart';

void main() {
  const sub = ImageModelSpec(
    id: 'sub',
    name: 'Image Model',
    baseUrl: 'https://example.com/v1',
    apiKey: 'key',
    provider: 'openai',
    modelId: 'gpt-image-2.5',
  );
  const main = ImageModelSpec(
    id: 'main',
    name: 'Main Model',
    baseUrl: 'https://example.com/v1',
    apiKey: 'key',
    provider: 'openai',
    modelId: 'gpt-6.1-sol',
  );

  ImageAgentCapability buildCap(SessionImageRegistry registry) =>
      ImageAgentCapability(
        subCard: sub,
        mainCard: main,
        workDir: '',
        registry: registry,
      );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('image_cap_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File createImage(String name) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    return file;
  }

  test('画图能力注册 image_generate 工具并带兜底说明', () {
    final cap = buildCap(SessionImageRegistry());

    expect(cap.isActive, isTrue);
    expect(cap.toolDefinitions, hasLength(1));
    final function =
        cap.toolDefinitions.first['function'] as Map<String, dynamic>;
    expect(function['name'], 'image_generate');
    expect(cap.toolHandlers.containsKey('image_generate'), isTrue);
    expect(cap.systemPromptExtension, contains('image_generate'));
    expect(cap.systemPromptExtension, contains('mode=edit'));
  });

  test('缺少 prompt 时返回结构化错误，不发起网络请求', () async {
    final cap = buildCap(SessionImageRegistry());

    final raw = await cap.toolHandlers['image_generate']!({'prompt': '  '});
    final result = jsonDecode(raw) as Map<String, dynamic>;

    expect(result['status'], 'error');
    expect(result['code'], 'INVALID_ARGS');
  });

  test('子模型被删除时仍激活，走主模型兜底', () {
    final cap = ImageAgentCapability(
      subCard: null,
      mainCard: main,
      workDir: '',
      registry: SessionImageRegistry(),
      unavailableReason: '子画图模型已被删除或不可用',
    );

    expect(cap.isActive, isTrue);
  });

  test('mode=new 携带输入图时拒绝，并提示改用 edit', () async {
    final registry = SessionImageRegistry();
    final file = createImage('cat.png');
    registry.beginTurn([FileAttachment.fromFile(file)]);
    final cap = buildCap(registry);

    final raw = await cap.toolHandlers['image_generate']!({
      'prompt': '改成水彩',
      'mode': 'new',
      'input_image_ids': ['A1'],
    });
    final result = jsonDecode(raw) as Map<String, dynamic>;

    expect(result['status'], 'error');
    expect(result['code'], 'INVALID_MODE');
    expect(result['detail'], contains('mode=edit'));
  });

  test('单数 input_image_id 也能被解析并参与校验', () async {
    final registry = SessionImageRegistry();
    final file = createImage('cat.png');
    registry.beginTurn([FileAttachment.fromFile(file)]);
    final cap = buildCap(registry);

    final raw = await cap.toolHandlers['image_generate']!({
      'prompt': '改成水彩',
      'mode': 'new',
      'input_image_id': 'A1',
    });
    final result = jsonDecode(raw) as Map<String, dynamic>;

    expect(result['status'], 'error');
    expect(result['code'], 'INVALID_MODE');
  });

  test('mode=edit 没有输入图时拒绝', () async {
    final cap = buildCap(SessionImageRegistry());

    final raw = await cap.toolHandlers['image_generate']!({
      'prompt': '修改这张图',
      'mode': 'edit',
    });
    final result = jsonDecode(raw) as Map<String, dynamic>;

    expect(result['status'], 'error');
    expect(result['code'], 'INVALID_MODE');
    expect(result['available_image_ids'], isEmpty);
  });

  test('引用不存在的图片 ID 时返回可用 ID 列表', () async {
    final registry = SessionImageRegistry();
    final file = createImage('cat.png');
    registry.beginTurn([FileAttachment.fromFile(file)]);
    final cap = buildCap(registry);

    final raw = await cap.toolHandlers['image_generate']!({
      'prompt': '改成水彩',
      'mode': 'edit',
      'input_image_ids': ['G99'],
    });
    final result = jsonDecode(raw) as Map<String, dynamic>;

    expect(result['status'], 'error');
    expect(result['code'], 'IMAGE_REFERENCE');
    expect(result['available_image_ids'], contains('A1'));
  });

  test('图片上下文清单包含 A/G 编号、本轮标记与引用规则', () {
    final registry = SessionImageRegistry();
    final file = createImage('cat.png');
    final newIds = registry.beginTurn([FileAttachment.fromFile(file)]);
    final generatedId = registry.registerGenerated(
      '${tempDir.path}${Platform.pathSeparator}out.png',
      prompt: '一只猫',
    );

    final note = registry.buildContextNote(currentTurnIds: newIds.toSet());
    expect(note, contains('[图片上下文]'));
    expect(note, contains('A1'));
    expect(note, contains('本轮上传'));
    expect(note, contains(generatedId));
    expect(note, contains('mode=edit'));
  });

  test('子模型失败且主模型不支持画图时，明确提示跳过兜底', () async {
    const badSub = ImageModelSpec(
      id: 'bad',
      name: 'Bad Image Model',
      baseUrl: '',
      apiKey: '',
      provider: 'openai',
      modelId: 'gpt-image-2',
    );

    try {
      await ImageAgentService.generate(
        prompt: '一只猫',
        workDir: tempDir.path,
        subCard: badSub,
        mainCard: null,
      );
      fail('应当抛出 ImageAgentException');
    } on ImageAgentException catch (e) {
      expect(e.message, contains('主模型不支持画图'));
      expect(e.message, contains('已跳过兜底'));
    }
  });

  test('last / last_generated 别名解析到最近图片', () {
    final registry = SessionImageRegistry();
    final file = createImage('cat.png');
    registry.beginTurn([FileAttachment.fromFile(file)]);
    final generatedId = registry.registerGenerated(
      '${tempDir.path}${Platform.pathSeparator}out.png',
      prompt: '一只猫',
    );

    expect(registry.findById('last')?.id, generatedId);
    expect(registry.findById('last_generated')?.id, generatedId);
    expect(registry.findById('last_attachment')?.id, 'A1');
  });
}

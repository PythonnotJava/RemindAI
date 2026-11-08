import 'package:flutter_test/flutter_test.dart';
import 'package:remind_ai/core/settings/app_settings.dart';

void main() {
  AppSettings base() => const AppSettings(
    databasePath: 'db.sqlite',
    historyPath: 'history',
    skillsPath: 'skills',
    logsPath: 'logs',
    pandocPath: '',
  );

  test('子画图模型选择与兜底开关可以序列化/反序列化', () {
    final settings = base().copyWith(
      imageAgentModelId: 'card-image-1',
      imageAgentFallbackToMain: true,
    );

    final json = settings.toJson();
    expect(json['imageAgentModelId'], 'card-image-1');
    expect(json['imageAgentFallbackToMain'], isTrue);

    final restored = AppSettings.fromJson(json);
    expect(restored.imageAgentModelId, 'card-image-1');
    expect(restored.imageAgentFallbackToMain, isTrue);
  });

  test('旧版 settings.json 缺少字段时使用安全默认值', () {
    final restored = AppSettings.fromJson({'databasePath': 'old.db'});

    expect(restored.imageAgentModelId, isEmpty);
    expect(restored.imageAgentFallbackToMain, isFalse);
  });
}

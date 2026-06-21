// ─────────────────────────────────────────────────────────────
// 火山引擎 TTS 实现参考了 Radiant303/astrbot_plugin_clonetts 项目
// https://github.com/Radiant303/astrbot_plugin_clonetts
// 感谢 Radiant303 提供的火山引擎 ICL 音色克隆调用方案
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// TTS 引擎类型
enum TtsEngineType {
  /// 系统 TTS (Windows SAPI)
  system,

  /// 火山引擎声音复刻 (seed-icl-2.0)
  volcano,
}

/// TTS 播放状态
enum TtsPlayState { idle, speaking }

/// TTS 配置
class TtsConfig {
  final TtsEngineType engine;

  // 系统 TTS 参数
  final double systemVolume; // 0.0 ~ 1.0
  final double systemRate; // 0.0 ~ 1.0
  final String? systemVoice;

  // 火山引擎参数
  final String volcanoAppId;
  final String volcanoToken;
  final String volcanoVoiceType;
  final int volcanoSpeed; // -50 ~ 100
  final int volcanoLoudness; // -50 ~ 100
  final int volcanoSampleRate;

  const TtsConfig({
    this.engine = TtsEngineType.system,
    this.systemVolume = 0.8,
    this.systemRate = 0.5,
    this.systemVoice,
    this.volcanoAppId = '',
    this.volcanoToken = '',
    this.volcanoVoiceType = '',
    this.volcanoSpeed = 20,
    this.volcanoLoudness = 0,
    this.volcanoSampleRate = 24000,
  });

  TtsConfig copyWith({
    TtsEngineType? engine,
    double? systemVolume,
    double? systemRate,
    String? systemVoice,
    String? volcanoAppId,
    String? volcanoToken,
    String? volcanoVoiceType,
    int? volcanoSpeed,
    int? volcanoLoudness,
    int? volcanoSampleRate,
  }) {
    return TtsConfig(
      engine: engine ?? this.engine,
      systemVolume: systemVolume ?? this.systemVolume,
      systemRate: systemRate ?? this.systemRate,
      systemVoice: systemVoice ?? this.systemVoice,
      volcanoAppId: volcanoAppId ?? this.volcanoAppId,
      volcanoToken: volcanoToken ?? this.volcanoToken,
      volcanoVoiceType: volcanoVoiceType ?? this.volcanoVoiceType,
      volcanoSpeed: volcanoSpeed ?? this.volcanoSpeed,
      volcanoLoudness: volcanoLoudness ?? this.volcanoLoudness,
      volcanoSampleRate: volcanoSampleRate ?? this.volcanoSampleRate,
    );
  }

  Map<String, dynamic> toJson() => {
    'engine': engine.name,
    'systemVolume': systemVolume,
    'systemRate': systemRate,
    'systemVoice': systemVoice,
    'volcanoAppId': volcanoAppId,
    'volcanoToken': volcanoToken,
    'volcanoVoiceType': volcanoVoiceType,
    'volcanoSpeed': volcanoSpeed,
    'volcanoLoudness': volcanoLoudness,
    'volcanoSampleRate': volcanoSampleRate,
  };

  factory TtsConfig.fromJson(Map<String, dynamic> json) {
    return TtsConfig(
      engine: TtsEngineType.values.firstWhere(
        (e) => e.name == json['engine'],
        orElse: () => TtsEngineType.system,
      ),
      systemVolume: (json['systemVolume'] as num?)?.toDouble() ?? 0.8,
      systemRate: (json['systemRate'] as num?)?.toDouble() ?? 0.5,
      systemVoice: json['systemVoice'] as String?,
      volcanoAppId: json['volcanoAppId'] as String? ?? '',
      volcanoToken: json['volcanoToken'] as String? ?? '',
      volcanoVoiceType: json['volcanoVoiceType'] as String? ?? '',
      volcanoSpeed: json['volcanoSpeed'] as int? ?? 20,
      volcanoLoudness: json['volcanoLoudness'] as int? ?? 0,
      volcanoSampleRate: json['volcanoSampleRate'] as int? ?? 24000,
    );
  }

  /// 火山引擎配置是否完整
  bool get volcanoReady =>
      volcanoAppId.isNotEmpty &&
      volcanoToken.isNotEmpty &&
      volcanoVoiceType.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────
// TtsService — 纯 Dart 实现，无 Python 依赖
// ─────────────────────────────────────────────────────────────

/// TTS 服务单例
///
/// 支持两种引擎：
/// - system: Windows SAPI (PowerShell)
/// - volcano: 火山引擎声音复刻 (Dio SSE)
class TtsService extends ChangeNotifier {
  TtsService._();
  static final TtsService instance = TtsService._();

  TtsConfig _config = const TtsConfig();
  TtsPlayState _state = TtsPlayState.idle;
  final Dio _dio = Dio();
  Process? _speakingProcess;
  CancelToken? _cancelToken;

  TtsConfig get config => _config;
  TtsPlayState get state => _state;
  bool get isSpeaking => _state == TtsPlayState.speaking;

  /// 回调：说话开始/结束
  VoidCallback? onSpeakStart;
  VoidCallback? onSpeakEnd;

  /// 更新配置（同时持久化到本地）
  void updateConfig(TtsConfig config) {
    _config = config;
    _persistConfig();
    notifyListeners();
  }

  /// 从本地 JSON 加载 TTS 配置
  Future<void> loadPersistedConfig() async {
    try {
      final file = await _configFile;
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _config = TtsConfig.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TTS] 加载配置失败: $e');
    }
  }

  /// 持久化当前配置到本地 JSON
  Future<void> _persistConfig() async {
    try {
      final file = await _configFile;
      await file.writeAsString(jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('[TTS] 保存配置失败: $e');
    }
  }

  /// 配置文件路径: `<appData>/tts_config.json`
  Future<File> get _configFile async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'tts_config.json'));
  }

  /// 合成并播放，返回是否成功
  Future<bool> speak(String text, {String? context}) async {
    if (text.trim().isEmpty) return false;
    if (_state == TtsPlayState.speaking) await stop();

    _state = TtsPlayState.speaking;
    onSpeakStart?.call();
    notifyListeners();

    try {
      switch (_config.engine) {
        case TtsEngineType.system:
          await _speakSystem(text);
        case TtsEngineType.volcano:
          await _speakVolcano(text, context: context);
      }
      return true;
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      return false;
    } finally {
      _state = TtsPlayState.idle;
      onSpeakEnd?.call();
      notifyListeners();
    }
  }

  /// 停止播放
  Future<void> stop() async {
    _cancelToken?.cancel('用户打断');
    _cancelToken = null;
    _speakingProcess?.kill();
    _speakingProcess = null;
    if (_state == TtsPlayState.speaking) {
      _state = TtsPlayState.idle;
      onSpeakEnd?.call();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    _dio.close();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 系统 TTS (Windows SAPI via PowerShell)
  // ═══════════════════════════════════════════════════════════

  Future<void> _speakSystem(String text) async {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '`"')
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
    final rate = ((_config.systemRate - 0.5) * 20).round().clamp(-10, 10);
    final vol = (_config.systemVolume * 100).round().clamp(0, 100);

    final script =
        '''
Add-Type -AssemblyName System.Speech
\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$s.Rate = $rate
\$s.Volume = $vol
\$s.Speak("$escaped")
''';
    _speakingProcess = await Process.start('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    await _speakingProcess!.exitCode;
    _speakingProcess = null;
  }

  // ═══════════════════════════════════════════════════════════
  // 火山引擎 TTS (Dio SSE 流式)
  // ═══════════════════════════════════════════════════════════

  static const _volcanoUrl =
      'https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse';

  Future<void> _speakVolcano(String text, {String? context}) async {
    if (!_config.volcanoReady) {
      debugPrint('[TTS] Volcano 配置不完整，回退到系统 TTS');
      await _speakSystem(text);
      return;
    }

    // 构造请求
    final additions = <String, dynamic>{
      'explicit_language': 'zh-cn',
      'disable_markdown_filter': true,
      'enable_latex_tn': true,
    };
    if (context != null && context.isNotEmpty) {
      additions['context_texts'] = [context];
    }

    final body = {
      'user': {'uid': DateTime.now().millisecondsSinceEpoch.toString()},
      'req_params': {
        'text': text,
        'speaker': _config.volcanoVoiceType,
        'audio_params': {
          'format': 'mp3',
          'sample_rate': _config.volcanoSampleRate,
          'speech_rate': _config.volcanoSpeed,
          'loudness_rate': _config.volcanoLoudness,
        },
        'additions': jsonEncode(additions),
      },
    };

    debugPrint(
      '[TTS] Volcano 合成: ${text.length > 30 ? '${text.substring(0, 30)}...' : text}',
    );

    // 流式请求（带 CancelToken 支持打断）
    _cancelToken = CancelToken();
    final response = await _dio.post<ResponseBody>(
      _volcanoUrl,
      data: body,
      cancelToken: _cancelToken,
      options: Options(
        headers: {
          'X-Api-App-Id': _config.volcanoAppId,
          'X-Api-Access-Key': _config.volcanoToken,
          'X-Api-Resource-Id': 'seed-icl-2.0',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );

    // 解析 SSE 流，收集音频 chunks
    final audioChunks = <int>[];
    final stream = response.data!.stream;
    final buffer = StringBuffer();

    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));

      // 按行解析
      while (true) {
        final content = buffer.toString();
        final newlineIdx = content.indexOf('\n');
        if (newlineIdx == -1) break;

        final line = content.substring(0, newlineIdx).trim();
        buffer.clear();
        buffer.write(content.substring(newlineIdx + 1));

        if (!line.startsWith('data:')) continue;
        final dataStr = line.substring(5).trim();
        if (dataStr.isEmpty) continue;

        try {
          final data = jsonDecode(dataStr) as Map<String, dynamic>;
          if (data['code'] == 0 && data['data'] != null) {
            audioChunks.addAll(base64Decode(data['data'] as String));
          } else if (data['code'] == 20000000) {
            break; // 合成完毕
          }
        } catch (_) {}
      }
    }

    if (audioChunks.isEmpty) {
      debugPrint('[TTS] Volcano 返回空音频');
      return;
    }

    debugPrint('[TTS] 收到音频 ${audioChunks.length} bytes');

    // 写临时文件并播放
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      p.join(
        tempDir.path,
        'pet_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
      ),
    );
    await tempFile.writeAsBytes(Uint8List.fromList(audioChunks));

    await _playAudioFile(tempFile.path);

    // 清理
    try {
      await tempFile.delete();
    } catch (_) {}
  }

  /// 播放 mp3 文件 (Windows, 使用 PresentationCore MediaPlayer)
  Future<void> _playAudioFile(String filePath) async {
    // 用 ps1 脚本方式避免变量转义问题
    final tempDir = await getTemporaryDirectory();
    final scriptFile = File(p.join(tempDir.path, 'play_audio.ps1'));
    await scriptFile.writeAsString('''
Add-Type -AssemblyName PresentationCore
\$m = New-Object System.Windows.Media.MediaPlayer
\$m.Open([Uri]"$filePath")
Start-Sleep -Milliseconds 300
\$m.Play()
while (\$m.NaturalDuration.HasTimeSpan -eq \$false) { Start-Sleep -Milliseconds 100 }
while (\$m.Position -lt \$m.NaturalDuration.TimeSpan) { Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds 100
\$m.Close()
''');
    _speakingProcess = await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptFile.path,
    ]);
    await _speakingProcess!.exitCode;
    _speakingProcess = null;
    try {
      await scriptFile.delete();
    } catch (_) {}
  }
}

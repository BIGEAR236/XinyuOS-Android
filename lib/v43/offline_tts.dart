import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// One named voice from the bundled theresa model (804 speakers). The sid
/// numbers are a spread across the speaker space; what a given sid sounds
/// like can only be judged by ear — hence the audition button in the UI.
class XyVoicePreset {
  final String name;
  final String desc;
  final int sid;
  const XyVoicePreset(this.name, this.desc, this.sid);
}

const voicePresets = <XyVoicePreset>[
  XyVoicePreset('霸道总裁', '低沉、有压迫感', 5),
  XyVoicePreset('低音大叔', '沉稳磁性', 12),
  XyVoicePreset('小奶狗', '软萌少年感', 27),
  XyVoicePreset('阳光少年', '清亮活泼', 40),
  XyVoicePreset('清冷学长', '干净疏离', 58),
  XyVoicePreset('温柔姐姐', '轻柔耐心', 66),
  XyVoicePreset('御姐', '成熟慵懒', 74),
  XyVoicePreset('甜妹', '甜而不腻', 89),
  XyVoicePreset('软糯小猫', '撒娇感', 102),
  XyVoicePreset('知性女声', '新闻主播风', 117),
  XyVoicePreset('元气少女', '高亮有活力', 130),
  XyVoicePreset('沙哑烟嗓', '故事感', 145),
];

/// On-device neural TTS (sherpa-onnx VITS, vits-zh-hf-theresa, 804 voices).
/// Model files are bundled by CI under assets/sherpa/tts/ and copied to the
/// app-support dir on first use. Playback goes through just_audio; awaiting
/// speak() resolves when playback finishes (or is stopped), which drives the
/// hands-free conversation loop.
class XyOfflineTts {
  sherpa_onnx.OfflineTts? _engine;
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;

  bool get isReady => _engine != null;
  int get numSpeakers => _engine?.numSpeakers ?? 0;

  /// Copies the bundled model out of assets (once) and loads the engine.
  /// Returns false when the bundle is absent or the native lib fails.
  Future<bool> init() async {
    if (_engine != null || _loading) return _engine != null;
    _loading = true;
    try {
      final dir = await _copyAssets();
      final config = sherpa_onnx.OfflineTtsConfig(
        model: sherpa_onnx.OfflineTtsModelConfig(
          vits: sherpa_onnx.OfflineTtsVitsModelConfig(
            model: '$dir/theresa.onnx',
            lexicon: '$dir/lexicon.txt',
            tokens: '$dir/tokens.txt',
            dictDir: '$dir/dict',
            lengthScale: 1.0,
          ),
          numThreads: 2,
          debug: false,
        ),
        ruleFsts: '$dir/phone.fst,$dir/date.fst,$dir/number.fst',
        maxNumSentences: 1,
      );
      _engine = sherpa_onnx.OfflineTts(config);
      return true;
    } catch (_) {
      _engine = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  Future<String> _copyAssets() async {
    final base = await getApplicationSupportDirectory();
    final targetRoot = Directory('${base.path}/tts');
    await targetRoot.create(recursive: true);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith('assets/sherpa/tts/')) continue;
      final relative = asset.substring('assets/sherpa/tts/'.length);
      if (relative.isEmpty) continue;
      final target = File('${targetRoot.path}/$relative');
      await target.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      if (!await target.exists() ||
          await target.length() != data.lengthInBytes) {
        await target.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
      }
    }
    return targetRoot.path;
  }

  /// Generates audio for [text] with speaker [sid] and plays it. The returned
  /// future completes when playback ends or is stopped (e.g. by [stop]).
  Future<void> speak(String text,
      {int sid = 0, double speed = 1.0}) async {
    final engine = _engine;
    if (engine == null || text.isEmpty) return;
    final audio = engine.generate(text: text, sid: sid, speed: speed);
    if (audio.samples.isEmpty) return;
    final bytes = _wavBytes(audio.samples, audio.sampleRate);
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/xy_tts_$sid.wav');
    await file.writeAsBytes(bytes, flush: true);
    await _player.stop();
    await _player.setFilePath(file.path);
    await _player.play();
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) { /* player may already be stopped */ }
  }

  Uint8List _wavBytes(Float32List samples, int sampleRate) {
    final bytes = ByteData(44 + samples.length * 2);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final v = (samples[i] * 32767).clamp(-32768.0, 32767.0).round();
      bytes.setInt16(44 + i * 2, v, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  void dispose() {
    _engine?.free();
    _engine = null;
    _player.dispose();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// One suggested voice from the bundled kokoro model. Gender is GUARANTEED
/// by the official sid map (female 3-57, male 58-102); the flavour text is
/// only a hint — audition before committing.
class XyVoicePreset {
  final String name;
  final String hint;
  final int sid;
  final bool male;
  const XyVoicePreset(this.name, this.hint, this.sid, this.male);
}

/// Official kokoro-multi-lang-v1_1 speaker layout: female 3-57, male 58-102.
const int kFemaleSidMin = 3, kFemaleSidMax = 57;
const int kMaleSidMin = 58, kMaleSidMax = 102;

const voicePresets = <XyVoicePreset>[
  XyVoicePreset('女声 · 一号', '清亮自然', 3, false),
  XyVoicePreset('女声 · 二号', '温润亲和', 10, false),
  XyVoicePreset('女声 · 三号', '知性大方', 21, false),
  XyVoicePreset('女声 · 四号', '轻柔细腻', 33, false),
  XyVoicePreset('女声 · 五号', '甜美活泼', 45, false),
  XyVoicePreset('女声 · 六号', '优雅从容', 55, false),
  XyVoicePreset('男声 · 一号', '干净利落', 58, true),
  XyVoicePreset('男声 · 二号', '沉稳大气', 64, true),
  XyVoicePreset('男声 · 三号', '磁性低音', 72, true),
  XyVoicePreset('男声 · 四号', '阳光青年', 81, true),
  XyVoicePreset('男声 · 五号', '成熟厚重', 90, true),
  XyVoicePreset('男声 · 六号', '温柔少年', 100, true),
];

/// On-device neural TTS (sherpa-onnx kokoro int8, 103 voices, 24kHz).
/// Files are bundled by CI under assets/sherpa/tts/ (flat) and copied to the
/// app-support dir on first use.
///
/// Playback is a double-buffered pipeline: sentence N+1 is synthesized while
/// sentence N is playing, so inter-sentence gaps shrink to roughly
/// max(0, playtime - synthtime). Synthesis itself is a synchronous native
/// call; it briefly blocks the UI thread but never the audio playback.
class XyOfflineTts {
  sherpa_onnx.OfflineTts? _engine;
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  /// True while a synchronous generate() call is running (for UI hints).
  bool synthesizing = false;
  /// Monotonic speak() generation: stop() and a newer speak() invalidate
  /// any pipeline still running by bumping the counter.
  int _speakGeneration = 0;

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
          kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
            model: '$dir/model.int8.onnx',
            voices: '$dir/voices.bin',
            tokens: '$dir/tokens.txt',
            lexicon: '$dir/lexicon-us-en.txt,$dir/lexicon-zh.txt',
          ),
          numThreads: 2,
          debug: false,
        ),
        ruleFsts: '$dir/phone-zh.fst,$dir/date-zh.fst,$dir/number-zh.fst',
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
      if (relative.isEmpty || relative.contains('/')) continue;
      final target = File('${targetRoot.path}/$relative');
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

  /// Speaks [text] sentence by sentence with double buffering; the returned
  /// future completes when everything finished playing (or was stopped).
  Future<void> speak(String text, {int sid = 0, double speed = 1.0}) async {
    final engine = _engine;
    if (engine == null || text.isEmpty) return;
    // Old saves may carry sids from the previous model; clamp into range.
    final safeSid = sid.clamp(0, engine.numSpeakers - 1);
    final generation = ++_speakGeneration;
    final sentences = _splitSentences(text);
    final tmp = await getTemporaryDirectory();
    // Sentence 0: synthesized before any audio plays (brief UI freeze).
    var file = await _synthesize(engine, sentences[0], safeSid, speed, tmp, 0);
    if (generation != _speakGeneration) return;
    await _player.stop();
    await _player.setFilePath(file.path);
    var playback = _player.play();
    // Sentence i: synthesized WHILE sentence i-1 plays (audio runs on the
    // platform thread and is not blocked by the synchronous synthesis).
    for (var i = 1; i < sentences.length; i++) {
      file = await _synthesize(engine, sentences[i], safeSid, speed, tmp, i);
      if (generation != _speakGeneration) return;
      await playback; // previous sentence finished playing
      await _player.setFilePath(file.path);
      playback = _player.play();
    }
    await playback;
  }

  Future<File> _synthesize(sherpa_onnx.OfflineTts engine, String sentence,
      int sid, double speed, Directory tmp, int index) async {
    synthesizing = true;
    try {
      final audio = engine.generate(text: sentence, sid: sid, speed: speed);
      final bytes =
          audio.samples.isEmpty ? null : _wavBytes(audio.samples, audio.sampleRate);
      final file = File('${tmp.path}/xy_tts_${sid}_$index.wav');
      if (bytes == null) {
        // Empty synthesis result: write a tiny silent wav so the pipeline
        // keeps its double-buffer sequencing intact.
        await file.writeAsBytes(_wavBytes(Float32List(1), audio.sampleRate),
            flush: true);
      } else {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file;
    } finally {
      synthesizing = false;
    }
  }

  /// Splits text into speakable sentences (merge tiny fragments so the
  /// pipeline is not dominated by split-second blips).
  List<String> _splitSentences(String text) {
    const breaks = '。！？!?；;\n';
    final raw = <String>[];
    var buffer = '';
    for (final char in text.split('')) {
      buffer += char;
      if (breaks.contains(char)) {
        if (buffer.trim().isNotEmpty) raw.add(buffer.trim());
        buffer = '';
      }
    }
    if (buffer.trim().isNotEmpty) raw.add(buffer.trim());
    final merged = <String>[];
    for (final sentence in raw) {
      if (merged.isNotEmpty && (sentence.length < 4 || merged.last.length < 4)) {
        merged[merged.length - 1] = '${merged.last}$sentence';
      } else {
        merged.add(sentence);
      }
    }
    return merged.isEmpty ? [text] : merged;
  }

  Future<void> stop() async {
    _speakGeneration++; // Invalidate any running pipeline.
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

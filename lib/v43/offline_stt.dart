import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// On-device streaming speech recognition (sherpa-onnx zipformer, WenetSpeech).
/// Fallback for Android ROMs that ship no system RecognitionService at all
/// (common on domestic devices without GMS). Fully offline after the bundled
/// model is copied out of the APK assets on first use.
///
/// Model files are placed into assets/sherpa/ by the release CI; a local
/// debug build without them makes [init] return false and callers fall back
/// to the system recognizer path.
class XyOfflineStt {
  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;

  static const _sampleRate = 16000;
  // icefall-asr-zipformer-streaming-wenetspeech-20230615 (int8 streaming).
  static const _encoderFile = 'encoder-epoch-12-avg-4-chunk-16-left-128.int8.onnx';
  static const _decoderFile = 'decoder-epoch-12-avg-4-chunk-16-left-128.onnx';
  static const _joinerFile = 'joiner-epoch-12-avg-4-chunk-16-left-128.onnx';
  static const _tokensFile = 'tokens.txt';

  bool get isReady => _recognizer != null;

  /// Copies the bundled model out of assets (once) and loads the engine.
  /// Returns false when the model bundle is absent or the native lib fails.
  Future<bool> init() async {
    if (_recognizer != null) return true;
    try {
      sherpa_onnx.initBindings();
      final dir = await getApplicationSupportDirectory();
      Future<String> copyModel(String name) async {
        final data = await rootBundle.load('assets/sherpa/$name');
        final target = File('${dir.path}/stt_$name');
        if (!await target.exists() || await target.length() != data.lengthInBytes) {
          await target.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true);
        }
        return target.path;
      }
      final config = sherpa_onnx.OnlineRecognizerConfig(
        model: sherpa_onnx.OnlineModelConfig(
          transducer: sherpa_onnx.OnlineTransducerModelConfig(
            encoder: await copyModel(_encoderFile),
            decoder: await copyModel(_decoderFile),
            joiner: await copyModel(_joinerFile),
          ),
          tokens: await copyModel(_tokensFile),
          modelType: 'zipformer2',
        ),
        ruleFsts: '',
      );
      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      return true;
    } catch (_) {
      _recognizer = null;
      return false;
    }
  }

  /// Starts streaming recognition; [onUpdate] fires with the growing text.
  /// Throws when microphone permission is denied.
  Future<void> start(void Function(String text) onUpdate) async {
    final recognizer = _recognizer;
    if (recognizer == null) return;
    if (!await _recorder.hasPermission()) {
      throw const FileSystemException('麦克风权限未授予');
    }
    await stop();
    _stream?.free();
    _stream = recognizer.createStream();
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    );
    final audio = await _recorder.startStream(config);
    _audioSub = audio.listen((data) {
      final stream = _stream;
      if (stream == null) return;
      recognizer.acceptWaveform(stream,
          samples: _bytesToFloat32(data), sampleRate: _sampleRate);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final text = recognizer.getResult(stream).text;
      if (text.isNotEmpty) onUpdate(text);
      if (recognizer.isEndpoint(stream)) {
        recognizer.reset(stream);
      }
    });
  }

  /// Stops recording and returns the final recognized text of this turn.
  Future<String> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) { /* recorder may already be stopped */ }
    final recognizer = _recognizer;
    final stream = _stream;
    var text = '';
    if (recognizer != null && stream != null) {
      text = recognizer.getResult(stream).text;
      stream.free();
      _stream = null;
    }
    return text;
  }

  Float32List _bytesToFloat32(Uint8List bytes) {
    final values = Float32List(bytes.length ~/ 2);
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      values[i ~/ 2] = data.getInt16(i, Endian.little) / 32768.0;
    }
    return values;
  }

  void dispose() {
    _audioSub?.cancel();
    _recorder.dispose();
    _stream?.free();
    _stream = null;
    _recognizer?.free();
    _recognizer = null;
  }
}

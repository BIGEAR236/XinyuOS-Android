import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'local_data.dart';
import 'models.dart';

/// One player for the whole application, not one player per page.
/// Music keeps playing as the user navigates inside 心屿 OS.
class MusicController extends ChangeNotifier {
  final LocalData local;
  final AudioPlayer player = AudioPlayer();
  StreamSubscription<PlayerState>? _subscription;
  String? trackId;
  String trackTitle = '';
  String? lastError;
  bool get playing => player.playing;
  bool get hasTrack => trackId != null;

  MusicController(this.local) {
    unawaited(player.setLoopMode(LoopMode.one).catchError((Object _) {})); // repeat current song
    _subscription = player.playerStateStream.listen((_) => notifyListeners());
  }

  Future<void> toggleTrack(LocalTrack track) async {
    if (trackId == track.id) {
      await togglePause();
      return;
    }
    try {
      final file = local.resolve(track.relativePath);
      if (!await file.exists()) throw const FileSystemException('歌曲文件不存在');
      await player.setFilePath(file.path);
      trackId = track.id;
      trackTitle = track.title;
      lastError = null;
      notifyListeners();
      _startPlayback();
    } catch (error) {
      lastError = '无法播放这首歌：$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clearTrack() async {
    await player.stop();
    trackId = null;
    trackTitle = '';
    lastError = null;
    notifyListeners();
  }

  Future<void> togglePause() async {
    if (!hasTrack) return;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      _startPlayback();
    }
    notifyListeners();
  }

  void _startPlayback() {
    // AudioPlayer.play() resolves when playback completes. Do not await here.
    unawaited(player.play().catchError((Object error) {
      lastError = '播放过程中出错：$error';
      notifyListeners();
    }));
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(player.dispose());
    super.dispose();
  }
}

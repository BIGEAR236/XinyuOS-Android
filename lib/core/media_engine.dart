import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Persist imported media to an app-owned directory; file picker temporary paths can expire.
Future<String?> pickOwnedFile({required List<String> extensions}) async {
  final file=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:extensions);
  if(file==null)return null;
  final input=file.path;
  if(input==null || !await File(input).exists()) {
    throw StateError('系统提供的文件暂时无法读取，请先下载到本地再试');
  }
  final folder=Directory('${(await getApplicationDocumentsDirectory()).path}/intimacy_media');
  if(!await folder.exists()) await folder.create(recursive:true);
  final clean=file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
  final destination=File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}_$clean');
  await File(input).copy(destination.path);
  return destination.path;
}

class TimedLine {
  final Duration at;
  final String text;
  const TimedLine(this.at,this.text);
}

List<TimedLine> parseLrc(String raw) {
  final pattern=RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final out=<TimedLine>[];
  for(final line in raw.split(RegExp(r'\r?\n'))) {
    final matches=pattern.allMatches(line).toList();
    final lyric=line.replaceAll(pattern,'').trim();
    if(lyric.isEmpty)continue;
    for(final match in matches) {
      final fraction=(match.group(3)??'0').padRight(3,'0').substring(0,3);
      out.add(TimedLine(Duration(minutes:int.parse(match.group(1)!),seconds:int.parse(match.group(2)!),milliseconds:int.parse(fraction)),lyric));
    }
  }
  out.sort((a,b)=>a.at.compareTo(b.at));return out;
}

List<TimedLine> parseSrt(String raw) {
  final out=<TimedLine>[];
  final pattern=RegExp(r'(?:(\d\d):)?(\d\d):(\d\d),(\d{3})\s*-->.*');
  for(final block in raw.split(RegExp(r'\n\s*\n'))) {
    final lines=block.split(RegExp(r'\r?\n'));
    for(var i=0;i<lines.length;i++) {
      final match=pattern.firstMatch(lines[i]);
      if(match==null)continue;
      final text=lines.skip(i+1).join(' ').replaceAll(RegExp(r'<[^>]*>'),'').trim();
      if(text.isEmpty)continue;
      out.add(TimedLine(Duration(hours:int.parse(match.group(1)??'0'),minutes:int.parse(match.group(2)!),seconds:int.parse(match.group(3)!),milliseconds:int.parse(match.group(4)!)),text));
      break;
    }
  }
  out.sort((a,b)=>a.at.compareTo(b.at));return out;
}

String lineAt(List<TimedLine> lines,Duration position) {
  var text='';
  for(final line in lines) { if(line.at>position)break; text=line.text; }
  return text;
}

class MusicRoom extends ChangeNotifier {
  final player=AudioPlayer();
  String? path, title;
  List<TimedLine> lyrics=[];
  bool shareCurrentLyric=false;
  MusicRoom() {
    player.setLoopMode(LoopMode.all);
    player.playerStateStream.listen((_)=>notifyListeners());
  }
  Future<void> importTrack() async {
    final picked=await pickOwnedFile(extensions:['mp3','wav','m4a','aac','flac','ogg']);
    if(picked==null)return;
    await player.setFilePath(picked);
    path=picked; title=File(picked).uri.pathSegments.last.split('_').skip(1).join('_');
    if(title!.isEmpty)title=File(picked).uri.pathSegments.last;
    notifyListeners(); unawaited(player.play());
  }
  Future<void> importLyrics() async {
    final picked=await pickOwnedFile(extensions:['lrc','txt']);
    if(picked==null)return;
    lyrics=parseLrc(await File(picked).readAsString());notifyListeners();
  }
  Future<void> toggle() async {
    if(player.playing) {await player.pause();} else if(path!=null) {unawaited(player.play());}
    notifyListeners();
  }
  Future<void> clear() async {await player.stop();path=null;title=null;lyrics=[];notifyListeners();}
  @override void dispose(){player.dispose();super.dispose();}
}

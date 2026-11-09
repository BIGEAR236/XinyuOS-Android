import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../core/companion.dart';
import '../core/media_engine.dart';
import '../widgets/chat_overlay.dart';

class MusicPage extends StatefulWidget {
  final CompanionController agent; final MusicRoom room;
  final VoidCallback? onVoiceCall;
  const MusicPage({super.key,required this.agent,required this.room,this.onVoiceCall});
  @override State<MusicPage> createState()=>_MusicPageState();
}
class _MusicPageState extends State<MusicPage> {
  Timer? ticker;
  int lastAutoMinute=-1;
  @override void initState(){super.initState();
    ticker=Timer.periodic(const Duration(seconds:2),(_){if(mounted)setState((){}); maybeReact();});
  }
  void maybeReact(){
    final room=widget.room;
    if(room.path==null || !room.player.playing)return;
    final minute=room.player.position.inMinutes;
    if(minute<=0 || minute%2!=0 || minute==lastAutoMinute)return;
    lastAutoMinute=minute;
    final lyric=room.shareCurrentLyric?lineAt(room.lyrics,room.player.position):'';
    widget.agent.event('与你一起听《${room.title}》，当前播放到${room.player.position.inMinutes}分钟。${lyric.isEmpty?'未分享歌词':'用户允许分享当前短句歌词：${lyric.length>60?lyric.substring(0,60):lyric}'}。请自然讨论音乐，不能声称听到了音频本身');
  }
  @override void dispose(){ticker?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    final r=widget.room;
    return CompanionScaffold(title:'🎵 和${widget.agent.roleName}一起听歌',agent:widget.agent,
      onVoiceCall:widget.onVoiceCall,
      child:ListView(padding:const EdgeInsets.all(18),children:[
        const SizedBox(height:12),
        Center(child:Container(width:190,height:190,decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xFFE8CDFA),Color(0xFFFFD6EA)])),
          child:const Icon(Icons.album,color:Colors.white,size:102))),
        const SizedBox(height:18),
        Text(r.title??'还没有导入歌曲',textAlign:TextAlign.center,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        StreamBuilder<Duration>(stream:r.player.positionStream,builder:(context,snapshot){
          final at=snapshot.data??Duration.zero;
          final max=r.player.duration??const Duration(seconds:1);
          return Column(children:[
            Slider(value:at.inMilliseconds.clamp(0,max.inMilliseconds).toDouble(),max:mathMax(1,max.inMilliseconds.toDouble()),onChanged:r.path==null?null:(v)=>r.player.seek(Duration(milliseconds:v.toInt()))),
            Text('${fmt(at)} / ${fmt(max)}',style:const TextStyle(fontSize:12,color:Colors.black45)),
            const SizedBox(height:9),
            Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFFF9F0FB),borderRadius:BorderRadius.circular(14)),
              child:Text(lineAt(r.lyrics,at).isEmpty?'导入 .lrc 歌词后，此处会自动同步显示':lineAt(r.lyrics,at),textAlign:TextAlign.center,style:const TextStyle(fontSize:18,color:Color(0xFF805F87),fontWeight:FontWeight.w600))),
          ]);
        }),
        const SizedBox(height:12),
        Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:8,children:[
          FilledButton.tonalIcon(onPressed:()async{try{await r.importTrack();if(r.path!=null)widget.agent.event('你和${widget.agent.roleName}一起开始听歌《${r.title}》');}catch(e){showError(e);}},icon:const Icon(Icons.library_music),label:const Text('导入音乐')),
          FilledButton.icon(onPressed:r.path==null?null:()=>r.toggle(),icon:Icon(r.player.playing?Icons.pause:Icons.play_arrow),label:Text(r.player.playing?'暂停':'播放')),
          TextButton.icon(onPressed:()async{await r.clear();},icon:const Icon(Icons.close),label:const Text('关闭播放器')),
          TextButton.icon(onPressed:()async{try{await r.importLyrics();}catch(e){showError(e);}},icon:const Icon(Icons.lyrics),label:const Text('导入歌词')),
        ]),
        SwitchListTile(title:const Text('允许 AI 使用当前歌词参与交流'),subtitle:const Text('关闭时 AI 只能看到歌曲名称和进度，不会看到歌词'),value:r.shareCurrentLyric,onChanged:(v)=>setState(()=>r.shareCurrentLyric=v)),
        const Text('播放器由上层共享，离开本页返回互动空间后仍继续播放；不等于已启用锁屏后台服务。',style:TextStyle(fontSize:12,color:Colors.black45)),
      ]),
    );
  }
  void showError(Object e){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('导入失败：$e')));}
}
String fmt(Duration d)=>'${d.inMinutes.toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
double mathMax(double a,double b)=>a>b?a:b;

class WatchPage extends StatefulWidget {
  final CompanionController agent;
  final VoidCallback? onVoiceCall;
  const WatchPage({super.key,required this.agent,this.onVoiceCall});
  @override State<WatchPage> createState()=>_WatchPageState();
}
class _WatchPageState extends State<WatchPage> {
  VideoPlayerController? controller;
  String? filename;
  List<TimedLine> subtitles=[];
  Timer? timer;
  int lastReactMinute=-1;
  bool shareSubtitles=false;
  @override void initState(){super.initState();timer=Timer.periodic(const Duration(seconds:1),(_){
    if(!mounted)return;
    final p=controller;
    if(p==null||!p.value.isInitialized)return;
    setState((){});
    if(!p.value.isPlaying)return;
    final m=p.value.position.inMinutes;
    if(m>0 && m%2==0 && m!=lastReactMinute){
      lastReactMinute=m;
      final text=shareSubtitles?lineAt(subtitles,p.value.position):'';
      widget.agent.event('你们一起观看本地视频《$filename》，播放到${fmt(p.value.position)}。${text.isEmpty?'没有可见画面、字幕上下文':'用户允许分享的字幕短句：${text.length>60?text.substring(0,60):text}'}。不能假称看到画面。');
    }
  });}
  Future<void> importVideo() async {
    try {
      final path=await pickOwnedFile(extensions:['mp4','mov','m4v','webm']);
      if(path==null)return;
      await controller?.dispose();
      final next=VideoPlayerController.file(File(path));
      await next.initialize();
      await next.setLooping(false);
      if(!mounted){await next.dispose();return;}
      setState((){controller=next;filename=File(path).uri.pathSegments.last;lastReactMinute=-1;});
      await next.play();
      widget.agent.event('和用户一起打开了本地视频《$filename》，当前没有视觉帧或音频数据发送给模型。请友好邀请用户聊剧情。');
    }catch(e){showError(e);}
  }
  Future<void> importSubtitles() async {
    try {
      final path=await pickOwnedFile(extensions:['srt']);if(path==null)return;
      setState(()=>subtitles=parseSrt(File(path).readAsStringSync()));
    } catch(e){showError(e);}
  }
  void showError(Object e){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('播放失败：$e')));}
  @override void dispose(){timer?.cancel();controller?.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final p=controller;
    return CompanionScaffold(title:'🎬 和${widget.agent.roleName}一起看视频',agent:widget.agent,
      onVoiceCall:widget.onVoiceCall,
      child:ListView(padding:const EdgeInsets.all(16),children:[
        AspectRatio(aspectRatio:16/9,child:Container(color:const Color(0xFF292438),child:p?.value.isInitialized==true?
          Center(child:AspectRatio(aspectRatio:p!.value.aspectRatio,child:VideoPlayer(p))):
          const Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.movie_creation_outlined,size:64,color:Colors.white70),Text('导入本地视频',style:TextStyle(color:Colors.white70))])))),
        const SizedBox(height:10),
        Text(filename??'还没有视频',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
        if(p!=null && p.value.isInitialized) ...[
          Slider(value:p.value.position.inMilliseconds.clamp(0,p.value.duration.inMilliseconds).toDouble(),
            max:mathMax(1,p.value.duration.inMilliseconds.toDouble()),onChanged:(v)=>p.seekTo(Duration(milliseconds:v.toInt()))),
          Text('${fmt(p.value.position)} / ${fmt(p.value.duration)}',textAlign:TextAlign.center),
          Card(color:const Color(0xFFF9F0FB),child:Padding(padding:const EdgeInsets.all(12),child:Text(
            lineAt(subtitles,p.value.position).isEmpty?'导入 SRT 字幕可显示同步台词':lineAt(subtitles,p.value.position),textAlign:TextAlign.center))),
        ],
        Wrap(alignment:WrapAlignment.center,spacing:8,children:[
          FilledButton.tonalIcon(onPressed:importVideo,icon:const Icon(Icons.folder_open),label:const Text('导入本地视频')),
          FilledButton.icon(onPressed:p==null?null:()async{
            p.value.isPlaying?await p.pause():await p.play();setState((){});
            widget.agent.event('${widget.agent.roleName}和用户${p.value.isPlaying?'继续观看':'暂停'}视频《$filename》，进度${fmt(p.value.position)}');
          },icon:Icon(p?.value.isPlaying==true?Icons.pause:Icons.play_arrow),label:Text(p?.value.isPlaying==true?'暂停':'播放')),
          TextButton.icon(onPressed:importSubtitles,icon:const Icon(Icons.subtitles),label:const Text('导入字幕')),
        ]),
        SwitchListTile(title:const Text('允许 AI 读取当前字幕'),subtitle:const Text('不发送视频本身。需要实际看懂画面须另接有视觉能力的模型。'),value:shareSubtitles,onChanged:(v)=>setState(()=>shareSubtitles=v)),
        const Text('切换播放、用户发表评论、经过重要段落时触发 AI 互动；不会每秒发送模型请求。',style:TextStyle(color:Colors.black45,fontSize:12)),
      ]),
    );
  }
}

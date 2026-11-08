import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../app_controller.dart';
import '../ui_local_apps.dart';
import '../v39/ai_journal_page.dart';
import 'avatar_core.dart';
import 'digital_person_page.dart';

class XyNotebookShell extends StatefulWidget {
  final String notebookKey;
  final String title;
  final Widget child;
  const XyNotebookShell({super.key, required this.notebookKey,
    required this.title, required this.child});
  @override State<XyNotebookShell> createState() => _XyNotebookShellState();
}
class _XyNotebookShellState extends State<XyNotebookShell> {
  final prefs = SharedPreferencesAsync();
  String path = '';
  @override void initState() {super.initState(); _load();}
  Future<void> _load() async {
    path = await prefs.getString('v41.note.wallpaper.${widget.notebookKey}') ?? '';
    if(mounted)setState(() {});
  }
  Future<void> _change() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if(file==null)return;
      final bytes = await file.readAsBytes();
      if(bytes.length > 12*1024*1024)throw const FormatException('单张壁纸最大 12MB');
      path = await DigitalPersonStore.saveMedia('notebook_${widget.notebookKey}', 'png', bytes);
      await prefs.setString('v41.note.wallpaper.${widget.notebookKey}',path);
      if(mounted)setState(() {});
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('壁纸导入失败：$e')));
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title),actions:[
      IconButton(tooltip:'更换本日记/备忘录壁纸',onPressed:_change,
        icon:const Icon(Icons.wallpaper_outlined)),
      if(path.isNotEmpty)IconButton(tooltip:'恢复默认',onPressed:() async {
        await prefs.remove('v41.note.wallpaper.${widget.notebookKey}');
        if(mounted)setState(()=>path='');
      },icon:const Icon(Icons.restore))]),
    body: Stack(fit:StackFit.expand,children:[
      const DecoratedBox(decoration:BoxDecoration(gradient:LinearGradient(
        colors:[Color(0xFFFFEEF5),Color(0xFFEAE7FA)]))),
      if(path.isNotEmpty&&File(path).existsSync())
        Opacity(opacity:.3, child:Image.file(File(path),fit:BoxFit.cover)),
      Theme(data:Theme.of(context).copyWith(scaffoldBackgroundColor:Colors.transparent),
        child:widget.child),
    ]));
}

class XyDiaryLibraryPage extends StatelessWidget {
  final AppController controller;
  const XyDiaryLibraryPage({super.key,required this.controller});
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor:const Color(0xFFFFF7FA),
    appBar:AppBar(title:const Text('心屿手账 · 日记书架')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('每一本日记属于一个人',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      const Text('AI 日记来自你确认保存的聊天草稿；也支持手动写。原来的个人日记仍然保留。'),
      const SizedBox(height:18),
      _book(context,'我的日记','写下自己的小秘密',const Color(0xFFF5BCD1),
        () => XyNotebookShell(notebookKey:'diary.me',title:'我的日记',
          child:LocalNotesScreen(controller:controller,category:'diary',embedded:true))),
      for(final role in controller.data.characters)
        _book(context,'${role.name}的日记','AI 生成草稿 · 手动记录 · 本地归档',
          const Color(0xFFD3C7F4),
          () => XyNotebookShell(notebookKey:'diary.${role.id}',title:'${role.name}的日记',
            child:AiJournalPage(controller:controller,roleId:role.id,embedded:true))),
    ]));
  Widget _book(BuildContext context,String title,String detail,Color tint,Widget Function() page) =>
    Card(elevation:0,color:tint.withValues(alpha:.32),margin:const EdgeInsets.only(bottom:12),
      child:ListTile(contentPadding:const EdgeInsets.symmetric(vertical:14,horizontal:17),
        leading:Container(width:54,height:70,alignment:Alignment.center,
          decoration:BoxDecoration(color:tint,borderRadius:BorderRadius.circular(7)),
          child:const Icon(Icons.auto_stories_outlined,size:31,color:Colors.white)),
        title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),
        subtitle:Text(detail),trailing:const Icon(Icons.chevron_right_rounded),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page()))));
}

class XyDigitalGalleryPage extends StatelessWidget {
  final AppController controller;
  const XyDigitalGalleryPage({super.key,required this.controller});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('数字人图像与音色馆')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('为每个 AI 好友收藏专属的形象与音色',
        style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
      const SizedBox(height:6),
      const Text('可导入图片、使用自己配置的文生图 API 生成形象，录入合法授权的音色样本。数字人功能默认关闭。'),
      const SizedBox(height:16),
      if(controller.data.characters.isEmpty)
        const ListTile(title:Text('还没有 AI 好友，请先从通讯录建立角色。')),
      for(final role in controller.data.characters)
        FutureBuilder<DigitalPersonConfig>(
          future:DigitalPersonStore.load(role.id),builder:(context,snapshot){
            final item=snapshot.data;
            return Card(child:ListTile(
              leading:CircleAvatar(radius:28,
                backgroundImage:item!=null&&item.portraitPath.isNotEmpty&&File(item.portraitPath).existsSync()
                  ? FileImage(File(item.portraitPath)):null,
                child:item==null||item.portraitPath.isEmpty
                  ? const Icon(Icons.face_3_outlined):null),
              title:Text(role.name),
              subtitle:Text(item?.enabled==true?'数字人已开启 · 点击管理':'默认关闭 · 点击创建数字人'),
              trailing:const Icon(Icons.chevron_right_rounded),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>
                DigitalPersonPage(controller:controller,roleId:role.id)))));
          }),
    ]));
}

class XyVideoLibraryPage extends StatefulWidget {
  final AppController controller;
  const XyVideoLibraryPage({super.key,required this.controller});
  @override State<XyVideoLibraryPage> createState()=>_XyVideoLibraryPageState();
}
class _XyVideoLibraryPageState extends State<XyVideoLibraryPage> {
  final prefs=SharedPreferencesAsync();
  final items=<Map<String,String>>[];
  bool importing=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try {
      final raw=await prefs.getString('v41.localVideos');
      if(raw==null)return;
      final value=jsonDecode(raw);
      if(value is! List)return;
      if(mounted)setState(() {
        items..clear()..addAll(value.whereType<Map>().map((e)=>
          Map<String,String>.from(e.map((key,v)=>MapEntry('$key','$v')))));
      });
    } catch(_){ /* corrupted gallery: do not delete local media */ }
  }
  Future<void> _persist()=>prefs.setString('v41.localVideos',jsonEncode(items));
  Future<void> _import() async {
    if(importing)return;
    setState(()=>importing=true);
    try {
      final selected=await FilePicker.pickFiles(type:FileType.video);
      for(final file in selected){
        final size=await file.length();
        if(size!=null&&size>400*1024*1024)throw FormatException('${file.name} 超过 400MB');
        final relative=await widget.controller.local.copyIntoApp(file,'video_v41');
        final saved=widget.controller.local.resolve(relative);
        if(await saved.length()>400*1024*1024){await saved.delete();throw const FormatException('视频超过 400MB');}
        items.add({'title':file.name,'path':relative});
        await _persist();
      }
      if(mounted)setState((){});
    } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('导入失败：$e')));}
    finally{if(mounted)setState(()=>importing=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('本地视频库'),actions:[
      IconButton(onPressed:importing?null:_import,icon:const Icon(Icons.video_call_outlined))]),
    body:items.isEmpty?const Center(child:Text('还没有视频。点击右上角导入本地视频。')):
    ListView.builder(itemCount:items.length,itemBuilder:(context,index){
      final item=items[index];
      return ListTile(leading:const Icon(Icons.play_circle_fill_rounded,color:Color(0xFFA38AC4),size:34),
        title:Text(item['title']??'未命名视频'),
        subtitle:const Text('存储于应用私有目录；不会上传第三方服务器'),
        trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:() async {
          setState(()=>items.removeAt(index));await _persist();
        }),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>
          _XyLocalVideoPlayer(path:widget.controller.local.resolve(item['path']??'').path,
            title:item['title']??'视频'))));
    }),floatingActionButton:FloatingActionButton.extended(onPressed:importing?null:_import,
      icon:const Icon(Icons.add),label:const Text('导入视频')));
}
class _XyLocalVideoPlayer extends StatefulWidget {
  final String path,title;
  const _XyLocalVideoPlayer({required this.path,required this.title});
  @override State<_XyLocalVideoPlayer> createState()=>_XyLocalVideoPlayerState();
}
class _XyLocalVideoPlayerState extends State<_XyLocalVideoPlayer> {
  late final VideoPlayerController player;
  @override void initState(){super.initState();player=VideoPlayerController.file(File(widget.path));
    player.initialize().then((_){if(mounted)setState((){});});}
  @override void dispose(){player.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.title)),
    body:Center(child:player.value.isInitialized?Column(mainAxisSize:MainAxisSize.min,children:[
      AspectRatio(aspectRatio:player.value.aspectRatio,child:VideoPlayer(player)),
      VideoProgressIndicator(player,allowScrubbing:true),
      IconButton(icon:Icon(player.value.isPlaying?Icons.pause:Icons.play_arrow),onPressed:() {
        player.value.isPlaying?player.pause():player.play();setState((){});
      }),
    ]):const CircularProgressIndicator()));
}

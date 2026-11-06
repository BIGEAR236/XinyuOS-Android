import 'package:flutter/material.dart';
import '../core/companion.dart';
import '../core/media_engine.dart';
import '../core/storage.dart';
import 'game_page.dart';
import 'media_page.dart';
import 'pet_page.dart';
import 'story_page.dart';

/// This is the drop-in entrypoint for the EXISTING role profile page.
/// State is scoped to roleId; never share a pet save between characters.
class CompanionHub extends StatefulWidget {
  final String roleId, roleName;
  final String persona;
  final RoleResponder? responder;
  final MusicRoom? musicRoom;
  final void Function(String roleId, String description)? onLocalEvent;
  const CompanionHub({super.key,required this.roleId,required this.roleName,this.persona='',this.responder,this.musicRoom,this.onLocalEvent});
  @override State<CompanionHub> createState()=>_CompanionHubState();
}
class _CompanionHubState extends State<CompanionHub> {
  late CompanionController agent;
  late MusicRoom music;
  late bool ownsMusic;
  @override void initState(){super.initState();
    agent=CompanionController(roleId:widget.roleId,roleName:widget.roleName,persona:widget.persona,responder:widget.responder,onLocalEvent:widget.onLocalEvent);
    CompanionStorage().getGameAiEnabled(widget.roleId).then((enabled) {
      if (mounted) agent.setGameAiEnabled(enabled);
    });
    music=widget.musicRoom??MusicRoom();ownsMusic=widget.musicRoom==null;
  }
  @override void dispose(){agent.dispose();if(ownsMusic)music.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFFFFAFD),
    appBar:AppBar(title:Text('${widget.roleName} · 亲密互动'),backgroundColor:const Color(0xFFFFF6FB)),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(elevation:0,color:const Color(0xFFFCE5F3),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('♡ 和喜欢的角色，共同生活',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:Color(0xFF8A567F))),
        const SizedBox(height:7),
        Text('专属角色：${widget.roleName}  ·  各角色独立宠物存档',style:const TextStyle(fontSize:12,color:Color(0xFF826A80))),
        const SizedBox(height:10),
        const Text('进入任一空间，右下角圆形按钮可展开聊天。游戏 AI 评论默认关闭，节省 API 费用。',style:TextStyle(fontSize:12)),
      ]))),
      const SizedBox(height:12),
      _item('🥚','一起养宠物','彩绘蛋壳 · 30种宠物 · 现实时间冷却 · 等级成长',()=>PetPage(agent:agent)),
      _item('🎵','一起听歌','本地音乐 · 同步 LRC 歌词 · 一边听一边说',()=>MusicPage(agent:agent,room:music)),
      _item('🎬','一起看视频','本地视频 · SRT 字幕 · 边看边聊天',()=>WatchPage(agent:agent)),
      _item('🎲','一起玩游戏','五子棋 · 飞行棋 · 星币大富翁',()=>GamesPage(agent:agent)),
      _item('📝','沉浸剧情渲染','动作／对白／内心／状态 · 自动分层',()=>StoryPreviewPage(
        roleId: widget.roleId, roleName:widget.roleName, persona:widget.persona,
        responder: agent.responder,
        client:agent.responder is CompatibleResponder?StoryApiClient(
          endpoint:(agent.responder as CompatibleResponder).endpoint,
          model:(agent.responder as CompatibleResponder).model,
          apiKey:(agent.responder as CompatibleResponder).apiKey):null)),
      const SizedBox(height:12),
      const Text('游戏每步 AI 评论默认关闭，可在游戏列表或棋盘里手动开启；手动聊天仍会调用模型。',style:TextStyle(fontSize:12,color:Colors.black54)),
    ]),
  );
  Widget _item(String emoji,String title,String subtitle,Widget Function() page)=>Card(color:Colors.white,elevation:0,child:ListTile(
    contentPadding:const EdgeInsets.symmetric(vertical:9,horizontal:15),
    leading:Text(emoji,style:const TextStyle(fontSize:28)),
    title:Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),subtitle:Text(subtitle,style:const TextStyle(fontSize:12)),trailing:const Icon(Icons.chevron_right),
    onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page())),
  ));
}

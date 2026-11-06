import 'package:flutter/material.dart';
import 'core/companion.dart';
import 'core/media_engine.dart';
import 'pages/hub_page.dart';

void main() => runApp(const CompanionDemoApp());

class CompanionDemoApp extends StatelessWidget {
  const CompanionDemoApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'心屿 OS · 亲密互动功能演示',
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFFB47CA4)),useMaterial3:true,
      scaffoldBackgroundColor:const Color(0xFFFFFAFD)),
    home:const DemoRolePicker(),
  );
}

class DemoRolePicker extends StatefulWidget {
  const DemoRolePicker({super.key});
  @override State<DemoRolePicker> createState()=>_DemoRolePickerState();
}
class _DemoRolePickerState extends State<DemoRolePicker> {
  final endpoint=TextEditingController(text:'https://api.deepseek.com/v1');
  final model=TextEditingController(text:'deepseek-chat');
  final key=TextEditingController();
  RoleResponder? active;
  final music = MusicRoom();
  @override void dispose(){endpoint.dispose();model.dispose();key.dispose();music.dispose();super.dispose();}
  Future<void> configure() async {
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('为互动配置自己的 API（可跳过）'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:endpoint,decoration:const InputDecoration(labelText:'Base URL / Chat Completions 兼容接口')),
        TextField(controller:model,decoration:const InputDecoration(labelText:'模型 ID')),
        TextField(controller:key,obscureText:true,decoration:const InputDecoration(labelText:'API Key（只保留在当前内存中）')),
        const SizedBox(height:8),
        const Text('此独立样例支持 HTTPS OpenAI 兼容协议。Claude/Gemini 原生协议请接入原心屿 OS 的模型适配器。',style:TextStyle(fontSize:11,color:Colors.black54)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('取消')),
        FilledButton(onPressed:(){
          setState(()=>active=key.text.trim().isEmpty?null:CompatibleResponder(endpoint:endpoint.text.trim(),model:model.text.trim(),apiKey:key.text.trim()));
          Navigator.pop(ctx);
        },child:const Text('保存'))],
    ));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('心屿 OS V3.8 · 亲密互动')),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      const Text('这是可独立编译的 Flutter 互动模块演示，不包含旧版激活系统、通讯录和聊天记录。实际升级时需接入 V3.7 工程。',style:TextStyle(color:Colors.black54,fontSize:12)),
      const SizedBox(height:16),
      Card(color:const Color(0xFFF9EAF4),child:ListTile(
        leading:const Icon(Icons.settings_input_antenna),title:Text(active==null?'AI 状态：离线示例发言':'AI 状态：真实 API 互动'),
        subtitle:const Text('保留自己已有 API Key，不要嵌入安装包'),trailing:const Icon(Icons.chevron_right),onTap:configure,
      )),
      const SizedBox(height:14),
      const Text('选择一个角色，进入“角色资料 → 亲密互动”',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      for(final r in const [('xiaoman','小满','温柔细腻，喜欢照顾小动物'),('louyi','楼一','嘴硬心软，擅长幽默吐槽'),('linlin','林林','开朗活泼，喜欢音乐和游戏')])
        Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xFFF6DEED),child:Text(r.$2.substring(0,1))),
          title:Text(r.$2),subtitle:Text(r.$3),trailing:const Icon(Icons.favorite_border),
          onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CompanionHub(
            roleId:r.$1,roleName:r.$2,persona:r.$3,responder:active,musicRoom:music,
          ))),
        )),
    ]),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/story_parser.dart';
import '../core/companion.dart';

class StoryPreviewPage extends StatefulWidget {
  final StoryApiClient? client;
  final String roleName, persona;
  const StoryPreviewPage({super.key,this.client,this.roleName='楼一',this.persona=''});
  @override State<StoryPreviewPage> createState()=>_StoryPreviewPageState();
}
class _StoryPreviewPageState extends State<StoryPreviewPage> {
  final editor=TextEditingController(text:'''**16:45** | 纳沙泰尔·湖边咖啡馆

`他低头看了一眼手机，笑出声`

楼一 | ……这是什么？过年红包都没你这个准时。

`他抬眼看你，手指在屏幕上点了两下`

楼一 | 「祝你开心」——行，那我就却之不恭了。

> `她倒是比从前开朗多了。`

```
剧情地点：纳沙泰尔·湖边咖啡馆
好感度：38%
爱意：12%
醋意：0%
内心：这家伙，发红包都这么理直气壮。
```''');
  late StoryScene parsed;
  bool showSource=false;
  bool generating=false;
  final prompt=TextEditingController();
  String? error;
  @override void initState(){super.initState();parsed=StoryParser.parse(editor.text,fallbackName:'楼一');}
  @override void dispose(){editor.dispose();prompt.dispose();super.dispose();}
  Future<void> generate() async {
    final text=prompt.text.trim();if(text.isEmpty)return;
    setState((){generating=true;error=null;});
    try{
      final output=await widget.client!.generate(roleName:widget.roleName,persona:widget.persona,
        userMessage:text,formatContract:StoryParser.outputContract,virtualPlace:parsed.place.isEmpty?'虚拟场景':parsed.place);
      if(!mounted)return;
      setState((){editor.text=output;parsed=StoryParser.parse(output,fallbackName:widget.roleName);});
    }catch(e){if(mounted)setState(()=>error='调用模型失败：$e');}
    finally{if(mounted)setState(()=>generating=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('剧情格式 · 分层渲染')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      SwitchListTile(title:const Text('展开原始 Markdown 文本'),subtitle:const Text('演示：即使模型回传 Markdown，也能把动作、对白、内心、状态分开'),value:showSource,onChanged:(v)=>setState(()=>showSource=v)),
      if(showSource)...[
        TextField(controller:editor,maxLines:10,minLines:6,decoration:const InputDecoration(border:OutlineInputBorder(),hintText:'粘贴模型回复 Markdown 或 JSON')),
        Align(alignment:Alignment.centerRight,child:FilledButton(onPressed:()=>setState(()=>parsed=StoryParser.parse(editor.text,fallbackName:'楼一')),child:const Text('重新解析'))),
      ],
      const SizedBox(height:9),
      TextField(controller:prompt,maxLines:2,decoration:InputDecoration(
        hintText:widget.client==null?'未绑定 API：可展开原始文本测试格式解析':'输入消息，例如：这个红包是送给你的',
        border:const OutlineInputBorder(),suffixIcon:const Icon(Icons.mode_comment_outlined))),
      const SizedBox(height:7),
      FilledButton.icon(onPressed:widget.client==null || generating?null:generate,
        icon:generating?const SizedBox.square(dimension:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):const Icon(Icons.auto_awesome),
        label:Text(generating?'模型正在生成':'根据人格与格式要求生成')),
      if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:12),
      StorySceneCard(scene:parsed),
      if(StoryParser.validate(parsed).isNotEmpty)
        Padding(padding:const EdgeInsets.all(8),child:Text('格式检查：${StoryParser.validate(parsed).join('、')}',
          style:const TextStyle(fontSize:12,color:Color(0xFFC5804B))))
      else const Padding(padding:EdgeInsets.all(8),child:Text('格式检查通过：时间、场景、内容、角色状态均可识别',
        style:TextStyle(fontSize:12,color:Color(0xFF4D9275)))) ,
      Align(alignment:Alignment.centerRight,child:TextButton.icon(
        onPressed:() async {await Clipboard.setData(ClipboardData(text:StoryParser.toMarkdown(parsed)));
          if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('已复制符合格式的 Markdown')));
        },icon:const Icon(Icons.copy),label:const Text('复制标准 Markdown'))),
      const SizedBox(height:12),
      const Text('推荐：把人格文件作为独立角色设定；调用模型时按内部 JSON 契约要求 beats 分开输出；客户端校验后用组件渲染，用户不用手动选择 JSON/Markdown。',style:TextStyle(fontSize:12,color:Colors.black54)),
    ]),
  );
}

class StorySceneCard extends StatelessWidget {
  final StoryScene scene;
  const StorySceneCard({super.key,required this.scene});
  @override Widget build(BuildContext context)=>Card(elevation:0,color:const Color(0xFFFFF9FC),child:Padding(
    padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Icon(Icons.schedule,color:Color(0xFF9A759D),size:18),const SizedBox(width:8),
        Text(scene.time.isEmpty?'--:--':scene.time,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)),
        const SizedBox(width:10),Expanded(child:Text(scene.place,style:const TextStyle(fontSize:12,color:Colors.black54)))
      ]),const SizedBox(height:14),
      for(final beat in scene.beats) Padding(padding:const EdgeInsets.only(bottom:12),child:
        beat.kind==StoryKind.action?
          Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFECE9F1),borderRadius:BorderRadius.circular(10)),
            child:Text(beat.text,style:const TextStyle(fontSize:12,color:Color(0xFF777180),fontStyle:FontStyle.italic))):
        beat.kind==StoryKind.thought?
          Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFFEEE4F8),borderRadius:BorderRadius.circular(10)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${beat.speaker} · 内心独白',style:const TextStyle(fontSize:11,color:Color(0xFF8E6598),fontWeight:FontWeight.w600)),
              const SizedBox(height:5),Text(beat.text,style:const TextStyle(fontSize:13,color:Color(0xFF836394),fontStyle:FontStyle.italic))])):
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Padding(padding:const EdgeInsets.only(left:4,bottom:4),child:Text(beat.speaker,style:const TextStyle(fontSize:12,color:Color(0xFF5A4C61),fontWeight:FontWeight.w700))),
            Container(width:double.infinity,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0xFFEFE5EF))),
              child:Text(beat.text,style:const TextStyle(color:Color(0xFF392E3E),fontSize:16,height:1.55))),
          ])
      ),
      const Divider(),
      const Text('剧情状态',style:TextStyle(color:Color(0xFF8E6598),fontWeight:FontWeight.bold,fontSize:12)),
      const SizedBox(height:6),
      Wrap(spacing:12,runSpacing:7,children:[
        for(final key in ['好感度','爱意','醋意'])if(scene.status.containsKey(key))
          Chip(label:Text('$key ${scene.status[key]}',style:const TextStyle(fontSize:12)),side:BorderSide.none,backgroundColor:const Color(0xFFF1E7F6)),
      ]),
      if(scene.status.containsKey('剧情地点'))Text('地点：${scene.status['剧情地点']}',style:const TextStyle(fontSize:12)),
      if(scene.status.containsKey('内心'))Padding(padding:const EdgeInsets.only(top:6),child:Text('内心：${scene.status['内心']}',style:const TextStyle(fontSize:12,color:Color(0xFF8E6598)))),
    ]),
  ));
}

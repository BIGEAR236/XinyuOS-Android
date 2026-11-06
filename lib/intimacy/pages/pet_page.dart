import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/companion.dart';
import '../core/pet_engine.dart';
import '../core/storage.dart';
import '../widgets/chat_overlay.dart';
import '../widgets/pet_art.dart';

class PetPage extends StatefulWidget {
  final CompanionController agent;
  const PetPage({super.key,required this.agent});
  @override State<PetPage> createState()=>_PetPageState();
}
class _PetPageState extends State<PetPage> {
  final storage=CompanionStorage();
  PetState? pet;
  String status='孵化的惊喜，藏在每次陪伴里';
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final p=await storage.getPet(widget.agent.roleId);
    if(!mounted) return;
    p.decay(DateTime.now());
    setState(()=>pet=p);
  }
  void save(){final p=pet;if(p!=null) storage.setPet(widget.agent.roleId,p);}
  void action(String value){
    final p=pet;if(p==null) return;
    setState(()=>status=p.act(value,DateTime.now()));
    save();widget.agent.event('你们共同照顾宠物。宠物：${p.kind?.name ?? p.egg}；性格：${p.kind?.trait ?? '尚未孵化'}；动作：$value；结果：$status；当前心情：${p.expression}。请围绕当前动作自然回应。');
  }
  Future<void> changeEgg() async {
    final next=await showModalBottomSheet<String>(context:context,builder:(context)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      const ListTile(title:Text('选一颗等待孵化的蛋'),subtitle:Text('不同蛋拥有不同主题外观，不保证孵化哪一种宠物')),
      for(final egg in ['云朵蛋','森林蛋','海洋蛋','星光蛋','梦幻蛋']) ListTile(
        title:Text(egg),leading:const Icon(Icons.egg_outlined),onTap:()=>Navigator.pop(context,egg)),
    ])));
    if(next==null || pet==null) return;
    setState(()=>pet!.egg=next);save();
  }
  Future<void> drawEgg() async {
    final p=pet;if(p==null)return;
    var brush=0;
    var brushSize=4.0;
    await showDialog<void>(context:context,builder:(context)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
      title:const Text('给宠物蛋画上祝福'),
      content:SizedBox(width:300,height:350,child:Column(mainAxisSize:MainAxisSize.min,children:[
        SizedBox(height:250,child:EggPaintBoard(strokes:p.strokes,colorIndex:brush,brushWidth:brushSize,onChanged:(_)=>save())),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          for(var i=0;i<eggPalette.length;i++) GestureDetector(onTap:()=>update(()=>brush=i),child:Container(
            width:27,height:27,margin:const EdgeInsets.symmetric(horizontal:4),decoration:BoxDecoration(
            shape:BoxShape.circle,color:eggPalette[i],border:Border.all(color:brush==i?Colors.black:Colors.transparent,width:2)))),
        ]),
        Slider(value:brushSize,min:2,max:12,label:'画笔 $brushSize',onChanged:(v)=>update(()=>brushSize=v)),
      ])),
      actions:[
        TextButton(onPressed:(){update(()=>p.strokes.clear());save();},child:const Text('清空')),
        TextButton(onPressed:(){update((){if(p.strokes.isNotEmpty)p.strokes.removeLast();});save();},child:const Text('撤销')),
        FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('完成')),
      ],
    )));
    action('绘画');
  }

  void hatch() {
    final p=pet;if(p==null)return;
    try {
      final s=p.hatch(debugSkipTime:kDebugMode);
      setState(()=>status='哇！你们一起孵出了${s.name}！');save();
      widget.agent.event('宠物蛋孵化成功，出现一只${s.name}，性格${s.trait}，请和用户一起为它庆祝');
    } catch(e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
  }
  Widget stat(String title,int value,Color color)=>Expanded(child:Column(children:[
    Text('$title  $value',style:const TextStyle(fontSize:12)),
    const SizedBox(height:5),
    LinearProgressIndicator(value:value/100,minHeight:5,borderRadius:BorderRadius.circular(6),color:color,backgroundColor:color.withValues(alpha:.15)),
  ]));
  @override Widget build(BuildContext context){
    final p=pet;
    return CompanionScaffold(title:'与${widget.agent.roleName}一起养宠物',agent:widget.agent,
      actions:[IconButton(tooltip:'宠物图鉴',onPressed:()=>showDialog<void>(context:context,builder:(context)=>AlertDialog(
        title:const Text('15种萌宠图鉴'),content:SizedBox(width:320,height:390,child:ListView(children:[for(final s in petSpecies)
          ListTile(leading:Text(s.emoji,style:const TextStyle(fontSize:25)),title:Text(s.name),subtitle:Text('${s.rarity} · ${s.trait}'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('关闭'))])),icon:const Icon(Icons.auto_stories_outlined))],
      child:p==null?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.symmetric(horizontal:16,vertical:18),children:[
        Card(color:const Color(0xFFFFF2FA),elevation:0,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
          Text(p.isHatched ? '${p.kind?.emoji ?? ''} ${p.name} · Lv.${p.level}' : '${p.egg} · 等待孵化',style:const TextStyle(fontWeight:FontWeight.w700,fontSize:19)),
          const SizedBox(height:10),
          Center(child:CutePetArt(egg:!p.isHatched,eggTheme:p.egg,species:p.kind,mood:p.expression,strokes:p.strokes)),
          const SizedBox(height:8),
          Text(status,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF776375))),
          const SizedBox(height:12),
          if(!p.isHatched) ...[
            Row(children:[stat('亲密值',p.eggProgress,const Color(0xFFB77AA3)),const SizedBox(width:10),stat('陪伴值',p.affection,const Color(0xFF7B9CB9))]),
            const SizedBox(height:8),
            const Text('达到80点亲密值，并陪伴满1小时后可孵化。Debug模式允许快速验收。',textAlign:TextAlign.center,style:TextStyle(fontSize:11,color:Colors.black54)),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              TextButton(onPressed:changeEgg,child:const Text('更换蛋壳主题')),
              const SizedBox(width:8),
              FilledButton.tonal(onPressed:hatch,child:const Text('孵化 / 抽取宠物')),
            ]),
          ] else ...[
            Row(children:[stat('饱足',100-p.hunger,const Color(0xFFE0A670)),const SizedBox(width:10),stat('心情',p.joy,const Color(0xFFB77AA3)),const SizedBox(width:10),stat('精力',p.energy,const Color(0xFF8CBAC6))]),
            const SizedBox(height:12),
            Text('Lv.${p.level} · 当前心情：${p.expression} · 经验 ${p.xp}/${p.level*90}'),
          ],
        ]))),
        const SizedBox(height:12),
        Text(p.isHatched?'和它互动':'一起照顾宠物蛋',style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          for(final s in (p.isHatched?['喂食','玩球','抚摸','洗澡','睡觉','挠痒痒','轻拍','训练','探险']:
            ['唱歌','抚摸','讲故事','摇篮曲','绘画','拥抱']))
            ActionChip(label:Text(s),avatar:Icon(s=='绘画'?Icons.brush:s=='喂食'?Icons.restaurant:s=='唱歌'?Icons.music_note:Icons.favorite_outline,size:16),
              onPressed:()=>s=='绘画'?drawEgg():action(s)),
        ]),
        const SizedBox(height:12),
        const Text('每个 AI 好友有独立的宠物存档。宠物反应由本地数值驱动，角色的说话内容由右下方互动聊天触发。',style:TextStyle(color:Colors.black54,fontSize:12)),
      ]),
    );
  }
}

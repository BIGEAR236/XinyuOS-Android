import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../intimacy/core/pet_engine.dart';
import '../intimacy/core/storage.dart';
import '../intimacy/widgets/pet_art.dart';

/// Tiny character-bound hatched pet: draggable in the private chat.
/// Tap to pat it, long-press for the care menu, X to hide the bubble.
/// A hatched pet can be cared for anytime (the hourly cooldown only
/// paces egg hatching); the save itself is kept while hidden.
class XyChatPetCompanion extends StatefulWidget {
  final String roleId;
  const XyChatPetCompanion({super.key,required this.roleId});
  @override State<XyChatPetCompanion> createState()=>_XyChatPetCompanionState();
}
class _XyChatPetCompanionState extends State<XyChatPetCompanion> {
  final storage=CompanionStorage();
  final prefs=SharedPreferencesAsync();
  PetState? pet;
  double x=0.73,y=.69;
  String? expression;
  String? badge;
  bool hidden=false;
  String get hiddenKey=>'v41.petHidden.${widget.roleId}';
  String get posKey=>'v41.petPosition.${widget.roleId}';
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async {
    final state=await storage.getPet(widget.roleId);
    final pos=await prefs.getStringList(posKey);
    if(pos!=null&&pos.length==2){x=double.tryParse(pos[0])??x;y=double.tryParse(pos[1])??y;}
    final h=await prefs.getBool(hiddenKey)??false;
    state.decay(DateTime.now());
    if(!mounted)return;
    setState(()=>pet=state);
    setState(()=>hidden=h);
  }
  Future<void> _savePosition()=>prefs.setStringList(posKey,[x.toString(),y.toString()]);
  Future<void> _care(String action,{String? emoji,String? face}) async {
    final p=pet;if(p==null)return;
    final message=p.act(action,DateTime.now());
    await storage.setPet(widget.roleId,p);
    if(!mounted)return;
    setState((){expression=face??'享受';badge=emoji??'💗';});
    Future.delayed(const Duration(seconds:2),(){
      if(mounted)setState(()=>expression=null);});
    Future.delayed(const Duration(seconds:2),(){
      if(mounted)setState(()=>badge=null);});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:Text(message),duration:const Duration(seconds:2)));
  }
  Future<void> _hide() async {
    await prefs.setBool(hiddenKey,true);
    if(!mounted)return;
    setState(()=>hidden=true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:Text('宠物浮窗已隐藏；随时可在宠物页重新开启。')));
  }
  Future<void> _menu() async {
    const acts=[('喂食','🍗','享受'),('玩球','⚽','兴奋'),('洗澡','🫧','享受'),
      ('睡觉','💤','困倦'),('抚摸','💗','享受'),('挠痒痒','✨','兴奋')];
    final action=await showModalBottomSheet<String>(context:context,
      builder:(sheet)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(title:Text('${pet?.name.isEmpty??true?(pet?.kind?.name??'宠物'):pet!.name} · 随时互动'),
          subtitle:const Text('轻拍摸摸它 · 长按打开本菜单 · 拖动改变位置')),
        for(final entry in acts) ListTile(
          leading:Text(entry.$2,style:const TextStyle(fontSize:22)),
          title:Text(entry.$1),onTap:()=>Navigator.pop(sheet,entry.$1)),
        const Divider(height:1),
        ListTile(leading:const Icon(Icons.visibility_off_outlined),
          title:const Text('在聊天中隐藏宠物'),
          onTap:()=>Navigator.pop(sheet,'__hide__')),
        const SizedBox(height:6),
      ])));
    if(action==null)return;
    if(action=='__hide__'){await _hide();return;}
    const emojis={'喂食':'🍗','玩球':'⚽','洗澡':'🫧','睡觉':'💤','抚摸':'💗','挠痒痒':'✨'};
    const faces={'喂食':'享受','玩球':'兴奋','洗澡':'享受','睡觉':'困倦','抚摸':'享受','挠痒痒':'兴奋'};
    await _care(action,emoji:emojis[action],face:faces[action]);
  }
  @override Widget build(BuildContext context){
    final current=pet;
    if(current==null||!current.isHatched||hidden)return const SizedBox.shrink();
    return LayoutBuilder(builder:(context,size)=>Stack(children:[
      Positioned(left:(size.maxWidth*x-43).clamp(0, (size.maxWidth-86).clamp(0,double.infinity)).toDouble(),
        top:(size.maxHeight*y-43).clamp(0, (size.maxHeight-100).clamp(0,double.infinity)).toDouble(),
        child:SizedBox(height:100,width:86,child:Stack(clipBehavior:Clip.none,children:[
          GestureDetector(onPanUpdate:(d){
              setState(() {
                x=(x+d.delta.dx/size.maxWidth).clamp(0,1).toDouble();
                y=(y+d.delta.dy/size.maxHeight).clamp(0,1).toDouble();
              });
            },onPanEnd:(_)=>_savePosition(),
            onTap:()=>_care('轻拍',emoji:'💗',face:'享受'),
            onLongPress:_menu,
            child:Container(height:94,width:86,
              decoration:BoxDecoration(color:Colors.white.withValues(alpha:.74),
                borderRadius:BorderRadius.circular(20),
                border:Border.all(color:const Color(0xCCFFFFFF))),
              child:Column(children:[
                SizedBox(height:68,width:78,child:FittedBox(child:CutePetArt(
                  species:current.kind,mood:expression??current.expression,badge:badge))),
                Text('Lv.${current.level} · 轻拍/长按',style:const TextStyle(fontSize:9)),
              ]))),
          Positioned(right:-4,top:-8,child:SizedBox(height:24,width:24,child:IconButton(
            padding:EdgeInsets.zero,tooltip:'隐藏宠物',onPressed:_hide,
            icon:Container(decoration:BoxDecoration(shape:BoxShape.circle,
              color:Colors.white.withValues(alpha:.9),
              border:Border.all(color:const Color(0x33726D80))),
              child:const Icon(Icons.close,size:13,color:Color(0xFF726D80)))))),
        ]))),
    ]));
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../intimacy/core/pet_engine.dart';
import '../intimacy/core/storage.dart';
import '../intimacy/widgets/pet_art.dart';

/// Tiny character-bound hatched pet: draggable in the private chat.
/// Tapping earns care only when the real one-hour cooldown has elapsed.
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
  @override void initState(){super.initState(); _load();}
  Future<void> _load() async {
    final state=await storage.getPet(widget.roleId);
    final pos=await prefs.getStringList('v41.petPosition.${widget.roleId}');
    if(pos!=null&&pos.length==2){x=double.tryParse(pos[0])??x;y=double.tryParse(pos[1])??y;}
    if(mounted)setState(()=>pet=state);
  }
  Future<void> _tap() async {
    if(pet==null)return;
    final now=DateTime.now();
    if(!pet!.canInteract(now)){
      final remain=pet!.remainingCooldown(now).inMinutes+1;
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('宠物需要休息，约 $remain 分钟后才能再次领取亲密奖励。')));
      return;
    }
    final message=pet!.act('轻拍',now);
    await storage.setPet(widget.roleId,pet!);
    if(mounted){setState(()=>expression='开心');ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(message)));}
  }
  @override Widget build(BuildContext context){
    final current=pet;
    if(current==null||!current.isHatched)return const SizedBox.shrink();
    return LayoutBuilder(builder:(context,size)=>Stack(children:[
      Positioned(left:(size.maxWidth*x-43).clamp(0, (size.maxWidth-86).clamp(0,double.infinity)).toDouble(),
        top:(size.maxHeight*y-43).clamp(0, (size.maxHeight-94).clamp(0,double.infinity)).toDouble(),
        child:GestureDetector(onPanUpdate:(d){
          setState(() {
            x=(x+d.delta.dx/size.maxWidth).clamp(0,1).toDouble();
            y=(y+d.delta.dy/size.maxHeight).clamp(0,1).toDouble();
          });
        },onPanEnd:(_)=>prefs.setStringList('v41.petPosition.${widget.roleId}',
          [x.toString(),y.toString()]),
        onTap:_tap,
        child:Container(height:94,width:86,
          decoration:BoxDecoration(color:Colors.white.withValues(alpha:.74),
            borderRadius:BorderRadius.circular(20),
            border:Border.all(color:const Color(0xCCFFFFFF))),
          child:Column(children:[
            SizedBox(height:68,width:78,child:FittedBox(child:CutePetArt(
              species:current.kind,mood:expression??current.expression))),
            Text('Lv.${current.level} · 轻点摸摸',style:const TextStyle(fontSize:9)),
          ])))),
    ]));
  }
}

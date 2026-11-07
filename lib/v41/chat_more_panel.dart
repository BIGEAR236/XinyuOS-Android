import 'package:flutter/material.dart';

/// Two compact, horizontally swipeable pages; never covers entire chat screen.
class XyChatMorePanel extends StatefulWidget {
  final bool hasRole;
  const XyChatMorePanel({super.key, required this.hasRole});
  static Future<String?> open(BuildContext context, bool hasRole) =>
    showModalBottomSheet<String>(context: context, showDragHandle: true,
      isScrollControlled: false, backgroundColor: const Color(0xFFFFF8FC),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top:Radius.circular(22))),
      builder: (_) => XyChatMorePanel(hasRole: hasRole));
  @override State<XyChatMorePanel> createState() => _XyChatMorePanelState();
}
class _XyChatMorePanelState extends State<XyChatMorePanel> {
  final pages = PageController();
  int current = 0;
  @override void dispose(){pages.dispose();super.dispose();}
  static const entries = [
    ('image','图片',Icons.image_outlined,Color(0xFF8AAFCA)),
    ('call','音视频对话',Icons.video_call_rounded,Color(0xFFB38BD4)),
    ('red','红包',Icons.redeem_rounded,Color(0xFFE88E7E)),
    ('gift','礼物',Icons.card_giftcard_rounded,Color(0xFFE1A777)),
    ('game','一起玩游戏',Icons.sports_esports_rounded,Color(0xFF87A0D9)),
    ('music','一起听歌',Icons.headphones_rounded,Color(0xFF8EBCA8)),
    ('watch','一起看视频',Icons.ondemand_video_rounded,Color(0xFFC39ABF)),
    ('pet','一起养宠物',Icons.pets_rounded,Color(0xFFE5B4B9)),
  ];
  Widget _tile((String,String,IconData,Color) item) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => Navigator.pop(context, item.$1),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width:54,height:54,decoration:BoxDecoration(color:item.$4.withValues(alpha:.18),
        borderRadius:BorderRadius.circular(18)),child:Icon(item.$3,color:item.$4,size:30)),
      const SizedBox(height:7), Text(item.$2,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600)),
    ]));
  @override Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .3;
    return SafeArea(top:false,child:SizedBox(height:height.clamp(226,295).toDouble(),
      child:Column(children:[
        const Text('添加到聊天',style:TextStyle(fontSize:15,fontWeight:FontWeight.w600)),
        Expanded(child:PageView(controller:pages,onPageChanged:(v)=>setState(()=>current=v),
          children:[for(var page=0;page<2;page++)
            GridView.count(crossAxisCount:4,mainAxisSpacing:0,crossAxisSpacing:2,
              physics:const NeverScrollableScrollPhysics(),childAspectRatio:.76,
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
              children:[for(final item in entries.skip(page*4).take(4)) _tile(item)])])),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(2,(i)=>
          AnimatedContainer(duration:const Duration(milliseconds:170),margin:const EdgeInsets.all(3),
            width:i==current?18:7,height:7,decoration:BoxDecoration(
              color:i==current?const Color(0xFFA876A3):const Color(0xFFDEC8D8),
              borderRadius:BorderRadius.circular(10))))),
        const SizedBox(height:8),
      ])));
  }
}

class XyRedEnvelopeDraft {
  final int amount;
  final String message;
  final String cover;
  const XyRedEnvelopeDraft(this.amount,this.message,this.cover);
}
class XyRedEnvelopeComposer extends StatefulWidget {
  final String recipient;
  final int balance;
  const XyRedEnvelopeComposer({super.key,required this.recipient,required this.balance});
  @override State<XyRedEnvelopeComposer> createState()=>_XyRedEnvelopeComposerState();
}
class _XyRedEnvelopeComposerState extends State<XyRedEnvelopeComposer> {
  final amount=TextEditingController(text:'20');
  final note=TextEditingController(text:'祝你每天都有小惊喜');
  String cover='樱花祝福';
  @override void dispose(){amount.dispose();note.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFFFF4F0),
    appBar:AppBar(title:Text('给${widget.recipient}发红包'),backgroundColor:const Color(0xFFFFF4F0)),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const SizedBox(height:20),
      const Center(child:Icon(Icons.redeem_rounded,size:75,color:Color(0xFFD96B55))),
      const SizedBox(height:26),
      TextField(controller:amount,keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'金额（虚拟星币）',suffixText:'⭐',filled:true,
          fillColor:Colors.white,border:OutlineInputBorder())),
      const SizedBox(height:14),
      TextField(controller:note,maxLength:60,decoration:const InputDecoration(
        labelText:'红包祝福语',filled:true,fillColor:Colors.white,border:OutlineInputBorder())),
      const SizedBox(height:5),
      Text('红包封面',style:Theme.of(context).textTheme.titleSmall),
      const SizedBox(height:8),
      Wrap(spacing:8,children:['樱花祝福','星空心愿','暖阳陪伴'].map((v)=>
        ChoiceChip(selected:cover==v,label:Text(v),onSelected:(_)=>setState(()=>cover=v))).toList()),
      const SizedBox(height:16),
      Text('当前虚拟余额：${widget.balance} 星币 · 不涉及真实资金',
        style:const TextStyle(fontSize:12,color:Colors.black54)),
      const SizedBox(height:20),
      FilledButton(style:FilledButton.styleFrom(backgroundColor:const Color(0xFFD95D4F),
          minimumSize:const Size.fromHeight(52)),onPressed:(){
        final count=int.tryParse(amount.text.trim());
        if(count==null || count<1 || count>500 || count>widget.balance){
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:Text('请输入 1～500 星币且不超过余额的金额。')));return;
        }
        Navigator.pop(context,XyRedEnvelopeDraft(count,note.text.trim(),cover));
      },child:const Text('塞钱进红包',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold))),
    ]));
}

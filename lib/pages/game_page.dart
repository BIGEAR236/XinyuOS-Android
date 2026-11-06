import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/companion.dart';
import '../core/game_engines.dart';
import '../widgets/chat_overlay.dart';

class GamesPage extends StatelessWidget {
  final CompanionController agent;
  const GamesPage({super.key,required this.agent});
  @override Widget build(BuildContext context) => CompanionScaffold(title:'和${agent.roleName}玩游戏',agent:agent,
    child:ListView(padding:const EdgeInsets.all(16),children:[
      _game(context,'⚫','五子棋','15×15 棋盘 · AI 会阻挡四连并尝试连五',()=>GomokuPage(agent:agent)),
      _game(context,'✈️','飞行棋','双人简化规则 · 骰子起飞与撞机',()=>FlightPage(agent:agent)),
      _game(context,'🏠','大富翁','16 格迷你地产棋 · 星币买地和收租',()=>MonopolyPage(agent:agent)),
      const Padding(padding:EdgeInsets.all(14),child:Text('游戏胜负和资金由本地代码决定，AI 只负责个性化聊天。飞行棋和大富翁目前属于可玩的轻量规则，不是商业桌游的完整复刻。',style:TextStyle(fontSize:12,color:Colors.black54))),
    ]),
  );
  Widget _game(BuildContext context,String emoji,String title,String description,Widget Function() next)=>Card(
    color:const Color(0xFFFDF0F7),elevation:0,child:ListTile(
      leading:Text(emoji,style:const TextStyle(fontSize:30)),
      title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),
      subtitle:Text(description),trailing:const Icon(Icons.chevron_right),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>next())),
    ),
  );
}

class GomokuPage extends StatefulWidget {
  final CompanionController agent;
  const GomokuPage({super.key,required this.agent});
  @override State<GomokuPage> createState()=>_GomokuPageState();
}
class _GomokuPageState extends State<GomokuPage> {
  Gomoku game=Gomoku();
  String tip='你执黑子先手。点击棋盘任意交叉点落子。';
  void move(int row,int col){
    if(!game.put(row,col,1)) return;
    if(game.over) { setState(()=>tip='你赢了！五子连珠！'); widget.agent.event('用户在五子棋战胜了${widget.agent.roleName}'); return; }
    final ai=game.bestAiMove();
    if(ai!=null) game.put(ai.$1,ai.$2,2);
    setState(()=>tip=game.over?'${widget.agent.roleName}五子连珠！':'你走(${row+1},${col+1})，AI 回应(${(ai?.$1??0)+1},${(ai?.$2??0)+1})');
    widget.agent.event('五子棋新回合，$tip。当前需要聊棋局而不是随意编造落点');
  }
  @override Widget build(BuildContext context)=>CompanionScaffold(title:'⚫ 和${widget.agent.roleName}下五子棋',agent:widget.agent,
    actions:[IconButton(tooltip:'重新开始',onPressed:(){setState((){game=Gomoku();tip='新的一局开始了';});widget.agent.event('五子棋重新开局');},icon:const Icon(Icons.refresh))],
    child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      const Padding(padding:EdgeInsets.all(10),child:Text('你：⚫ 黑棋　 AI：⚪ 白棋',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold))),
      LayoutBuilder(builder:(context,c){
        final side=math.min(c.maxWidth-16,420.0);
        return Center(child:GestureDetector(onTapUp:(d){
          const edge=13.0;
          final spacing=(side-edge*2)/14;
          final col=((d.localPosition.dx-edge)/spacing).round().clamp(0,14).toInt();
          final row=((d.localPosition.dy-edge)/spacing).round().clamp(0,14).toInt();
          move(row,col);
        },child:CustomPaint(size:Size(side,side),painter:_GomokuPainter(game.board))));
      }),
      Padding(padding:const EdgeInsets.all(16),child:Text(tip,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF7A627C)))),
    ]),
  );
}
class _GomokuPainter extends CustomPainter {
  final List<int> board;
  _GomokuPainter(this.board);
  @override void paint(Canvas c,Size size){
    c.drawRRect(RRect.fromRectAndRadius(Offset.zero&size,const Radius.circular(14)),Paint()..color=const Color(0xFFF3DAAF));
    const e=13.0;final cell=(size.width-2*e)/14;
    for(var i=0;i<15;i++){
      final v=e+i*cell;
      c.drawLine(Offset(v,e),Offset(v,size.height-e),Paint()..color=const Color(0xFF8F795F)..strokeWidth=0.9);
      c.drawLine(Offset(e,v),Offset(size.width-e,v),Paint()..color=const Color(0xFF8F795F)..strokeWidth=0.9);
    }
    for(var i=0;i<15;i++)for(var j=0;j<15;j++){
      final v=board[i*15+j]; if(v==0)continue;
      c.drawCircle(Offset(e+j*cell,e+i*cell),cell*.39,Paint()..color=v==1?const Color(0xFF36353E):Colors.white);
      c.drawCircle(Offset(e+j*cell,e+i*cell),cell*.39,Paint()..color=const Color(0xFF746451)..style=PaintingStyle.stroke..strokeWidth=0.5);
    }
  }
  @override bool shouldRepaint(_GomokuPainter old)=>true;
}

class FlightPage extends StatefulWidget {
  final CompanionController agent;
  const FlightPage({super.key,required this.agent});
  @override State<FlightPage> createState()=>_FlightPageState();
}
class _FlightPageState extends State<FlightPage>{
  FlightChess game=FlightChess();
  int die=0;List<int> options=[];
  void roll(){
    if(game.over)return;
    setState((){die=game.roll();options=game.humanOptions(die);});
    if(options.isEmpty){
      final ai=game.aiTurn();
      widget.agent.event('飞行棋：你掷出$die点，没有可移动飞机。$ai');
      setState((){die=0;});
    }
  }
  void selectPlane(int idx){
    final s=game.humanMove(die,idx);
    final ai=game.over ? game.winner : game.aiTurn();
    setState((){die=0;options=[];});
    widget.agent.event('飞行棋：$s。$ai');
  }
  Widget fleet(String label,List<int> positions,Color color)=>Card(color:color.withValues(alpha:.15),child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
    Text(label,style:const TextStyle(fontWeight:FontWeight.bold)),
    for(var i=0;i<2;i++)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[
      Icon(Icons.flight_takeoff,color:color),const SizedBox(width:8),Text('${i+1}号'),const SizedBox(width:8),
      Expanded(child:LinearProgressIndicator(value:(positions[i]+1).clamp(0,24)/24,color:color,borderRadius:BorderRadius.circular(6))),
      const SizedBox(width:10),Text(positions[i]<0?'机库':positions[i]>=24?'终点':'${positions[i]+1}/24'),
    ])),
  ])));
  @override Widget build(BuildContext context)=>CompanionScaffold(title:'✈️ 双人飞行棋',agent:widget.agent,
    actions:[IconButton(onPressed:()=>setState((){game=FlightChess();die=0;options=[];}),icon:const Icon(Icons.refresh))],
    child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('轻量规则：6点起飞，双方各两架飞机，走满24格到达终点，落在对方飞机位置可将其送回机库。',style:TextStyle(color:Colors.black54,fontSize:12)),
      const SizedBox(height:10),fleet('你 · 粉色战机',game.human,const Color(0xFFDA789F)),
      fleet('${widget.agent.roleName} · 蓝色战机',game.ai,const Color(0xFF76A4D1)),
      Card(color:const Color(0xFFF9EFFC),child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
        const Text('🎲',style:TextStyle(fontSize:45)),
        Text(die==0?'轮到你掷骰子':'本轮掷出 $die 点',style:const TextStyle(fontSize:18)),
        const SizedBox(height:9),
        if(game.over)Text(game.winner) else if(die==0) FilledButton(onPressed:roll,child:const Text('掷骰子'))
          else Wrap(spacing:8,children:[for(final i in options)FilledButton.tonal(onPressed:()=>selectPlane(i),child:Text('移动${i+1}号飞机'))]),
      ]))),
      ListTile(title:Text(game.news),subtitle:Text('AI 上次骰子：${game.lastAiDice}')),
    ]),
  );
}

class MonopolyPage extends StatefulWidget {
  final CompanionController agent;
  const MonopolyPage({super.key,required this.agent});
  @override State<MonopolyPage> createState()=>_MonopolyPageState();
}
class _MonopolyPageState extends State<MonopolyPage>{
  TinyMonopoly game=TinyMonopoly();
  bool buy=true;
  void round(){
    final a=game.turn(0,buy:buy);
    final b=game.finished?'':game.turn(1,buy:true);
    setState((){});
    widget.agent.event('你和${widget.agent.roleName}在虚拟大富翁：$a。$b。当前虚拟资金你${game.balances[0]}星币，AI ${game.balances[1]}星币');
  }
  int? tileIndex(int row,int col){
    if(row==0)return col;
    if(col==4)return 4+row;
    if(row==4)return 12-col;
    if(col==0)return 16-row;
    return null;
  }
  @override Widget build(BuildContext context)=>CompanionScaffold(title:'🏠 星币大富翁',agent:widget.agent,
    actions:[IconButton(onPressed:()=>setState(()=>game=TinyMonopoly()),icon:const Icon(Icons.refresh))],
    child:ListView(padding:const EdgeInsets.all(12),children:[
      Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
        Text('你：${game.balances[0]} ⭐',style:const TextStyle(fontWeight:FontWeight.bold)),
        Text('${widget.agent.roleName}：${game.balances[1]} ⭐',style:const TextStyle(fontWeight:FontWeight.bold)),
      ]),const SizedBox(height:12),
      AspectRatio(aspectRatio:1,child:GridView.builder(physics:const NeverScrollableScrollPhysics(),
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:5,mainAxisSpacing:2,crossAxisSpacing:2),itemCount:25,
        itemBuilder:(context,i){
          final r=i~/5,c=i%5,idx=tileIndex(r,c);
          if(idx==null)return Container(color:const Color(0xFFFFF6FD),child:i==12?const Center(child:Text('✨\n星光\n小镇',textAlign:TextAlign.center)):null);
          final t=game.tiles[idx];
          final people='${game.positions[0]==idx?'🩷':''}${game.positions[1]==idx?'🩵':''}';
          return Container(decoration:BoxDecoration(color:t.owner==0?const Color(0xFFFFDBE9):t.owner==1?const Color(0xFFD8E7FA):const Color(0xFFF0E3F3),borderRadius:BorderRadius.circular(5)),
            alignment:Alignment.center,padding:const EdgeInsets.all(3),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text(t.name,maxLines:2,textAlign:TextAlign.center,style:const TextStyle(fontSize:9,fontWeight:FontWeight.w600)),
              if(t.price>0)Text('${t.price}⭐',style:const TextStyle(fontSize:8)),
              Text(people,style:const TextStyle(fontSize:11)),
            ]));
        },
      )),
      SwitchListTile(title:const Text('路过无主地产时自动购买'),value:buy,onChanged:(v)=>setState(()=>buy=v)),
      FilledButton.icon(onPressed:game.finished?null:round,icon:const Icon(Icons.casino_outlined),label:const Text('掷骰子 · 我方行动后 AI 自动行动')),
      const SizedBox(height:12),
      if(game.log.isNotEmpty)for(final line in game.log.take(5))ListTile(dense:true,leading:const Icon(Icons.receipt_long,size:16),title:Text(line,style:const TextStyle(fontSize:12))),
      const Text('仅使用本地虚拟星币，无支付、充值和实际交易。',style:TextStyle(fontSize:11,color:Colors.black54)),
    ]),
  );
}

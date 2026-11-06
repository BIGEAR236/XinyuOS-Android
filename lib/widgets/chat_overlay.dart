import 'package:flutter/material.dart';
import '../core/companion.dart';

class SoftChatBar extends StatefulWidget {
  final CompanionController agent;
  const SoftChatBar({super.key,required this.agent});
  @override State<SoftChatBar> createState()=>_SoftChatBarState();
}
class _SoftChatBarState extends State<SoftChatBar> {
  final input=TextEditingController();
  bool expanded=false;
  @override void dispose() {input.dispose();super.dispose();}
  @override Widget build(BuildContext context) => AnimatedBuilder(animation:widget.agent,builder:(context,_){
    final a=widget.agent;
    return Container(
      decoration:const BoxDecoration(color:Color(0xF5FDF8FD),boxShadow:[BoxShadow(color:Color(0x15000000),blurRadius:12)]),
      padding:EdgeInsets.fromLTRB(12,8,12,MediaQuery.of(context).padding.bottom+7),
      child: Column(mainAxisSize:MainAxisSize.min,children:[
        Row(children:[
          const Icon(Icons.favorite_border,color:Color(0xFFB57BB0),size:18),
          const SizedBox(width:7),
          Text('${a.roleName} · ${a.sourceLabel}',style:const TextStyle(fontSize:11,color:Color(0xFF846A81))),
          const Spacer(),
          TextButton.icon(onPressed:()=>setState(()=>expanded=!expanded),icon:Icon(expanded?Icons.expand_more:Icons.expand_less,size:16),label:Text(expanded?'收起':'展开对话')),
        ]),
        if (expanded) SizedBox(height:140,child:ListView.builder(
          reverse:true,itemCount:a.lines.length,itemBuilder:(context,i){
            final line=a.lines[a.lines.length-i-1];
            return Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text('${line.source}：${line.text}',style:TextStyle(color:line.isUser?const Color(0xFF72578D):const Color(0xFF554D59),fontSize:12)));
          },
        )) else if(a.lines.isNotEmpty) Align(alignment:Alignment.centerLeft,child:Text(
          '${a.lines.last.source}：${a.lines.last.text}',maxLines:2,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontSize:12,color:Color(0xFF625665)),
        )),
        const SizedBox(height:5),
        Row(children:[
          Expanded(child:TextField(controller:input,maxLines:1,
            decoration:InputDecoration(isDense:true,hintText:'边玩边和${a.roleName}说话…',filled:true,fillColor:Colors.white,
              contentPadding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
              border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.circular(25))),
            onSubmitted:(_)=>submit(),
          )),
          const SizedBox(width:7),
          IconButton.filled(onPressed:a.busy?null:submit,icon:a.busy?
            const SizedBox.square(dimension:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)):
            const Icon(Icons.send_rounded),style:IconButton.styleFrom(backgroundColor:const Color(0xFFAC7AA4))),
        ])
      ]),
    );
  });
  void submit(){
    final m=input.text.trim(); if(m.isEmpty) return;
    input.clear(); FocusScope.of(context).unfocus();
    widget.agent.event(widget.agent.lastEvent,automatic:false,message:m);
  }
}

class CompanionScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final CompanionController agent;
  final List<Widget>? actions;
  const CompanionScaffold({super.key,required this.title,required this.child,required this.agent,this.actions});
  @override Widget build(BuildContext context)=> Scaffold(
    backgroundColor:const Color(0xFFFFFBFE),
    appBar:AppBar(title:Text(title),backgroundColor:const Color(0xFFFFF7FC),actions:actions),
    body:child,
    bottomNavigationBar:SoftChatBar(agent:agent),
  );
}

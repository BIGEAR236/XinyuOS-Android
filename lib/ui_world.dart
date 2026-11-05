import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_chat.dart';
import 'ui_extras.dart';

/// This entire module is a LOCAL simulation. No real balances, purchases,
/// deliveries, bank transfers or third-party platform impersonation.
Future<String?> worldTextDialog(BuildContext context, String title,
    {String hint = '', String initial = ''}) async {
  final edit = TextEditingController(text: initial);
  try {
    return await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(title: Text(title),
        content: TextField(controller: edit, autofocus: true,
          maxLines: 2, minLines: 1, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, edit.text.trim()),
            child: const Text('确定')),
        ]));
  } finally { edit.dispose(); }
}

void worldNotice(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message),
    behavior: SnackBarBehavior.floating));
}

class WorldHubScreen extends StatelessWidget {
  final AppController controller;
  const WorldHubScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('我的虚拟世界')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('心屿 · 共同生活', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('所有账户、红包、订单和宠物都是本地虚拟模拟，不是真实货币或现实服务。',
            style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 8, children: [
            Chip(avatar: const Icon(Icons.stars_rounded, size: 18),
              label: Text('${controller.data.worldBalance} 星币')),
            Chip(avatar: const Icon(Icons.pets, size: 18),
              label: Text('${controller.data.worldPet.name} · Lv.${controller.data.worldPet.level}')),
          ]),
        ]))),
        const SizedBox(height: 12),
        _entry(context,Icons.account_balance_wallet_outlined,'星币钱包与红包',
          '虚拟收支、签到、给 AI 发红包',VirtualWalletScreen(controller:controller)),
        _entry(context,Icons.pets_outlined,'一起养宠物',
          '喂食、玩耍、休息、成长和共同记忆',VirtualPetScreen(controller:controller)),
        _entry(context,Icons.shopping_bag_outlined,'星愿商店',
          '本地模拟挑礼物、购物车和订单',VirtualShopScreen(controller:controller)),
        _entry(context,Icons.ondemand_video_outlined,'一起看视频',
          '导入本地影片，观看时直接聊天',CoWatchScreen(controller:controller)),
        _entry(context,Icons.music_note_outlined,'一起听音乐',
          '打开本地音乐，可在聊天中持续播放',MusicScreen(controller:controller)),
        _entry(context,Icons.timeline_outlined,'共同经历',
          '查看红包、购物、照顾宠物等本地事件',WorldTimelineScreen(controller:controller)),
        const SizedBox(height: 12),
        const Padding(padding: EdgeInsets.all(8),child: Text(
          '本版本不接入淘宝、京东、真实视频平台或支付接口；这些功能属于模拟场景，不产生真实订单。',
          style: TextStyle(fontSize: 12,color:Colors.grey))),
      ])));

  Widget _entry(BuildContext context, IconData icon, String name,
      String hint, Widget screen) => Card(child: ListTile(
        leading: Icon(icon), title: Text(name), subtitle: Text(hint),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,MaterialPageRoute(builder:(_)=>screen))));
}

class VirtualWalletScreen extends StatelessWidget {
  final AppController controller;
  const VirtualWalletScreen({super.key,required this.controller});

  Future<void> _gift(BuildContext context) async {
    if (controller.data.characters.isEmpty) { worldNotice(context,'请先添加一位 AI 好友'); return; }
    final friend = await showModalBottomSheet<Character>(context:context,
      showDragHandle:true,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,
        children:[const ListTile(title:Text('选择虚拟红包收件人')),
        ...controller.data.characters.map((c)=>ListTile(title:Text(c.name),
          onTap:()=>Navigator.pop(ctx,c)))])));
    if (friend == null || !context.mounted) return;
    final value = await worldTextDialog(context,'给 ${friend.name} 发星币红包',
      hint:'请输入1～500整数；仅为虚拟星币');
    if (!context.mounted || value==null) return;
    final amount=int.tryParse(value);
    if (amount==null || !controller.giveRedEnvelope(friend.id,amount)) {
      worldNotice(context,'金额不正确或余额不足'); return;
    }
    worldNotice(context,'虚拟红包已记账，不发生真实转账');
    if (context.mounted) Navigator.push(context,MaterialPageRoute(
      builder:(_)=>ChatScreen(controller:controller,friend:friend)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:controller,
    builder:(context,_)=>Scaffold(
      appBar:AppBar(title:const Text('星币钱包（虚拟）')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
          const Icon(Icons.auto_awesome,size:32),
          Text('${controller.data.worldBalance}',
            style:Theme.of(context).textTheme.displayMedium),
          const Text('虚拟星币 · 无法提现、兑换或购买真实商品'),
          const SizedBox(height:12),
          Wrap(alignment:WrapAlignment.center,spacing:8,children:[
            FilledButton.icon(onPressed:(){
              worldNotice(context,controller.dailyCheckIn() ? '签到成功：+60 星币' : '今天已经签到过了');
            },icon:const Icon(Icons.event_available),label:const Text('每日签到')),
            OutlinedButton.icon(onPressed:()=>_gift(context),
              icon:const Icon(Icons.card_giftcard),label:const Text('发虚拟红包')),
          ]),
        ]))),
        const SizedBox(height:12),
        Text('最近收支',style:Theme.of(context).textTheme.titleMedium),
        for(final entry in controller.data.worldLedger.reversed.take(50))
          ListTile(leading:Icon(entry.delta>0?Icons.add_circle_outline:Icons.remove_circle_outline),
            title:Text(entry.description),
            subtitle:Text(entry.createdAt.toLocal().toString().substring(0,16)),
            trailing:Text('${entry.delta>0?'+':''}${entry.delta}',
              style:TextStyle(color:entry.delta>0?Colors.green:Theme.of(context).colorScheme.onSurface))),
      ])));
}

class VirtualPetScreen extends StatefulWidget {
  final AppController controller;
  const VirtualPetScreen({super.key,required this.controller});
  @override State<VirtualPetScreen> createState()=>_VirtualPetScreenState();
}

class _VirtualPetScreenState extends State<VirtualPetScreen> {
  String? withFriendId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation:widget.controller,
    builder:(context,_) {
      final pet=widget.controller.data.worldPet;
      return Scaffold(appBar:AppBar(title:const Text('我们的宠物')),
        body:ListView(padding:const EdgeInsets.all(16),children:[
          Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(children:[
            Text(pet.species=='狗'?'🐶':'🐱',style:const TextStyle(fontSize:88)),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text('${pet.name} · Lv.${pet.level}',style:Theme.of(context).textTheme.headlineSmall),
              IconButton(tooltip:'改名',onPressed:() async {
                final v=await worldTextDialog(context,'给宠物改名',initial:pet.name);
                if(v!=null) widget.controller.renamePet(v);
              },icon:const Icon(Icons.edit_outlined)),
            ]),
            Text('陪伴亲密度：${pet.affection}'),
            const SizedBox(height:12),
            _bar('饱腹',pet.hunger),_bar('开心',pet.happiness),_bar('精力',pet.energy),
          ]))),
          const SizedBox(height:14),
          DropdownButtonFormField<String>(
            initialValue:withFriendId,
            hint:const Text('邀请哪位 AI 一起照顾？（可选）'),
            items:[const DropdownMenuItem<String>(value:'none',child:Text('我自己')),
              ...widget.controller.data.characters.map((c)=>DropdownMenuItem<String>(
                value:c.id,child:Text(c.name)))],
            onChanged:(value)=>setState(()=>withFriendId=value)),
          const SizedBox(height:14),
          Wrap(spacing:8,runSpacing:8,children:[
            FilledButton.icon(onPressed:()=>_act('feed'),icon:const Icon(Icons.restaurant),
              label:const Text('喂食（12星币）')),
            FilledButton.tonalIcon(onPressed:()=>_act('play'),icon:const Icon(Icons.sports_esports),
              label:const Text('一起玩')),
            OutlinedButton.icon(onPressed:()=>_act('rest'),icon:const Icon(Icons.bedtime_outlined),
              label:const Text('休息')),
          ]),
          const SizedBox(height:12),
          if(withFriendId!=null && withFriendId!='none')
            OutlinedButton.icon(onPressed:(){
              final c=widget.controller.character(withFriendId!);
              if(c!=null) Navigator.push(context,MaterialPageRoute(builder:(_)=>
                ChatScreen(controller:widget.controller,friend:c)));
            },icon:const Icon(Icons.chat_outlined),label:const Text('聊聊刚才一起照顾宠物的事')),
          const ListTile(title:Text('成长说明'),subtitle:Text(
            '所有宠物动作都保存在本机。AI 只有在你聊天调用其模型时，才会收到与自己相关的共同经历摘要。')),
        ]));
    });

  Widget _bar(String label,int value)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),
    child:Row(children:[SizedBox(width:44,child:Text(label)),
      Expanded(child:LinearProgressIndicator(value:value/100,minHeight:9,
        borderRadius:BorderRadius.circular(10))),
      SizedBox(width:40,child:Text('$value',textAlign:TextAlign.end))]));
  void _act(String action){
    final ok=widget.controller.careForPet(action,
      withCharacterId:withFriendId=='none'?null:withFriendId);
    worldNotice(context,ok?'已记录到共同经历':'余额不足，无法喂食');
  }
}

class VirtualShopScreen extends StatefulWidget {
  final AppController controller;
  const VirtualShopScreen({super.key,required this.controller});
  @override State<VirtualShopScreen> createState()=>_VirtualShopScreenState();
}
class _VirtualShopScreenState extends State<VirtualShopScreen> {
  Future<void> _askCompanion(VirtualShopItem item) async {
    if (widget.controller.data.characters.isEmpty) {
      worldNotice(context,'请先添加 AI 好友'); return;
    }
    final c=await showModalBottomSheet<Character>(context:context,
      showDragHandle:true,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,
        children:[const ListTile(title:Text('邀请好友一起逛模拟商店')),
        ...widget.controller.data.characters.map((x)=>ListTile(title:Text(x.name),
          onTap:()=>Navigator.pop(ctx,x)))])));
    if (c==null || !mounted) return;
    Navigator.push(context,MaterialPageRoute(builder:(_)=>
      ChatScreen(controller:widget.controller,friend:c)));
    await widget.controller.sendPrivate(c,
      '我们在星愿商店逛街，看到了「${item.title}」，你觉得适不适合我们？',
      contextHint:'这里是本机模拟购物场景，虚拟商品：${item.title}，${item.cost}星币。'
        '无真实订单、付款或配送。你只需陪伴讨论，不应谎称已经购买。');
  }

  String? giftTo;
  String selectedCategory='全部';
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.controller,
    builder:(context,_){
      final data=widget.controller.data;
      final items=selectedCategory=='全部'?virtualShop:
        virtualShop.where((e)=>e.category==selectedCategory).toList();
      return Scaffold(appBar:AppBar(title:const Text('星愿商店 · 模拟购物')),
        body:ListView(padding:const EdgeInsets.all(12),children:[
          Card(child:ListTile(leading:const Icon(Icons.stars_rounded),
            title:Text('余额 ${data.worldBalance} 星币'),
            subtitle:const Text('虚拟货币 / 模拟商品 / 不会真实付款或配送'))),
          SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
            for(final category in const ['全部','礼物','美食','宠物','家居','穿搭','约会','生活'])
              Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(
                label:Text(category),selected:selectedCategory==category,
                onSelected:(_)=>setState(()=>selectedCategory=category))),
          ])),
          for(final item in items) Card(child:ListTile(
            leading:Text(item.emoji,style:const TextStyle(fontSize:30)),
            title:Text(item.title),subtitle:Text('${item.category} · ${item.cost}星币'),
            trailing:Row(mainAxisSize:MainAxisSize.min,children:[
              IconButton(tooltip:'和 AI 一起挑选',onPressed:()=>_askCompanion(item),
                icon:const Icon(Icons.chat_bubble_outline,size:21)),
              IconButton(tooltip:'减少',onPressed:()=>widget.controller.changeCart(
                item.id,(data.worldCart[item.id]??0)-1),icon:const Icon(Icons.remove_circle_outline)),
              Text('${data.worldCart[item.id]??0}'),
              IconButton(tooltip:'添加',onPressed:()=>widget.controller.changeCart(
                item.id,(data.worldCart[item.id]??0)+1),icon:const Icon(Icons.add_circle_outline)),
            ]))),
          const Divider(),
          DropdownButtonFormField<String>(initialValue:giftTo,
            hint:const Text('收货角色（可选，模拟礼物）'),
            items:[const DropdownMenuItem<String>(value:'none',child:Text('留给自己')),
              ...widget.controller.data.characters.map((c)=>DropdownMenuItem(
                value:c.id,child:Text('送给${c.name}')))],
            onChanged:(v)=>setState(()=>giftTo=v)),
          const SizedBox(height:10),
          FilledButton(onPressed:widget.controller.worldCartTotal<=0?null:(){
            final ok=widget.controller.checkoutVirtualCart(
              giftTo:giftTo=='none'?null:giftTo);
            worldNotice(context,ok?'已生成本地模拟订单':'余额不足或商品无效');
          },child:Text('模拟结算 · ${widget.controller.worldCartTotal} 星币')),
          const SizedBox(height:15),
          Text('订单历史',style:Theme.of(context).textTheme.titleMedium),
          for(final order in data.worldOrders.reversed.take(40)) ListTile(
            leading:const Icon(Icons.receipt_long_outlined),
            title:Text('${order.title} × ${order.count}'),
            subtitle:Text(order.giftedTo==null?'自己收藏':'送给${widget.controller.displayName(order.giftedTo!)}'),
            trailing:Text('${order.total}星币')),
        ]));
    });
}

class WorldTimelineScreen extends StatelessWidget {
  final AppController controller;
  const WorldTimelineScreen({super.key,required this.controller});
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:controller,
    builder:(context,_)=>Scaffold(appBar:AppBar(title:const Text('共同经历')),
      body:controller.data.worldEvents.isEmpty
      ? const Center(child:Text('还没有共同经历，试试照顾宠物或一起购物。'))
      : ListView.builder(itemCount:controller.data.worldEvents.length,
        itemBuilder:(context,i){
          final entry=controller.data.worldEvents.reversed.elementAt(i);
          return ListTile(leading:const Icon(Icons.auto_stories_outlined),
            title:Text(entry.description),
            subtitle:Text(entry.createdAt.toLocal().toString().substring(0,16)));
        })));
}

/// Offline video playback with a chat pane. The model is NOT given video
/// frames, audio or a transcription — only the title, elapsed time and user text.
class CoWatchScreen extends StatefulWidget {
  final AppController controller;
  const CoWatchScreen({super.key,required this.controller});
  @override State<CoWatchScreen> createState()=>_CoWatchScreenState();
}
class _CoWatchScreenState extends State<CoWatchScreen> {
  VideoPlayerController? player;
  final input=TextEditingController();
  String? friendId;
  String videoTitle='';
  bool loading=false;

  @override void dispose(){player?.dispose();input.dispose();super.dispose();}

  Future<void> _pickVideo() async {
    if(loading) return;
    setState(()=>loading=true);
    try {
      final picked=await FilePicker.pickFile(type:FileType.video);
      if(picked==null)return;
      final size=await picked.length();
      if(size!=null && size>250*1024*1024){
        worldNotice(context,'为保护手机空间，单个视频限250MB');return;
      }
      final path=await widget.controller.local.copyIntoApp(picked,'watch_videos');
      widget.controller.setWatchPath(path);
      await _openVideo(path,title:picked.name);
    } catch(e){if(mounted) worldNotice(context,'加载视频失败：$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }

  Future<void> _openVideo(String path,{String? title}) async {
    final file=widget.controller.local.resolve(path);
    if(!await file.exists()){if(mounted)worldNotice(context,'原视频文件不存在');return;}
    final next=VideoPlayerController.file(file);
    try{
      await next.initialize();
      if(!mounted){await next.dispose();return;}
      final old=player;
      setState(() { player=next; videoTitle=title??path.split('/').last; });
      await old?.dispose();
      await next.play();
    }catch(e){await next.dispose();if(mounted)worldNotice(context,'此视频格式暂不支持：$e');}
  }

  Future<void> _send() async {
    final c=widget.controller.character(friendId??'');
    final value=input.text.trim();
    if(c==null){worldNotice(context,'请先选择一位 AI 朋友');return;}
    if(value.isEmpty)return;
    final current=player?.value.position.inSeconds ?? 0;
    input.clear();FocusScope.of(context).unfocus();
    final error=await widget.controller.sendPrivate(c,value,
      contextHint:'用户正在本机播放名为「$videoTitle」的视频，当前播放至第${current~/60}分${current%60}秒。'
        '你没有接收到视频画面/声音，不要假装自己看见内容；可根据用户描述陪伴讨论。');
    if(mounted&&error!=null)worldNotice(context,error);
  }

  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:widget.controller,
    builder:(context,_){
      final c=widget.controller.character(friendId??'');
      final recent=c==null?<ChatEntry>[]:
        widget.controller.threadMessages(privateThread(c.id)).reversed.take(6).toList().reversed.toList();
      return Scaffold(appBar:AppBar(title:const Text('一起看 · 本地视频')),
        body:Column(children:[
          if(player!=null && player!.value.isInitialized)
            AnimatedBuilder(animation:player!,builder:(context,_){
              final v=player!.value;
              final secs=v.duration.inMilliseconds<=0?1:v.duration.inMilliseconds;
              return Column(children:[
                AspectRatio(aspectRatio:v.aspectRatio>0?v.aspectRatio:16/9,
                  child:VideoPlayer(player!)),
                Row(children:[
                  IconButton(onPressed:(){v.isPlaying?player!.pause():player!.play();},
                    icon:Icon(v.isPlaying?Icons.pause:Icons.play_arrow)),
                  Expanded(child:Slider(value:(v.position.inMilliseconds/secs).clamp(0.0,1.0).toDouble(),
                    onChanged:(x)=>player!.seekTo(Duration(milliseconds:(x*secs).round())))),
                  Text('${v.position.inMinutes}:${(v.position.inSeconds%60).toString().padLeft(2,'0')}  '),
                ])]);
            })
          else const SizedBox(height:128,child:Center(child:Text('选择本机视频开始一起看'))),
          Row(children:[
            Expanded(child:TextButton.icon(onPressed:loading?null:_pickVideo,
              icon:const Icon(Icons.video_file_outlined),label:Text(loading?'加载中':'导入视频'))),
            Expanded(child:DropdownButton<String>(value:friendId,
              hint:const Text('选择AI朋友'),isExpanded:true,
              items:widget.controller.data.characters.map((c)=>DropdownMenuItem(
                value:c.id,child:Text(c.name,overflow:TextOverflow.ellipsis))).toList(),
              onChanged:(v)=>setState(()=>friendId=v))),
          ]),
          const Divider(height:1),
          Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[
            const Text('本机共同观影：AI 只能理解你的文字描述和播放进度，不会自动识别画面。',
              style:TextStyle(color:Colors.grey,fontSize:12)),
            for(final m in recent) Align(
              alignment:m.senderId=='me'?Alignment.centerRight:Alignment.centerLeft,
              child:Card(child:Padding(padding:const EdgeInsets.all(9),
                child:Text('${widget.controller.displayName(m.senderId)}：${m.text}')))),
            if(c!=null && widget.controller.busy.contains(privateThread(c.id)))
              Row(children:[const SizedBox(width:12,height:12,
                child:CircularProgressIndicator(strokeWidth:2)),
                const SizedBox(width:8),Expanded(child:Text(widget.controller.partialReplies[privateThread(c.id)]??'AI正在回复…'))]),
          ])),
          SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(8),
            child:Row(children:[Expanded(child:TextField(controller:input,
              minLines:1,maxLines:3,decoration:const InputDecoration(
                hintText:'边看边和 TA 聊…',border:OutlineInputBorder()))),
              IconButton(icon:const Icon(Icons.send),
                onPressed:c==null || widget.controller.busy.contains(privateThread(c.id))?null:_send)]))),
        ]));
    });
}

import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../v40/catalog.dart';
import '../v40/marketplace_page.dart';
import '../v42/product_illustration.dart';
import 'gift_inventory.dart';

class XyOwnedGiftPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const XyOwnedGiftPage({super.key,required this.controller,required this.roleId});
  @override State<XyOwnedGiftPage> createState()=>_XyOwnedGiftPageState();
}
class _XyOwnedGiftPageState extends State<XyOwnedGiftPage> {
  Map<String,int> bag={};
  bool loading=true;
  bool sending=false;
  bool immediateReply=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    final next=await XyGiftInventory.load();
    if(mounted)setState(() {bag=next;loading=false;});
  }
  Widget _image(XyProduct product) => XyProductArt(product: product, height: 58);
  Future<void> _send(XyProduct product) async {
    if(sending)return;
    setState(()=>sending=true);
    try{
      if(widget.controller.character(widget.roleId)==null)throw StateError('好友不存在');
      if(!await XyGiftInventory.consume(product.id))throw StateError('该商品已送完或未购买');
      if(!widget.controller.sendOwnedVirtualGift(widget.roleId,product.name,sku:product.id)){
        await XyGiftInventory.add({product.id:1});
        throw StateError('无法投递礼物');
      }
      await _load();
      if(immediateReply){
        final role=widget.controller.character(widget.roleId)!;
        final error=await widget.controller.sendPrivate(role,
          '我刚刚把我的已购虚拟礼物「${product.name}」送给了你，你喜欢吗？');
        if(error!=null)throw StateError('礼物已发送，但模型回复失败：$error');
      }
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('礼物已赠送 · 已购库存 -1')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
    finally{if(mounted)setState(()=>sending=false);}
  }
  @override Widget build(BuildContext context){
    final role=widget.controller.character(widget.roleId);
    return Scaffold(appBar:AppBar(title:Text('送礼给${role?.name??'AI 好友'}')),
      body:loading?const Center(child:CircularProgressIndicator()):
      ListView(padding:const EdgeInsets.all(15),children:[
        const Text('我的已购礼物',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        const SizedBox(height:7),
        const Text('只有已经购买的虚拟商品能赠送；每送出一件就会从物品库减少一件。'),
        SwitchListTile(value:immediateReply,onChanged:(v)=>setState(()=>immediateReply=v),
          title:const Text('收到礼物后让 AI 立即回复'),
          subtitle:const Text('默认关闭；开启后会额外调用角色绑定的付费聊天 API。')),
        const Divider(),
        if(bag.isEmpty)const Padding(padding:EdgeInsets.all(20),
          child:Text('购物袋还是空的。先去星愿商城买喜欢的物品吧。')),
        for(final entry in bag.entries)
          if(xyProductById[entry.key]!=null)
            Card(child:ListTile(contentPadding:const EdgeInsets.all(10),
              leading:SizedBox(height:58,width:58,child:_image(xyProductById[entry.key]!)),
              title:Text(xyProductById[entry.key]!.name),
              subtitle:Text('剩余 ${entry.value} 件'),
              trailing:FilledButton.tonal(onPressed:sending?null:()=>_send(xyProductById[entry.key]!),
                child:const Text('赠送')))),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>
          XyMarketplacePage(controller:widget.controller,roleId:widget.roleId))).then((_)=>_load()),
          icon:const Icon(Icons.shopping_bag_outlined),label:const Text('去星愿商城选礼物')),
      ]));
  }
}

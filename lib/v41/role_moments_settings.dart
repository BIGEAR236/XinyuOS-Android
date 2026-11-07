import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_controller.dart';

/// Per-character autonomous posting. Global switch + role grant + this switch
/// must all be on. Every enabled option warns about extra model API calls.
class XyRoleMomentSettings extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const XyRoleMomentSettings({super.key,required this.controller,required this.roleId});
  @override State<XyRoleMomentSettings> createState()=>_XyRoleMomentSettingsState();
}
class _XyRoleMomentSettingsState extends State<XyRoleMomentSettings> {
  final prefs=SharedPreferencesAsync();
  bool enabled=false;
  int hours=24;
  bool loading=true;
  String get key=>'v41.roleMoment.${widget.roleId}';
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    enabled=await prefs.getBool('$key.enabled')??false;
    hours=await prefs.getInt('$key.hours')??24;
    if(mounted)setState(()=>loading=false);
  }
  @override Widget build(BuildContext context){
    final ctl=widget.controller;
    return AnimatedBuilder(animation:ctl,builder:(context,_)=>Column(children:[
      const ListTile(title:Text('这个 AI 的自主朋友圈'),
        subtitle:Text('全部默认关闭；额外生成动态和邀请评论都会消耗第三方模型 API 额度。')),
      SwitchListTile(title:const Text('启用朋友圈自主发布总开关'),
        subtitle:const Text('只在 App 前台检查，不是真正的关机后台任务。'),
        value:ctl.data.autoMomentPosting,
        onChanged:(v)=>ctl.setAutoMomentPosting(v)),
      SwitchListTile(title:const Text('允许当前角色随机发布'),
        subtitle:const Text('结合最近聊天感受写动态；此开关仍需该角色已授权发动态。'),
        value:enabled,
        onChanged:loading?null:(v) async {
          await prefs.setBool('$key.enabled',v);
          if(mounted)setState(()=>enabled=v);
        }),
      if(enabled)ListTile(title:const Text('当前角色最短发帖间隔'),
        subtitle:Text('$hours 小时 · 真实检查时间会带有随机抖动'),
        trailing:DropdownButton<int>(value:hours,
          items:const [6,12,24,48,72].map((v)=>DropdownMenuItem(
            value:v,child:Text('$v 小时'))).toList(),
          onChanged:(v) async {
            if(v==null)return;
            await prefs.setInt('$key.hours',v);
            if(mounted)setState(()=>hours=v);
          })),
      SwitchListTile(title:const Text('允许 AI 自动参加朋友圈评论点赞'),
        subtitle:const Text('默认关闭；前台随机间隔检查，最多每小时 2 位 AI 参与一条。'),
        value:ctl.data.autoMomentInteractions,
        onChanged:(v)=>ctl.setAutoMomentInteractions(v)),
    ]));
  }
}

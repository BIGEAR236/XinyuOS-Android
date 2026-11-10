import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../v39/desktop_icon_settings.dart';
import '../v39/font_import_policy.dart';
import 'desktop_grid.dart';

class XySettingsHome extends StatelessWidget {
  final AppController controller;
  const XySettingsHome({super.key, required this.controller});
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFFFF7FB),
    appBar:AppBar(title:const Text('个性化设置')),
    body:ListView(padding:const EdgeInsets.fromLTRB(16,18,16,20),children:[
      _entry(context,Icons.grid_view_rounded,'桌面图标','自定义图片 · 大小 · 自由摆放',
        XyIconSettings(controller:controller)),
      _entry(context,Icons.palette_outlined,'主题与字体','本地壁纸 · 主题色 · 字体大小与字体导入',
        XyThemeSettings(controller:controller)),
      _entry(context,Icons.verified_user_outlined,'须知与隐私','虚拟金币 · 数据保存 · 服务器与 API 使用',
        const XyPrivacyNotice()),
    ]));
  Widget _entry(BuildContext context,IconData icon,String title,String subtitle,Widget page)=>
    Card(elevation:0,color:Colors.white,margin:const EdgeInsets.only(bottom:12),
      child:ListTile(contentPadding:const EdgeInsets.all(14),
        leading:CircleAvatar(backgroundColor:const Color(0xFFF9EAF2),
          child:Icon(icon,color:const Color(0xFF9C6D91))),title:Text(title,
          style:const TextStyle(fontSize:17,fontWeight:FontWeight.w600)),
        subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right_rounded),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page))));
}
class XyIconSettings extends StatelessWidget {
  final AppController controller;
  const XyIconSettings({super.key,required this.controller});
  static const labels={'chat':'心屿通讯','api':'API 连接','music':'本地音乐',
    'video':'本地视频','settings':'设置','memo':'备忘录','diary':'日记','album':'数字人图库'};
  /// Same defaults the desktop tiles use, so the preview here matches the
  /// real home screen.
  static const _defaults = <String, (IconData, Color)>{
    'chat': (Icons.chat_bubble_rounded, Color(0xFF90BDAE)),
    'api': (Icons.hub_rounded, Color(0xFF9AABDC)),
    'music': (Icons.music_note_rounded, Color(0xFFD49CB3)),
    'video': (Icons.play_circle_rounded, Color(0xFFB1A5D5)),
    'album': (Icons.face_3_rounded, Color(0xFFD6A9BE)),
    'memo': (Icons.note_alt_rounded, Color(0xFFE4BC92)),
    'diary': (Icons.auto_stories_rounded, Color(0xFFC59FC3)),
    'settings': (Icons.settings_rounded, Color(0xFF8E99AB)),
  };
  Future<void> _import(BuildContext context,String id) async {
    try{
      final file=await FilePicker.pickFile(type:FileType.image);
      if(file==null)return;
      final size=await file.length();
      if(size!=null&&size>6*1024*1024)throw const FormatException('图标图片最大 6MB');
      final path=await controller.local.copyIntoApp(file,'icons');
      final saved=controller.local.resolve(path);
      if(await saved.length()>6*1024*1024){await saved.delete();throw const FormatException('图标图片最大 6MB');}
      controller.setDesktopIcon(id,path);
    }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:controller,
    builder:(context,_)=>Scaffold(appBar:AppBar(title:const Text('桌面图标')),
      body:ListView(children:[
        ListTile(leading:const Icon(Icons.aspect_ratio),title:const Text('桌面图标大小'),
          subtitle:const Text('70%～150%，保留你的图片图标'),onTap:()=>showDialog(
            context:context,builder:(_)=>const DesktopIconSizeDialog())),
        ListTile(leading:const Icon(Icons.grid_on_rounded),title:const Text('恢复默认图标位置'),
          subtitle:const Text('桌面可以长按拖到空位或与其他图标交换'),
          onTap:()=>XyDesktopSlots.reset()),
        const Divider(),
        const Padding(padding:EdgeInsets.all(16),child:Text('图标图片 · 点击选择相册中的自定义图片；左侧为当前实际图标')),
        for(final id in XyDesktopSlots.visible)
          Builder(builder:(context){
            final preset=_defaults[id] ?? (Icons.apps_rounded, const Color(0xFF8E99AB));
            final custom=controller.data.desktopIcons[id];
            final file=(custom!=null&&custom.isNotEmpty)?
              controller.local.resolve(custom):null;
            final customized=file!=null&&file.existsSync();
            return ListTile(title:Text(labels[id]??id),
              subtitle:Text(customized?'已自定义 · 点击更换':'默认图标 · 点击设置图片'),
              leading:customized
                ?CircleAvatar(radius:26,backgroundImage:FileImage(file))
                :CircleAvatar(radius:26,backgroundColor:preset.$2.withValues(alpha:.18),
                  child:Icon(preset.$1,color:preset.$2)),
              trailing:IconButton(tooltip:'恢复系统图标',onPressed:()=>controller.clearDesktopIcon(id),
                icon:const Icon(Icons.restore_rounded)),onTap:()=>_import(context,id));
          })
      ])));
}
class XyThemeSettings extends StatelessWidget {
  final AppController controller;
  const XyThemeSettings({super.key,required this.controller});
  Future<void> _wallpaper(BuildContext context) async {
    try{
      final file=await FilePicker.pickFile(type:FileType.image);
      if(file==null)return;
      final size=await file.length();
      if(size!=null&&size>12*1024*1024)throw const FormatException('壁纸最大 12MB');
      final path=await controller.local.copyIntoApp(file,'wallpapers');
      final saved=controller.local.resolve(path);
      if(await saved.length()>12*1024*1024){await saved.delete();throw const FormatException('壁纸最大 12MB');}
      controller.changeAppearance(wallpaper:path);
    }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  Future<void> _font(BuildContext context) async {
    try{
      final file=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:['ttf','otf']);
      if(file==null)return;
      final pre=FontImportPolicy.validate(filename:file.name,bytes:await file.length());
      if(pre!=null)throw FormatException(pre);
      final path=await controller.local.copyIntoApp(file,'fonts');
      final saved=controller.local.resolve(path);
      final check=FontImportPolicy.validate(filename:file.name,bytes:await saved.length());
      if(check!=null){await saved.delete();throw FormatException(check);}
      controller.setFontPath(path);
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('字体已导入，重启 App 后生效。')));
    }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e')));}
  }
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:controller,
    builder:(context,_)=>Scaffold(appBar:AppBar(title:const Text('主题与字体')),
      body:ListView(padding:const EdgeInsets.symmetric(vertical:12),children:[
        ListTile(leading:const Icon(Icons.wallpaper_rounded),title:const Text('上传本地桌面壁纸'),
          onTap:()=>_wallpaper(context)),
        if(controller.data.wallpaperPath.isNotEmpty)
          ListTile(title:const Text('恢复默认壁纸'),onTap:()=>controller.changeAppearance(wallpaper:'')),
        SwitchListTile(title:const Text('深色模式'),value:controller.data.darkMode,
          onChanged:(v)=>controller.changeAppearance(dark:v)),
        const Divider(),
        const ListTile(title:Text('主题颜色')),
        Padding(padding:const EdgeInsets.symmetric(horizontal:15),child:Wrap(spacing:9,
          children:[0xFFB984B9,0xFFCE889D,0xFF819EC8,0xFF8BB6A0,0xFFE6B779].map((value)=>
            ChoiceChip(label:const SizedBox.square(dimension:15),
              avatar:CircleAvatar(backgroundColor:Color(value)),
              selected:controller.data.themeColor==value,
              onSelected:(_)=>controller.changeAppearance(color:value))).toList())),
        const Divider(),
        ListTile(title:const Text('全局字体大小'),
          subtitle:Text('${(controller.data.fontScale*100).round()}%')),
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Slider(
          min:.85,max:1.35,divisions:10,value:controller.data.fontScale.clamp(.85,1.35).toDouble(),
          onChanged:(v)=>controller.changeAppearance(scale:v))),
        ListTile(leading:const Icon(Icons.font_download_outlined),title:const Text('导入 TTF / OTF 字体'),
          subtitle:const Text('最大 50MB · 重新打开 App 生效'),onTap:()=>_font(context)),
        if(controller.data.fontPath.isNotEmpty)
          ListTile(title:const Text('恢复系统字体'),onTap:()=>controller.setFontPath('')),
      ])));
}
class XyPrivacyNotice extends StatelessWidget {
  const XyPrivacyNotice({super.key});
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('须知与隐私')),
    body:ListView(padding:const EdgeInsets.all(18),children:const [
      ListTile(leading:Icon(Icons.lock_outlined),title:Text('本地优先'),
        subtitle:Text('聊天、日记、数字人图片和音色样本原则上保存在本机应用私有空间。卸载可能删除数据。')),
      ListTile(leading:Icon(Icons.cloud_outlined),title:Text('无自建服务器'),
        subtitle:Text('真实模型仍使用你主动配置的第三方 HTTPS API。聊天、文生图、识别与语音合成将向相应服务商传输必要数据。')),
      ListTile(leading:Icon(Icons.payments_outlined),title:Text('付费提示'),
        subtitle:Text('模型调用可能产生费用，虚拟星币、虚拟红包及礼物没有现实货币价值。')),
      ListTile(leading:Icon(Icons.mic_off_outlined),title:Text('数字人默认关闭'),
        subtitle:Text('启用后才会在主动操作时调用外部 STT、TTS 或图片生成 API。不得未经本人同意克隆声音。')),
      ListTile(leading:Icon(Icons.history_edu_outlined),title:Text('日常与剧情分离'),
        subtitle:Text('两种模式分别保留聊天记录，但原版本的旧消息不会被强制迁移或删除。')),
    ]));
}

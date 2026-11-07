import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../v42/animated_portrait.dart';
import 'avatar_core.dart';
import 'digital_call_page.dart';

/// Simple-first digital person: local photo + phone speech services. No extra API setup.
class DigitalPersonPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const DigitalPersonPage({super.key, required this.controller, required this.roleId});
  @override State<DigitalPersonPage> createState() => _DigitalPersonPageState();
}
class _DigitalPersonPageState extends State<DigitalPersonPage> {
  DigitalPersonConfig? config;
  bool importing = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final next = await DigitalPersonStore.load(widget.roleId);
    if (mounted) setState(() => config = next);
  }
  void _msg(Object value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$value')));
  }
  Future<void> _pick() async {
    if (importing || config == null) return;
    setState(() => importing = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final size = await file.length();
      if (size != null && size > 15 * 1024 * 1024) {
        throw const FormatException('图片请控制在 15MB 以内');
      }
      final bytes = await file.readAsBytes();
      final path = await DigitalPersonStore.saveMedia(widget.roleId, 'png', Uint8List.fromList(bytes));
      final c = config!;
      c.portraitPath = path;
      c.portraitGallery = [...c.portraitGallery, path].toSet().toList();
      await DigitalPersonStore.save(c);
      if (mounted) setState(() {});
    } catch (e) { _msg(e); }
    finally { if (mounted) setState(() => importing = false); }
  }
  @override Widget build(BuildContext context) {
    final c = config;
    final role = widget.controller.character(widget.roleId);
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text('${role?.name ?? 'AI 好友'} · 我的数字人')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 12),
        Center(child: XyAnimatedPortrait(path: c.portraitPath, width: 192, height: 240)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: importing ? null : _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(importing ? '正在导入…' : '上传一张角色形象照片')),
        const SizedBox(height: 7),
        const Text('不用文生图、STT 或 TTS API：直接使用手机语音能力。照片会轻微呼吸浮动，不会变成真实口型视频。',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        if (c.portraitGallery.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('已保存的形象'),
          SizedBox(height: 96, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final path in c.portraitGallery)
              if (File(path).existsSync()) Padding(padding: const EdgeInsets.only(right: 8),
                child: InkWell(onTap: () async {
                  c.portraitPath = path;
                  await DigitalPersonStore.save(c);
                  if (mounted) setState(() {});
                }, child: Container(width: 76, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.portraitPath == path
                      ? const Color(0xFFBD79AD) : Colors.transparent, width: 3)),
                  child: Image.file(File(path), fit: BoxFit.cover)))),
          ])),
        ],
        SwitchListTile(title: const Text('启用数字人语音互动'),
          subtitle: const Text('默认关闭。语音识别是否联网由系统语音服务决定；聊天模型仍走原来的 API。'),
          value: c.enabled, onChanged: (value) async {
            c.enabled = value;
            await DigitalPersonStore.save(c);
            if (mounted) setState(() {});
          }),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: c.enabled ? () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            DigitalCallPage(controller: widget.controller, roleId: widget.roleId))) : null,
          icon: const Icon(Icons.mic_none_rounded), label: const Text('进入语音聊天')),
        const SizedBox(height: 18),
        const ListTile(leading: Icon(Icons.shield_outlined),
          title: Text('隐私与说明'), subtitle: Text('本地照片仅保存在应用私有目录。系统语音引擎可能使用网络；真正的离线识别需另装本地模型。未经同意请勿上传或仿制他人肖像、声音。')),
      ]));
  }
}

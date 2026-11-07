import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'avatar_core.dart';
import 'digital_call_page.dart';

/// Character-bound portrait, API configuration, and consented audio sample library.
/// Portrait generation makes one optional BYOK image request; it cannot create
/// a talking-head video by itself.
class DigitalPersonPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const DigitalPersonPage({super.key, required this.controller, required this.roleId});
  @override State<DigitalPersonPage> createState() => _DigitalPersonPageState();
}

class _DigitalPersonPageState extends State<DigitalPersonPage> {
  DigitalPersonConfig? config;
  bool saving = false;
  final imageUrl = TextEditingController();
  final imageModel = TextEditingController();
  final imageKey = TextEditingController();
  final sttUrl = TextEditingController();
  final sttModel = TextEditingController();
  final sttKey = TextEditingController();
  final ttsUrl = TextEditingController();
  final ttsModel = TextEditingController();
  final ttsKey = TextEditingController();
  final voiceId = TextEditingController();
  final prompt = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final c = await DigitalPersonStore.load(widget.roleId);
    if (!mounted) return;
    setState(() {
      config = c;
      imageUrl.text = c.imageEndpoint; imageModel.text = c.imageModel;
      sttUrl.text = c.sttEndpoint; sttModel.text = c.sttModel;
      ttsUrl.text = c.ttsEndpoint; ttsModel.text = c.ttsModel;
      voiceId.text = c.voiceId;
      final role = widget.controller.character(widget.roleId);
      final persona = (role?.persona ?? '').replaceAll(RegExp(r'\s+'), ' ');
      prompt.text = '精致、自然、具有独特气质的原创二次元半身数字人形象，清晰五官，柔和光线，纯净背景，'
        '人物设定：${persona.substring(0, persona.length.clamp(0, 550).toInt())}';
    });
  }
  void _msg(Object error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  Future<void> _save() async {
    final c = config;
    if (c == null) return;
    setState(() => saving = true);
    try {
      c.imageEndpoint = imageUrl.text.trim(); c.imageModel = imageModel.text.trim();
      c.sttEndpoint = sttUrl.text.trim(); c.sttModel = sttModel.text.trim();
      c.ttsEndpoint = ttsUrl.text.trim(); c.ttsModel = ttsModel.text.trim();
      c.voiceId = voiceId.text.trim();
      await DigitalPersonStore.save(c);
      await DigitalPersonStore.setKey(widget.roleId, 'image', imageKey.text);
      await DigitalPersonStore.setKey(widget.roleId, 'stt', sttKey.text);
      await DigitalPersonStore.setKey(widget.roleId, 'tts', ttsKey.text);
      imageKey.clear(); sttKey.clear(); ttsKey.clear();
      _msg('数字人配置已保存在本机，API Key 存在安全存储区。');
    } catch (e) { _msg('保存失败：$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> _importPortrait() async {
    try {
      final selected = await FilePicker.pickFile(type: FileType.image);
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      final path = await DigitalPersonStore.saveMedia(widget.roleId, 'png', Uint8List.fromList(bytes));
      config!.portraitPath = path;
      config!.portraitGallery=[...config!.portraitGallery,path];
      await DigitalPersonStore.save(config!);
      if (mounted) setState(() {});
    } catch (e) { _msg(e); }
  }
  Future<void> _importVoice() async {
    if (config?.voiceConsent != true) { _msg('请先确认你拥有该音色样本的使用授权。'); return; }
    try {
      final selected = await FilePicker.pickFile(type: FileType.audio);
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      final extension = selected.name.split('.').last.toLowerCase();
      if (!const {'wav','mp3','m4a','aac','ogg','flac'}.contains(extension)) {
        throw const FormatException('仅支持常用音频样本格式。');
      }
      final path = await DigitalPersonStore.saveMedia(widget.roleId, extension, Uint8List.fromList(bytes));
      config!.voiceSamplePath = path;
      config!.voiceSamples=[...config!.voiceSamples,path];
      await DigitalPersonStore.save(config!);
      if (mounted) setState(() {});
      _msg('样本只保存在本机。音色克隆仍需由所选服务商提供克隆接口并返回 voice ID。');
    } catch (e) { _msg(e); }
  }
  Future<void> _generate() async {
    if (config == null || saving) return;
    await _save();
    if (!mounted) return;
    final permission = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('生成专属数字人形象'),
      content: const Text('将下方画面描述（可能包含角色人格设定）发送到你填写的文生图服务商，可能产生费用。生成的是静态头像，不包含实时口型驱动。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意并生成'))]));
    if (permission != true || !mounted) return;
    setState(() => saving = true);
    try {
      final bytes = await DigitalPersonApi.generatePortrait(endpoint: config!.imageEndpoint,
        model: config!.imageModel,
        key: await DigitalPersonStore.getKey(widget.roleId, 'image'),
        prompt: prompt.text.trim());
      config!.portraitPath = await DigitalPersonStore.saveMedia(widget.roleId, 'png', bytes);
      config!.portraitGallery=[...config!.portraitGallery,config!.portraitPath];
      await DigitalPersonStore.save(config!);
      if (mounted) setState(() {});
      _msg('新形象已生成并存入数字人图库。');
    } catch (e) { _msg('生成失败：$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Widget _field(TextEditingController ctrl, String title, {bool secret = false, int lines = 1}) =>
      Padding(padding: const EdgeInsets.only(bottom: 9), child: TextField(
        controller: ctrl, obscureText: secret, maxLines: lines, autocorrect: false,
        decoration: InputDecoration(labelText: title, border: const OutlineInputBorder(),
          isDense: true)));
  @override void dispose() {
    for (final c in [imageUrl,imageModel,imageKey,sttUrl,sttModel,sttKey,ttsUrl,ttsModel,ttsKey,voiceId,prompt]) { c.dispose(); }
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    final c = config;
    final role = widget.controller.character(widget.roleId);
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text('${role?.name ?? 'AI 好友'} · 数字人')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Container(height: 220, width: 170, decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(
            colors: [Color(0xFFFBE7F0),Color(0xFFE3E7FA)])),
          clipBehavior: Clip.antiAlias,
          child: c.portraitPath.isNotEmpty && File(c.portraitPath).existsSync()
            ? Image.file(File(c.portraitPath), fit: BoxFit.cover)
            : const Icon(Icons.face_3_outlined, size: 80, color: Color(0xFF9F82AE)))),
        const SizedBox(height: 12),
        if(c.portraitGallery.isNotEmpty) ...[
          const ListTile(title:Text('我的数字人形象仓库'),subtitle:Text('点击某张形象设为当前数字人')),
          SizedBox(height:100,child:ListView(scrollDirection:Axis.horizontal,children:[
            for(final filePath in c.portraitGallery)
              if(File(filePath).existsSync())Padding(padding:const EdgeInsets.only(right:9),
                child:InkWell(onTap:() async {c.portraitPath=filePath;
                  await DigitalPersonStore.save(c);if(mounted)setState(() {});},
                  child:Container(width:75,decoration:BoxDecoration(
                    border:Border.all(color:filePath==c.portraitPath
                      ? const Color(0xFFBB79A2):Colors.transparent,width:3),
                    borderRadius:BorderRadius.circular(12)),
                    clipBehavior:Clip.antiAlias,child:Image.file(File(filePath),fit:BoxFit.cover)))),
          ])),
        ],
        const SizedBox(height: 8),
        SwitchListTile(title: const Text('启用此角色数字人'),
          subtitle: const Text('默认关闭；关闭后不录音、不生成语音，也不请求数字人 API。'),
          value: c.enabled, onChanged: (v) async {c.enabled = v; await DigitalPersonStore.save(c); if (mounted) setState(() {});}),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _importPortrait,
          icon: const Icon(Icons.upload_file), label: const Text('导入形象'))),
          const SizedBox(width: 8), Expanded(child: FilledButton.tonalIcon(onPressed: saving ? null : _generate,
            icon: const Icon(Icons.auto_awesome), label: const Text('AI 生成形象')))]),
        const SizedBox(height: 14),
        Text('文生图 API（OpenAI Images 兼容）', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        _field(imageUrl, '完整图片生成 HTTPS 地址，如 /v1/images/generations'),
        _field(imageModel, '文生图模型 ID'),
        _field(imageKey, '文生图 API Key（留空则保留旧密钥）', secret: true),
        _field(prompt, '生成形象的描述，可编辑', lines: 5),
        const Divider(height: 30),
        Text('语音识别 STT', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        _field(sttUrl, '完整 HTTPS 语音识别地址，如 /v1/audio/transcriptions'),
        _field(sttModel, 'STT 模型 ID'),
        _field(sttKey, 'STT API Key（留空保留）', secret: true),
        const Divider(height: 30),
        Text('语音合成 TTS 与音色仓库', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 7),
        _field(ttsUrl, '完整 HTTPS 语音合成地址，如 /v1/audio/speech'),
        _field(ttsModel, 'TTS 模型 ID'),
        _field(ttsKey, 'TTS API Key（留空保留）', secret: true),
        _field(voiceId, '服务商音色 / 克隆后 Voice ID'),
        CheckboxListTile(value: c.voiceConsent, onChanged: (v) async {
          c.voiceConsent = v == true; await DigitalPersonStore.save(c);
          if (mounted) setState(() {});
        }, title: const Text('我确认拥有该声音的使用权或已获本人明确授权'),
          subtitle: const Text('不支持未经同意克隆他人的声音；导入样本不会自动上传。')),
        OutlinedButton.icon(onPressed: _importVoice, icon: const Icon(Icons.library_music_outlined),
          label: const Text('导入音色样本到本地仓库')),
        if(c.voiceSamples.isNotEmpty) ...[
          const Text('本地音色样本仓库（点击选作当前样本）'),
          for(final voice in c.voiceSamples)RadioListTile<String>(
            value:voice,groupValue:c.voiceSamplePath,
            title:Text(voice.split('/').last,overflow:TextOverflow.ellipsis),
            onChanged:(v) async {if(v==null)return;
              c.voiceSamplePath=v;await DigitalPersonStore.save(c);
              if(mounted)setState(() {});}),
        ],
        const SizedBox(height: 12),
        const Text('样本不等于克隆成功：服务商必须明确支持音色训练/克隆，返回可用于 TTS 的音色 ID。',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: saving ? null : _save,
          icon: const Icon(Icons.save), label: const Text('保存数字人设置')),
        const SizedBox(height: 7),
        FilledButton.tonalIcon(onPressed: !c.enabled ? null : () async {
          await _save(); if (!context.mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => DigitalCallPage(
            controller: widget.controller, roleId: widget.roleId)));
        }, icon: const Icon(Icons.call), label: const Text('进入数字人语音对话')),
        const SizedBox(height: 18),
      ]));
  }
}

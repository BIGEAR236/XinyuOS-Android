import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app_controller.dart';
import '../models.dart';
import 'avatar_core.dart';

/// Sequential voice turn MVP: mic -> chosen STT -> ORIGINAL role chat model ->
/// chosen TTS -> playback. Not a video stream, real-time RTC, or lip-synced 3D.
class DigitalCallPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const DigitalCallPage({super.key, required this.controller, required this.roleId});
  @override State<DigitalCallPage> createState() => _DigitalCallPageState();
}

class _DigitalCallPageState extends State<DigitalCallPage> {
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  final message = TextEditingController();
  DigitalPersonConfig? profile;
  bool recording = false;
  bool busy = false;
  bool speaking = false;
  String lastTranscript = '';
  String lastReply = '';
  String stateText = '语音对话就绪';

  @override void initState() { super.initState(); _load();
    player.playerStateStream.listen((state) {
      if (mounted) setState(() => speaking = state.playing);
    });
  }
  Future<void> _load() async {
    final loaded = await DigitalPersonStore.load(widget.roleId);
    if (mounted) setState(() => profile = loaded);
  }
  void _show(Object text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$text'))); }

  Future<void> _recordToggle() async {
    if (busy || profile?.enabled != true) return;
    if (recording) {
      setState(() { recording = false; busy = true; stateText = '正在识别你的声音…'; });
      try {
        final path = await recorder.stop();
        if (path == null) throw StateError('没有生成录音文件。');
        final p = profile!;
        final text = await DigitalPersonApi.transcribe(endpoint: p.sttEndpoint,
          model: p.sttModel, key: await DigitalPersonStore.getKey(widget.roleId,'stt'),
          audio: File(path));
        if (text.isEmpty) throw StateError('录音未识别出文字。');
        if (mounted) setState(() { lastTranscript = text; stateText = '正在向角色原绑定模型发送消息…'; });
        await _sendToOriginalModel(text);
      } catch (e) { _show(e); }
      finally { if (mounted) setState(() => busy = false); }
    } else {
      try {
        if (!await recorder.hasPermission()) throw StateError('未获得麦克风权限，请前往系统设置开启。');
        final temp = await getTemporaryDirectory();
        await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: '${temp.path}/xinyu_voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
        if (mounted) setState(() { recording = true; stateText = '正在录音，点击结束并发送'; });
      } catch (e) { _show(e); }
    }
  }

  Future<void> _sendToOriginalModel(String text) async {
    final role = widget.controller.character(widget.roleId);
    if (role == null) throw StateError('角色不存在');
    final thread = widget.controller.activePrivateThread(widget.roleId);
    final old = widget.controller.threadMessages(thread).where((m) => m.senderId == role.id).length;
    final error = await widget.controller.sendPrivate(role, text);
    if (error != null) throw StateError(error);
    final newReplies = widget.controller.threadMessages(thread)
      .where((m) => m.senderId == role.id).toList();
    if (newReplies.length <= old) return;
    final answer = newReplies.skip(old).map((m) => m.text).join(' ');
    if (mounted) setState(() {lastReply = answer; stateText = '正在合成角色声音…';});
    final p = profile!;
    if (p.ttsEndpoint.isEmpty || p.voiceId.isEmpty) {
      if (mounted) setState(() => stateText = '已收到文字回复；尚未配置 TTS。');
      return;
    }
    final bytes = await DigitalPersonApi.synthesize(endpoint:p.ttsEndpoint,
      model:p.ttsModel, voice:p.voiceId,
      key: await DigitalPersonStore.getKey(widget.roleId,'tts'), text:answer);
    final root = await getTemporaryDirectory();
    final out = File('${root.path}/xinyu_tts_${DateTime.now().microsecondsSinceEpoch}.mp3');
    await out.writeAsBytes(bytes, flush:true);
    await player.setFilePath(out.path);
    await player.play();
    if (mounted) setState(() => stateText = '语音播报结束');
  }

  @override void dispose() {
    if (recording) { recorder.stop(); }
    recorder.dispose(); player.dispose(); message.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) {
    final c = profile;
    final role = widget.controller.character(widget.roleId);
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text('${role?.name ?? 'AI 角色'} · 数字人语音对话')),
      body: LayoutBuilder(builder: (context, bounds) => Stack(children: [
        Container(decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF6FC),Color(0xFFE8EAF9)]))),
        Positioned(left: bounds.maxWidth * c.dx - 95 * c.scale,
          top: (bounds.maxHeight * c.dy - 115 * c.scale).clamp(10, bounds.maxHeight * .6).toDouble(),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                c.dx = (c.dx + details.delta.dx / bounds.maxWidth).clamp(0,1).toDouble();
                c.dy = (c.dy + details.delta.dy / bounds.maxHeight).clamp(0,1).toDouble();
              });
            }, onPanEnd: (_) => DigitalPersonStore.save(c),
            child: AnimatedScale(scale: speaking ? c.scale * 1.035 : c.scale,
              duration: const Duration(milliseconds: 260),
              child: Container(width: 190, height: 230,
                decoration: BoxDecoration(color:Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x1F715B9A),blurRadius:22)]),
                clipBehavior: Clip.antiAlias,
                child: c.portraitPath.isNotEmpty && File(c.portraitPath).existsSync()
                  ? Image.file(File(c.portraitPath),fit:BoxFit.cover)
                  : const Icon(Icons.face_3_outlined,size:90,color:Color(0xFFB89BBF)))))),
        Positioned(left:16,right:16,bottom:0,child:SafeArea(child: Card(
          color: Colors.white.withValues(alpha:.94), child:Padding(
          padding:const EdgeInsets.all(14),child:Column(mainAxisSize:MainAxisSize.min,children:[
            Text(stateText,style:Theme.of(context).textTheme.titleSmall),
            const SizedBox(height:8),
            if (!c.enabled) const Text('此角色的数字人默认关闭，请先到数字人图库启用。'),
            if (lastTranscript.isNotEmpty) Align(alignment:Alignment.centerLeft,
              child:Text('我：$lastTranscript',maxLines:3)),
            if (lastReply.isNotEmpty) Align(alignment:Alignment.centerLeft,
              child:Text('${role?.name ?? 'AI'}：$lastReply',maxLines:5)),
            Slider(value:c.scale.clamp(.5,1.8).toDouble(),min:.5,max:1.8,
              onChanged:(v) => setState(() => c.scale = v),
              onChangeEnd:(_) => DigitalPersonStore.save(c)),
            Row(children:[Expanded(child:TextField(controller:message,
              decoration:const InputDecoration(hintText:'也可以先输入文字…'))),
              IconButton(icon:const Icon(Icons.send_rounded),
                onPressed:busy || !c.enabled ? null : () async {
                  final input=message.text.trim();if(input.isEmpty)return;
                  setState((){busy=true;stateText='正在生成回复…';lastTranscript=input;});
                  try{await _sendToOriginalModel(input);message.clear();}
                  catch(e){_show(e);}finally{if(mounted)setState(()=>busy=false);}
                })]),
            const SizedBox(height:8),
            FilledButton.icon(onPressed:busy || !c.enabled ? null : _recordToggle,
              icon:Icon(recording?Icons.stop_circle_outlined:Icons.mic_rounded),
              label:Text(recording?'结束录音并发送':'按下开始录音（按轮对话）')),
            const SizedBox(height:4),
            const Text('当前为图片数字人＋轮次语音互动，不是实时视频流或自动口型同步。',
              style:TextStyle(fontSize:11,color:Colors.black54)),
          ]))))),
      ])));
  }
}

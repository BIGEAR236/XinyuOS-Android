import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;
import '../app_controller.dart';
import '../v42/animated_portrait.dart';
import 'avatar_core.dart';

/// Turn-based phone speech recognition -> original role LLM -> phone TTS.
/// Phone speech engines may use a network. This is NOT a continuous video call.
class DigitalCallPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  const DigitalCallPage({super.key, required this.controller, required this.roleId});
  @override State<DigitalCallPage> createState() => _DigitalCallPageState();
}
class _DigitalCallPageState extends State<DigitalCallPage> {
  final speech.SpeechToText recognizer = speech.SpeechToText();
  final FlutterTts speaker = FlutterTts();
  final TextEditingController input = TextEditingController();
  DigitalPersonConfig? profile;
  bool available = false;
  bool listening = false;
  bool sending = false;
  bool talking = false;
  String status = '正在准备语音功能';
  String reply = '';
  @override void initState() {
    super.initState();
    _init();
    speaker.setStartHandler(() { if (mounted) setState(() => talking = true); });
    speaker.setCompletionHandler(() { if (mounted) setState(() => talking = false); });
    speaker.setErrorHandler((_) { if (mounted) setState(() => talking = false); });
  }
  Future<void> _init() async {
    final p = await DigitalPersonStore.load(widget.roleId);
    try {
      available = await recognizer.initialize();
      await speaker.setLanguage('zh-CN');
      await speaker.setSpeechRate(.49);
      status = available ? '点击麦克风，说完后发送' : '系统语音识别不可用；仍可文字交流';
    } catch (e) { status = '系统语音服务不可用：$e'; }
    if (mounted) setState(() => profile = p);
  }
  void _toast(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
  Future<void> _mic() async {
    if (sending || !available || profile?.enabled != true) return;
    try {
      if (listening) {
        await recognizer.stop();
        if (mounted) setState(() { listening = false; status = '识别完成，可检查文字后发送'; });
      } else {
        await speaker.stop();
        await recognizer.listen(onResult: (result) {
          if (!mounted) return;
          setState(() { input.text = result.recognizedWords; });
        }, localeId: 'zh_CN');
        if (mounted) setState(() { listening = true; status = '正在听你说话…'; });
      }
    } catch (e) { _toast(e); if (mounted) setState(() => listening = false); }
  }
  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending || profile?.enabled != true) return;
    final role = widget.controller.character(widget.roleId);
    if (role == null) return;
    if (listening) await recognizer.stop();
    await speaker.stop();
    setState(() { sending = true; listening = false; status = '正在联系原聊天模型…'; });
    try {
      final thread = widget.controller.activePrivateThread(widget.roleId);
      final oldCount = widget.controller.threadMessages(thread)
        .where((m) => m.senderId == role.id).length;
      final error = await widget.controller.sendPrivate(role, text);
      if (error != null) throw StateError(error);
      final messages = widget.controller.threadMessages(thread)
        .where((m) => m.senderId == role.id).skip(oldCount).toList();
      final answer = messages.map((m) => m.text).join('\n').trim();
      if (!mounted) return;
      setState(() { reply = answer; input.clear(); status = '已收到回复'; });
      if (answer.isNotEmpty) {
        await speaker.speak(answer.length > 900 ? answer.substring(0, 900) : answer);
      }
    } catch (e) { _toast(e); if (mounted) setState(() => status = '发送失败，请检查原模型配置'); }
    finally { if (mounted) setState(() => sending = false); }
  }
  @override void dispose() {
    recognizer.cancel();
    speaker.stop();
    input.dispose();
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    final c = profile;
    final name = widget.controller.character(widget.roleId)?.name ?? 'AI';
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text('和$name语音聊天')),
      body: LayoutBuilder(builder: (context, bounds) => Stack(children: [
        Container(decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [Color(0xFFFFF4FA), Color(0xFFEDEAF9)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter))),
        Positioned(left: (bounds.maxWidth * c.dx - 95 * c.scale)
            .clamp(0, bounds.maxWidth - 95).toDouble(),
          top: (bounds.maxHeight * c.dy - 115 * c.scale)
            .clamp(0, bounds.maxHeight * .55).toDouble(),
          child: GestureDetector(onPanUpdate: (details) {
            setState(() {
              c.dx = (c.dx + details.delta.dx / bounds.maxWidth).clamp(0, 1).toDouble();
              c.dy = (c.dy + details.delta.dy / bounds.maxHeight).clamp(0, 1).toDouble();
            });
          }, onPanEnd: (_) => DigitalPersonStore.save(c),
          child: Transform.scale(scale: c.scale,
            child: XyAnimatedPortrait(path: c.portraitPath, talking: talking)))),
        Positioned(left: 12, right: 12, bottom: 0, child: SafeArea(child:
          Card(color: Colors.white.withValues(alpha: .95), child: Padding(
            padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(status, style: Theme.of(context).textTheme.titleSmall),
              if (reply.isNotEmpty) Padding(padding: const EdgeInsets.all(8),
                child: Text('$name：$reply', maxLines: 4, overflow: TextOverflow.ellipsis)),
              Slider(min: .5, max: 1.8, value: c.scale.clamp(.5, 1.8).toDouble(),
                onChanged: (v) => setState(() => c.scale = v),
                onChangeEnd: (_) => DigitalPersonStore.save(c)),
              Row(children: [
                IconButton(onPressed: sending ? null : _mic,
                  icon: Icon(listening ? Icons.stop_circle : Icons.mic_none_rounded),
                  tooltip: listening ? '结束识别' : '开始说话'),
                Expanded(child: TextField(controller: input, maxLines: 2,
                  decoration: const InputDecoration(hintText: '语音识别文字，可编辑…'))),
                IconButton(onPressed: sending ? null : _send,
                  icon: const Icon(Icons.send_rounded)),
              ]),
              TextButton.icon(onPressed: () => speaker.stop(),
                icon: const Icon(Icons.volume_off_outlined), label: const Text('停止朗读')),
              const Text('按轮对话 · 不是实时视频或口型同步。系统语音识别可能联网。',
                style: TextStyle(fontSize: 10)),
            ]))))),
      ])));
  }
}

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
    // Android STT and system TTS are independent services.
    // Missing STT must not prevent text sending or speech playback.
    try {
      available = await recognizer.initialize();
      status = available ? '点击麦克风，说完后发送' :
        '本机没有可用的系统语音识别服务。可以继续输入文字。';
    } catch (_) {
      available = false;
      status = '本机没有可用的系统语音识别服务。可以继续输入文字。';
    }
    try {
      await speaker.setLanguage('zh-CN');
      await speaker.setSpeechRate(.49);
    } catch (_) { /* TTS may have no Chinese voice; manual text remains available. */ }
    if (mounted) setState(() => profile = p);
  }
  void _speechHelp() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('无法使用语音识别'),
      content: const SingleChildScrollView(child: Text(
        '此功能使用手机的 Android 系统语音识别，并不依赖聊天大模型 API。\n\n'
        '你可以先检查：\n'
        '1. 在手机设置中允许「小雨机」使用麦克风；\n'
        '2. 检查是否安装、启用了系统语音识别服务（例如 Google 语音识别与合成，或手机厂商自带服务）；\n'
        '3. 在语言与输入法／语音输入设置中选择可用服务；\n'
        '4. 如果仍报错，检查新 APK 的 AndroidManifest.xml 是否包含 RecognitionService 的 <queries> 声明。\n\n'
        '没有该服务时，仍可发送文字并由原聊天模型回复。')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        FilledButton(onPressed: () { Navigator.pop(ctx); _init(); },
          child: const Text('重新检测')),
      ],
    ));
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
              if (!available) ListTile(
                leading:const Icon(Icons.mic_off_outlined,color:Color(0xFF8A70AD)),
                title:Text(status),
                subtitle:const Text('这是设备语音服务问题，不影响原聊天模型。'),
                trailing:TextButton(onPressed:_speechHelp,child:const Text('解决方法')),
              ) else Text(status, style: Theme.of(context).textTheme.titleSmall),
              if (reply.isNotEmpty) Padding(padding: const EdgeInsets.all(8),
                child: Text('$name：$reply', maxLines: 4, overflow: TextOverflow.ellipsis)),
              Slider(min: .5, max: 1.8, value: c.scale.clamp(.5, 1.8).toDouble(),
                onChanged: (v) => setState(() => c.scale = v),
                onChangeEnd: (_) => DigitalPersonStore.save(c)),
              Row(children: [
                IconButton(onPressed: sending || (!available && !listening) ? null : _mic,
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

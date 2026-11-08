import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;
import '../app_controller.dart';
import '../v42/animated_portrait.dart';
import '../v43/offline_stt.dart';
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
  /// 'system' uses the Android RecognitionService; 'offline' falls back to
  /// the bundled sherpa-onnx engine for ROMs without any system service.
  String engine = 'system';
  final XyOfflineStt offline = XyOfflineStt();
  /// Hands-free conversation loop: listen -> (endpoint) -> send -> TTS ->
  /// listen again. Only with the offline engine (native endpoint detection).
  bool convo = false;
  String convoState = ''; // '' | 'listening' | 'thinking' | 'speaking'
  Timer? _convoDebounce;
  @override void initState() {
    super.initState();
    _init();
    speaker.setStartHandler(() { if (mounted) setState(() => talking = true); });
    speaker.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => talking = false);
      // Hands-free loop: resume listening right after the reply finished.
      if (convo && convoState == 'speaking') _convoListen();
    });
    speaker.setErrorHandler((_) {
      if (!mounted) return;
      setState(() => talking = false);
      if (convo && convoState == 'speaking') _convoListen();
    });
  }
  Future<void> _init() async {
    final p = await DigitalPersonStore.load(widget.roleId);
    // Android STT and system TTS are independent services.
    // Missing STT must not prevent text sending or speech playback.
    var systemOk = false;
    try {
      systemOk = await recognizer.initialize();
    } catch (_) { systemOk = false; }
    if (systemOk) {
      engine = 'system';
      available = true;
      status = '点击麦克风，说完后发送';
    } else {
      // Most domestic ROMs ship no RecognitionService; use the bundled
      // offline engine instead (first load copies ~60MB out of the APK).
      status = '系统识别服务不可用，正在启动本机离线引擎…';
      if (mounted) setState(() {});
      final offlineOk = await offline.init();
      engine = offlineOk ? 'offline' : 'none';
      available = offlineOk;
      status = offlineOk
        ? '点击麦克风，说完后发送（本机离线识别，无需联网）'
        : '本机没有可用的系统语音识别服务，且离线引擎未能启动。可以继续输入文字。';
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
        '语音识别优先使用手机系统服务；不可用时自动切换本机离线引擎（首次使用需从安装包释放模型，稍等几秒）。两者都不用时，可检查：\n'
        '1. 在手机设置中允许「小雨机」使用麦克风；\n'
        '2. 检查是否安装、启用了系统语音识别服务（例如 Google 语音识别，或手机厂商自带服务）；\n'
        '3. 在语言与输入法／语音输入设置中选择可用服务；\n'
        '4. 离线引擎随安装包提供，不联网；若它也未能启动，可能是安装包不含模型或设备内存不足。\n\n'
        '没有语音时，仍可发送文字并由原聊天模型回复。')),
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
    if (engine == 'offline') {
      await _micOffline();
      return;
    }
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
  Future<void> _micOffline() async {
    try {
      if (listening) {
        final text = await offline.stop();
        if (!mounted) return;
        setState(() {
          listening = false;
          if (text.isNotEmpty) input.text = text;
          status = '识别完成，可检查文字后发送';
        });
      } else {
        await speaker.stop();
        await offline.start((partial) {
          if (!mounted) return;
          setState(() => input.text = partial);
        });
        if (mounted) setState(() { listening = true; status = '正在听你说话（离线）…'; });
      }
    } catch (e) { _toast(e); if (mounted) setState(() => listening = false); }
  }
  Future<void> _send([String? override]) async {
    final text = (override ?? input.text).trim();
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
        if (convo) setState(() => convoState = 'speaking');
        await speaker.speak(answer.length > 900 ? answer.substring(0, 900) : answer);
      } else if (convo) {
        _convoListen(); // Empty reply: skip TTS and keep listening.
      }
    } catch (e) {
      _toast(e);
      if (mounted) setState(() => status = '发送失败，请检查原模型配置');
      if (convo && mounted) _convoListen(); // Let the user retry by voice.
    }
    finally { if (mounted) setState(() => sending = false); }
  }

  // ---- Hands-free conversation loop (offline engine only) ----
  Future<void> _toggleConvo() async {
    if (convo) { _stopConvo(); return; }
    if (engine != 'offline') {
      _toast('连续对话需要本机离线引擎（系统服务不支持自动断句）');
      return;
    }
    if (profile?.enabled != true) { _toast('请先开启数字人'); return; }
    setState(() => convo = true);
    await _convoListen();
  }
  void _stopConvo() {
    _convoDebounce?.cancel();
    unawaited(offline.stop());
    if (!mounted) return;
    setState(() { convo = false; convoState = ''; listening = false;
      status = '连续对话已结束'; });
  }
  Future<void> _convoListen() async {
    if (!convo || !mounted) return;
    _convoDebounce?.cancel();
    _convoDebounce = null;
    setState(() { convoState = 'listening'; listening = true;
      status = '连续对话：在听你说…（说完自动发送）'; });
    try {
      await offline.start((partial) {
        if (!mounted || !convo) return;
        // Still speaking: drop the pending auto-submit; the next endpoint
        // after this new speech schedules a fresh one.
        _convoDebounce?.cancel();
        _convoDebounce = null;
        setState(() => input.text = partial);
      }, onEndpoint: () {
        // isEndpoint stays true for every silent audio chunk, so schedule
        // exactly once (??=) and let it fire 650ms after the FIRST endpoint.
        _convoDebounce ??= Timer(const Duration(milliseconds: 650), _convoSubmit);
      });
    } catch (e) {
      _toast(e);
      if (mounted) _stopConvo();
    }
  }
  Future<void> _convoSubmit() async {
    if (!convo || convoState != 'listening') return;
    final text = await offline.stop();
    if (!mounted || !convo) return;
    if (text.trim().isEmpty) { await _convoListen(); return; }
    setState(() { convoState = 'thinking'; listening = false; });
    await _send(text);
  }
  String _convoLabel() => switch (convoState) {
    'listening' => '● 在听你说…说完停顿即自动发送',
    'thinking' => '… 思考中，正在联系原聊天模型',
    'speaking' => '◉ 正在回复，可点打断',
    _ => '',
  };
  @override void dispose() {
    _convoDebounce?.cancel();
    recognizer.cancel();
    speaker.stop();
    offline.dispose();
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
              if (available && engine == 'offline') Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  FilledButton.tonal(
                    onPressed: sending ? null : _toggleConvo,
                    style: FilledButton.styleFrom(
                      backgroundColor: convo ? const Color(0xFFF3D9E8) : null),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(convo ? Icons.stop_circle_outlined : Icons.all_inclusive, size: 18),
                      const SizedBox(width: 4),
                      Text(convo ? '结束' : '连续对话'),
                    ])),
                  if (convo) ...[
                    const SizedBox(width: 8),
                    Expanded(child: Text(_convoLabel(),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF776375)))),
                    if (convoState == 'speaking') TextButton.icon(
                      onPressed: () => speaker.stop(),
                      icon: const Icon(Icons.front_hand_outlined, size: 16),
                      label: const Text('打断')),
                  ],
                ])),
              Row(children: [
                IconButton(onPressed: sending || !available || convo ? null : _mic,
                  icon: Icon(listening ? Icons.stop_circle : Icons.mic_none_rounded),
                  tooltip: listening ? '结束识别' : '开始说话'),
                Expanded(child: TextField(controller: input, maxLines: 2,
                  decoration: const InputDecoration(hintText: '语音识别文字，可编辑…'))),
                IconButton(onPressed: sending ? null : _send,
                  icon: const Icon(Icons.send_rounded)),
              ]),
              TextButton.icon(onPressed: () => speaker.stop(),
                icon: const Icon(Icons.volume_off_outlined), label: const Text('停止朗读')),
              const Text('按轮或连续对话 · 不是实时视频或口型同步。连续对话用本机离线引擎自动断句，思考时调用原模型可能联网。',
                style: TextStyle(fontSize: 10)),
            ]))))),
      ])));
  }
}

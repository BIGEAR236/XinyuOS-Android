import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;
import '../app_controller.dart';
import '../v42/animated_portrait.dart';
import '../v43/offline_stt.dart';
import '../v43/offline_tts.dart';
import '../v43/tts_speech_filter.dart';
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
  /// Neural voice bank: voiceSid >= 0 speaks replies with the bundled
  /// theresa model (sid), -1 keeps the system TTS. Persisted per role in
  /// DigitalPersonConfig.voiceId as '' or 'sid:N'.
  final XyOfflineTts voice = XyOfflineTts();
  int voiceSid = -1;
  bool voiceReady = false;
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
      _onSpeakDone();
    });
    speaker.setErrorHandler((_) {
      if (!mounted) return;
      setState(() => talking = false);
      _onSpeakDone();
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
    _applyVoiceId(p.voiceId);
    if (voiceSid >= 0) {
      // Warm the neural voice bank in the background (first copy ~130MB).
      voice.init().then((ok) {
        if (mounted) setState(() => voiceReady = ok);
      });
    }
    if (mounted) setState(() => profile = p);
  }
  void _applyVoiceId(String value) {
    voiceSid = value.startsWith('sid:') ?
      int.tryParse(value.substring(4)) ?? -1 : -1;
  }
  Future<void> _persistVoiceId() async {
    final p = profile;
    if (p == null) return;
    p.voiceId = voiceSid >= 0 ? 'sid:$voiceSid' : '';
    await DigitalPersonStore.save(p);
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
    final thread = widget.controller.activePrivateThread(widget.roleId);
    // Streaming first-sentence pre-speak (offline voice channel): as soon as
    // the LLM stream yields one complete sentence, synthesize and play it;
    // the rest of the reply continues seamlessly afterwards. This cuts the
    // time-to-first-sound from (full reply + full synthesis) to (first
    // sentence + first-sentence synthesis).
    var preSpoken = '';
    var preSource = '';
    var preSpeakDone = Future<void>.value();
    Timer? streamPoll;
    if (voiceSid >= 0 && voiceReady) {
      streamPoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final partial = widget.controller.partialReplies[thread] ?? '';
        if (partial.length <= preSource.length || preSpoken.isNotEmpty) return;
        preSource = partial;
        final first = _firstSpeakableSentence(spokenText(partial));
        if (first == null) return;
        preSpoken = first;
        if (convo) setState(() => convoState = 'speaking');
        if (mounted) setState(() => talking = true);
        preSpeakDone = voice.speak(first, sid: voiceSid);
      });
    }
    try {
      final oldCount = widget.controller.threadMessages(thread)
        .where((m) => m.senderId == role.id).length;
      final error = await widget.controller.sendPrivate(role, text);
      if (error != null) throw StateError(error);
      final messages = widget.controller.threadMessages(thread)
        .where((m) => m.senderId == role.id).skip(oldCount).toList();
      final answer = messages.map((m) => m.text).join('\n').trim();
      if (!mounted) return;
      setState(() { reply = answer; input.clear(); status = '已收到回复'; });
      // Speak only the spoken words: roleplay actions, markdown and gift
      // tokens would otherwise be read aloud verbatim (esp. story mode).
      final speakable = spokenText(
          answer.length > 1200 ? answer.substring(answer.length - 1200) : answer);
      if (voiceSid >= 0 && voiceReady) {
        // Skip what the pre-speak already covered, then continue playing.
        var remaining = speakable;
        if (preSpoken.isNotEmpty) {
          if (speakable.startsWith(preSpoken)) {
            remaining = speakable.substring(preSpoken.length);
          } else if (speakable.contains(preSpoken)) {
            remaining = speakable.substring(
                speakable.indexOf(preSpoken) + preSpoken.length);
          }
        }
        await preSpeakDone; // Let the first sentence finish uninterrupted.
        if (!mounted) return;
        if (remaining.isNotEmpty) {
          if (convo) setState(() => convoState = 'speaking');
          setState(() => talking = true);
          await voice.speak(remaining, sid: voiceSid);
        }
        if (!mounted) return;
        setState(() => talking = false);
        _onSpeakDone();
      } else if (speakable.isNotEmpty) {
        await _speakOut(speakable);
      } else if (convo) {
        _convoListen(); // Nothing speakable (pure actions): keep listening.
      }
    } catch (e) {
      _toast(e);
      if (mounted) setState(() => status = '发送失败，请检查原模型配置');
      if (convo && mounted) _convoListen(); // Let the user retry by voice.
    }
    finally {
      streamPoll?.cancel();
      if (mounted) setState(() => sending = false);
    }
  }

  /// The first complete, long-enough sentence of [text] for pre-speaking;
  /// null while the stream has not produced one yet. Over-long unpunctuated
  /// prefixes are force-cut so pre-speak is not starved.
  String? _firstSpeakableSentence(String text) {
    const marks = '。！？!?；;';
    for (var i = 0; i < text.length; i++) {
      if (i >= 46) return text.substring(0, 46);
      if (marks.contains(text[i]) && i + 1 >= 6) return text.substring(0, i + 1);
    }
    return null;
  }

  // ---- Unified speech output (system TTS or bundled neural voices) ----
  Future<void> _speakOut(String text) async {
    final capped = text.length > 900 ? text.substring(0, 900) : text;
    if (voiceSid >= 0 && voiceReady) {
      if (convo) setState(() => convoState = 'speaking');
      if (mounted) setState(() => talking = true);
      await voice.speak(capped, sid: voiceSid);
      if (!mounted) return;
      setState(() => talking = false);
      _onSpeakDone();
    } else {
      if (convo) setState(() => convoState = 'speaking');
      await speaker.speak(capped); // completion handler calls _onSpeakDone.
    }
  }
  void _onSpeakDone() {
    // Hands-free loop: resume listening right after the reply finished.
    if (convo && convoState == 'speaking') _convoListen();
  }
  Future<void> _stopSpeaking() async {
    await speaker.stop();
    await voice.stop();
  }

  // ---- Voice bank picker ----
  Future<void> _voiceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, refresh) =>
        SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('为「${widget.controller.character(widget.roleId)?.name ?? 'TA'}」选择音色',
            style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(voiceReady
              ? '内置 ${voice.numSpeakers} 个音色（离线音色库）· 点“试听”后选“使用”'
              : voiceSid >= 0 ? '离线音色引擎加载中（首次约 10 秒）…'
              : '离线音色引擎未加载，选择音色后将自动加载'),
          ),
          RadioListTile<int>(
            title: const Text('系统音色（手机自带）'),
            subtitle: const Text('默认。音色取决于手机 TTS 引擎。'),
            value: -1, groupValue: voiceSid,
            onChanged: (v) { refresh(() {}); setState(() => voiceSid = v ?? -1); _persistVoiceId(); },
          ),
          const Divider(),
          for (final preset in voicePresets)
            ListTile(
              leading: CircleAvatar(radius: 17, backgroundColor: const Color(0xFFEBD9F2),
                child: Text(preset.name.substring(0, 1), style: const TextStyle(fontSize: 13))),
              title: Text('${preset.name} · ${preset.desc}'),
              subtitle: Text('编号 ${preset.sid} · 实际听感以试听为准'),
              trailing: Wrap(spacing: 4, children: [
                TextButton(onPressed: voiceReady ? () async {
                  await speaker.stop();
                  await voice.speak('你好，我是${preset.name}音色，很高兴认识你。', sid: preset.sid);
                } : null, child: const Text('试听')),
                if (voiceSid == preset.sid)
                  const Icon(Icons.check_circle, color: Color(0xFF8A70AD), size: 20)
                else TextButton(onPressed: () {
                  setState(() => voiceSid = preset.sid);
                  _persistVoiceId();
                  if (!voiceReady) {
                    voice.init().then((ok) {
                      if (mounted) setState(() => voiceReady = ok);
                    });
                  }
                  refresh(() {});
                }, child: const Text('使用')),
              ]),
            ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(child: Text('自定义编号（0-${voice.numSpeakers > 0 ? voice.numSpeakers - 1 : 803}）：',
                style: const TextStyle(fontSize: 12))),
              SizedBox(width: 74, child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, hintText: '如 200'),
                onSubmitted: (value) {
                  final sid = int.tryParse(value.trim());
                  if (sid == null || sid < 0) return;
                  setState(() => voiceSid = sid);
                  _persistVoiceId();
                  if (!voiceReady) {
                    voice.init().then((ok) {
                      if (mounted) setState(() => voiceReady = ok);
                    });
                  }
                  refresh(() {});
                })),
            ])),
          const Padding(padding: EdgeInsets.only(bottom: 10),
            child: Text('命名仅供参考，实际听感因模型而异；试听满意再使用。',
              style: TextStyle(fontSize: 11, color: Colors.black54))),
        ])))));
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
    voice.dispose();
    input.dispose();
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    final c = profile;
    final name = widget.controller.character(widget.roleId)?.name ?? 'AI';
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(appBar: AppBar(title: Text('和$name语音聊天'),
      actions: [
        IconButton(tooltip: '音色', onPressed: _voiceSheet,
          icon: const Icon(Icons.record_voice_over_outlined)),
      ]),
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
                      onPressed: () => _stopSpeaking(),
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
              TextButton.icon(onPressed: () => _stopSpeaking(),
                icon: const Icon(Icons.volume_off_outlined), label: const Text('停止朗读')),
              const Text('按轮或连续对话 · 不是实时视频或口型同步。连续对话用本机离线引擎自动断句，思考时调用原模型可能联网。',
                style: TextStyle(fontSize: 10)),
            ]))))),
      ])));
  }
}

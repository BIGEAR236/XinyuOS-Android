import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/companion.dart';

/// A single draggable circular affordance in the corner. Tapping it opens a
/// menu: text chat with the character, or the voice/video call page. The
/// chat room itself does not take any layout height while closed.
class FloatingCompanionChat extends StatefulWidget {
  final CompanionController agent;
  /// Opens the digital voice/video call page; null hides that menu entry.
  final VoidCallback? onVoiceCall;
  const FloatingCompanionChat({super.key, required this.agent, this.onVoiceCall});
  @override
  State<FloatingCompanionChat> createState() => _FloatingCompanionChatState();
}

class _FloatingCompanionChatState extends State<FloatingCompanionChat> {
  final input = TextEditingController();
  bool open = false;
  /// Offset from the default bottom-right anchor; null until first drag.
  Offset? dragOffset;
  static const _fabSize = 44.0;

  @override
  void dispose() { input.dispose(); super.dispose(); }

  void submit() {
    final text = input.text.trim();
    if (text.isEmpty || widget.agent.busy) return;
    input.clear();
    FocusScope.of(context).unfocus();
    widget.agent.event(widget.agent.lastEvent, automatic: false, message: text);
  }

  Future<void> _menu() async {
    final choice = await showModalBottomSheet<String>(context: context,
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.chat_bubble_rounded,
            color: Color(0xFFB37BA8)),
          title: const Text('文字聊天'),
          subtitle: const Text('边玩边和TA打字说话（调用模型）'),
          onTap: () => Navigator.pop(sheet, 'chat')),
        if (widget.onVoiceCall != null)
          ListTile(leading: const Icon(Icons.record_voice_over_rounded,
              color: Color(0xFF8A70AD)),
            title: const Text('音视频对话'),
            subtitle: const Text('语音/连续对话，共用角色原有模型'),
            onTap: () => Navigator.pop(sheet, 'call')),
      ])));
    if (!mounted) return;
    if (choice == 'chat') setState(() => open = true);
    if (choice == 'call') widget.onVoiceCall?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.agent,
    builder: (context, _) => LayoutBuilder(builder: (context, bounds) {
      final a = widget.agent;
      final width = math.min(360.0, bounds.maxWidth - 28);
      final height = math.min(380.0, bounds.maxHeight * .48);
      final base = Offset(bounds.maxWidth - 14 - _fabSize,
          bounds.maxHeight - 18 - _fabSize);
      final fabPos = base + (dragOffset ?? Offset.zero);
      final clamped = Offset(
        fabPos.dx.clamp(4.0, bounds.maxWidth - _fabSize - 4).toDouble(),
        fabPos.dy.clamp(4.0, bounds.maxHeight - _fabSize - 4).toDouble());
      return Stack(children: [
        if (open) Positioned(right: 14, bottom: 76,
          child: Container(width: width, height: height,
            decoration: BoxDecoration(color: const Color(0xF9FFFAFE),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Color(0x35000000), blurRadius: 24)]),
            child: Column(children: [
              ListTile(dense: true,
                leading: const Icon(Icons.favorite, color: Color(0xFFAA79A4)),
                title: Text('与${a.roleName}悄悄说话'),
                subtitle: Text(a.sourceLabel),
                trailing: IconButton(tooltip: '隐藏聊天',
                  icon: const Icon(Icons.close), onPressed: () => setState(() => open = false))),
              const Divider(height: 1),
              Expanded(child: a.lines.isEmpty
                ? const Center(child: Text('点击发送，和角色边玩边聊', style: TextStyle(fontSize: 12)))
                : ListView.builder(padding: const EdgeInsets.all(12),
                    reverse: true, itemCount: a.lines.length,
                    itemBuilder: (context, index) {
                      final item = a.lines[a.lines.length - 1 - index];
                      return Align(alignment: item.isUser
                        ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(margin: const EdgeInsets.symmetric(vertical: 4),
                          constraints: BoxConstraints(maxWidth: width * .82),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: item.isUser ? const Color(0xFFEFE1FB) : Colors.white,
                            borderRadius: BorderRadius.circular(14)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.source, style: const TextStyle(fontSize: 10,
                              color: Color(0xFF8E7793))),
                            const SizedBox(height: 4),
                            SelectableText(item.text, style: const TextStyle(fontSize: 13)),
                          ])),
                      );
                    })),
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 4, 9, 9),
                child: Row(children: [
                  Expanded(child: TextField(controller: input,
                    minLines: 1, maxLines: 2,
                    decoration: InputDecoration(isDense: true,
                      hintText: '边玩边和${a.roleName}说话…',
                      fillColor: Colors.white, filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22))))),
                  IconButton.filled(
                    tooltip: '发送消息（可能调用付费模型）',
                    onPressed: a.busy ? null : submit,
                    icon: a.busy
                      ? const SizedBox(width: 17, height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded)),
                ]))),
            ]))),
        Positioned(left: clamped.dx, top: clamped.dy,
          child: GestureDetector(
            onPanUpdate: (details) => setState(() {
              dragOffset = (dragOffset ?? Offset.zero) + details.delta;
            }),
            onPanEnd: (_) {
              // Keep the offset within bounds after the drag settles.
              final over = Offset(
                (clamped.dx - fabPos.dx), (clamped.dy - fabPos.dy));
              if (over != Offset.zero) {
                dragOffset = (dragOffset ?? Offset.zero) + over;
              }
            },
            onTap: _menu,
            child: SizedBox(width: _fabSize, height: _fabSize, child: FloatingActionButton.small(
              heroTag: 'intimacy_chat_${a.roleId}',
              tooltip: '聊天 / 音视频对话（可拖动）',
              backgroundColor: const Color(0xFFB37BA8),
              foregroundColor: Colors.white,
              onPressed: _menu,
              child: const Icon(Icons.all_inclusive_rounded),
            )),
          )),
      ]);
    }),
  );
}

class CompanionScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final CompanionController agent;
  final List<Widget>? actions;
  /// Passed through to the corner button's voice-call menu entry.
  final VoidCallback? onVoiceCall;
  const CompanionScaffold({super.key, required this.title,
    required this.child, required this.agent, this.actions, this.onVoiceCall});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFBFE),
    appBar: AppBar(title: Text(title),
      backgroundColor: const Color(0xFFFFF7FC), actions: actions),
    body: Stack(children: [
      Positioned.fill(child: child),
      Positioned.fill(
        child: FloatingCompanionChat(agent: agent, onVoiceCall: onVoiceCall)),
    ]),
  );
}

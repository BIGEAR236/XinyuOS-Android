import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/companion.dart';

/// A circular floating chat affordance. The chat room does not take any
/// layout height while closed. Expanded content overlays only a small region.
class FloatingCompanionChat extends StatefulWidget {
  final CompanionController agent;
  const FloatingCompanionChat({super.key, required this.agent});
  @override
  State<FloatingCompanionChat> createState() => _FloatingCompanionChatState();
}

class _FloatingCompanionChatState extends State<FloatingCompanionChat> {
  final input = TextEditingController();
  bool open = false;
  @override
  void dispose() { input.dispose(); super.dispose(); }

  void submit() {
    final text = input.text.trim();
    if (text.isEmpty || widget.agent.busy) return;
    input.clear();
    FocusScope.of(context).unfocus();
    widget.agent.event(widget.agent.lastEvent, automatic: false, message: text);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.agent,
    builder: (context, _) {
      final a = widget.agent;
      final width = math.min(360.0, MediaQuery.sizeOf(context).width - 28);
      final height = math.min(380.0, MediaQuery.sizeOf(context).height * .48);
      return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (open) Container(width: width, height: height,
            margin: const EdgeInsets.only(bottom: 10),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)))),
                  IconButton.filled(
                    tooltip: '发送消息（可能调用付费模型）',
                    onPressed: a.busy ? null : submit,
                    icon: a.busy
                      ? const SizedBox(width: 17, height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded)),
                ]))),
            ])),
          FloatingActionButton.small(
            heroTag: 'intimacy_chat_${a.roleId}',
            tooltip: open ? '收起亲密聊天' : '打开亲密聊天',
            backgroundColor: const Color(0xFFB37BA8),
            foregroundColor: Colors.white,
            onPressed: () => setState(() => open = !open),
            child: Icon(open ? Icons.keyboard_arrow_down : Icons.chat_bubble_rounded),
          ),
        ]);
    },
  );
}

class CompanionScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final CompanionController agent;
  final List<Widget>? actions;
  const CompanionScaffold({super.key, required this.title,
    required this.child, required this.agent, this.actions});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFFBFE),
    appBar: AppBar(title: Text(title),
      backgroundColor: const Color(0xFFFFF7FC), actions: actions),
    body: Stack(children: [
      Positioned.fill(child: child),
      Positioned(right: 14, bottom: 18,
        child: FloatingCompanionChat(agent: agent)),
    ]),
  );
}

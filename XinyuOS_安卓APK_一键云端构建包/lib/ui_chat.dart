import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_contacts.dart';
import 'ui_shell.dart';

class ChatScreen extends StatefulWidget {
  final AppController controller;
  final Character? friend;
  final ChatGroup? group;
  const ChatScreen({super.key, required this.controller, this.friend, this.group});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  String get thread => widget.group != null
      ? groupThread(widget.group!.id) : privateThread(widget.friend!.id);
  @override
  void dispose() { _input.dispose(); super.dispose(); }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (message.isEmpty || widget.controller.busy.contains(thread)) return;
    _input.clear();
    String? err;
    if (widget.group != null) {
      err = await widget.controller.sendGroup(widget.group!, message);
    } else {
      final c = widget.controller.character(widget.friend!.id);
      if (c == null) { err = '此角色已被删除。'; }
      else { err = await widget.controller.sendPrivate(c, message); }
    }
    if (err != null && mounted) {
      // If preflight fails without saving a sent message, keep the draft.
      if (widget.controller.latestText(thread) != message &&
          !widget.controller.threadMessages(thread).any(
            (m) => m.senderId == 'me' && m.text == message)) {
        _input.text = message;
      }
      uiError(context, err);
    }
  }

  Future<void> _groupSettings() async {
    final group = widget.group;
    if (group == null) return;
    var count = group.maxReplies.toDouble();
    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, setDialog) => AlertDialog(
        title: const Text('群聊调度设置'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('每轮最多 ${count.round()} 个 AI 回复'),
          Slider(min: 1, max: 6, divisions: 5, value: count,
            onChanged: (v) => setDialog(() => count = v)),
          const Text('采用顺序回复；AI 可阅读本轮之前的群聊消息。不会无限续聊。',
            style: TextStyle(fontSize: 12)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消')),
          FilledButton(onPressed: () {
            widget.controller.setGroupMaxReplies(group.id, count.round());
            Navigator.pop(dialogContext);
          }, child: const Text('保存'))],
      )));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final friend = widget.friend == null ? null :
        widget.controller.character(widget.friend!.id);
      final group = widget.group;
      final messages = widget.controller.threadMessages(thread);
      final running = widget.controller.busy.contains(thread);
      final title = group?.name ?? friend?.name ?? '聊天';
      final last = messages.isNotEmpty ? messages.last : null;
      return Scaffold(
        appBar: AppBar(title: Column(children: [Text(title),
          Text(group != null ? '${group.memberIds.length} 位 AI · 每轮最多 ${group.maxReplies} 条' :
            (friend?.apiProfileId == null ? '未绑定 API' : 'AI 角色'),
            style: const TextStyle(fontSize: 11))]),
          actions: [
            if (running) IconButton(tooltip: '停止生成', onPressed: () =>
              widget.controller.stop(thread), icon: const Icon(Icons.stop_circle_outlined)),
            if (group != null) IconButton(onPressed: _groupSettings,
              icon: const Icon(Icons.tune_rounded), tooltip: '群聊设置'),
            if (friend != null) IconButton(tooltip: '编辑角色',
              icon: const Icon(Icons.person_outline),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                CharacterDetailScreen(controller: widget.controller,
                  characterId: friend.id)))),
          ]),
        body: Column(children: [
          if (messages.isEmpty) Padding(padding: const EdgeInsets.all(22),
            child: Text(group != null
              ? '群聊已建立。AI 将依次调用各自绑定的模型。'
              : '这是与 $title 的私聊。先为好友绑定 API，再发消息。',
              textAlign: TextAlign.center)),
          Expanded(child: ListView.builder(reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: messages.length + (running ? 1 : 0),
            itemBuilder: (context, index) {
              if (running && index == 0) {
                return const Padding(padding: EdgeInsets.all(12), child: Row(children: [
                  SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 9), Text('正在请求模型…')
                ]));
              }
              final shifted = index - (running ? 1 : 0);
              final m = messages[messages.length - shifted - 1];
              return ChatBubble(entry: m, controller: widget.controller);
            })),
          if (last != null && last.senderId == 'me' && !running)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('如果模型连接失败，消息仍保存在本机，错误会显示在页面底部。',
                style: TextStyle(fontSize: 11, color: Colors.grey))),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            child: Row(children: [
              Expanded(child: TextField(controller: _input,
                minLines: 1, maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: '发送消息…',
                  filled: true, border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none)))),
              const SizedBox(width: 7),
              IconButton.filled(onPressed: running ? null : _send,
                icon: const Icon(Icons.arrow_upward_rounded)),
            ]))),
        ]),
      );
    });
}

class ChatBubble extends StatelessWidget {
  final ChatEntry entry;
  final AppController controller;
  const ChatBubble({super.key, required this.entry, required this.controller});
  @override
  Widget build(BuildContext context) {
    if (entry.senderId == 'system') return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(entry.text, textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall));
    final mine = entry.senderId == 'me';
    final senderCharacter = controller.character(entry.senderId);
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!mine) ...[
          if (senderCharacter != null)
            CharacterAvatar(character: senderCharacter, radius: 17)
          else
            const CircleAvatar(radius: 17, child: Icon(Icons.smart_toy_outlined, size: 18)),
          const SizedBox(width: 8),
        ],
        Flexible(child: Column(crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Text('${controller.displayName(entry.senderId)} · ${clockTime(entry.createdAt)}',
            style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16)),
            child: SelectableText(entry.text)),
        ])),
      ]));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_contacts.dart';
import 'ui_shell.dart';
import 'ui_extras.dart';

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

  Future<void> _regenerate() async {
    final c = widget.friend == null ? null : widget.controller.character(widget.friend!.id);
    if (c == null) return;
    final err = await widget.controller.regeneratePrivate(c);
    if (mounted && err != null) uiError(context, err);
  }

  Future<void> _edit(ChatEntry entry) async {
    final text = TextEditingController(text: entry.text);
    try {
      final result = await showDialog<String>(context: context,
        builder: (ctx) => AlertDialog(title: const Text('编辑消息'),
          content: TextField(controller: text, autofocus: true,
            minLines: 2, maxLines: 9,
            decoration: const InputDecoration(border: OutlineInputBorder())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, text.text.trim()),
              child: const Text('保存'))]));
      if (!mounted || result == null || result.isEmpty || result == entry.text) return;
      if (entry.senderId == 'me') {
        final confirmed = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(title: const Text('修改已发送消息'),
            content: const Text('为保持对话上下文一致，编辑这条用户消息会删除它之后的回复。你可以重新生成。'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认编辑'))]));
        if (confirmed != true) return;
      }
      widget.controller.editMessage(thread, entry.id, result);
    } finally { text.dispose(); }
  }

  Future<void> _messageAction(ChatEntry entry) async {
    if (widget.controller.busy.contains(thread)) return;
    final choice = await showModalBottomSheet<String>(context: context,
      showDragHandle: true, builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.copy_all_outlined),
            title: const Text('复制消息'),
            onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑这条消息'),
            onTap: () => Navigator.pop(ctx, 'edit')),
          if (widget.friend != null && entry.senderId == widget.friend!.id)
            ListTile(leading: const Icon(Icons.refresh),
              title: const Text('重新生成最近一条回复'),
              onTap: () => Navigator.pop(ctx, 'retry')),
        ])));
    if (!mounted) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: entry.text));
      if (mounted) uiError(context, '已复制');
    } else if (choice == 'edit') {
      await _edit(entry);
    } else if (choice == 'retry') {
      await _regenerate();
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
      final partial = widget.controller.partialReplies[thread];
      final pendingSender = widget.controller.partialSenders[thread] ?? friend?.id ?? 'system';
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 18)),
          actions: [
            if (friend != null && !running) IconButton(
              tooltip: '重新生成最近一条回复', onPressed: _regenerate,
              icon: const Icon(Icons.refresh_outlined)),
            if (running) IconButton(tooltip: '停止生成', onPressed: () =>
              widget.controller.stop(thread), icon: const Icon(Icons.stop_circle_outlined)),
            if (group != null) IconButton(onPressed: _groupSettings,
              icon: const Icon(Icons.more_horiz_rounded), tooltip: '群聊设置'),
            if (friend != null) IconButton(tooltip: '角色资料',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                CharacterDetailScreen(controller: widget.controller,
                  characterId: friend.id)))),
          ]),
        body: Column(children: [
          Expanded(child: messages.isEmpty && !running
            ? Center(child: Text('发一条消息，开始对话',
                style: TextStyle(color: scheme.onSurfaceVariant)))
            : ListView.builder(reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: messages.length + (running ? 1 : 0),
              itemBuilder: (context, index) {
                if (running && index == 0) {
                  if (partial != null && partial.isNotEmpty) {
                    return ChatBubble(entry: ChatEntry(id: 'live', threadId: thread,
                      senderId: pendingSender, text: partial,
                      createdAt: DateTime.now()), controller: widget.controller,
                      groupChat: group != null, streaming: true);
                  }
                  return const Padding(padding: EdgeInsets.all(16),
                    child: Row(children: [
                      SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10), Text('对方正在输入…'),
                    ]));
                }
                final shifted = index - (running ? 1 : 0);
                final msg = messages[messages.length - shifted - 1];
                return ChatBubble(entry: msg, controller: widget.controller,
                  groupChat: group != null, onAction: _messageAction);
              })),
          MiniPlayer(controller: widget.controller),
          SafeArea(top: false, child: Container(
            color: scheme.surface,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(children: [
              Expanded(child: TextField(controller: _input,
                minLines: 1, maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: '输入消息',
                  filled: true, fillColor: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none)))),
              const SizedBox(width: 8),
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
  final bool groupChat;
  final bool streaming;
  final void Function(ChatEntry)? onAction;
  const ChatBubble({super.key, required this.entry, required this.controller,
    this.groupChat = false, this.streaming = false, this.onAction});

  @override
  Widget build(BuildContext context) {
    if (entry.senderId == 'system') {
      return Padding(padding: const EdgeInsets.all(8),
        child: Text(entry.text, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall));
    }
    final mine = entry.senderId == 'me';
    final character = controller.character(entry.senderId);
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            character == null
              ? const CircleAvatar(radius: 18, child: Icon(Icons.smart_toy_outlined, size: 18))
              : CharacterAvatar(character: character, local: controller.local, radius: 18),
            const SizedBox(width: 8),
          ],
          Flexible(child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine && groupChat)
                Padding(padding: const EdgeInsets.only(bottom: 3),
                  child: Text(controller.displayName(entry.senderId),
                    style: Theme.of(context).textTheme.labelSmall)),
              GestureDetector(
                onLongPress: onAction == null ? null : () => onAction!(entry),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Color(mine ? controller.data.myBubbleColor :
                      controller.data.aiBubbleColor).withValues(
                      alpha: controller.data.chatBubbleOpacity),
                    borderRadius: BorderRadius.circular(9)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.text,
                      style: TextStyle(color: ThemeData.estimateBrightnessForColor(
                        Color(mine ? controller.data.myBubbleColor :
                          controller.data.aiBubbleColor)) == Brightness.light
                        ? Colors.black87 : Colors.white)),
                    if (streaming) const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: SizedBox(width: 8, height: 8,
                        child: CircularProgressIndicator(strokeWidth: 1.4))),
                  ]))),
              if (!streaming && controller.data.showChatTime)
                Padding(padding: const EdgeInsets.only(top: 3),
                  child: Text(clockTime(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall)),
            ])),
          if (mine) const SizedBox(width: 5),
        ]));
  }
}

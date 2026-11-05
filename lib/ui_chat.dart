import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_contacts.dart';
import 'ui_shell.dart';
import 'ui_extras.dart';
import 'ui_proactive.dart';

/// Chat actions are local operations. There is no remote recall: a model may
/// have already processed a previously sent message.
class ChatScreen extends StatefulWidget {
  final AppController controller;
  final Character? friend;
  final ChatGroup? group;
  const ChatScreen({super.key, required this.controller, this.friend, this.group});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final Set<String> _selected = {};
  ChatEntry? _quote;
  bool _selecting = false;
  String get thread => widget.group != null ? groupThread(widget.group!.id)
      : privateThread(widget.friend!.id);

  @override
  void dispose() { _input.dispose(); super.dispose(); }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (message.isEmpty || widget.controller.busy.contains(thread)) return;
    final quote = _quote;
    _input.clear(); setState(() => _quote = null);
    String? err;
    if (widget.group != null) {
      err = await widget.controller.sendGroup(widget.group!, message, quote: quote);
    } else {
      final c = widget.controller.character(widget.friend!.id);
      err = c == null ? '此角色已被删除。'
          : await widget.controller.sendPrivate(c, message, quote: quote);
    }
    if (!mounted) return;
    if (err != null) {
      if (!widget.controller.threadMessages(thread).any((m) =>
          m.senderId == 'me' && m.text == message)) _input.text = message;
      uiError(context, err);
    }
    if (widget.friend != null && RegExp(r'下周|明天|后天|比赛|考试|面试').hasMatch(message)) {
      final c = widget.controller.character(widget.friend!.id);
      if (c != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('这件事要让 AI 以后主动关心你吗？'),
          action: SnackBarAction(label: '添加事件', onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) =>
              ProactiveEventsScreen(controller: widget.controller,
                initialCharacterId: c.id, initialTopic: message)));
          })));
      }
    }
  }

  Future<void> _regenerate() async {
    final c = widget.friend == null ? null :
        widget.controller.character(widget.friend!.id);
    if (c == null) return;
    final err = await widget.controller.regeneratePrivate(c);
    if (mounted && err != null) uiError(context, err);
  }

  Future<bool> _confirm(String title, String text) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
        child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定'))])) ?? false;
  }

  Future<void> _edit(ChatEntry entry) async {
    if (entry.senderId == 'system' || entry.recalled) return;
    final tc = TextEditingController(text: entry.text);
    try {
      final result = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(title: const Text('编辑本地消息'),
          content: TextField(controller: tc, autofocus: true, minLines: 2,
            maxLines: 8), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, tc.text.trim()),
            child: const Text('保存'))]));
      if (!mounted || result == null || result.isEmpty || result == entry.text) return;
      final laterExists = widget.controller.threadMessages(thread).any((m) =>
        m.createdAt.isAfter(entry.createdAt));
      if (laterExists && entry.senderId == 'me' && !await _confirm('修改较早的消息',
        '修改自己的这条消息后，系统会删除它后面的本地回复，以避免上下文矛盾。确定继续吗？')) return;
      if (laterExists && entry.senderId != 'me' && !await _confirm('编辑 AI 回复',
        '修改 AI 消息只影响本机历史与以后发送给模型的上下文，不会改变已经生成的后续消息。确定继续吗？')) return;
      widget.controller.editMessage(thread, entry.id, result);
    } finally { tc.dispose(); }
  }

  Future<void> _forward(List<String> ids) async {
    final targets = <({String id, String name})>[
      ...widget.controller.data.characters.map((c) =>
        (id: privateThread(c.id), name: c.name)),
      ...widget.controller.data.groups.map((g) =>
        (id: groupThread(g.id), name: '${g.name}（群聊）')),
    ];
    final to = await showDialog<String>(context: context, builder: (ctx) =>
      SimpleDialog(title: const Text('转发到'), children: targets.map((t) =>
        ListTile(title: Text(t.name), onTap: () => Navigator.pop(ctx, t.id))).toList()));
    if (to == null || !mounted) return;
    widget.controller.forwardLocalMessages(thread, to, ids);
    setState(() { _selected.clear(); _selecting = false; });
    uiError(context, '已转发到所选会话（本地记录，不会自动调用模型）');
  }

  Future<void> _delete(List<String> ids) async {
    if (!await _confirm('删除本地消息', '确定删除选中的 ${ids.length} 条本地消息吗？此操作不可撤销。')) return;
    widget.controller.deleteLocalMessages(thread, ids.toSet());
    setState(() { _selected.clear(); _selecting = false; });
  }

  Future<void> _action(ChatEntry entry) async {
    if (widget.controller.busy.contains(thread)) return;
    if (_selecting) {
      setState(() {
        if (_selected.contains(entry.id)) { _selected.remove(entry.id); }
        else { _selected.add(entry.id); }
      });
      return;
    }
    final choice = await showModalBottomSheet<String>(context: context,
      showDragHandle: true, builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
        if (!entry.recalled)
          ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('复制'),
            onTap: () => Navigator.pop(ctx,'copy')),
        if (!entry.recalled)
          ListTile(leading: const Icon(Icons.format_quote), title: const Text('引用回复'),
            onTap: () => Navigator.pop(ctx,'quote')),
        if (!entry.recalled)
          ListTile(leading: const Icon(Icons.forward_outlined), title: const Text('转发'),
            onTap: () => Navigator.pop(ctx,'forward')),
        ListTile(leading: const Icon(Icons.checklist), title: const Text('多选'),
          onTap: () => Navigator.pop(ctx,'multi')),
        if (!entry.recalled)
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('编辑'),
            onTap: () => Navigator.pop(ctx,'edit')),
        if (!entry.recalled && entry.senderId == 'me')
          ListTile(leading: const Icon(Icons.undo), title: const Text('撤回（仅本机）'),
            onTap: () => Navigator.pop(ctx,'recall')),
        if (widget.friend != null && entry.senderId == widget.friend!.id)
          ListTile(leading: const Icon(Icons.refresh),
            title: const Text('重新生成最近回复'),
            onTap: () => Navigator.pop(ctx,'regenerate')),
        ListTile(leading: const Icon(Icons.delete_outline),
          title: const Text('删除本地消息'),
          onTap: () => Navigator.pop(ctx,'delete')),
      ])));
    if (!mounted) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: entry.text));
      if (mounted) uiError(context, '已复制');
    } else if (choice == 'quote') {
      setState(() => _quote = entry);
    } else if (choice == 'forward') {
      await _forward([entry.id]);
    } else if (choice == 'multi') {
      setState(() { _selecting = true; _selected.add(entry.id); });
    } else if (choice == 'edit') {
      await _edit(entry);
    } else if (choice == 'recall') {
      if (await _confirm('撤回消息',
        '只会从本机聊天记录撤回，已发送给模型的内容无法撤销。')) {
        widget.controller.recallMyMessage(thread, entry.id);
      }
    } else if (choice == 'regenerate') {
      await _regenerate();
    } else if (choice == 'delete') {
      await _delete([entry.id]);
    }
  }

  Future<void> _groupSettings() async {
    final group = widget.group;
    if (group == null) return;
    var count = group.maxReplies.toDouble();
    await showDialog<void>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, change) => AlertDialog(
        title: const Text('群聊调度设置'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('每轮最多 ${count.round()} 个 AI 回复'),
          Slider(min: 1, max: 6, divisions: 5, value: count,
            onChanged: (v) => change(() => count = v)),
          const Text('AI 按顺序发言，不会无限互相回复。', style: TextStyle(fontSize: 12)),
        ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('取消')),
          FilledButton(onPressed: () {
            widget.controller.setGroupMaxReplies(group.id, count.round());
            Navigator.pop(ctx);
          }, child: const Text('保存'))])));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller, builder: (context, _) {
    final c = widget.friend == null ? null :
      widget.controller.character(widget.friend!.id);
    final group = widget.group;
    final messages = widget.controller.threadMessages(thread);
    final running = widget.controller.busy.contains(thread);
    final scheme = Theme.of(context).colorScheme;
    final partial = widget.controller.partialReplies[thread];
    final pending = widget.controller.partialSenders[thread] ?? c?.id ?? 'system';
    return Scaffold(backgroundColor: scheme.surfaceContainerLow,
      appBar: AppBar(title: _selecting
          ? Text('已选择 ${_selected.length} 条',
              style: const TextStyle(fontSize: 18))
          : (c != null ? InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => CharacterDetailScreen(
                  controller: widget.controller, characterId: c.id))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CharacterAvatar(character: c,
                  local: widget.controller.local, radius: 15),
                const SizedBox(width: 8),
                Flexible(child: Text(c.name, style: const TextStyle(fontSize: 18),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ])) : Text(group?.name ?? '聊天',
                style: const TextStyle(fontSize: 18))),
        leading: _selecting ? IconButton(icon: const Icon(Icons.close),
          onPressed: () => setState(() { _selecting = false; _selected.clear(); })) : null,
        actions: _selecting ? [
          IconButton(tooltip: '转发', icon: const Icon(Icons.forward),
            onPressed: _selected.isEmpty ? null : () => _forward(_selected.toList())),
          IconButton(tooltip: '删除', icon: const Icon(Icons.delete_outline),
            onPressed: _selected.isEmpty ? null : () => _delete(_selected.toList())),
        ] : [
          if (running) IconButton(tooltip: '停止生成', icon: const Icon(Icons.stop_circle),
            onPressed: () => widget.controller.stop(thread)),
          if (group != null) IconButton(icon: const Icon(Icons.more_horiz),
            tooltip: '群聊设置', onPressed: _groupSettings),
          if (c != null) PopupMenuButton<String>(tooltip: '聊天选项',
            onSelected: (v) async {
              if (v == 'profile') {
                if (context.mounted) Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CharacterDetailScreen(controller: widget.controller,
                    characterId: c.id)));
              } else if (v == 'reset') {
                if (await _confirm('清空当前会话',
                  '将删除这一段本地聊天记录，但角色设定仍会保留。此操作不可恢复。')) {
                  widget.controller.clearThreadHistory(thread);
                }
              }
            }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('角色资料')),
              PopupMenuItem(value: 'reset', child: Text('清空当前会话（重新开始）')),
            ], icon: const Icon(Icons.more_horiz)),
        ]),
      body: Column(children: [
        Expanded(child: Stack(fit: StackFit.expand, children: [
          if (c != null && c.chatBackgroundPath.isNotEmpty &&
              widget.controller.local.resolve(c.chatBackgroundPath).existsSync())
            Opacity(opacity: .38, child: Image.file(
              File(widget.controller.local.resolve(c.chatBackgroundPath).path),
              fit: BoxFit.cover)),
          messages.isEmpty && !running
          ? const Center(child: Text('开始一段自然的对话'))
          : ListView.builder(reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: messages.length + (running ? 1 : 0),
            itemBuilder: (context, index) {
              if (running && index == 0) {
                if (partial != null && partial.isNotEmpty) {
                  return ChatBubble(entry: ChatEntry(id: 'live', threadId: thread,
                    senderId: pending, text: partial, createdAt: DateTime.now()),
                    controller: widget.controller, groupChat: group != null,
                    streaming: true);
                }
                return const Padding(padding: EdgeInsets.all(12), child: Row(children: [
                  SizedBox(width: 15, height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10), Text('正在输入…') ]));
              }
              final offset = index - (running ? 1 : 0);
              final item = messages[messages.length - offset - 1];
              return ChatBubble(entry: item, controller: widget.controller,
                groupChat: group != null, selected: _selected.contains(item.id),
                selectionMode: _selecting,
                onAction: _action, onTap: _selecting ? (e) => setState(() {
                  if (_selected.contains(e.id)) { _selected.remove(e.id); }
                  else { _selected.add(e.id); }
                }) : null);
            }),
        ])),
        MiniPlayer(controller: widget.controller),
        if (!_selecting && _quote != null)
          Container(color: scheme.surfaceContainer, child: ListTile(dense: true,
            leading: const Icon(Icons.format_quote, size: 18),
            title: Text('引用 ${widget.controller.displayName(_quote!.senderId)}',
              style: const TextStyle(fontSize: 12)),
            subtitle: Text(_quote!.text, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.close),
              onPressed: () => setState(() => _quote = null)))),
        if (!_selecting) SafeArea(top: false, child: Container(
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(children: [
            Expanded(child: TextField(controller: _input, minLines: 1, maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(hintText: '输入消息', filled: true,
                fillColor: scheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none)))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: running ? null : _send,
              icon: const Icon(Icons.arrow_upward_rounded)),
          ]))),
      ]));
  });
}

class ChatBubble extends StatelessWidget {
  final ChatEntry entry;
  final AppController controller;
  final bool groupChat;
  final bool streaming;
  final bool selected;
  final bool selectionMode;
  final void Function(ChatEntry)? onAction;
  final void Function(ChatEntry)? onTap;
  const ChatBubble({super.key, required this.entry, required this.controller,
    this.groupChat = false, this.streaming = false, this.selected = false,
    this.selectionMode = false, this.onAction, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entry.senderId == 'system') return Padding(
      padding: const EdgeInsets.all(8), child: Text(entry.text,
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall));
    final mine = entry.senderId == 'me';
    final character = controller.character(entry.senderId);
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = Color(mine ? controller.data.myBubbleColor :
      controller.data.aiBubbleColor);
    final color = ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.light
      ? Colors.black87 : Colors.white;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (selectionMode) ...[
          Checkbox(value: selected, onChanged: (_) => onTap?.call(entry)),
          const SizedBox(width: 4),
        ],
        if (!mine) ...[
          character == null ? const CircleAvatar(radius: 18,
            child: Icon(Icons.smart_toy_outlined, size: 18))
            : CharacterAvatar(character: character, local: controller.local, radius: 18),
          const SizedBox(width: 8),
        ],
        Flexible(child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end :
          CrossAxisAlignment.start, children: [
          if (!mine && groupChat)
            Padding(padding: const EdgeInsets.only(bottom: 3),
              child: Text(controller.displayName(entry.senderId),
                style: Theme.of(context).textTheme.labelSmall)),
          GestureDetector(onLongPress: onAction == null ? null : () => onAction!(entry),
            onTap: onTap == null ? null : () => onTap!(entry),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: selected ? Border.all(color: scheme.primary, width: 2) : null,
                color: bubbleColor.withValues(alpha: controller.data.chatBubbleOpacity),
                borderRadius: BorderRadius.circular(9)),
              child: entry.recalled
                ? Text('你撤回了一条消息（仅本机）', style: TextStyle(
                    color: color.withValues(alpha: .75), fontSize: 13))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (entry.forwardedFrom != null)
                    Padding(padding: const EdgeInsets.only(bottom: 5),
                      child: Text('转发自 ${entry.forwardedFrom}', style: TextStyle(
                        color: color.withValues(alpha: .7), fontSize: 11))),
                  if (entry.quotedText != null)
                    Container(margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: color.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(5)),
                      child: Text('${entry.quotedSender ?? '对方'}：${entry.quotedText}',
                        maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color.withValues(alpha: .8), fontSize: 12))),
                  Text(entry.text, style: TextStyle(color: color)),
                  if (entry.editedAt != null)
                    Text('已编辑', style: TextStyle(fontSize: 10,
                      color: color.withValues(alpha: .65))),
                  if (streaming) const Padding(padding: EdgeInsets.only(top: 4),
                    child: SizedBox(width: 8, height: 8,
                      child: CircularProgressIndicator(strokeWidth: 1.3))),
                ]))),
          if (!streaming && controller.data.showChatTime)
            Text(clockTime(entry.createdAt),
              style: Theme.of(context).textTheme.labelSmall),
        ])),
        if (mine) const SizedBox(width: 5),
      ]));
  }
}

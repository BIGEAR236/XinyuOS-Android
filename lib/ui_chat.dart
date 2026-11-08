import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_contacts.dart';
import 'ui_shell.dart';
import 'ui_extras.dart';
import 'ui_proactive.dart';
import 'intimacy/core/story_parser.dart';
import 'intimacy/pages/story_page.dart';
import 'v39/chat_extras.dart';
import 'intimacy/app_role_responder.dart';
import 'intimacy/pages/hub_page.dart';
import 'v41/chat_more_panel.dart';
import 'v41/digital_call_page.dart';
import 'v41/digital_person_page.dart';
import 'v41/chat_pet_companion.dart';
import 'v41/avatar_core.dart';
import 'v41/owned_gift_page.dart';
import 'v42/product_illustration.dart';
import 'v43/red_packet_presenter.dart';
import 'v40/catalog.dart';
import 'v40/marketplace_page.dart';

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
  final _focus = FocusNode();
  final Set<String> _selected = {};
  ChatEntry? _quote;
  bool _selecting = false;
  int _petVersion = 0;
  String get thread => widget.group != null ? groupThread(widget.group!.id)
      : widget.controller.activePrivateThread(widget.friend!.id);

  @override
  void dispose() { _input.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _send() async {
    final message = _input.text.trim();
    if (message.isEmpty || widget.controller.busy.contains(thread)) return;
    if (widget.controller.formatFor(thread) != 'auto') {
      widget.controller.setThreadFormat(thread, 'auto');
    }
    final quote = _quote;
    _input.clear(); _focus.unfocus(); setState(() => _quote = null);
    if (widget.controller.runLocalCommand(thread,message)) return;
    final beforeReplies = widget.friend == null ? 0 :
      widget.controller.threadMessages(thread)
        .where((m) => m.senderId == widget.friend!.id).length;
    String? err;
    if (widget.group != null) {
      err = await widget.controller.sendGroup(widget.group!, message, quote: quote);
    } else {
      final c = widget.controller.character(widget.friend!.id);
      err = c == null ? '此角色已被删除。'
          : await widget.controller.sendPrivate(c, message, quote: quote);
    }
    if (!mounted) return;
    if (err == null && widget.friend != null &&
        widget.controller.threadMessages(thread)
          .where((m) => m.senderId == widget.friend!.id).length > beforeReplies) {
      widget.controller.awardVirtualActivity('chat', roleId: widget.friend!.id);
    }
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
    if (widget.controller.formatFor(thread) != 'auto') {
      widget.controller.setThreadFormat(thread, 'auto');
    }
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
      final action = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(title: const Text('编辑消息'),
          content: TextField(controller: tc, autofocus: true, minLines: 2,
            maxLines: 8), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx,'save'), child: const Text('只保存')),
          if (entry.senderId == 'me' && widget.friend != null)
            FilledButton(onPressed: () => Navigator.pop(ctx,'resend'),
              child: const Text('编辑并重发')),
        ]));
      if (!mounted || action == null || tc.text.trim().isEmpty ||
          tc.text.trim() == entry.text.trim()) return;
      final laterUserExists = widget.controller.threadMessages(thread).any((m) =>
          m.senderId == 'me' && m.createdAt.isAfter(entry.createdAt));
      if (laterUserExists && entry.senderId == 'me' && !await _confirm('修改较早的消息',
        '修改此条消息会移除之后的本地消息与回复，以保持上下文一致。继续吗？')) return;
      if (widget.controller.busy.contains(thread)) widget.controller.stop(thread);
      if (action == 'resend' && entry.senderId == 'me' && widget.friend != null) {
        final c = widget.controller.character(widget.friend!.id);
        if (c == null) return;
        if (widget.controller.formatFor(thread) != 'auto') {
          widget.controller.setThreadFormat(thread, 'auto');
        }
        final error = await widget.controller.editAndResendPrivate(c,entry.id,tc.text);
        if (mounted && error != null) uiError(context,error);
      } else {
        widget.controller.editMessage(thread, entry.id, tc.text);
      }
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

  Future<void> _openPlusMenu() async {
    if (widget.controller.busy.contains(thread)) return;
    final friend = widget.friend == null ? null :
      widget.controller.character(widget.friend!.id);
    _focus.unfocus();
    final choice = await XyChatMorePanel.open(context,friend!=null);
    if (choice == null || !mounted) return;
    if (choice == 'image') { await _pickImage(); return; }
    if (friend == null) {uiError(context,'请进入 AI 好友私聊体验该功能');return;}
    if (choice == 'call') {
      final avatar = await DigitalPersonStore.load(friend.id);
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>
        avatar.enabled ? DigitalCallPage(controller:widget.controller,roleId:friend.id)
          : DigitalPersonPage(controller:widget.controller,roleId:friend.id)));
      if(!mounted)return;
      return;
    }
    if (choice == 'red') {await _sendVirtualRedPacket(friend);return;}
    if (choice == 'gift') {await _sendVirtualGift(friend);return;}
    if (!const {'pet','music','watch','game'}.contains(choice)) return;
    widget.controller.addLocalActivityInvite(friend.id,choice);
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>CompanionHub(
      roleId:friend.id,roleName:friend.name,persona:friend.persona,
      appController:widget.controller,
      initialActivity:choice,
      responder:widget.controller.profile(friend.apiProfileId)==null
        ? null:AppRoleResponder(widget.controller),
      onLocalEvent:widget.controller.recordIntimacyEvent,
    )));
    if(mounted)setState(()=>_petVersion++);
  }

  Future<void> _sendVirtualRedPacket(Character friend) async {
    final draft = await Navigator.push<XyRedEnvelopeDraft>(context,
      MaterialPageRoute(builder:(_)=>XyRedEnvelopeComposer(
        recipient:friend.name,balance:widget.controller.data.worldBalance,
        controller:widget.controller)));
    if(draft==null||!mounted)return;
    if(!widget.controller.giveRedEnvelope(friend.id,draft.amount,
        note:draft.message,coverPath:draft.coverPath)) {
      uiError(context,'红包发送失败：金额无效或虚拟余额不足。');
    } else if (draft.replyWithModel) {
      final error = await widget.controller.respondToVirtualPresent(friend.id,
        description:'一份红包（祝福：${draft.message}）');
      if (mounted && error != null) uiError(context,error);
    }
  }

  Future<void> _sendVirtualGift(Character friend) async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>
      XyOwnedGiftPage(controller:widget.controller,roleId:friend.id)));
  }

    /// Per-role avatar of the PLAYER inside this private chat: a different
    /// "me" for different characters, falling back to the global avatar.
    Future<void> _pickMyAvatarHere(Character c) async {
      final current = widget.controller.data.meAvatarByRole[c.id];
      final action = await showModalBottomSheet<String>(context: context,
        builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('我在「${c.name}」聊天中的形象'),
            subtitle: Text(current == null
              ? '当前使用全局总头像，仅在这个聊天可换专属形象'
              : '已设置专属形象，只在这个聊天显示'),),
          ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择专属形象'),
            onTap: () => Navigator.pop(sheet, 'pick')),
          if (current != null)
            ListTile(leading: const Icon(Icons.restore_rounded),
              title: const Text('恢复使用总头像'),
              onTap: () => Navigator.pop(sheet, 'clear')),
        ])));
      if (action == 'pick') {
        try {
          final file = await FilePicker.pickFile(type: FileType.image);
          if (file == null) return;
          final bytes = await file.length();
          if (bytes != null && bytes > 8 * 1024 * 1024) {
            if (mounted) uiError(context, '头像不能超过 8MB');
            return;
          }
          final path = await widget.controller.local.copyIntoApp(file, 'me_avatar');
          widget.controller.setMeAvatarForRole(c.id, path);
        } catch (e) {
          if (mounted) uiError(context, '$e');
        }
      } else if (action == 'clear') {
        widget.controller.clearMeAvatarForRole(c.id);
      }
    }
  
  Future<void> _pickImage() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.length();
      if (bytes != null && bytes > 5 * 1024 * 1024) {
        if (mounted) uiError(context, '发送给模型的图片不能超过 5MB'); return;
      }
      final path = await widget.controller.local.copyIntoApp(file, 'chat_images');
      if (widget.friend == null) {
        widget.controller.sendLocalImage(thread, path);
        if (mounted) uiError(context, '群聊图片目前仅保存在本地，不调用多模态模型');
      } else {
        _focus.unfocus();
        final c = widget.controller.character(widget.friend!.id);
        if (c == null) return;
        if (widget.controller.formatFor(thread) != 'auto') {
          widget.controller.setThreadFormat(thread, 'auto');
        }
        final err = await widget.controller.sendPrivateImage(c, path);
        if (mounted && err != null) uiError(context, err);
      }
    } catch (e) { if (mounted) uiError(context, e); }
  }

  void _chooseModel() async {
    final c = widget.friend == null ? null :
      widget.controller.character(widget.friend!.id);
    if (c == null) return;
    final next = await showModalBottomSheet<String>(context: context,
      showDragHandle: true, builder: (ctx) => SafeArea(child: ListView(
        shrinkWrap: true, children: [
          const ListTile(title: Text('切换当前好友模型'), subtitle: Text('切换后下条消息生效')),
          ...widget.controller.data.profiles.map((p) => RadioListTile<String>(
            title: Text(p.label), subtitle: Text(p.modelId),
            value: p.id, groupValue: c.apiProfileId,
            onChanged: (v) => Navigator.pop(ctx, v))),
        ])));
    if (next != null) widget.controller.bindCharacterModel(c.id, next);
  }

  Future<void> _showVersions(ChatEntry entry) async {
    if (entry.previousVersions.isEmpty) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .55,
        child: ListView(children: [
          const ListTile(title: Text('历史版本（本地保留）')),
          for (var i = 0; i < entry.previousVersions.length; i++)
            ListTile(title: Text('版本 ${i + 1}'), subtitle: SelectableText(
              entry.previousVersions[i]), isThreeLine: true),
        ]))));
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
          if (c != null) IconButton(
            tooltip:'切换日常／剧情（独立聊天记忆）',
            icon:Icon(widget.controller.roleChatMode(c.id)=='story'
              ? Icons.auto_stories_outlined:Icons.chat_bubble_outline),
            onPressed:() async {
              final old=widget.controller.roleChatMode(c.id);
              final next=await showModalBottomSheet<String>(context:context,
                showDragHandle:true,builder:(sheet)=>SafeArea(child:Column(
                  mainAxisSize:MainAxisSize.min,children:[
                    const ListTile(title:Text('选择聊天模式'),
                      subtitle:Text('日常和沉浸剧情分别保留自己的对话历史，不会清空旧聊天。')),
                    ListTile(leading:const Icon(Icons.chat_bubble_outline),
                      title:const Text('日常聊天'),selected:old=='daily',
                      onTap:()=>Navigator.pop(sheet,'daily')),
                    ListTile(leading:const Icon(Icons.auto_stories_outlined),
                      title:const Text('沉浸剧情'),selected:old=='story',
                      onTap:()=>Navigator.pop(sheet,'story')),
                  ])));
              if(next!=null){widget.controller.setRoleChatMode(c.id,next);if(mounted)setState((){});}
            }),
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

              } else if (v == 'meavatar') {
                await _pickMyAvatarHere(c);
              } else if (v == 'reset') {
                if (await _confirm('清空当前会话',
                  '将删除这一段本地聊天记录，但角色设定仍会保留。此操作不可恢复。')) {
                  widget.controller.clearThreadHistory(thread);
                }
              }
            }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('角色资料')),
              PopupMenuItem(value: 'meavatar', child: Text('我在此聊天的形象')),
              PopupMenuItem(value: 'reset', child: Text('清空当前会话（重新开始）')),
            ], icon: const Icon(Icons.more_horiz)),
        ]),
      body: Column(children: [
        Expanded(child: Stack(fit: StackFit.expand, children: [
          if (c != null && c.chatBackgroundPath.isNotEmpty &&
              widget.controller.local.resolve(c.chatBackgroundPath).existsSync())
            Opacity(opacity: c.chatBackgroundOpacity, child: Image.file(
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
                    peerId: c?.id,
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
                groupChat: group != null, peerId: c?.id,
                selected: _selected.contains(item.id),
                selectionMode: _selecting,
                onAction: _action, onEdit: _edit,
                onRegenerate: widget.friend != null &&
                  messages.lastWhere((m) => m.senderId == widget.friend!.id,
                    orElse: () => item).id == item.id ? _regenerate : null,
                onVersions: _showVersions,
                onTap: _selecting ? (e) => setState(() {
                  if (_selected.contains(e.id)) { _selected.remove(e.id); }
                  else { _selected.add(e.id); }
                }) : null);
            }),
          if(c!=null) XyChatPetCompanion(
            key:ValueKey('${c.id}_$_petVersion'),roleId:c.id),
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
            IconButton(tooltip: '更多 · 红包／礼物／互动／购物',
              icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
              onPressed: _openPlusMenu),
            if (widget.friend != null) IconButton(tooltip: '切换模型',
              onPressed: _chooseModel, icon: const Icon(Icons.tune, size: 21)),
            Expanded(child: TextField(controller: _input, focusNode: _focus, minLines: 1, maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(hintText: '输入消息', filled: true,
                fillColor: scheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none)))),
            const SizedBox(width: 8),
            IconButton.filled(tooltip: running ? '停止生成' : '发送',
              onPressed: running ? () => widget.controller.stop(thread) : _send,
              icon: Icon(running ? Icons.stop_rounded : Icons.arrow_upward_rounded)),
          ]))),
      ]));
  });
}

class ChatBubble extends StatelessWidget {
  final ChatEntry entry;
  final AppController controller;
  final bool groupChat;
  /// The character whose private chat this bubble belongs to; enables the
  /// per-role avatar of the PLAYER (data.meAvatarByRole) with the global
  /// myAvatarPath as fallback.
  final String? peerId;
  final bool streaming;
  final bool selected;
  final bool selectionMode;
  final void Function(ChatEntry)? onAction;
  final void Function(ChatEntry)? onTap;
  final Future<void> Function(ChatEntry)? onEdit;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(ChatEntry)? onVersions;
  const ChatBubble({super.key, required this.entry, required this.controller,
    this.groupChat = false, this.peerId, this.streaming = false, this.selected = false,
    this.selectionMode = false, this.onAction, this.onTap,
    this.onEdit, this.onRegenerate, this.onVersions});

  @override
  Widget build(BuildContext context) {
    if (entry.senderId == 'system') return Padding(
      padding: const EdgeInsets.all(8), child: Text(entry.text,
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall));
    final mine = entry.senderId == 'me';
    final sentEnvelope = mine && entry.text.startsWith('🧧 虚拟红包 ');
    final giftCard = mine && entry.text.startsWith('🎁虚拟礼物卡:');
    final giftCode = giftCard ? entry.text.substring('🎁虚拟礼物卡:'.length).split('|').first : '';
    final giftedProduct = xyProductById[giftCode];
    final gift = !mine && entry.senderId != 'system' && !entry.recalled && !streaming
      ? VirtualGiftOffer.parse(entry.text) : null;
    final character = controller.character(entry.senderId);
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = Color(mine ? controller.data.myBubbleColor :
      controller.data.aiBubbleColor);
    final color = ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.light
      ? Colors.black87 : Colors.white;
    final avatar = mine
      ? (() {
          final perRole = peerId == null
            ? null : controller.data.meAvatarByRole[peerId];
          final path = perRole != null && perRole.isNotEmpty
            ? perRole : controller.data.myAvatarPath;
          return path.isNotEmpty && controller.local.resolve(path).existsSync()
            ? CircleAvatar(radius: 13, backgroundImage: FileImage(
                controller.local.resolve(path)))
            : const CircleAvatar(radius: 13, child: Icon(Icons.person, size: 15));
        })()
      : character == null ? const CircleAvatar(radius: 13,
          child: Icon(Icons.smart_toy_outlined, size: 15))
          : CharacterAvatar(character: character, local: controller.local, radius: 13);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (selectionMode) Checkbox(value: selected,
            onChanged: (_) => onTap?.call(entry)),
          Flexible(child: Column(crossAxisAlignment: mine
            ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              avatar,
              const SizedBox(width: 6),
              Text(mine ? '我' : controller.displayName(entry.senderId),
                style: Theme.of(context).textTheme.labelSmall),
            ]),
            const SizedBox(height: 5),
            GestureDetector(onLongPress: onAction == null ? null : () => onAction!(entry),
              onTap: onTap == null ? null : () => onTap!(entry),
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: selected ? Border.all(color: scheme.primary, width: 2) : null,
                  color: bubbleColor.withValues(alpha: controller.data.chatBubbleOpacity),
                  borderRadius: BorderRadius.circular(15)),
                child: entry.recalled
                  ? Text('已撤回（仅本机）', style: TextStyle(color: color, fontSize: 12))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (entry.quotedText != null)
                      Text('${entry.quotedSender ?? '对方'}：${entry.quotedText}',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: color.withValues(alpha: .7))),
                    if (!sentEnvelope && entry.imagePath.isNotEmpty &&
                        controller.local.resolve(entry.imagePath).existsSync())
                      ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: Image.file(controller.local.resolve(entry.imagePath),
                          width: 210, fit: BoxFit.cover)),
                    if (giftCard && giftedProduct != null) Container(
                      width:218,padding:const EdgeInsets.all(9),
                      decoration:BoxDecoration(color:const Color(0xFFFFEDF4),
                        borderRadius:BorderRadius.circular(14)),
                      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        XyProductArt(product:giftedProduct,height:105),
                        const SizedBox(height:7),
                        Text(giftedProduct.name,style:const TextStyle(
                          fontSize:15,fontWeight:FontWeight.w700)),
                        const Text('礼物已送达 ♡',style:TextStyle(fontSize:11)),
                      ]))
                    else if (sentEnvelope) Container(
                      width:220,padding:const EdgeInsets.all(14),
                      decoration:BoxDecoration(gradient:const LinearGradient(
                        colors:[Color(0xFFE58059),Color(0xFFC95E4A)]),
                        borderRadius:BorderRadius.circular(13)),
                      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        const Row(children:[Icon(Icons.redeem,color:Colors.white,size:30),
                          SizedBox(width:8),Text('虚拟红包',style:TextStyle(
                            color:Colors.white,fontSize:17,fontWeight:FontWeight.bold))]),
                        if (entry.imagePath.isNotEmpty &&
                            controller.local.resolve(entry.imagePath).existsSync()) ...[
                          const SizedBox(height:8),
                          ClipRRect(borderRadius:BorderRadius.circular(9),
                            child:Image.file(controller.local.resolve(entry.imagePath),
                              width:190,height:90,fit:BoxFit.cover)),
                        ],
                        const SizedBox(height:9),
                        Text(XyRedPacketPresenter.blessing(entry.text),
                          style:const TextStyle(color:Colors.white)),
                        const SizedBox(height:5),
                        const Text('对方已收下',
                          style:TextStyle(color:Colors.white70,fontSize:11)),
                      ]))
                    else if (!giftCard && entry.text != '[图片]')
                      ChatFormattedText(text: gift == null ?
                        entry.text.replaceAll('（来自我的已购商品）','') :
                        entry.text.replaceFirst(RegExp(
                          r'(?:^|\n)\s*\[虚拟(?:红包|礼物)[:：][^\]\n]+\]\s*$'),''), color: color,
                        roleName: controller.displayName(entry.senderId),
                        immersive: !mine && character!=null && controller.roleChatMode(character.id)=='story'),
                    if (gift != null) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(
                        borderRadius:BorderRadius.circular(12),
                        onTap: controller.hasClaimedAiGift(entry.id) ? null : () {
                          final result = controller.claimAiGift(entry);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(result ?? (gift.isRedPacket
                              ? '已领取${gift.coins}虚拟星币' : '已收下${gift.name}'))));
                        },
                        child:Container(width:228,padding:const EdgeInsets.all(13),
                          decoration:BoxDecoration(gradient:LinearGradient(colors: gift.isRedPacket
                            ? const [Color(0xFFE9956A),Color(0xFFC65B52)]
                            : const [Color(0xFFE9C2D6),Color(0xFFBD95C2)]),
                            borderRadius:BorderRadius.circular(12)),
                          child:Row(children:[Icon(gift.isRedPacket
                            ? Icons.redeem_rounded:Icons.card_giftcard_rounded,
                              color:Colors.white,size:29),
                            const SizedBox(width:10),
                            Expanded(child:Text(controller.hasClaimedAiGift(entry.id)
                              ? '已领取' : gift.isRedPacket
                                ? '领取红包 · ${gift.coins}⭐' : '收下${gift.name}',
                              style:const TextStyle(color:Colors.white,
                                fontWeight:FontWeight.bold))),
                          ]))),
                      ),
                    if (entry.editedAt != null)
                      Text('已编辑', style: TextStyle(fontSize: 10,
                        color: color.withValues(alpha: .65))),
                    if (streaming) const Padding(padding: EdgeInsets.only(top: 5),
                      child: SizedBox(width: 9, height: 9,
                        child: CircularProgressIndicator(strokeWidth: 1.5))),
                  ]))),
            if (!streaming && !selectionMode && !entry.recalled)
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (entry.senderId != 'me' && onRegenerate != null)
                  IconButton(tooltip: '重新生成', icon: const Icon(Icons.refresh, size: 17),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                    onPressed: onRegenerate),
                if (onEdit != null)
                  IconButton(tooltip: '直接编辑', icon: const Icon(Icons.edit_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                    onPressed: () => onEdit!(entry)),
                if (entry.previousVersions.isNotEmpty && onVersions != null)
                  IconButton(tooltip: '查看之前的版本',
                    icon: const Icon(Icons.history, size: 17),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onVersions!(entry)),
                if (onAction != null)
                  IconButton(tooltip: '更多操作', icon: const Icon(Icons.more_horiz, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onAction!(entry)),
                if (entry.inputTokens != null || entry.outputTokens != null)
                  Text('↑${entry.inputTokens ?? '—'} ↓${entry.outputTokens ?? '—'} tokens',
                    style: Theme.of(context).textTheme.labelSmall),
                if (controller.data.showChatTime)
                  Text(clockTime(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
          ])),
        ]));
  }
}

/// Full GitHub-flavored Markdown, including tables and fenced code blocks.
/// The renderer does not execute source code or arbitrary HTML.
class ChatFormattedText extends StatelessWidget {
  final String text;
  final Color color;
  final String roleName;
  final bool immersive;
  const ChatFormattedText({super.key, required this.text, required this.color,
    this.roleName = '角色', this.immersive = false});

  // Only recognized story replies use the special renderer. Ordinary text,
  // Markdown tables and code examples must continue to display normally.
  bool get _hasStoryEnvelope {
    final raw = text.trimLeft();
    return RegExp(r'^\*\*\d{2}:\d{2}\*\*\s*\|', multiLine: true).hasMatch(raw) ||
        (raw.startsWith('{') && raw.contains('"beats"') &&
         raw.contains('"time"') && raw.contains('"status"'));
  }

  @override
  Widget build(BuildContext context) {
    if (_hasStoryEnvelope) { // Auto-detect valid story envelopes in ordinary chats too.
      final scene = StoryParser.parse(text, fallbackName: roleName);
      if (scene.beats.isNotEmpty) return StorySceneCard(scene: scene);
    }
    final theme=Theme.of(context);
    return MarkdownBody(data:text,selectable:true,
      styleSheet:MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: TextStyle(color:color,fontSize:15,height:1.35),
        code:TextStyle(color:color,fontFamily:'monospace',fontSize:13),
        blockquote:TextStyle(color:color.withValues(alpha:.85),fontSize:14),
      ));
  }
}
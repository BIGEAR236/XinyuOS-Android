import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'proactive_service.dart';
import 'ui_extras.dart';
import 'ui_shell.dart';

/// In-device event memory. The user confirms every date and every character's
/// right to initiate a follow-up. No server, no silent unlimited API calls.
class ProactiveEventsScreen extends StatefulWidget {
  final AppController controller;
  final String? initialCharacterId;
  final String? initialTopic;
  const ProactiveEventsScreen({super.key, required this.controller,
    this.initialCharacterId, this.initialTopic});
  @override
  State<ProactiveEventsScreen> createState() => _ProactiveEventsScreenState();
}

class _ProactiveEventsScreenState extends State<ProactiveEventsScreen> {
  bool _adding = false;

  Future<void> _newEvent() async {
    if (_adding) return;
    final chars = widget.controller.data.characters;
    if (chars.isEmpty) { uiError(context, '请先创建 AI 好友'); return; }
    final topic = TextEditingController(text: widget.initialTopic ?? '');
    var charId = widget.initialCharacterId ?? chars.first.id;
    if (!chars.any((c) => c.id == charId)) charId = chars.first.id;
    var date = DateTime.now().add(const Duration(days: 7));
    var time = const TimeOfDay(hour: 18, minute: 0);
    try {
      final confirmed = await showDialog<bool>(context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
          title: const Text('添加事件记忆'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: topic, maxLines: 3, maxLength: 150,
                decoration: const InputDecoration(labelText: '例如：下周要参加足球比赛')),
              DropdownButtonFormField<String>(initialValue: charId,
                decoration: const InputDecoration(labelText: '由哪个角色主动关心'),
                items: chars.map((c) => DropdownMenuItem(value: c.id,
                  child: Text(c.name))).toList(),
                onChanged: (v) { if (v != null) update(() => charId = v); }),
              const SizedBox(height: 8),
              ListTile(title: const Text('提醒日期'),
                subtitle: Text('${date.year}-${date.month}-${date.day}'),
                trailing: const Icon(Icons.calendar_month), onTap: () async {
                  final next = await showDatePicker(context: ctx,
                    initialDate: date, firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (next != null) update(() => date = next);
                }),
              ListTile(title: const Text('提醒时间'),
                subtitle: Text(time.format(ctx)),
                trailing: const Icon(Icons.access_time), onTap: () async {
                  final next = await showTimePicker(context: ctx, initialTime: time);
                  if (next != null) update(() => time = next);
                }),
              const Text('需要用户确认日期。通知不会调用模型；只有打开 App 后，AI 才根据记忆生成自然消息。',
                style: TextStyle(fontSize: 12)),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存事件')),
          ])));
      if (confirmed != true || !mounted) return;
      if (topic.text.trim().isEmpty) { uiError(context, '请填写事件内容'); return; }
      final dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (!dueAt.isAfter(DateTime.now())) { uiError(context, '时间必须在未来'); return; }
      setState(() => _adding = true);
      try {
        await widget.controller.addProactiveEvent(ProactiveEvent(
          id: newId(), characterId: charId, topic: topic.text.trim(), dueAt: dueAt));
        if (mounted) uiError(context, '事件已保存；角色权限打开后会按设定提醒');
      } catch (e) {
        if (mounted) uiError(context, '事件已保存，但手机通知可能未成功：$e');
      } finally { if (mounted) setState(() => _adding = false); }
    } finally { topic.dispose(); }
  }

  Future<void> _toggleGlobal(bool value) async {
    if (value) {
      try {
        final okay = await ProactiveNotificationService.requestPermission();
        if (!okay && mounted) uiError(context, '未获通知权限。打开 App 时仍可生成到期关怀消息。');
      } catch (e) {
        if (mounted) uiError(context, '通知权限请求失败：$e');
      }
    }
    try { await widget.controller.setAllowProactive(value); }
    catch (e) { if (mounted) uiError(context, '通知安排失败：$e'); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller, builder: (context, _) {
    final ctl = widget.controller;
    final events = [...ctl.data.proactiveEvents]
      ..sort((a,b) => a.dueAt.compareTo(b.dueAt));
    return Scaffold(appBar: AppBar(title: const Text('主动关怀与事件记忆')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _newEvent,
        icon: const Icon(Icons.add), label: const Text('新增事件')),
      body: ListView(children: [
        SwitchListTile(title: const Text('允许 AI 主动关怀'),
          subtitle: const Text('默认关闭；每个角色还须单独授权。到期通知和应用内消息都依赖此开关。'),
          value: ctl.data.allowProactiveMessages,
          onChanged: _toggleGlobal),
        const ListTile(leading: Icon(Icons.notifications_active_outlined),
          title: Text('打开 App 时弹出关怀提示'),
          subtitle: Text('到期事件会在虚拟桌面弹出较大的本地提示，每个事件只弹一次；点击进入角色聊天。真正的 AI 回复仍需要启用权限和可用的模型。')),
        const Divider(),
        const ListTile(title: Text('各角色的独立权限'),
          subtitle: Text('只能为你明确允许的角色生成主动消息。')),
        ...ctl.data.characters.map((c) => SwitchListTile(
          title: Text(c.name), value: c.allowProactiveMessages,
          onChanged: (v) async {
            try { await ctl.setCharacterProactive(c.id, v); }
            catch (e) { if (context.mounted) uiError(context, e); }
          })),
        const Divider(),
        const ListTile(title: Text('已保存的事件'),
          subtitle: Text('到期后仅尝试一次自然关怀；失败有冷却期，不会无限耗费 API 额度。')),
        if (events.isEmpty) const ListTile(title: Text('还没有事件，点击右下角新增')),
        ...events.map((e) => ListTile(
          leading: Icon(e.delivered ? Icons.check_circle_outline : Icons.event_note),
          title: Text(e.topic, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${ctl.displayName(e.characterId)} · '
            '${e.dueAt.year}-${e.dueAt.month}-${e.dueAt.day} '
            '${e.dueAt.hour.toString().padLeft(2,'0')}:${e.dueAt.minute.toString().padLeft(2,'0')}'
            '${e.delivered ? ' · 已关怀' : ''}'),
          trailing: IconButton(tooltip: '删除事件',
            icon: const Icon(Icons.delete_outline), onPressed: () async {
              try { await ctl.removeProactiveEvent(e.id); }
              catch (err) { if (context.mounted) uiError(context, err); }
            }))),
        const Padding(padding: EdgeInsets.all(16),
          child: Text('无服务器版本的区别：手机在指定时间发送预设的本地提醒；真正的 AI 文字在你再次打开社交应用、网络可用时生成。省电限制可能导致通知延后。',
            style: TextStyle(fontSize: 12))),
        const SizedBox(height: 80),
      ]));
  });
}

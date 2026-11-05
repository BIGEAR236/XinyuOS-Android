import 'dart:convert';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui_contacts.dart';
import 'ui_proactive.dart';

/// Social app settings. These never duplicate the virtual phone OS settings.
class SocialSettingsScreen extends StatelessWidget {
  final AppController controller;
  const SocialSettingsScreen({super.key, required this.controller});

  void _open(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通讯设置')),
    body: ListView(children: [
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.chat_bubble_outline),
        title: const Text('聊天'),
        subtitle: const Text('日常聊天或沉浸剧情'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ChatModeSettingsScreen(controller: controller))),
      const Divider(height: 1, indent: 55),
      ListTile(leading: const Icon(Icons.palette_outlined),
        title: const Text('界面与显示'),
        subtitle: const Text('聊天气泡、透明度、颜色、时间'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ChatAppearanceSettingsScreen(controller: controller))),
      const Divider(height: 1, indent: 55),
      ListTile(leading: const Icon(Icons.people_outline),
        title: const Text('朋友权限'),
        subtitle: const Text('AI 朋友圈与主动消息授权'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, FriendPermissionsScreen(controller: controller))),
      const Divider(height: 1, indent: 55),
      ListTile(leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('主动关怀与事件记忆'),
        subtitle: const Text('比赛、考试等事件提醒'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ProactiveEventsScreen(controller: controller))),
      const Divider(height: 1, indent: 55),
      ListTile(leading: const Icon(Icons.storage_outlined),
        title: const Text('存储空间'),
        subtitle: const Text('管理本地聊天记录'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, ChatStorageSettingsScreen(controller: controller))),
      const SizedBox(height: 28),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text('这里仅管理心屿通讯的聊天功能。壁纸、图标排列、桌面主题'
          '在虚拟手机的「系统设置」里修改。',
          style: TextStyle(fontSize: 12, color: Colors.grey))),
    ]),
  );
}

class ChatModeSettingsScreen extends StatelessWidget {
  final AppController controller;
  const ChatModeSettingsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('聊天模式')),
      body: ListView(children: [
        const ListTile(title: Text('选择对话呈现方式'),
          subtitle: Text('沉浸剧情保留角色动作、场景描写和故事设定，不会自动切换到日常聊天。')),
        RadioListTile<String>(value: 'story', groupValue: controller.data.chatMode,
          title: const Text('沉浸剧情'),
          subtitle: const Text('继续角色世界观与场景互动'),
          onChanged: (v) { if (v != null) controller.setChatMode(v); }),
        RadioListTile<String>(value: 'daily', groupValue: controller.data.chatMode,
          title: const Text('日常聊天'),
          subtitle: const Text('像即时通讯那样简短对话'),
          onChanged: (v) { if (v != null) controller.setChatMode(v); }),
      ])));
}

class ChatAppearanceSettingsScreen extends StatelessWidget {
  final AppController controller;
  const ChatAppearanceSettingsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) => Scaffold(
    appBar: AppBar(title: const Text('界面与显示')),
    body: ListView(children: [
      ListTile(title: Text('气泡透明度 ${(controller.data.chatBubbleOpacity * 100).round()}%')),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Slider(value: controller.data.chatBubbleOpacity.clamp(.35, 1.0),
          min: .35, max: 1, divisions: 13,
          onChanged: (v) => controller.setChatStyle(opacity: v))),
      const ListTile(title: Text('我的气泡颜色')),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [0xFFB8EC9C, 0xFFFFE2AE,
          0xFFC6E6F8, 0xFFFFD8E2, 0xFFD8D2FF, 0xFFFFFFFF].map((v) =>
          ChoiceChip(label: const Text('  '),
            avatar: CircleAvatar(backgroundColor: Color(v)),
            selected: controller.data.myBubbleColor == v,
            onSelected: (_) => controller.setChatStyle(mine: v))).toList())),
      const ListTile(title: Text('对方气泡颜色')),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [0xFFFFFFFF, 0xFFF3EAF9,
          0xFFDBF2FA, 0xFFFFE9D9, 0xFFD6F3E3].map((v) =>
          ChoiceChip(label: const Text('  '),
            avatar: CircleAvatar(backgroundColor: Color(v)),
            selected: controller.data.aiBubbleColor == v,
            onSelected: (_) => controller.setChatStyle(theirs: v))).toList())),
      SwitchListTile(title: const Text('显示每条消息的时间'),
        value: controller.data.showChatTime,
        onChanged: (v) => controller.setChatStyle(showTime: v)),
      const ListTile(title: Text('单独的好友聊天背景'),
        subtitle: Text('请在好友资料 → 聊天背景中设置。')),
    ])));
}

class FriendPermissionsScreen extends StatelessWidget {
  final AppController controller;
  const FriendPermissionsScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('朋友权限')),
      body: ListView(children: [
        const ListTile(title: Text('角色权限'),
          subtitle: Text('每位 AI 单独管理发布朋友圈、点赞评论和主动关怀权限。')),
        ...controller.data.characters.map((c) => ListTile(
          title: Text(c.name),
          subtitle: Text('主动消息：${c.allowProactiveMessages ? '允许' : '关闭'}'
            ' · 朋友圈：${c.allowSocialInteractions ? '允许互动' : '关闭互动'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            CharacterDetailScreen(controller: controller, characterId: c.id))))),
      ])));
}

class ChatStorageSettingsScreen extends StatelessWidget {
  final AppController controller;
  const ChatStorageSettingsScreen({super.key, required this.controller});

  Future<void> _clear(BuildContext context) async {
    final okay = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('清空聊天记录'),
        content: const Text('只删除本机的私聊和群聊记录，不会删除角色、'
          'API 配置、朋友圈和激活数据。不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空')),
        ]));
    if (okay == true) controller.clearLocalChatHistory();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('存储空间')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.storage_outlined),
          title: const Text('本地聊天记录'),
          subtitle: Text('${controller.data.messages.length} 条消息 · '
            '本地配置约 ${(utf8.encode(controller.data.serialize()).length / 1024).toStringAsFixed(1)} KB')),
        ListTile(leading: const Icon(Icons.delete_outline),
          title: const Text('清理聊天记录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _clear(context)),
        const ListTile(leading: Icon(Icons.shield_outlined),
          title: Text('隐私说明'),
          subtitle: Text('聊天存储在手机上，但模型请求会将必要内容发送给你配置的 API 服务商。')),
      ])));
}

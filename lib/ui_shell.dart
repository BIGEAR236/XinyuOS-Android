import 'dart:io';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'local_data.dart';
import 'ui_chat.dart';
import 'ui_contacts.dart';
import 'ui_extras.dart';

void uiError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$error', maxLines: 4, overflow: TextOverflow.ellipsis),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 6),
  ));
}

String clockTime(DateTime time) =>
  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class CharacterAvatar extends StatelessWidget {
  final Character character;
  final LocalData local;
  final double radius;
  const CharacterAvatar({super.key, required this.character, required this.local,
    this.radius = 23});
  @override
  Widget build(BuildContext context) {
    final source = character.avatarPath.isEmpty ? null :
      local.resolve(character.avatarPath);
    if (source != null && source.existsSync()) {
      return ClipOval(child: Image.file(source,
        width: radius * 2, height: radius * 2, fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback()));
    }
    return _fallback();
  }
  Widget _fallback() => CircleAvatar(radius: radius,
    backgroundColor: Color(character.avatarColor),
    child: Text(character.name.isNotEmpty
      ? String.fromCharCode(character.name.runes.first) : '?',
      style: TextStyle(color: Colors.white, fontSize: radius * .85,
        fontWeight: FontWeight.bold)));
}

class PhoneHomeScreen extends StatelessWidget {
  final AppController controller;
  const PhoneHomeScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final file = controller.data.wallpaperPath.isEmpty ? null :
      controller.local.resolve(controller.data.wallpaperPath);
    final current = DateTime.now();
    return Scaffold(body: Stack(fit: StackFit.expand, children: [
      Container(decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF6C6D9B), Color(0xFFB8A9C9), Color(0xFFE8C9C1)]))),
      if (file != null && file.existsSync())
        Image.file(File(file.path), fit: BoxFit.cover),
      Container(color: Colors.black.withValues(alpha: .12)),
      SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(children: [
          Text(clockTime(current), style: const TextStyle(color: Colors.white,
            fontSize: 64, fontWeight: FontWeight.w200)),
          Text('${current.year} / ${current.month} / ${current.day}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 10),
          const Text('心屿 · 让故事继续',
            style: TextStyle(color: Colors.white70, letterSpacing: 2)),
          const Spacer(),
          MiniPlayer(controller: controller),
          const SizedBox(height: 12),
          Wrap(spacing: 22, runSpacing: 25, alignment: WrapAlignment.center,
            children: [
              HomeIcon(icon: Icons.chat_bubble_rounded, name: '心屿通讯',
                iconPath: controller.data.desktopIcons['chat'], local: controller.local,
                color: const Color(0xFF78BBA1), onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => SocialScreen(controller: controller)))),
              HomeIcon(icon: Icons.hub_rounded, name: 'API 连接',
                iconPath: controller.data.desktopIcons['api'], local: controller.local,
                color: const Color(0xFF809AD2), onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ApiProfileListScreen(controller: controller)))),
              HomeIcon(icon: Icons.music_note_rounded, name: '本地音乐',
                iconPath: controller.data.desktopIcons['music'], local: controller.local,
                color: const Color(0xFFCA8DA6), onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => MusicScreen(controller: controller)))),
              HomeIcon(icon: Icons.settings_rounded, name: '设置',
                iconPath: controller.data.desktopIcons['settings'], local: controller.local,
                color: const Color(0xFF8B8C98), onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => SettingsScreen(controller: controller)))),
            ]),
          const Spacer(),
          Container(width: 110, height: 5, decoration: BoxDecoration(
            color: Colors.white70, borderRadius: BorderRadius.circular(8))),
        ]))),
    ]));
  }
}

class HomeIcon extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color color;
  final VoidCallback onTap;
  final String? iconPath;
  final LocalData local;
  const HomeIcon({super.key, required this.icon, required this.name,
    required this.color, required this.onTap, required this.local, this.iconPath});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(width: 94, child: Column(mainAxisSize: MainAxisSize.min,
      children: [Container(height: 69, width: 69, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(19),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)]),
        child: (iconPath != null && iconPath!.isNotEmpty &&
            local.resolve(iconPath!).existsSync())
          ? ClipRRect(borderRadius: BorderRadius.circular(19),
              child: Image.file(local.resolve(iconPath!), fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(icon, color: Colors.white, size: 35)))
          : Icon(icon, color: Colors.white, size: 35)),
        const SizedBox(height: 8),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w600)),
      ])));
}

class SocialScreen extends StatefulWidget {
  final AppController controller;
  const SocialScreen({super.key, required this.controller});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}
class _SocialScreenState extends State<SocialScreen> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final titles = ['聊天', '通讯录', '朋友圈', '我的'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[index]), actions: [
        if (index == 0 || index == 1) PopupMenuButton<String>(
          tooltip: '添加好友或创建群聊',
          onSelected: (value) async {
            if (value == 'friend') {
              await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                CharacterEditorScreen(controller: widget.controller)));
            } else {
              final created = await Navigator.push<ChatGroup>(context,
                MaterialPageRoute(builder: (_) => CreateGroupScreen(controller: widget.controller)));
              if (created != null && context.mounted) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                  ChatScreen(controller: widget.controller, group: created)));
              }
            }
          }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'friend', child: Text('添加 AI 好友')),
            PopupMenuItem(value: 'group', child: Text('发起群聊')),
          ], child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.add_circle_outline_rounded))),
      ]),
      body: AnimatedBuilder(animation: widget.controller, builder: (context, _) =>
        IndexedStack(index: index, children: [
          ChatListTab(controller: widget.controller),
          ContactsTab(controller: widget.controller),
          MomentsTab(controller: widget.controller),
          MyTab(controller: widget.controller),
        ])),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        MiniPlayer(controller: widget.controller),
        NavigationBar(selectedIndex: index,
        onDestinationSelected: (next) => setState(() => index = next),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble), label: '聊天'),
          NavigationDestination(icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people), label: '通讯录'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt), label: '朋友圈'),
          NavigationDestination(icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person), label: '我的'),
        ]),
      ]),
    );
  }
}

class ChatListTab extends StatelessWidget {
  final AppController controller;
  const ChatListTab({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller.data.characters;
    final groups = controller.data.groups;
    if (c.isEmpty && groups.isEmpty) return Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
      const Text('还没有好友'),
      TextButton(onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => CharacterEditorScreen(controller: controller))),
        child: const Text('添加第一个 AI 好友')),
    ]));
    // One clean list, ordered by the last conversation event.
    final rows = <({String id, String title, String subtitle, DateTime? time,
      Widget avatar, VoidCallback onTap})>[];
    for (final group in groups) {
      final thread = groupThread(group.id);
      final entries = controller.threadMessages(thread);
      rows.add((id: thread, title: group.name,
        subtitle: entries.isEmpty ? '${group.memberIds.length} 位成员' : entries.last.text,
        time: entries.isEmpty ? null : entries.last.createdAt,
        avatar: const CircleAvatar(child: Icon(Icons.groups_rounded)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          ChatScreen(controller: controller, group: group)))));
    }
    for (final friend in c) {
      final thread = privateThread(friend.id);
      final entries = controller.threadMessages(thread);
      rows.add((id: thread, title: friend.name,
        subtitle: entries.isEmpty ? '开始聊天' : entries.last.text,
        time: entries.isEmpty ? null : entries.last.createdAt,
        avatar: CharacterAvatar(character: friend, local: controller.local),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          ChatScreen(controller: controller, friend: friend)))));
    }
    rows.sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return b.time!.compareTo(a.time!);
    });
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 74),
      itemBuilder: (context, index) {
        final r = rows[index];
        return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: r.avatar,
          title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: r.time == null ? null : Text(clockTime(r.time!),
            style: Theme.of(context).textTheme.labelSmall),
          onTap: r.onTap,
        );
      },
    );
  }
}

class MyTab extends StatelessWidget {
  final AppController controller;
  const MyTab({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListView(children: [
    const ListTile(leading: CircleAvatar(child: Icon(Icons.auto_awesome)),
      title: Text('心屿 OS'), subtitle: Text('V3.2 · 本地优先 · AI 社交')),
    const Divider(),
    ListTile(leading: const Icon(Icons.hub_outlined), title: const Text('API 管理'),
      subtitle: const Text('添加服务商、测试连接、修改模型'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        ApiProfileListScreen(controller: controller)))),
    ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('外观和本地设置'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        SettingsScreen(controller: controller)))),
    const ListTile(leading: Icon(Icons.privacy_tip_outlined),
      title: Text('关于隐私'),
      subtitle: Text('聊天存在本机；API Key 存系统安全存储。云端模型会收到你发出的内容。')),
    if (controller.persistenceError != null)
      ListTile(leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(controller.persistenceError!)),
  ]);
}

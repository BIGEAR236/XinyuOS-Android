import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'local_data.dart';
import 'ui_chat.dart';
import 'ui_contacts.dart';
import 'ui_extras.dart';
import 'ui_social_settings.dart';
import 'ui_local_apps.dart';
import 'v39/desktop_icon_settings.dart';
import 'v39/app_launch_care.dart';
import 'v40/wallet_page.dart';
import 'v40/marketplace_page.dart';
import 'v41/desktop_grid.dart';
import 'v41/collections_pages.dart';

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

class PhoneHomeScreen extends StatefulWidget {
  final AppController controller;
  const PhoneHomeScreen({super.key, required this.controller});

  @override
  State<PhoneHomeScreen> createState() => _PhoneHomeScreenState();
}

class _PhoneHomeScreenState extends State<PhoneHomeScreen>
    with WidgetsBindingObserver {
  Timer? _socialTimer;
  bool _foreground = true;
  final _random = math.Random();
  void _planSocial() {
    _socialTimer?.cancel();
    if (!_foreground) return;
    // Foreground only, randomized 25-50 minute intervals and existing hourly caps.
    _socialTimer = Timer(Duration(minutes:25+_random.nextInt(26)),() {
      if(!mounted)return;
      _checkSocial();
      _planSocial();
    });
  }
  void _checkSocial() {
    if (_foreground && mounted) unawaited(_runSocialChecks());
  }
  Future<void> _runSocialChecks() async {
    try {
      if (controller.data.autoMomentPosting) {
        await controller.maybeAutoPostMoment();
      }
      if (controller.data.autoMomentInteractions) {
        await controller.maybeAutoSocialSweep();
      }
    } catch (_) { /* Opt-in background check; never block the desktop. */ }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _planSocial();
      _checkSocial();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _socialTimer?.cancel();
    }
  }
  @override void dispose() {
    _socialTimer?.cancel();WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(XyDesktopSlots.load());
    _planSocial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Generate an authorized, due AI message without making the popup wait
      // for a network call; the popup itself is always a local reminder.
      unawaited(controller.processDueEvents().catchError((Object _) {}));
      _checkSocial();
      unawaited(AppLaunchCarePrompt.checkAndShow(context, controller)
        .catchError((Object _) {}));
    });
  }

  Widget _desktopTile(BuildContext context, String key) {
    late final IconData icon;
    late final String title;
    late final Color color;
    late final Widget destination;
    switch (key) {
      case 'chat':
        icon=Icons.chat_bubble_rounded; title='雨雨机';
        color=const Color(0xFF90BDAE); destination=SocialScreen(controller:controller); break;
      case 'api':
        icon=Icons.hub_rounded; title='API 连接';
        color=const Color(0xFF9AABDC); destination=ApiProfileListScreen(controller:controller); break;
      case 'music':
        icon=Icons.music_note_rounded;title='本地音乐';
        color=const Color(0xFFD49CB3);destination=MusicScreen(controller:controller);break;
      case 'video':
        icon=Icons.play_circle_rounded;title='本地视频';
        color=const Color(0xFFB1A5D5);destination=XyVideoLibraryPage(controller:controller);break;
      case 'album':
        icon=Icons.face_3_rounded;title='数字人图库';
        color=const Color(0xFFD6A9BE);destination=XyDigitalGalleryPage(controller:controller);break;
      case 'memo':
        icon=Icons.note_alt_rounded;title='备忘录';
        color=const Color(0xFFE4BC92);
        destination=XyNotebookShell(notebookKey:'memo.me',title:'我的备忘录',
          child:LocalNotesScreen(controller:controller,category:'memo',embedded:true));break;
      case 'diary':
        icon=Icons.auto_stories_rounded;title='日记';
        color=const Color(0xFFC59FC3);destination=XyDiaryLibraryPage(controller:controller);break;
      default:
        icon=Icons.settings_rounded;title='设置';
        color=const Color(0xFF8E99AB);destination=SettingsScreen(controller:controller);break;
    }
    return FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.topCenter,
      child:HomeIcon(icon:icon,name:title,color:color,
        iconScale:DesktopIconScale.current.value,
        iconPath:controller.data.desktopIcons[key],local:controller.local,
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>destination))));
  }

  @override
  Widget build(BuildContext context) {
    final file = controller.data.wallpaperPath.isEmpty ? null :
      controller.local.resolve(controller.data.wallpaperPath);
    final current = DateTime.now();
    return AnimatedBuilder(animation: controller, builder: (context, _) =>
      Scaffold(body: Stack(fit: StackFit.expand, children: [
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
          const Text('小雨机，把每句话送到对的AI',
            style: TextStyle(color: Colors.white70, letterSpacing: 2)),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(children: [
              MiniPlayer(controller: controller),
              const SizedBox(height: 12),
              ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
                child:ValueListenableBuilder<double>(
                  valueListenable:DesktopIconScale.current,
                  builder:(context,scale,_)=>XyDesktopGrid(scale:scale,
                    tileBuilder:(key)=>_desktopTile(context,key)))),
              const SizedBox(height: 18),
              const Text('长按图标，可自由拖到空位或与其他图标互换位置',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]))),
          const SizedBox(height: 16),
          Container(width: 110, height: 5, decoration: BoxDecoration(
            color: Colors.white70, borderRadius: BorderRadius.circular(8))),
        ]))),
    ])));
  }
}

class HomeIcon extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color color;
  final VoidCallback onTap;
  final String? iconPath;
  final LocalData local;
  final double iconScale;
  const HomeIcon({super.key, required this.icon, required this.name,
    required this.color, required this.onTap, required this.local,
    this.iconPath, this.iconScale = 1.0});
  @override
  Widget build(BuildContext context) {
    final scale = iconScale.clamp(0.7, 1.5).toDouble();
    return InkWell(onTap: onTap,
      borderRadius: BorderRadius.circular(14 * scale),
      child: SizedBox(width: 78 * scale,
        child: Column(mainAxisSize: MainAxisSize.min,
          children: [Container(height: 69 * scale, width: 69 * scale,
            decoration: BoxDecoration(color: color,
              borderRadius: BorderRadius.circular(19 * scale),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)]),
            child: (iconPath != null && iconPath!.isNotEmpty &&
                local.resolve(iconPath!).existsSync())
              ? ClipRRect(borderRadius: BorderRadius.circular(19 * scale),
                  child: Image.file(local.resolve(iconPath!), fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(icon,
                      color: Colors.white, size: 35 * scale)))
              : Icon(icon, color: Colors.white, size: 35 * scale)),
            SizedBox(height: 8 * scale),
            Text(name, maxLines: 2, textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w600)),
          ])));
  }
}

class SocialScreen extends StatefulWidget {
  final AppController controller;
  const SocialScreen({super.key, required this.controller});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}
class _SocialScreenState extends State<SocialScreen> with WidgetsBindingObserver {
  int index = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.processDueEvents();
        widget.controller.maybeAutoPostMoment();
        widget.controller.maybeAutoSocialSweep();
      }
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.processDueEvents();
      widget.controller.maybeAutoPostMoment();
      widget.controller.maybeAutoSocialSweep();
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
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
        onDestinationSelected: (next) async {
          setState(() => index = next);
          if (next == 2) {
            await widget.controller.maybeAutoPostMoment();
            final err = await widget.controller.maybeAutoSocialSweep();
            if (mounted && err != null) uiError(context, err);
          }
        },
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
      final thread = controller.activePrivateThread(friend.id);
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
  Future<void> _avatar(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) return;
      final length = await picked.length();
      if (length != null && length > 8 * 1024 * 1024) {
        throw const FormatException('头像不能超过 8MB');
      }
      final path = await controller.local.copyIntoApp(picked, 'my_avatars');
      controller.setMyAvatar(path);
    } catch (e) { if (context.mounted) uiError(context, e); }
  }
  @override
  Widget build(BuildContext context) => ListView(children: [
    ListTile(leading: controller.data.myAvatarPath.isNotEmpty &&
        controller.local.resolve(controller.data.myAvatarPath).existsSync()
      ? CircleAvatar(backgroundImage: FileImage(
          controller.local.resolve(controller.data.myAvatarPath)))
      : const CircleAvatar(child: Icon(Icons.person)),
      title: const Text('我的头像'), subtitle: const Text('从相册选择头像'),
      trailing: const Icon(Icons.edit_outlined), onTap: () => _avatar(context)),
    ListTile(leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
      title: const Text('我的虚拟账户'),
      subtitle: Text('星币余额 ${controller.data.worldBalance} ⭐ · AI 好友独立账户'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        XyWalletPage(controller: controller)))),
    ListTile(leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
      title: const Text('星愿商城'),subtitle:const Text('虚拟金币购物与购物车'),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>
        XyMarketplacePage(controller:controller)))),
    const ListTile(leading: CircleAvatar(child: Icon(Icons.auto_awesome)),
      title: Text('小雨机'), subtitle: Text('V4.0 · 聊天内虚拟生活 · 本地优先')),
    const Divider(),
    ListTile(leading: const Icon(Icons.tune_outlined), title: const Text('通讯设置'),
      subtitle: const Text('聊天、界面与显示、朋友权限、存储空间、主动关怀'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        SocialSettingsScreen(controller: controller)))),
    const ListTile(leading: Icon(Icons.privacy_tip_outlined),
      title: Text('关于隐私'),
      subtitle: Text('聊天存在本机；API Key 存系统安全存储。云端模型会收到你发出的内容。')),
    if (controller.persistenceError != null)
      ListTile(leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(controller.persistenceError!)),
  ]);
}

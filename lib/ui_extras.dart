
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_shell.dart';

class MomentsTab extends StatelessWidget {
  final AppController controller;
  const MomentsTab({super.key, required this.controller});

  Future<void> _showOptions(BuildContext context) async {
    await showModalBottomSheet<void>(context: context,
      isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('选择一个 AI 生成朋友圈',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          const SizedBox(height: 9),
          const Text('默认全部关闭。用户明确授权后，才允许手动生成。'
            '本版本不会后台自行发朋友圈。'),
          const SizedBox(height: 8),
          ...controller.data.characters.map((c) => ListTile(
            leading: CharacterAvatar(character: c, local: controller.local),
            title: Text(c.name),
            subtitle: Text(c.allowMoments ? '已授权生成朋友圈' : '尚未授权'),
            trailing: Switch(value: c.allowMoments,
              onChanged: (v) {
                controller.allowMoments(c.id, v);
                Navigator.pop(sheetContext);
                _showOptions(context);
              }),
            onTap: () async {
              if (!c.allowMoments) {
                uiError(context, '请先开启 ${c.name} 的朋友圈权限。'); return;
              }
              Navigator.pop(sheetContext);
              final err = await controller.generateMoment(c);
              if (err != null && context.mounted) uiError(context, err);
            },
          )),
        ]))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: controller.data.moments.isEmpty
      ? const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Text('朋友圈还是空的。\n点击右下角，选择已授权的 AI 生成第一条动态。',
          textAlign: TextAlign.center)))
      : ListView.separated(itemCount: controller.data.moments.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final m = controller.data.moments[index];
            final c = controller.character(m.characterId);
            return Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (c != null) CharacterAvatar(character: c, local: controller.local, radius: 19)
                  else const CircleAvatar(child: Icon(Icons.smart_toy)),
                  const SizedBox(width: 11),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c?.name ?? '已删除角色',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${m.createdAt.year}-${m.createdAt.month}-${m.createdAt.day} '
                      '${clockTime(m.createdAt)} · 虚拟动态',
                      style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ]),
                const SizedBox(height: 12),
                SelectableText(m.text),
              ]));
          }),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _showOptions(context),
      icon: const Icon(Icons.auto_awesome), label: const Text('生成动态')),
  );
}

class SettingsScreen extends StatelessWidget {
  final AppController controller;
  const SettingsScreen({super.key, required this.controller});

  Future<void> _wallpaper(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final fileSize = await file.length();
      if (fileSize != null && fileSize > 12 * 1024 * 1024) {
        throw const FormatException('壁纸文件不能超过 12 MB。');
      }
      final path = await controller.local.copyIntoApp(file, 'wallpapers');
      final savedFile = controller.local.resolve(path);
      if (await savedFile.length() > 12 * 1024 * 1024) {
        await savedFile.delete();
        throw const FormatException('壁纸文件不能超过 12 MB。');
      }
      controller.changeAppearance(wallpaper: path);
      if (context.mounted) uiError(context, '壁纸已更新');
    } catch (e) { if (context.mounted) uiError(context, e); }
  }

  Future<void> _iconImage(BuildContext context, String id) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 6 * 1024 * 1024) {
        throw const FormatException('桌面图标图片不能超过 6MB。');
      }
      final relative = await controller.local.copyIntoApp(file, 'icons');
      final saved = controller.local.resolve(relative);
      if (await saved.length() > 6 * 1024 * 1024) {
        await saved.delete();
        throw const FormatException('桌面图标图片不能超过 6MB。');
      }
      controller.setDesktopIcon(id, relative);
      if (context.mounted) uiError(context, '已更新桌面图标');
    } catch (e) { if (context.mounted) uiError(context, e); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller,
    builder: (context, _) => Scaffold(appBar: AppBar(title: const Text('系统设置')),
      body: ListView(children: [
        const ListTile(title: Text('虚拟手机外观'),
          subtitle: Text('这些设置只影响心屿 OS 应用内的虚拟桌面。')),
        ListTile(leading: const Icon(Icons.wallpaper_outlined),
          title: const Text('上传本地壁纸'),
          subtitle: const Text('从手机文件或相册选择一张图'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _wallpaper(context)),
        if (controller.data.wallpaperPath.isNotEmpty)
          ListTile(title: const Text('恢复默认壁纸'),
            onTap: () => controller.changeAppearance(wallpaper: '')),
        const Divider(),
        const ListTile(title: Text('自定义虚拟手机桌面图标'),
          subtitle: Text('点击以下应用可上传 PNG / JPG 等图片；不会修改安卓系统桌面图标。')),
        ...[('chat', '心屿通讯'), ('api', 'API 连接'),
          ('music', '本地音乐'), ('settings', '设置')].map((item) {
          final path = controller.data.desktopIcons[item.$1];
          final img = path == null || path.isEmpty ? null : controller.local.resolve(path);
          return ListTile(
            leading: img != null && img.existsSync()
                ? ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.file(img, width: 39, height: 39, fit: BoxFit.cover))
                : const Icon(Icons.apps_rounded),
            title: Text(item.$2),
            subtitle: const Text('更换桌面图标'),
            trailing: img == null ? const Icon(Icons.chevron_right) :
                IconButton(onPressed: () => controller.clearDesktopIcon(item.$1),
                  tooltip: '恢复默认图标', icon: const Icon(Icons.restore)),
            onTap: () => _iconImage(context, item.$1),
          );
        }),
        SwitchListTile(secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('深色模式'), value: controller.data.darkMode,
          onChanged: (value) => controller.changeAppearance(dark: value)),
        const Divider(),
        const ListTile(title: Text('主题颜色')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Wrap(spacing: 12, children: [0xFF8870B5, 0xFF5E9B8E,
            0xFF568AB7, 0xFFCF8A86, 0xFFDA9B61].map((value) =>
              ChoiceChip(label: const SizedBox(width: 15, height: 15),
                avatar: CircleAvatar(backgroundColor: Color(value)),
                selected: controller.data.themeColor == value,
                onSelected: (_) => controller.changeAppearance(color: value))).toList())),
        const Divider(),
        ListTile(title: const Text('字体大小'),
          subtitle: Text('当前 ${(controller.data.fontScale * 100).round()}%')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(min: .85, max: 1.35, divisions: 10,
            value: controller.data.fontScale.clamp(.85, 1.35).toDouble(),
            onChanged: (value) => controller.changeAppearance(scale: value))),
        const Divider(),
        const ListTile(leading: Icon(Icons.lock_outline), title: Text('隐私和存储'),
          subtitle: Text('角色、普通聊天与动态保存在应用私有目录；'
            'API 密钥存储于 Android Keystore / iOS Keychain。'
            '本版本没有跨设备同步，也没有自动云端备份功能。')),
        const ListTile(leading: Icon(Icons.cloud_outlined), title: Text('不部署应用服务器'),
          subtitle: Text('但真实 AI 回复仍需要联网调用第三方模型 API，'
            '并可能产生服务商费用。')),
      ])));
}

/// Compact player stays mounted in chat/social routes. It reads the shared
/// MusicController instead of creating a new AudioPlayer per page.
class MiniPlayer extends StatelessWidget {
  final AppController controller;
  const MiniPlayer({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.music,
    builder: (context, _) {
      final music = controller.music;
      if (!music.hasTrack) return const SizedBox.shrink();
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(top: false, bottom: false,
          child: ListTile(dense: true,
            leading: const Icon(Icons.music_note, size: 22),
            title: Text(music.trackTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
            trailing: IconButton(tooltip: music.playing ? '暂停' : '播放',
              icon: Icon(music.playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => music.togglePause().catchError((Object e) {
                if (context.mounted) uiError(context, e);
              })),
          )),
      );
    },
  );
}

class MusicScreen extends StatefulWidget {
  final AppController controller;
  const MusicScreen({super.key, required this.controller});
  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool _importing = false;

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.pickFiles(type: FileType.audio);
      if (picked.isEmpty) return;
      for (final file in picked) {
        final bytes = await file.length();
        if (bytes != null && bytes > 80 * 1024 * 1024) {
          if (mounted) uiError(context, '${file.name} 超过 80MB，已跳过');
          continue;
        }
        try {
          final relative = await widget.controller.local.copyIntoApp(file, 'music');
          final saved = widget.controller.local.resolve(relative);
          if (await saved.length() > 80 * 1024 * 1024) {
            await saved.delete();
            if (mounted) uiError(context, '${file.name} 超过 80MB，已跳过');
            continue;
          }
          widget.controller.addTrack(LocalTrack(id: newId(), title: file.name,
            relativePath: relative));
        } catch (e) { if (mounted) uiError(context, e); }
      }
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _importing = false); }
  }

  Future<void> _play(LocalTrack track) async {
    try { await widget.controller.music.toggleTrack(track); }
    catch (e) { if (mounted) uiError(context, e); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.controller.music]),
    builder: (context, _) {
      final music = widget.controller.music;
      final tracks = widget.controller.data.tracks;
      return Scaffold(
        appBar: AppBar(title: const Text('本地音乐'), actions: [
          IconButton(tooltip: '导入歌曲', onPressed: _importing ? null : _import,
            icon: const Icon(Icons.library_add_outlined)),
        ]),
        body: Column(children: [
          const ListTile(title: Text('我的歌单'),
            subtitle: Text('播放时可返回聊天页面继续收听。音乐不上传服务器。')),
          Expanded(child: tracks.isEmpty
            ? const Center(child: Text('还没有歌曲。点击右上角导入音乐。'))
            : ListView.builder(itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final current = music.trackId == track.id;
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.music_note)),
                    title: Text(track.title, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                    trailing: Icon(current && music.playing
                        ? Icons.pause_circle : Icons.play_circle_outline),
                    onTap: () => _play(track),
                  );
                })),
          MiniPlayer(controller: widget.controller),
          if (music.lastError != null) Padding(
            padding: const EdgeInsets.all(8), child: Text(music.lastError!,
              style: const TextStyle(color: Colors.red))),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _importing ? null : _import,
          icon: const Icon(Icons.add), label: Text(_importing ? '正在导入…' : '导入歌曲')),
      );
    },
  );
}

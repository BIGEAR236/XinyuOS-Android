import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

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
            leading: CharacterAvatar(character: c),
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
                  if (c != null) CharacterAvatar(character: c, radius: 19)
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
      final selected = await FilePicker.platform.pickFiles(type: FileType.image);
      if (selected == null || selected.files.isEmpty) return;
      final file = selected.files.single;
      if (file.size > 12 * 1024 * 1024) {
        throw const FormatException('壁纸文件不能超过 12 MB。');
      }
      final path = await controller.local.copyIntoApp(file, 'wallpapers');
      controller.changeAppearance(wallpaper: path);
      if (context.mounted) uiError(context, '壁纸已更新');
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

class MusicScreen extends StatefulWidget {
  final AppController controller;
  const MusicScreen({super.key, required this.controller});
  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _currentTrackId;
  bool _importing = false;

  @override
  void dispose() { unawaited(_player.dispose()); super.dispose(); }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.audio, allowMultiple: true);
      if (picked == null) return;
      for (final f in picked.files) {
        if (f.size > 80 * 1024 * 1024) {
          if (mounted) uiError(context, '${f.name} 超过 80 MB，已跳过。');
          continue;
        }
        try {
          final path = await widget.controller.local.copyIntoApp(f, 'music');
          widget.controller.addTrack(LocalTrack(id: newId(),
            title: f.name, relativePath: path));
        } catch (e) { if (mounted) uiError(context, e); }
      }
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _importing = false); }
  }

  Future<void> _play(LocalTrack track) async {
    try {
      final file = widget.controller.local.resolve(track.relativePath);
      if (!await file.exists()) {
        throw const FileSystemException('已导入的歌曲文件不存在');
      }
      if (_currentTrackId == track.id && _player.playing) {
        await _player.pause(); return;
      }
      if (_currentTrackId != track.id) {
        await _player.setFilePath(file.path);
        setState(() => _currentTrackId = track.id);
      }
      unawaited(_player.play().catchError((Object error) {
        if (mounted) uiError(context, error);
      }));
    } catch (e) { if (mounted) uiError(context, e); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('本地音乐'), actions: [
      IconButton(tooltip: '导入歌曲', onPressed: _importing ? null : _import,
        icon: const Icon(Icons.library_add_outlined))]),
    body: AnimatedBuilder(animation: widget.controller, builder: (context, _) =>
      Column(children: [
        const ListTile(title: Text('我的歌单'),
          subtitle: Text('歌曲复制到应用私有目录，不上传至服务器。')),
        if (widget.controller.data.tracks.isEmpty)
          const Expanded(child: Center(child: Text('暂无歌曲。点击右上角导入 MP3、M4A 等音频。')))
        else Expanded(child: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snapshot) => ListView(children:
            widget.controller.data.tracks.map((track) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.music_note)),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Icon(_currentTrackId == track.id && _player.playing
                ? Icons.pause_circle : Icons.play_circle_outline),
              onTap: () => _play(track))).toList()))),
        if (_currentTrackId != null)
          StreamBuilder<PlayerState>(stream: _player.playerStateStream,
            builder: (context, _) => ListTile(
              leading: Icon(_player.playing ? Icons.graphic_eq : Icons.music_note),
              title: Text(widget.controller.data.tracks
                .where((t) => t.id == _currentTrackId)
                .map((t) => t.title).firstOrNull ?? '本地播放'),
              trailing: IconButton(onPressed: () async {
                if (_player.playing) { await _player.pause(); }
                else { unawaited(_player.play()); }
              }, icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow)))),
      ])),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _importing ? null : _import, icon: const Icon(Icons.add),
      label: Text(_importing ? '正在导入…' : '导入本地歌曲')),
  );
}

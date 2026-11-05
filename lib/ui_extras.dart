
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_shell.dart';

class MomentsTab extends StatefulWidget {
  final AppController controller;
  const MomentsTab({super.key, required this.controller});
  @override
  State<MomentsTab> createState() => _MomentsTabState();
}

class _MomentsTabState extends State<MomentsTab> {
  AppController get controller => widget.controller;

  Future<void> _showOptions() async {
    await showModalBottomSheet<void>(context: context,
      isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, refresh) =>
        SafeArea(child: Padding(padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
            const Text('生成虚拟朋友圈',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
            const SizedBox(height: 9),
            const Text('只有已允许发朋友圈的角色才能生成。不会在后台自动发布。'),
            const Divider(),
            ...controller.data.characters.map((c) => ListTile(
              leading: CharacterAvatar(character: c, local: controller.local),
              title: Text(c.name),
              subtitle: Text(c.allowMoments ? '已授权 · 点击生成动态' : '未授权发布'),
              trailing: Switch(value: c.allowMoments,
                onChanged: (value) {
                  controller.allowMoments(c.id, value);
                  refresh(() {});
                }),
              onTap: () async {
                if (!c.allowMoments) {
                  uiError(context, '请先打开 ${c.name} 的朋友圈发布权限。');
                  return;
                }
                Navigator.pop(sheetContext);
                final error = await controller.generateMoment(c);
                if (mounted && error != null) uiError(context, error);
              },
            )),
          ]))))));
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, refresh) =>
        SafeArea(child: Padding(padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('朋友圈互动设置',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SwitchListTile(title: const Text('打开朋友圈时自动邀请好友互动'),
              subtitle: const Text('默认关闭。仅在进入朋友圈时触发，最多每小时 1 条动态、2 位 AI。'),
              value: controller.data.autoMomentInteractions,
              onChanged: (value) {
                controller.setAutoMomentInteractions(value);
                refresh(() {});
              }),
            SwitchListTile(title: const Text('我评论后让 AI 自动回复'),
              subtitle: const Text('默认关闭。打开后最多调用两位已授权 AI，可能产生 API 费用。'),
              value: controller.data.autoMomentReplies,
              onChanged: (value) {
                controller.setAutoMomentReplies(value);
                refresh(() {});
              }),
            const Text('AI 好友关系和点赞/评论权限在每个联系人的资料中设置。\n'
              '不进行后台无限轮互动，只有用户操作或明确打开相关开关才调用模型。',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
          ])))));
  }

  Future<void> _comment(MomentEntry m, {MomentComment? parent}) async {
    final text = TextEditingController();
    try {
      final newComment = await showDialog<String>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(parent == null ? '发表评论' : '回复 ${controller.displayName(parent.authorId)}'),
          content: TextField(controller: text, autofocus: true,
            minLines: 2, maxLines: 5, maxLength: 300,
            decoration: const InputDecoration(hintText: '说点什么…', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, text.text.trim()),
              child: const Text('发表')),
          ],
        ));
      if (!mounted || newComment == null || newComment.isEmpty) return;
      final comment = controller.addMyMomentComment(m.id, newComment, parentId: parent?.id);
      if (comment == null) { uiError(context, '评论发送失败，请检查长度。'); return; }
      if (controller.data.autoMomentReplies) {
        final err = await controller.replyToMomentComment(m.id, comment.id);
        if (mounted && err != null) uiError(context, err);
      }
    } finally { text.dispose(); }
  }

  Future<void> _invite(MomentEntry moment) async {
    final error = await controller.inviteMomentInteractions(moment.id);
    if (mounted && error != null) uiError(context, error);
  }

  Future<void> _reply(MomentEntry m, MomentComment comment) async {
    final error = await controller.replyToMomentComment(m.id, comment.id);
    if (mounted && error != null) uiError(context, error);
  }

  Widget _commentRow(BuildContext context, MomentEntry m, MomentComment comment) {
    final parent = comment.parentId == null ? null :
      m.comments.where((c) => c.id == comment.parentId).firstOrNull;
    final display = controller.displayName(comment.authorId);
    final responding = controller.busy.contains('moment_reply:${m.id}:${comment.id}');
    return Padding(padding: EdgeInsets.only(left: comment.parentId == null ? 0 : 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: InkWell(onTap: () => _comment(m, parent: comment),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: display, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (parent != null) ...[
                const TextSpan(text: ' 回复 '),
                TextSpan(text: controller.displayName(parent.authorId),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              TextSpan(text: '：${comment.text}'),
            ]))))),
        IconButton(tooltip: '邀请 AI 回复这条评论',
          visualDensity: VisualDensity.compact,
          onPressed: responding ? null : () => _reply(m, comment),
          icon: responding ? const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)) :
            const Icon(Icons.smart_toy_outlined, size: 17)),
      ]));
  }

  Widget _momentCard(BuildContext context, MomentEntry m) {
    final c = controller.character(m.characterId);
    final busy = controller.busy.contains('moment_interact:${m.id}');
    return Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (c != null) CharacterAvatar(character: c,
            local: controller.local, radius: 21)
          else const CircleAvatar(child: Icon(Icons.smart_toy)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c?.name ?? '已删除的角色',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${m.createdAt.month}-${m.createdAt.day} ${clockTime(m.createdAt)} · 虚拟动态',
              style: Theme.of(context).textTheme.labelSmall),
          ])),
        ]),
        const SizedBox(height: 11),
        SelectableText(m.text),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(onPressed: () => controller.toggleMyMomentLike(m.id),
            icon: Icon(m.likedBy.contains('me') ? Icons.favorite : Icons.favorite_border,
              size: 18, color: m.likedBy.contains('me') ? Colors.redAccent : null),
            label: Text('点赞 ${m.likedBy.length}')),
          TextButton.icon(onPressed: () => _comment(m),
            icon: const Icon(Icons.mode_comment_outlined, size: 18),
            label: Text('评论 ${m.comments.length}')),
          const Spacer(),
          TextButton.icon(onPressed: busy ? null : () => _invite(m),
            icon: busy ? const SizedBox(width: 15, height: 15,
              child: CircularProgressIndicator(strokeWidth: 2)) :
              const Icon(Icons.auto_awesome_outlined, size: 17),
            label: const Text('好友互动')),
        ]),
        if (m.likedBy.isNotEmpty || m.comments.isNotEmpty)
          Container(width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(9)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m.likedBy.isNotEmpty) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.favorite, size: 15, color: Colors.redAccent),
                  const SizedBox(width: 7),
                  Expanded(child: Text(m.likedBy.map(controller.displayName).join('、'),
                    style: const TextStyle(fontSize: 13))),
                ]),
                if (m.comments.isNotEmpty) const Divider(height: 12),
              ],
              ...m.comments.map((comment) => _commentRow(context, m, comment)),
            ])),
      ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      Container(padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        child: Row(children: [
          const Icon(Icons.group_outlined, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('朋友圈只在本机模拟。好友需要建立关系并获得互动授权。',
            style: TextStyle(fontSize: 11))),
          IconButton(tooltip: '朋友圈设置', onPressed: _settings,
            icon: const Icon(Icons.settings_outlined)),
        ])),
      const Divider(height: 1),
      Expanded(child: controller.data.moments.isEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('朋友圈还是空的。\n点击右下角，选择已授权的 AI 生成动态。',
            textAlign: TextAlign.center)))
        : ListView.separated(itemCount: controller.data.moments.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _momentCard(context,
            controller.data.moments[index]))),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _showOptions,
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
        ListTile(leading: const Icon(Icons.drag_indicator),
          title: const Text('恢复桌面默认排列'),
          subtitle: const Text('长按桌面图标可拖动调整位置'),
          onTap: controller.resetDesktopOrder),
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


import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_shell.dart';
import 'v41/settings_home.dart';
import 'v39/desktop_icon_settings.dart';
import 'v39/font_import_policy.dart';
import 'v42/moment_photo_store.dart';

class MomentsTab extends StatefulWidget {
  final AppController controller;
  const MomentsTab({super.key, required this.controller});
  @override
  State<MomentsTab> createState() => _MomentsTabState();
}

class _MomentsTabState extends State<MomentsTab> {
  AppController get controller => widget.controller;

  Future<void> _composeMine() async {
    final input = TextEditingController();
    String photo = '';
    try {
      final value = await showDialog<String>(context: context,
        builder: (dialog) => StatefulBuilder(builder: (dialog, refresh) => AlertDialog(
          title: const Text('发表我的朋友圈'),
          content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
            TextField(controller: input, autofocus: true, maxLines: 5,
              maxLength: 1500, decoration: const InputDecoration(hintText: '分享此刻的心情…')),
            const SizedBox(height:8),
            OutlinedButton.icon(onPressed: () async {
              try {
                final path=await _pickMomentPhoto();
                if(path!=null)refresh(()=>photo=path);
              }catch(e){if(mounted)uiError(context,e);}
            },icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('添加本地图片')),
            if(photo.isNotEmpty && controller.local.resolve(photo).existsSync())
              Image.file(controller.local.resolve(photo),height:125,fit:BoxFit.cover),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog),child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(dialog, input.text.trim()),
              child: const Text('发表'))])));
      if (value != null && (value.isNotEmpty || photo.isNotEmpty)) {
        controller.addMyMoment(value.isEmpty ? '分享一张图片 ♡' : value);
        if (photo.isNotEmpty && controller.data.moments.isNotEmpty) {
          await XyMomentPhotoStore.set(controller.data.moments.first.id,photo);
          if(mounted)setState((){});
        }
        if (controller.data.autoMomentInteractions) {
          controller.maybeAutoSocialSweep().then((error) {
            if (mounted && error != null) uiError(context,error);
          });
        }
      }
    } finally { input.dispose(); }
  }

  Future<String?> _pickMomentPhoto() async {
    final picked=await FilePicker.pickFile(type:FileType.image);
    if(picked==null)return null;
    final bytes=await picked.length();
    if(bytes!=null && bytes>8*1024*1024)throw const FormatException('朋友圈图片最大 8MB');
    final relative=await controller.local.copyIntoApp(picked,'moment_photos');
    final saved=controller.local.resolve(relative);
    if(await saved.length()>8*1024*1024){await saved.delete();throw const FormatException('图片最大 8MB');}
    return relative;
  }

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
            const Text('只有已允许发朋友圈的角色才能生成。自动发布仅在前台检查，不会在关闭 App 后定时调用。'),
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
          child: ListView(shrinkWrap: true, children: [
            const Text('朋友圈自动互动（需主动开启，可能产生 API 费用）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SwitchListTile(title: const Text('允许 AI 定期发布朋友圈（前台）'),
              subtitle: const Text('默认关闭。打开后会将相关聊天片段发给该角色的模型以生成虚拟动态；可能产生额外 API 费用。关闭 App 时不会后台生成。'),
              value: controller.data.autoMomentPosting,
              onChanged: (value) {
                controller.setAutoMomentPosting(value);
                refresh(() {});
                if (value) {
                  controller.maybeAutoPostMoment().then((error) {
                    if (mounted && error != null) uiError(context,error);
                  });
                }
              }),
            if (controller.data.autoMomentPosting)
              ListTile(title: const Text('每位 AI 的最短发布间隔'),
                subtitle: Text('${controller.data.autoMomentEveryHours} 小时'),
                trailing: DropdownButton<int>(
                  value: controller.data.autoMomentEveryHours,
                  items: const [6,12,24,48,72,168].map((hours) =>
                    DropdownMenuItem(value:hours,child:Text('$hours 小时'))).toList(),
                  onChanged: (hours) {
                    if (hours!=null) controller.setAutoMomentHours(hours);
                    refresh(() {});
                  })),
            SwitchListTile(title: const Text('AI 自动点赞和评论'),
              subtitle: const Text('默认关闭。启用后在 App 前台按随机时间检查；最多每小时 1 条动态、2 位 AI，可能产生 API 费用。'),
              value: controller.data.autoMomentInteractions,
              onChanged: (value) {
                controller.setAutoMomentInteractions(value);
                refresh(() {});
                if (value) {
                  controller.maybeAutoSocialSweep().then((error) {
                    if (mounted && error != null) uiError(context,error);
                  });
                }
              }),
            const Divider(),
            const ListTile(title: Text('各 AI 自主发帖权限'),
              subtitle: Text('每个角色均默认关闭，须同时开启总开关和该角色许可；额外调用模型可能收费。')),
            ...controller.data.characters.map((role) => FutureBuilder<bool?>(
              future: SharedPreferencesAsync().getBool('v41.roleMoment.${role.id}.enabled'),
              builder: (context, snapshot) => SwitchListTile(
                title: Text(role.name),
                subtitle: Text(role.allowMoments ? '允许按间隔自主发帖' : '尚未授权角色发朋友圈'),
                value: snapshot.data == true,
                onChanged: (enabled) async {
                  await SharedPreferencesAsync().setBool('v41.roleMoment.${role.id}.enabled',enabled);
                  if(enabled && !role.allowMoments)controller.allowMoments(role.id,true);
                  refresh(() {});
                  if (enabled && controller.data.autoMomentPosting) {
                    controller.maybeAutoPostMoment().then((error) {
                      if (mounted && error != null) uiError(context,error);
                    });
                  }
                }))),
            const Divider(),
            const ListTile(title:Text('允许哪些 AI 自主点赞和评论'),
              subtitle:Text('只有授权的角色才会收到朋友圈内容并调用原聊天模型。AI 之间的动态仍遵循已建立的好友关系。')),
            ...controller.data.characters.map((role) => SwitchListTile(
              title:Text(role.name),
              subtitle:Text(role.allowSocialInteractions
                ? '已允许参与朋友圈评论与点赞' : '不参与朋友圈自动互动'),
              value:role.allowSocialInteractions,
              onChanged:(value) {
                controller.setSocialPermission(role.id,value);
                refresh(() {});
                if(value && controller.data.autoMomentInteractions){
                  controller.maybeAutoSocialSweep().then((error){
                    if(mounted && error!=null)uiError(context,error);
                  });
                }
              },
            )),
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
    return Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (m.characterId == 'me')
            (controller.data.myAvatarPath.isNotEmpty &&
              controller.local.resolve(controller.data.myAvatarPath).existsSync()
              ? CircleAvatar(radius: 21, backgroundImage: FileImage(
                  controller.local.resolve(controller.data.myAvatarPath)))
              : const CircleAvatar(child: Icon(Icons.person)))
          else if (c != null) CharacterAvatar(character: c,
            local: controller.local, radius: 21)
          else const CircleAvatar(child: Icon(Icons.smart_toy)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.characterId == 'me' ? '我' : c?.name ?? '已删除的角色',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${m.createdAt.month}-${m.createdAt.day} ${clockTime(m.createdAt)} · 虚拟动态',
              style: Theme.of(context).textTheme.labelSmall),
          ])),
        ]),
        const SizedBox(height: 11),
        SelectableText(m.text),
        FutureBuilder<String>(future:XyMomentPhotoStore.get(m.id),builder:(ctx,snapshot){
          final path=snapshot.data??'';
          final file=path.isEmpty?null:controller.local.resolve(path);
          if(file==null||!file.existsSync())return const SizedBox.shrink();
          return Padding(padding:const EdgeInsets.only(top:9),child:ClipRRect(
            borderRadius:BorderRadius.circular(12),
            child:Image.file(file,height:240,width:double.infinity,fit:BoxFit.cover)));
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 3, alignment: WrapAlignment.start, children: [
          TextButton.icon(onPressed: () => controller.toggleMyMomentLike(m.id),
            icon: Icon(m.likedBy.contains('me') ? Icons.favorite : Icons.favorite_border,
              size: 18, color: m.likedBy.contains('me') ? Colors.redAccent : null),
            label: Text('点赞 ${m.likedBy.length}')),
          TextButton.icon(onPressed: () => _comment(m),
            icon: const Icon(Icons.mode_comment_outlined, size: 18),
            label: Text('评论 ${m.comments.length}')),
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
          Expanded(child: Text(
            '自动发动态：${controller.data.autoMomentPosting ? '已开启' : '关闭'}  ·  '
            '自动点赞评论：${controller.data.autoMomentInteractions ? '已开启' : '关闭'}',
            style: const TextStyle(fontSize: 11))),
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
    floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton.small(heroTag: 'write_moment', onPressed: _composeMine,
        tooltip: '发表我的动态', child: const Icon(Icons.edit_outlined)),
      const SizedBox(height: 9),
      FloatingActionButton.extended(heroTag: 'ai_moment', onPressed: _showOptions,
        icon: const Icon(Icons.auto_awesome), label: const Text('AI 动态')),
    ]),
  );
}

/// Organized into the three pages requested by the user; appearance data
/// continues to use the existing AppController fields and local file storage.
class SettingsScreen extends StatelessWidget {
  final AppController controller;
  const SettingsScreen({super.key,required this.controller});
  @override Widget build(BuildContext context)=>XySettingsHome(controller:controller);
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
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: music.playing ? '暂停' : '播放',
                icon: Icon(music.playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => music.togglePause().catchError((Object e) {
                  if (context.mounted) uiError(context, e);
                })),
              IconButton(tooltip: '关闭播放器', icon: const Icon(Icons.close, size: 18),
                onPressed: music.clearTrack),
            ]),
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
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(current && music.playing
                          ? Icons.pause_circle : Icons.play_circle_outline),
                      IconButton(tooltip: '从歌单删除',
                        icon: const Icon(Icons.delete_outline, size: 19),
                        onPressed: () => widget.controller.removeTrack(track.id)),
                    ]),
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

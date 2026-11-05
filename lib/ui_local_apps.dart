import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui_shell.dart';

/// Genuine offline-only virtual apps. They don't impersonate third-party apps.
class LocalNotesScreen extends StatelessWidget {
  final AppController controller;
  final String category;
  const LocalNotesScreen({super.key, required this.controller,
    required this.category});
  bool get diary => category == 'diary';

  Future<void> _edit(BuildContext context, [LocalNote? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final content = TextEditingController(text: existing?.content ?? '');
    try {
      final save = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          title: Text(existing == null ? '新建${diary ? '日记' : '备忘录'}' : '编辑内容'),
          content: SizedBox(width: 400,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
              children: [TextField(controller: title, maxLength: 80,
                decoration: const InputDecoration(labelText: '标题')),
                TextField(controller: content, minLines: 5, maxLines: 12,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: '正文'))]))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'))]));
      if (save != true) return;
      controller.upsertNote(LocalNote(id: existing?.id ?? newId(),
        category: category, title: title.text.trim().isEmpty ? '无标题' : title.text.trim(),
        content: content.text.trim(), updatedAt: DateTime.now()));
    } finally { title.dispose(); content.dispose(); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller,
    builder: (context, _) {
      final notes = controller.data.notes.where((n) => n.category == category).toList()
        ..sort((a,b) => b.updatedAt.compareTo(a.updatedAt));
      return Scaffold(appBar: AppBar(title: Text(diary ? '我的日记' : '备忘录')),
        body: notes.isEmpty
          ? Center(child: Text(diary ? '还没有日记，写下今天的故事吧' : '还没有备忘录'))
          : ListView.separated(itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final note = notes[i];
              return ListTile(leading: Icon(diary ? Icons.book_outlined : Icons.note_outlined),
                title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(note.content.isEmpty ? '暂无正文' : note.content,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _edit(ctx, note),
                trailing: PopupMenuButton<String>(tooltip: '更多',
                  onSelected: (value) {
                    if (value == 'edit') _edit(ctx, note);
                    if (value == 'delete') controller.removeNote(note.id);
                  }, itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ]));
            }),
        floatingActionButton: FloatingActionButton(onPressed: () => _edit(context),
          child: const Icon(Icons.add)));
    });
}

class LocalAlbumScreen extends StatefulWidget {
  final AppController controller;
  const LocalAlbumScreen({super.key, required this.controller});
  @override
  State<LocalAlbumScreen> createState() => _LocalAlbumScreenState();
}

class _LocalAlbumScreenState extends State<LocalAlbumScreen> {
  bool picking = false;
  Future<void> _pick() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      for (final file in picked) {
        final length = await file.length();
        if (length != null && length > 10 * 1024 * 1024) {
          if (mounted) uiError(context, '${file.name} 超过 10MB，已跳过');
          continue;
        }
        final path = await widget.controller.local.copyIntoApp(file, 'album');
        widget.controller.addAlbumPhoto(path);
      }
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => picking = false); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller,
    builder: (context, _) {
      final photos = widget.controller.data.albumPaths;
      return Scaffold(appBar: AppBar(title: const Text('我的相册'), actions: [
        IconButton(tooltip: '导入照片', onPressed: picking ? null : _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined)),
      ]), body: photos.isEmpty
        ? const Center(child: Text('相册还是空的，点击右上角导入照片'))
        : GridView.builder(padding: const EdgeInsets.all(6),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: photos.length, itemBuilder: (context, index) {
            final path = photos[index];
            final file = widget.controller.local.resolve(path);
            return GestureDetector(onTap: () => showDialog<void>(context: context,
              builder: (ctx) => Dialog(child: SizedBox(height: 440, width: 360,
                child: Column(children: [
                  if (file.existsSync()) Expanded(child: Image.file(file, fit: BoxFit.contain)),
                  TextButton.icon(onPressed: () async {
                    Navigator.pop(ctx);
                    await widget.controller.removeAlbumPhoto(path);
                  }, icon: const Icon(Icons.delete_outline), label: const Text('删除本地照片')),
                ])))),
              child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image))
                : const Icon(Icons.broken_image));
          }), floatingActionButton: FloatingActionButton(
            onPressed: picking ? null : _pick, child: const Icon(Icons.add)));
    });
}

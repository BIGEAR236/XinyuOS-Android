import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_controller.dart';

/// Opt-in AI diary/memo drafting from EXISTING role conversations.
/// Entries are stored separately in local SharedPreferences, not in the old
/// LocalNote schema (which is not part of the supplied source files).
class AiJournalPage extends StatefulWidget {
  final AppController controller;
  final String roleId;
  /// Inside XyNotebookShell: drop our own AppBar so the title shows once.
  final bool embedded;
  const AiJournalPage({super.key, required this.controller, required this.roleId,
    this.embedded = false});
  @override
  State<AiJournalPage> createState() => _AiJournalPageState();
}

class _AiJournalPageState extends State<AiJournalPage> {
  final prefs = SharedPreferencesAsync();
  final editor = TextEditingController();
  final entries = <Map<String, dynamic>>[];
  bool busy = false;
  String kind = '日记';
  String get key => 'v39.aiJournal.${widget.roleId}';

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final raw = await prefs.getString(key);
      if (raw == null) return;
      final items = (jsonDecode(raw) as List).cast<Map>();
      if (mounted) setState(() {
        entries
          ..clear()
          ..addAll(items.map((m) => Map<String, dynamic>.from(m)));
      });
    } catch (_) { /* invalid old record: keep draft untouched */ }
  }

  Future<void> generate() async {
    if (busy) return;
    final role = widget.controller.character(widget.roleId);
    if (role == null) return;
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text('让${role.name}生成$kind？'),
        content: const Text('将最近最多20条私聊文字发送给该角色已绑定的模型服务商，可能产生 API 费用。生成后先预览修改，由你决定是否保存。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意生成')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final draft = await widget.controller.generateAiCompanionNote(role, kind: kind);
      if (mounted) setState(() => editor.text = draft);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败：$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final value = editor.text.trim();
    if (value.isEmpty) return;
    final entry = <String, dynamic>{
      'type': kind, 'text': value, 'createdAt': DateTime.now().toIso8601String(),
    };
    entries.insert(0, entry);
    try {
      await prefs.setString(key, jsonEncode(entries));
      editor.clear();
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存在本机 · AI 日记备忘录')));
    } catch (e) {
      entries.remove(entry);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  void dispose() { editor.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final c = widget.controller.character(widget.roleId);
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text('${c?.name ?? '角色'} · AI 日记备忘录')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('由 AI 根据聊天生成，所有条目需你确认后才会保存。',
          style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        SegmentedButton<String>(segments: const [
          ButtonSegment(value: '日记', label: Text('日记'), icon: Icon(Icons.book_outlined)),
          ButtonSegment(value: '备忘录', label: Text('备忘录'), icon: Icon(Icons.note_alt_outlined)),
        ], selected: {kind}, onSelectionChanged: (v) => setState(() => kind = v.first)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : generate,
          icon: busy ? const SizedBox.square(dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
          label: Text(busy ? '正在生成…' : '根据最近聊天生成$kind（需调用模型）')),
        const SizedBox(height: 12),
        TextField(controller: editor, minLines: 4, maxLines: 12,
          decoration: const InputDecoration(labelText: '生成草稿（可修改）',
            border: OutlineInputBorder())),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: save,
          icon: const Icon(Icons.save_outlined), label: const Text('确认并保存在本机')),
        const Divider(height: 30),
        Text('本地存档 (${entries.length})', style: Theme.of(context).textTheme.titleMedium),
        for (final e in entries) Card(child: ExpansionTile(
          title: Text('${e['type']} · ${('${e['createdAt'] ?? ''}').split('T').first}'),
          subtitle: Text('${e['text']}', maxLines: 2, overflow: TextOverflow.ellipsis),
          children: [Padding(padding: const EdgeInsets.all(14),
            child: SelectableText('${e['text']}')),
            TextButton.icon(onPressed: () async {
              entries.remove(e);
              await prefs.setString(key, jsonEncode(entries));
              if (mounted) setState(() {});
            }, icon: const Icon(Icons.delete_outline), label: const Text('删除此条')),
          ])),
      ]),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'local_data.dart';
import 'models.dart';
import 'ui_chat.dart';
import 'ui_shell.dart';

class ApiProfileListScreen extends StatelessWidget {
  final AppController controller;
  const ApiProfileListScreen({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('API 连接台')),
    body: AnimatedBuilder(animation: controller, builder: (context, _) =>
      ListView(children: [
        const ListTile(title: Text('模型服务商'),
          subtitle: Text('真正向模型接口发送 HTTPS 请求。密钥只保存在系统安全存储区。')),
        if (controller.data.profiles.isEmpty)
          const Padding(padding: EdgeInsets.all(22),
            child: Text('目前还没有连接。点击下方按钮添加。')),
        ...controller.data.profiles.map((p) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.hub_outlined)),
          title: Text(p.label), subtitle: Text(
            '${providerFor(p.provider).label} · ${p.modelId}\n${p.baseUrl}'),
          isThreeLine: true,
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ApiProfileEditorScreen(controller: controller, initial: p))))),
      ])),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ApiProfileEditorScreen(controller: controller))),
      icon: const Icon(Icons.add), label: const Text('添加 API')),
  );
}

class ApiProfileEditorScreen extends StatefulWidget {
  final AppController controller;
  final ApiProfile? initial;
  const ApiProfileEditorScreen({super.key, required this.controller, this.initial});
  @override
  State<ApiProfileEditorScreen> createState() => _ApiProfileEditorScreenState();
}
class _ApiProfileEditorScreenState extends State<ApiProfileEditorScreen> {
  late final TextEditingController _label;
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _anthropicVersion;
  late final TextEditingController _workspaceId;
  late String _provider;
  late String _id;
  bool _testing = false;
  bool _saving = false;
  bool _hideKey = true;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _id = initial?.id ?? newId();
    _provider = initial?.provider ?? 'deepseek';
    final sample = providerFor(_provider);
    _label = TextEditingController(text: initial?.label ?? sample.label);
    _base = TextEditingController(text: initial?.baseUrl ?? sample.baseUrl);
    _model = TextEditingController(text: initial?.modelId ?? sample.exampleModel);
    _key = TextEditingController();
    _anthropicVersion = TextEditingController(
      text: initial?.anthropicVersion ?? '2026-10-21');
    _workspaceId = TextEditingController(text: initial?.workspaceId ?? '');
    if (initial != null) {
      widget.controller.getKey(initial.id).then((value) {
        if (mounted && value != null && _key.text.isEmpty) _key.text = value;
      }).catchError((Object e) { if (mounted) uiError(context, e); });
    }
  }

  @override
  void dispose() {
    _label.dispose(); _base.dispose(); _model.dispose();
    _key.clear(); _key.dispose(); _anthropicVersion.dispose();
    _workspaceId.dispose();
    super.dispose();
  }

  ApiProfile _formProfile() => ApiProfile(id: _id,
    label: _label.text.trim(), provider: _provider,
    baseUrl: _base.text.trim(), modelId: _model.text.trim(),
    anthropicVersion: _anthropicVersion.text.trim(),
    workspaceId: _workspaceId.text.trim());

  Future<void> _test() async {
    if (_testing) return;
    setState(() { _testing = true; _testResult = null; });
    try {
      final answer = await widget.controller.testConnection(_formProfile(), _key.text.trim());
      if (mounted) setState(() => _testResult = '连接成功，模型真实回复：\n$answer');
    } catch (e) {
      if (mounted) setState(() => _testResult = '连接失败：\n$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_label.text.trim().isEmpty || _model.text.trim().isEmpty ||
        _base.text.trim().isEmpty) {
      uiError(context, '请填写连接名称、Base URL 和模型 ID。'); return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveProfile(_formProfile(), apiKey: _key.text);
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? '添加 API' : '编辑 API')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('连接到模型', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      const Text('不需要自己的服务器。调用费用由你选的模型服务商收取。'),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(value: _provider,
        decoration: const InputDecoration(labelText: '服务商', border: OutlineInputBorder()),
        items: presets.map((p) => DropdownMenuItem(value: p.id,
          child: Text(p.label))).toList(),
        onChanged: (selected) {
          if (selected == null) return;
          final p = providerFor(selected);
          setState(() {
            _provider = selected;
            _label.text = p.label;
            _base.text = p.baseUrl;
            _model.text = p.exampleModel;
            _testResult = null;
          });
        }),
      const SizedBox(height: 14),
      TextField(controller: _label, decoration: const InputDecoration(
        labelText: '连接名称', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextField(controller: _base, autocorrect: false,
        decoration: const InputDecoration(labelText: 'API Base URL',
          border: OutlineInputBorder(), helperText: '仅支持 HTTPS；请只连接可信服务商')),
      const SizedBox(height: 14),
      TextField(controller: _model, autocorrect: false,
        decoration: const InputDecoration(labelText: '模型 ID',
          border: OutlineInputBorder(), helperText: '示例 ID 可能不是你的账号可用模型')),
      if (_provider == 'anthropic') ...[
        const SizedBox(height: 14),
        TextField(controller: _anthropicVersion,
          decoration: const InputDecoration(labelText: 'Anthropic API Version',
            border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(controller: _workspaceId,
          decoration: const InputDecoration(labelText: 'Workspace ID（如需）',
            border: OutlineInputBorder(),
            helperText: '未绑定工作空间的 Claude API Key 可能需要填写')),
      ],
      const SizedBox(height: 14),
      TextField(controller: _key, obscureText: _hideKey, autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: 'API Key', border: const OutlineInputBorder(),
          suffixIcon: IconButton(onPressed: () => setState(() => _hideKey = !_hideKey),
            icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off)))),
      const SizedBox(height: 18),
      OutlinedButton.icon(onPressed: _testing ? null : _test,
        icon: _testing ? const SizedBox(height: 18, width: 18,
          child: CircularProgressIndicator(strokeWidth: 2)) :
          const Icon(Icons.wifi_tethering),
        label: Text(_testing ? '正在联系真实模型…' : '测试真实连接')),
      if (_testResult != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: SelectableText(_testResult!)),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined), label: const Text('保存 API 配置')),
      const SizedBox(height: 16),
      const Text('注意：测试连接也可能消耗 token。成功后仍要去好友资料绑定此 API。'
        '聊天内容会发给你选的模型服务商；请勿输入第三方网站提供的不可信 API 地址。',
        style: TextStyle(fontSize: 12)),
    ]),
  );
}

class ContactsTab extends StatelessWidget {
  final AppController controller;
  const ContactsTab({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ListView(children: [
    ListTile(leading: const Icon(Icons.person_add_alt_1),
      title: const Text('添加 AI 好友'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        CharacterEditorScreen(controller: controller)))),
    const Divider(),
    ...controller.data.characters.map((c) => ListTile(
      leading: CharacterAvatar(character: c), title: Text(c.name),
      subtitle: Text(controller.profile(c.apiProfileId)?.label ?? '未绑定模型'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        CharacterDetailScreen(controller: controller, characterId: c.id))))),
  ]);
}

class CharacterDetailScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterDetailScreen({super.key, required this.controller,
    required this.characterId});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller,
    builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
      return Scaffold(appBar: AppBar(title: Text(c.name)),
        body: ListView(children: [
          const SizedBox(height: 20), Center(child: CharacterAvatar(character: c, radius: 45)),
          Padding(padding: const EdgeInsets.all(22), child: Text(c.persona.isEmpty ?
            '还未填写人格内容' : c.persona,
            maxLines: 8, overflow: TextOverflow.ellipsis)),
          ListTile(leading: const Icon(Icons.hub_outlined),
            title: const Text('绑定模型'),
            subtitle: Text(controller.profile(c.apiProfileId)?.label ?? '尚未绑定')),
          SwitchListTile(title: const Text('允许 AI 发布朋友圈'),
            subtitle: const Text('默认关闭；仅在你手动点击生成时产生内容'),
            value: c.allowMoments,
            onChanged: (value) => controller.allowMoments(c.id, value)),
          Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            FilledButton.icon(onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ChatScreen(controller: controller, friend: c))),
              icon: const Icon(Icons.chat_outlined), label: const Text('发消息')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => CharacterEditorScreen(controller: controller, initial: c))),
              icon: const Icon(Icons.edit_outlined), label: const Text('编辑角色 / 上传人格')),
          ])),
        ]));
    });
}

class CharacterEditorScreen extends StatefulWidget {
  final AppController controller;
  final Character? initial;
  const CharacterEditorScreen({super.key, required this.controller, this.initial});
  @override
  State<CharacterEditorScreen> createState() => _CharacterEditorScreenState();
}
class _CharacterEditorScreenState extends State<CharacterEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _persona;
  late String _boundProfile;
  late int _avatarColor;
  late bool _canPost;
  bool _loadingFile = false;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c?.name ?? '');
    _persona = TextEditingController(text: c?.persona ?? '');
    _boundProfile = c?.apiProfileId ?? '';
    _avatarColor = c?.avatarColor ?? 0xFFB67BB8;
    _canPost = c?.allowMoments ?? false;
  }
  @override
  void dispose() { _name.dispose(); _persona.dispose(); super.dispose(); }

  Future<void> _import() async {
    setState(() => _loadingFile = true);
    try {
      final text = await PersonaFileReader.pickAndRead();
      if (text != null && mounted) setState(() => _persona.text = text);
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _loadingFile = false); }
  }

  void _save() {
    if (_name.text.trim().isEmpty || _persona.text.trim().isEmpty) {
      uiError(context, '请输入名字，并填写或导入人格内容。'); return;
    }
    final c = Character(id: widget.initial?.id ?? newId(),
      name: _name.text.trim(), persona: _persona.text.trim(),
      apiProfileId: _boundProfile.isEmpty ? null : _boundProfile,
      allowMoments: _canPost, avatarColor: _avatarColor);
    widget.controller.upsertCharacter(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.controller.data.profiles;
    final selectedProfile = profiles.any((p) => p.id == _boundProfile) ? _boundProfile : '';
    return Scaffold(appBar: AppBar(title: Text(widget.initial == null ? '添加 AI 好友' : '编辑 AI 好友')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(controller: _name, decoration: const InputDecoration(
          labelText: '角色昵称', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        TextField(controller: _persona, maxLines: 9, minLines: 5,
          decoration: const InputDecoration(labelText: '人格 / 世界观 / 说话习惯',
            alignLabelWithHint: true, border: OutlineInputBorder())),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _loadingFile ? null : _import,
          icon: _loadingFile ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)) :
            const Icon(Icons.upload_file_outlined),
          label: const Text('导入 TXT / MD / JSON / DOCX')),
        const SizedBox(height: 17),
        DropdownButtonFormField<String>(value: selectedProfile,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '绑定 API 配置',
            border: OutlineInputBorder()),
          items: [const DropdownMenuItem(value: '', child: Text('暂不绑定')),
            ...profiles.map((p) => DropdownMenuItem(value: p.id,
              child: Text('${p.label} · ${p.modelId}', overflow: TextOverflow.ellipsis)))],
          onChanged: (value) => setState(() => _boundProfile = value ?? '')),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                ApiProfileEditorScreen(controller: widget.controller)));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.add), label: const Text('新建 API 连接'))),
        const Text('头像颜色', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [0xFFB67BB8, 0xFFF0A5A4, 0xFF8BA9D1,
          0xFF77B6A2, 0xFFDCAC72, 0xFFBAA0CA].map((v) => ChoiceChip(
            avatar: CircleAvatar(backgroundColor: Color(v)),
            label: v == _avatarColor ? const Icon(Icons.check, size: 16) :
              const SizedBox(width: 12),
            selected: _avatarColor == v,
            onSelected: (_) => setState(() => _avatarColor = v))).toList()),
        SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('允许发布朋友圈'),
          subtitle: const Text('默认关闭；本版只支持手动触发生成'),
          value: _canPost, onChanged: (v) => setState(() => _canPost = v)),
        const SizedBox(height: 18),
        FilledButton(onPressed: _save, child: const Text('保存到通讯录')),
      ]));
  }
}

class CreateGroupScreen extends StatefulWidget {
  final AppController controller;
  const CreateGroupScreen({super.key, required this.controller});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}
class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _name = TextEditingController(text: '新的群聊');
  final Set<String> _selected = {};
  int _maxReplies = 3;
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  void _create() {
    if (_selected.length < 2) { uiError(context, '请至少选择两位 AI 好友。'); return; }
    if (_name.text.trim().isEmpty) { uiError(context, '请填写群名称。'); return; }
    final group = ChatGroup(id: newId(), name: _name.text.trim(),
      memberIds: widget.controller.data.characters
        .where((c) => _selected.contains(c.id)).map((c) => c.id).toList(),
      maxReplies: _maxReplies);
    widget.controller.addGroup(group);
    Navigator.pop(context, group);
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('发起群聊')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _name, decoration: const InputDecoration(
        labelText: '群聊名称', border: OutlineInputBorder())),
      const SizedBox(height: 18),
      const Text('选择群成员（至少两位）', style: TextStyle(fontWeight: FontWeight.bold)),
      ...widget.controller.data.characters.map((c) => CheckboxListTile(
        secondary: CharacterAvatar(character: c),
        title: Text(c.name),
        subtitle: Text(widget.controller.profile(c.apiProfileId)?.modelId ?? '尚未配置 API'),
        value: _selected.contains(c.id), onChanged: (value) => setState(() {
          if (value == true) { _selected.add(c.id); }
          else { _selected.remove(c.id); }
        }))),
      const SizedBox(height: 18),
      Text('每轮最多 $_maxReplies 个 AI 回复'),
      Slider(min: 1, max: 6, divisions: 5,
        value: _maxReplies.toDouble(), label: '$_maxReplies',
        onChanged: (value) => setState(() => _maxReplies = value.round())),
      const Text('AI 顺序读取本群最新消息，不会无休止地互相自动回复。',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      FilledButton(onPressed: _create, child: const Text('创建群聊')),
    ]));
}

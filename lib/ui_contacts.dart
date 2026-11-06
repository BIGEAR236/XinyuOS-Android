import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'app_controller.dart';
import 'local_data.dart';
import 'models.dart';
import 'ui_chat.dart';
import 'ui_extras.dart';
import 'ui_shell.dart';
import 'intimacy/app_role_responder.dart';
import 'intimacy/pages/hub_page.dart';

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
  late bool _streaming;
  late String _authMode;
  late String _apiProtocol;
  late String _id;
  bool _listingModels = false;
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
    _streaming = initial?.streaming ?? true;
    _authMode = initial?.authMode ?? 'bearer';
    _apiProtocol = initial?.apiProtocol ?? 'chat';
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
    workspaceId: _workspaceId.text.trim(), streaming: _streaming,
    authMode: _authMode, apiProtocol: _apiProtocol);

  Future<void> _test() async {
    if (_testing) return;
    setState(() { _testing = true; _testResult = null; });
    try {
      final clock = Stopwatch()..start();
      final answer = await widget.controller.testConnection(_formProfile(), _key.text.trim());
      clock.stop();
      if (mounted) setState(() => _testResult =
        '连接成功 · ${clock.elapsedMilliseconds}ms\n模型真实回复：\n$answer');
    } catch (e) {
      if (mounted) setState(() => _testResult = '连接失败：\n$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _fetchModels() async {
    if (_listingModels) return;
    setState(() => _listingModels = true);
    final client = http.Client();
    try {
      final key = _key.text.trim().isEmpty
        ? await widget.controller.getKey(_id) ?? '' : _key.text.trim();
      final models = await MultiModelApi.listModels(
        client: client, profile: _formProfile(), apiKey: key);
      if (!mounted) return;
      final search = TextEditingController();
      try {
        final chosen = await showModalBottomSheet<String>(context: context,
          isScrollControlled: true, showDragHandle: true,
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, refresh) {
              final visible = models.where((id) => id.toLowerCase().contains(
                search.text.trim().toLowerCase())).take(250).toList();
              return SafeArea(child: SizedBox(height: MediaQuery.sizeOf(sheetContext).height * .72,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(children: [
                    Text('可用模型（${models.length}）',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(controller: search,
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                        hintText: '搜索模型 ID', border: OutlineInputBorder()),
                      onChanged: (_) => refresh(() {})),
                    const SizedBox(height: 8),
                    Expanded(child: ListView.builder(itemCount: visible.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(visible[i]), trailing: const Icon(Icons.add),
                        onTap: () => Navigator.pop(sheetContext, visible[i])))),
                    const SizedBox(height: 6),
                    const Text('模型列表来自你填写的服务商；也可以手动输入 ID。',
                      style: TextStyle(fontSize: 12)),
                  ]))));
            }));
        if (chosen != null && mounted) setState(() => _model.text = chosen);
      } finally { search.dispose(); }
    } catch (e) { if (mounted) uiError(context, e); }
    finally { client.close(); if (mounted) setState(() => _listingModels = false); }
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
            _apiProtocol = 'chat';
            _testResult = null;
          });
        }),
      const SizedBox(height: 14),
      TextField(controller: _label, decoration: const InputDecoration(
        labelText: '连接名称', border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextField(controller: _base, autocorrect: false,
        decoration: const InputDecoration(labelText: 'API Base URL',
          border: OutlineInputBorder(), helperText: '仅支持 HTTPS；请只连接可信服务商'),
        onChanged: (_) => setState(() {})),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(controller: _model, autocorrect: false,
          decoration: const InputDecoration(labelText: '模型 ID（可手动填写）',
            border: OutlineInputBorder(), helperText: '请选择或输入服务商实际支持的 ID'))),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(onPressed: _listingModels ? null : _fetchModels,
            icon: _listingModels ? const SizedBox(width: 15, height: 15,
              child: CircularProgressIndicator(strokeWidth: 2)) :
              const Icon(Icons.list_alt_outlined),
            label: const Text('获取模型'))),
      ]),
      if (_provider == 'custom') ...[
        const SizedBox(height: 8),
        const Text('中转站常用 HTTPS 地址填写到 /v1；也可填写完整 /chat/completions 或 /responses 路径。'
          '如果中转站的模型接口并不兼容所选协议，依然可能请求失败。'
          '注意：中转站会接收你的 API Key 和聊天内容。',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _apiProtocol,
          decoration: const InputDecoration(labelText: '中转站 API 协议',
            border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'chat', child: Text('OpenAI Chat Completions')),
            DropdownMenuItem(value: 'responses', child: Text('OpenAI Responses API')),
          ], onChanged: (v) => setState(() => _apiProtocol = v ?? 'chat')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: _authMode,
          decoration: const InputDecoration(labelText: '中转站认证方式',
            border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'bearer', child: Text('Authorization: Bearer（常用）')),
            DropdownMenuItem(value: 'x-api-key', child: Text('x-api-key（部分中转站）')),
          ], onChanged: (v) => setState(() => _authMode = v ?? 'bearer')),
      ],
      const SizedBox(height: 4),
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('边生成边显示（流式回复）'),
        subtitle: const Text('大幅改善等待体验；少数中转站不兼容时可关闭'),
        value: _streaming,
        onChanged: (value) => setState(() => _streaming = value)),
      Padding(padding: const EdgeInsets.only(bottom: 8),
        child: Text(() {
          try { return '请求路径：${MultiModelApi.previewEndpoint(_formProfile())}'; }
          catch (_) { return '检查 Base URL 后会显示实际请求路径'; }
        }(), style: const TextStyle(fontSize: 11, color: Colors.grey))),
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
      leading: CharacterAvatar(character: c, local: controller.local), title: Text(c.name),
      subtitle: Text(controller.profile(c.apiProfileId)?.label ?? '未绑定模型'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
        CharacterDetailScreen(controller: controller, characterId: c.id))))),
  ]);
}

/// Compact contact hub and separate settings screens. The long persona document is
/// deliberately not displayed on the contact landing page.
class CharacterDetailScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterDetailScreen({super.key, required this.controller,
    required this.characterId});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(
        body: Center(child: Text('角色不存在')));
      final relatedCount = controller.data.characters.where(
        (other) => controller.areFriends(c.id, other.id)).length;
      final momentsCount = controller.data.moments.where(
        (moment) => moment.characterId == c.id).length;
      final model = controller.profile(c.apiProfileId);
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        appBar: AppBar(title: const Text('好友资料')),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 18, 14, 26),
          children: [
            Container(padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(17)),
              child: Row(children: [
                CharacterAvatar(character: c, local: controller.local,
                  radius: 35),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontSize: 23,
                    fontWeight: FontWeight.w600), maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(c.intro.isEmpty ? '还没有填写个人介绍' : c.intro,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ])),
              ])),
            const SizedBox(height: 16),
            Card(margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                _section(context, Icons.badge_outlined, '个人信息',
                  '昵称、头像、介绍和人格文件',
                  () => _open(context, CharacterBasicInfoScreen(
                    controller: controller, characterId: c.id))),
                const Divider(height: 1, indent: 57),
                _section(context, Icons.hub_outlined, '模型绑定',
                  model == null ? '未绑定模型' : '${model.label} · ${model.modelId}',
                  () => _open(context, CharacterModelBindingScreen(
                    controller: controller, characterId: c.id))),
                const Divider(height: 1, indent: 57),
                _section(context, Icons.people_outline, '添加好友关系',
                  '已关联 $relatedCount 位 AI 好友',
                  () => _open(context, CharacterFriendshipsScreen(
                    controller: controller, characterId: c.id))),
                const Divider(height: 1, indent: 57),
                _section(context, Icons.camera_alt_outlined, '朋友圈',
                  '$momentsCount 条动态 · 管理权限与查看朋友圈',
                  () => _open(context, CharacterMomentsScreen(
                    controller: controller, characterId: c.id))),
                const Divider(height: 1, indent: 57),
                _section(context, Icons.wallpaper_outlined, '聊天背景',
                  c.chatBackgroundPath.isEmpty ? '使用默认背景' : '已设置专属图片',
                  () => _open(context, CharacterChatBackgroundScreen(
                    controller: controller, characterId: c.id))),
                const Divider(height: 1, indent: 57),
                _section(context, Icons.favorite_border_rounded, '亲密互动',
                  '共同养宠 · 一起听歌 · 看视频 · 玩游戏',
                  () => _open(context, CompanionHub(
                    roleId: c.id, roleName: c.name, persona: c.persona,
                    responder: controller.profile(c.apiProfileId) == null
                        ? null : AppRoleResponder(controller)))),
              ])),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _open(context, ChatScreen(
                controller: controller, friend: c)),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('发消息')),
          ]),
      );
    });

  Widget _section(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    leading: Icon(icon, size: 22), title: Text(title),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right_rounded, size: 19),
    onTap: onTap,
  );
}

class CharacterBasicInfoScreen extends StatefulWidget {
  final AppController controller;
  final String characterId;
  const CharacterBasicInfoScreen({super.key, required this.controller,
    required this.characterId});
  @override
  State<CharacterBasicInfoScreen> createState() => _CharacterBasicInfoScreenState();
}

class _CharacterBasicInfoScreenState extends State<CharacterBasicInfoScreen> {
  late final TextEditingController _name;
  late final TextEditingController _intro;
  late String _persona;
  late String _avatarPath;
  bool _choosing = false;

  @override
  void initState() {
    super.initState();
    final c = widget.controller.character(widget.characterId)!;
    _name = TextEditingController(text: c.name);
    _intro = TextEditingController(text: c.intro);
    _persona = c.persona;
    _avatarPath = c.avatarPath;
  }

  @override
  void dispose() { _name.dispose(); _intro.dispose(); super.dispose(); }

  Future<void> _chooseAvatar() async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final fileSize = await file.length();
      if (fileSize != null && fileSize > 8 * 1024 * 1024) {
        throw const FormatException('头像不能超过 8MB');
      }
      final path = await widget.controller.local.copyIntoApp(file, 'avatars');
      final savedFile = widget.controller.local.resolve(path);
      if (await savedFile.length() > 8 * 1024 * 1024) {
        await savedFile.delete();
        throw const FormatException('头像不能超过 8MB');
      }
      if (mounted) setState(() => _avatarPath = path);
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _choosing = false); }
  }

  Future<void> _editPersona() async {
    final text = TextEditingController(text: _persona);
    try {
      final next = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('人格文件'), actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, text.text),
              child: const Text('完成')),
          ]),
          body: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text('人格和剧情文本只在此处编辑，好友资料首页不会直接展示全文。'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final imported = await PersonaFileReader.pickAndRead();
                    if (imported != null) text.text = imported;
                  } catch (e) { if (ctx.mounted) uiError(ctx, e); }
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('重新导入 TXT / MD / JSON / DOCX')),
              const SizedBox(height: 10),
              Expanded(child: TextField(controller: text, expands: true,
                minLines: null, maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: '角色与剧情设定'))),
            ]))))));
      if (mounted && next != null) setState(() => _persona = next);
    } finally { text.dispose(); }
  }

  void _save() {
    if (_name.text.trim().isEmpty || _persona.trim().isEmpty) {
      uiError(context, '昵称和人格文件不能留空'); return;
    }
    widget.controller.updateCharacterIntro(widget.characterId,
      name: _name.text, intro: _intro.text,
      persona: _persona, avatarPath: _avatarPath);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller.character(widget.characterId);
    if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
    final img = _avatarPath.isEmpty ? null :
      widget.controller.local.resolve(_avatarPath);
    return Scaffold(appBar: AppBar(title: const Text('个人信息')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Center(child: Column(children: [
          ClipOval(child: img != null && img.existsSync()
            ? Image.file(img, width: 78, height: 78, fit: BoxFit.cover)
            : CircleAvatar(radius: 39, backgroundColor: Color(c.avatarColor),
                child: const Icon(Icons.person, color: Colors.white, size: 36))),
          const SizedBox(height: 9),
          TextButton.icon(onPressed: _choosing ? null : _chooseAvatar,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('更换头像')),
        ])),
        const SizedBox(height: 15),
        TextField(controller: _name, maxLength: 40,
          decoration: const InputDecoration(labelText: '昵称',
            border: OutlineInputBorder())),
        const SizedBox(height: 13),
        TextField(controller: _intro, maxLength: 160, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: '个人介绍',
            hintText: '一句简短的角色介绍', border: OutlineInputBorder())),
        const SizedBox(height: 13),
        ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('人格与剧情文件'),
          subtitle: Text('已保存 ${_persona.length} 个字符，点击单独编辑'),
          trailing: const Icon(Icons.chevron_right), onTap: _editPersona),
        const SizedBox(height: 22),
        FilledButton(onPressed: _save, child: const Text('保存个人信息')),
      ]));
  }
}

class CharacterModelBindingScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterModelBindingScreen({super.key, required this.controller,
    required this.characterId});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
      return Scaffold(appBar: AppBar(title: const Text('模型绑定')),
        body: ListView(children: [
          const ListTile(title: Text('这个好友使用哪个模型？'),
            subtitle: Text('修改绑定不会删除原有人格和聊天记录。')),
          RadioListTile<String>(title: const Text('暂不绑定'),
            value: '', groupValue: c.apiProfileId ?? '',
            onChanged: (_) => controller.bindCharacterModel(c.id, null)),
          ...controller.data.profiles.map((p) => RadioListTile<String>(
            title: Text(p.label), subtitle: Text(p.modelId),
            value: p.id, groupValue: c.apiProfileId ?? '',
            onChanged: (_) => controller.bindCharacterModel(c.id, p.id))),
          const Divider(),
          ListTile(leading: const Icon(Icons.add_circle_outline),
            title: const Text('添加新的 API 连接'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ApiProfileEditorScreen(controller: controller)))),
        ]));
    });
}

class CharacterFriendshipsScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterFriendshipsScreen({super.key, required this.controller,
    required this.characterId});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
      return Scaffold(appBar: AppBar(title: const Text('AI 好友关系')),
        body: ListView(children: [
          const ListTile(title: Text('相互认识的角色'),
            subtitle: Text('建立双向好友关系后，角色才能看到对方允许公开的虚拟朋友圈。')),
          ...controller.data.characters.where((o) => o.id != c.id).map((other) =>
            SwitchListTile(
              secondary: CharacterAvatar(character: other,
                local: controller.local, radius: 19),
              title: Text(other.name),
              value: controller.areFriends(c.id, other.id),
              onChanged: (v) => controller.setFriendship(c.id, other.id, v))),
          if (controller.data.characters.length < 2)
            const ListTile(title: Text('还没有其他角色可以建立关系')),
        ]));
    });
}

class CharacterMomentsScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterMomentsScreen({super.key, required this.controller,
    required this.characterId});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
      final entries = controller.data.moments.where((m) =>
        m.characterId == c.id).toList().reversed.toList();
      return Scaffold(appBar: AppBar(title: const Text('朋友圈')),
        body: ListView(children: [
          SwitchListTile(title: const Text('允许发布朋友圈'),
            subtitle: const Text('默认关闭；需要手动触发生成'),
            value: c.allowMoments,
            onChanged: (v) => controller.allowMoments(c.id, v)),
          SwitchListTile(title: const Text('允许点赞、评论与回复'),
            subtitle: const Text('默认关闭；仅按已授权的好友关系互动'),
            value: c.allowSocialInteractions,
            onChanged: (v) => controller.setSocialPermission(c.id, v)),
          const Divider(),
          ListTile(title: const Text('这个角色的动态'),
            subtitle: Text('共 ${entries.length} 条')),
          if (entries.isEmpty)
            const ListTile(title: Text('还没有发布过动态')),
          ...entries.map((m) => ListTile(
            title: Text(m.text, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text('${m.createdAt.year}-${m.createdAt.month}-${m.createdAt.day} · '
              '${m.likedBy.length} 赞 · ${m.comments.length} 评论'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text('${c.name}的朋友圈')),
                body: MomentsTab(controller: controller)))))),
          const Divider(),
          ListTile(leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('打开朋友圈互动页面'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(title: const Text('朋友圈')),
                body: MomentsTab(controller: controller))))),
        ]));
    });
}

class CharacterChatBackgroundScreen extends StatelessWidget {
  final AppController controller;
  final String characterId;
  const CharacterChatBackgroundScreen({super.key, required this.controller,
    required this.characterId});

  Future<void> _pick(BuildContext context) async {
    try {
      final image = await FilePicker.pickFile(type: FileType.image);
      if (image == null) return;
      final imageSize = await image.length();
      if (imageSize != null && imageSize > 12 * 1024 * 1024) {
        throw const FormatException('聊天背景不能超过 12MB');
      }
      final relative = await controller.local.copyIntoApp(image, 'chat_backgrounds');
      final savedImage = controller.local.resolve(relative);
      if (await savedImage.length() > 12 * 1024 * 1024) {
        await savedImage.delete();
        throw const FormatException('聊天背景不能超过 12MB');
      }
      controller.setCharacterBackground(characterId, relative);
      if (context.mounted) uiError(context, '已保存这个好友的专属聊天背景');
    } catch (e) { if (context.mounted) uiError(context, e); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final c = controller.character(characterId);
      if (c == null) return const Scaffold(body: Center(child: Text('角色不存在')));
      final image = c.chatBackgroundPath.isNotEmpty ?
        controller.local.resolve(c.chatBackgroundPath) : null;
      return Scaffold(appBar: AppBar(title: const Text('聊天背景')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(borderRadius: BorderRadius.circular(15),
            child: Container(height: 260,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: image != null && image.existsSync()
                ? Image.file(image, fit: BoxFit.cover)
                : const Center(child: Text('默认聊天背景')))),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: () => _pick(context),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从手机选择图片')),
          if (c.chatBackgroundPath.isNotEmpty)
            TextButton(onPressed: () => controller.setCharacterBackground(c.id, ''),
              child: const Text('恢复默认背景')),
          const SizedBox(height: 15),
          Text('背景可见度 ${(c.chatBackgroundOpacity * 100).round()}%'),
          Slider(min: .05, max: 1.0, divisions: 19,
            value: c.chatBackgroundOpacity,
            onChanged: (value) => controller.setCharacterBackgroundOpacity(c.id, value)),
          const SizedBox(height: 15),
          const Text('只修改与当前角色的私聊背景，不会更换虚拟手机壁纸，'
            '也不会影响其他 AI 好友。'),
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
  late String _avatarPath;
  bool _importingAvatar = false;
  late bool _canPost;
  late bool _canInteract;
  bool _loadingFile = false;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c?.name ?? '');
    _persona = TextEditingController(text: c?.persona ?? '');
    _boundProfile = c?.apiProfileId ?? '';
    _avatarColor = c?.avatarColor ?? 0xFFB67BB8;
    _avatarPath = c?.avatarPath ?? '';
    _canPost = c?.allowMoments ?? false;
    _canInteract = c?.allowSocialInteractions ?? false;
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

  Future<void> _chooseAvatar() async {
    if (_importingAvatar) return;
    setState(() => _importingAvatar = true);
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 8 * 1024 * 1024) {
        throw const FormatException('头像图片不能超过 8MB。');
      }
      final relative = await widget.controller.local.copyIntoApp(file, 'avatars');
      final saved = widget.controller.local.resolve(relative);
      if (await saved.length() > 8 * 1024 * 1024) {
        await saved.delete();
        throw const FormatException('头像文件不能超过 8MB。');
      }
      if (mounted) setState(() => _avatarPath = relative);
    } catch (e) { if (mounted) uiError(context, e); }
    finally { if (mounted) setState(() => _importingAvatar = false); }
  }

  void _save() {
    if (_name.text.trim().isEmpty || _persona.text.trim().isEmpty) {
      uiError(context, '请输入名字，并填写或导入人格内容。'); return;
    }
    final c = Character(id: widget.initial?.id ?? newId(),
      name: _name.text.trim(), persona: _persona.text.trim(),
      apiProfileId: _boundProfile.isEmpty ? null : _boundProfile,
      allowMoments: _canPost, allowSocialInteractions: _canInteract,
      allowProactiveMessages: widget.initial?.allowProactiveMessages ?? false,
      friendIds: widget.initial?.friendIds ?? const [], avatarColor: _avatarColor,
      avatarPath: _avatarPath,
      intro: widget.initial?.intro ?? '',
      chatBackgroundPath: widget.initial?.chatBackgroundPath ?? '',
      chatBackgroundOpacity: widget.initial?.chatBackgroundOpacity ?? .38);
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
        const Text('角色头像', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(children: [
          if (_avatarPath.isNotEmpty &&
              widget.controller.local.resolve(_avatarPath).existsSync())
            ClipOval(child: Image.file(File(widget.controller.local.resolve(_avatarPath).path),
              width: 58, height: 58, fit: BoxFit.cover))
          else CircleAvatar(radius: 29, backgroundColor: Color(_avatarColor),
            child: const Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(onPressed: _importingAvatar ? null : _chooseAvatar,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_importingAvatar ? '正在导入…' : '从手机选择头像'))),
          if (_avatarPath.isNotEmpty) IconButton(
            tooltip: '移除自定义头像',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _avatarPath = '')),
        ]),
        const SizedBox(height: 12),
        const Text('备用头像颜色', style: TextStyle(fontWeight: FontWeight.bold)),
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
        SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('允许朋友圈点赞与评论'),
          subtitle: const Text('默认关闭；仅对好友、经手动触发或打开自动回复时生效'),
          value: _canInteract, onChanged: (v) => setState(() => _canInteract = v)),
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
        secondary: CharacterAvatar(character: c, local: widget.controller.local),
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
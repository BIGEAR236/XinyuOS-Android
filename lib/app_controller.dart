import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'local_data.dart';
import 'models.dart';

class AppController extends ChangeNotifier {
  final LocalData local;
  final FlutterSecureStorage _keys = const FlutterSecureStorage();
  AppData data;
  Future<void> _writes = Future<void>.value();
  final Set<String> busy = {};
  final Set<String> _stopped = {};
  final Map<String, http.Client> _clients = {};
  String? persistenceError;

  AppController(this.local, this.data);
  static Future<AppController> create() async {
    final local = await LocalData.open();
    return AppController(local, await local.load());
  }

  void _changed() {
    notifyListeners();
    final snapshot = data.serialize();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        await local.persist(snapshot);
        persistenceError = null;
      } catch (e) {
        persistenceError = '本地保存失败：$e';
        notifyListeners();
      }
    });
  }

  Future<void> flush() => _writes;

  Character? character(String id) {
    for (final c in data.characters) { if (c.id == id) return c; }
    return null;
  }

  ApiProfile? profile(String? id) {
    if (id == null) return null;
    for (final p in data.profiles) { if (p.id == id) return p; }
    return null;
  }

  String displayName(String senderId) {
    if (senderId == 'me') return '我';
    if (senderId == 'system') return '系统';
    return character(senderId)?.name ?? '已删除角色';
  }

  String? latestText(String threadId) {
    for (final entry in data.messages.reversed) {
      if (entry.threadId == threadId) return entry.text;
    }
    return null;
  }

  List<ChatEntry> threadMessages(String threadId) =>
      data.messages.where((e) => e.threadId == threadId).toList();

  Future<String?> getKey(String profileId) =>
      _keys.read(key: 'api_key_$profileId');

  Future<void> saveProfile(ApiProfile p, {String? apiKey}) async {
    final existing = profile(p.id);
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _keys.write(key: 'api_key_${p.id}', value: apiKey.trim());
    }
    if (existing == null) {
      data.profiles.add(p);
    } else {
      existing.label = p.label;
      existing.provider = p.provider;
      existing.baseUrl = p.baseUrl;
      existing.modelId = p.modelId;
      existing.anthropicVersion = p.anthropicVersion;
      existing.workspaceId = p.workspaceId;
    }
    _changed();
  }

  Future<String> testConnection(ApiProfile profile, String key) async {
    final client = http.Client();
    try {
      return await MultiModelApi.call(client: client, profile: profile,
        apiKey: key, persona: '你是 API 连通性测试程序。',
        turns: [const ModelTurn('user', '连接测试：请用一句简短的中文回答。')]);
    } finally { client.close(); }
  }

  void upsertCharacter(Character c) {
    final index = data.characters.indexWhere((item) => item.id == c.id);
    if (index == -1) { data.characters.add(c); }
    else { data.characters[index] = c; }
    _changed();
  }

  void allowMoments(String id, bool value) {
    final c = character(id);
    if (c == null) return;
    c.allowMoments = value;
    _changed();
  }

  void addGroup(ChatGroup g) { data.groups.add(g); _changed(); }

  void setGroupMaxReplies(String groupId, int replies) {
    for (final group in data.groups) {
      if (group.id == groupId) {
        group.maxReplies = replies.clamp(1, 6).toInt();
        _changed();
        return;
      }
    }
  }

  void changeAppearance({bool? dark, int? color, double? scale, String? wallpaper}) {
    if (dark != null) data.darkMode = dark;
    if (color != null) data.themeColor = color;
    if (scale != null) data.fontScale = scale;
    if (wallpaper != null) data.wallpaperPath = wallpaper;
    _changed();
  }

  void addTrack(LocalTrack t) { data.tracks.add(t); _changed(); }

  void stop(String threadId) {
    _stopped.add(threadId);
    _clients.remove(threadId)?.close();
    notifyListeners();
  }

  List<ModelTurn> _turns(String threadId, String aiId, {bool group = false}) {
    final entries = threadMessages(threadId)
        .where((m) => m.senderId != 'system').toList();
    final recent = entries.length > 20 ? entries.sublist(entries.length - 20) : entries;
    return recent.map((entry) => ModelTurn(
      entry.senderId == aiId ? 'assistant' : 'user',
      group ? '${displayName(entry.senderId)}：${entry.text}' : entry.text,
    )).toList();
  }

  void _addMessage(String thread, String sender, String text) {
    data.messages.add(ChatEntry(id: newId(), threadId: thread, senderId: sender,
      text: text, createdAt: DateTime.now()));
    _changed();
  }

  Future<String?> sendPrivate(Character c, String text) async {
    final thread = privateThread(c.id);
    if (busy.contains(thread)) return '上一条回复仍在生成中。';
    final p = profile(c.apiProfileId);
    if (p == null) return '请先在好友资料中绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '此 API 配置没有密钥，请先补充密钥。';
    _addMessage(thread, 'me', text);
    _stopped.remove(thread);
    busy.add(thread);
    notifyListeners();
    final client = http.Client();
    _clients[thread] = client;
    try {
      final answer = await MultiModelApi.call(client: client, profile: p,
        apiKey: key, persona: c.persona,
        turns: _turns(thread, c.id));
      if (!_stopped.contains(thread)) _addMessage(thread, c.id, answer);
      return null;
    } catch (e) {
      if (_stopped.contains(thread)) return null;
      return '$e';
    } finally {
      client.close();
      _clients.remove(thread);
      busy.remove(thread);
      _stopped.remove(thread);
      notifyListeners();
    }
  }

  Future<String?> sendGroup(ChatGroup group, String text) async {
    final thread = groupThread(group.id);
    if (busy.contains(thread)) return '当前群聊正在生成回复。';
    _addMessage(thread, 'me', text);
    _stopped.remove(thread);
    busy.add(thread);
    notifyListeners();
    var replied = 0;
    final failures = <String>[];
    try {
      for (final characterId in group.memberIds) {
        if (_stopped.contains(thread) || replied >= group.maxReplies) break;
        final c = character(characterId);
        if (c == null) continue;
        final p = profile(c.apiProfileId);
        if (p == null) { failures.add('${c.name}未绑定 API'); continue; }
        final key = await getKey(p.id);
        if (key == null || key.isEmpty) { failures.add('${c.name}缺少 API Key'); continue; }
        if (_stopped.contains(thread)) break;
        final client = http.Client();
        _clients[thread] = client;
        try {
          final answer = await MultiModelApi.call(client: client,
            profile: p, apiKey: key, persona: c.persona,
            turns: _turns(thread, c.id, group: true), group: true);
          if (!_stopped.contains(thread)) {
            _addMessage(thread, c.id, answer);
            replied++;
          }
        } catch (e) {
          if (!_stopped.contains(thread)) failures.add('${c.name}: $e');
        } finally {
          client.close();
          if (identical(_clients[thread], client)) _clients.remove(thread);
        }
      }
      return failures.isEmpty ? null : failures.join('\n');
    } finally {
      _clients.remove(thread)?.close();
      busy.remove(thread);
      _stopped.remove(thread);
      notifyListeners();
    }
  }

  Future<String?> generateMoment(Character c) async {
    if (!c.allowMoments) return '尚未授权该角色发朋友圈。';
    final thread = 'moment:${c.id}';
    if (busy.contains(thread)) return '该角色正在生成动态。';
    final p = profile(c.apiProfileId);
    if (p == null) return '先给该角色绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return 'API 密钥尚未配置。';
    busy.add(thread); notifyListeners();
    final client = http.Client();
    _clients[thread] = client;
    try {
      final text = await MultiModelApi.call(client: client,
        profile: p, apiKey: key, persona: c.persona,
        turns: [const ModelTurn('user',
          '请以当前角色第一人称写一条不超过 100 字的虚拟朋友圈动态。'
          '符合性格，不要冒充在现实中做过未经证实的事。只输出正文。')]);
      if (c.allowMoments && !_stopped.contains(thread)) {
        data.moments.insert(0, MomentEntry(id: newId(),
          characterId: c.id, text: text, createdAt: DateTime.now()));
        _changed();
      }
      return null;
    } catch (e) { return '$e'; }
    finally {
      client.close(); _clients.remove(thread);
      busy.remove(thread); _stopped.remove(thread); notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final client in _clients.values) { client.close(); }
    super.dispose();
  }
}

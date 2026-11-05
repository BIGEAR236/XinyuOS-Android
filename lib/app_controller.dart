import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'local_data.dart';
import 'models.dart';
import 'music_controller.dart';
import 'proactive_service.dart';

class AppController extends ChangeNotifier {
  final LocalData local;
  final FlutterSecureStorage _keys = const FlutterSecureStorage();
  AppData data;
  late final MusicController music;
  final Map<String, String> partialReplies = {};
  final Map<String, String> partialSenders = {};
  final Map<String, DateTime> _lastPartialPaint = {};
  Future<void> _writes = Future<void>.value();
  final Set<String> busy = {};
  final Set<String> _stopped = {};
  final Map<String, http.Client> _clients = {};
  String? persistenceError;
  bool _proactiveRunning = false;
  DateTime? _lastProactiveCheck;


  AppController(this.local, this.data) { music = MusicController(local); }
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
      existing.streaming = p.streaming;
      existing.authMode = p.authMode;
      existing.apiProtocol = p.apiProtocol;
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

  void updateCharacterIntro(String id, {required String name,
      required String intro, required String persona, required String avatarPath}) {
    final c = character(id);
    if (c == null) return;
    c.name = name.trim();
    c.intro = intro.trim();
    c.persona = persona;
    c.avatarPath = avatarPath;
    _changed();
  }

  void bindCharacterModel(String id, String? profileId) {
    final c = character(id);
    if (c == null) return;
    c.apiProfileId = profileId;
    _changed();
  }

  void setCharacterBackground(String id, String relativePath) {
    final c = character(id);
    if (c == null) return;
    c.chatBackgroundPath = relativePath;
    _changed();
  }

  void reorderDesktopIcon(String dragged, String target) {
    if (dragged == target || !defaultDesktopOrder.contains(dragged) ||
        !defaultDesktopOrder.contains(target)) return;
    final order = normalizeDesktopOrder(data.desktopOrder);
    order.remove(dragged);
    order.insert(order.indexOf(target), dragged);
    data.desktopOrder = order;
    _changed();
  }

  void resetDesktopOrder() {
    data.desktopOrder = [...defaultDesktopOrder];
    _changed();
  }

  void setSocialPermission(String id, bool value) {
    final c = character(id);
    if (c == null) return;
    c.allowSocialInteractions = value;
    _changed();
  }

  bool areFriends(String aId, String bId) {
    if (aId == bId) return false;
    final a = character(aId), b = character(bId);
    return a != null && b != null &&
      a.friendIds.contains(bId) && b.friendIds.contains(aId);
  }

  void setFriendship(String aId, String bId, bool connected) {
    if (aId == bId) return;
    final a = character(aId), b = character(bId);
    if (a == null || b == null) return;
    a.friendIds = {...a.friendIds, if (connected) bId}.toList()..removeWhere(
      (id) => !connected && id == bId);
    b.friendIds = {...b.friendIds, if (connected) aId}.toList()..removeWhere(
      (id) => !connected && id == aId);
    _changed();
  }

  void setAutoMomentReplies(bool enabled) {
    data.autoMomentReplies = enabled;
    _changed();
  }

  void setAutoMomentInteractions(bool enabled) {
    data.autoMomentInteractions = enabled;
    _changed();
  }

  /// Foreground-only, opt-in, max one post / two AI calls per 60 minutes.
  /// Never schedules tasks or invokes itself from generated AI comments.
  Future<String?> maybeAutoSocialSweep() async {
    if (!data.autoMomentInteractions || data.moments.isEmpty) return null;
    final now = DateTime.now();
    final last = data.lastAutoInteractionAt;
    if (last != null && now.difference(last) < const Duration(hours: 1)) return null;
    MomentEntry? eligible;
    for (final m in data.moments) {
      if (socialAudience(m).any((c) => c.allowSocialInteractions &&
          !m.likedBy.contains(c.id) &&
          !m.comments.any((cm) => cm.authorId == c.id && cm.parentId == null))) {
        eligible = m;
        break;
      }
    }
    if (eligible == null) return null;
    data.lastAutoInteractionAt = now;
    _changed();
    return inviteMomentInteractions(eligible.id);
  }

  void setChatMode(String value) {
    data.chatMode = value == 'story' ? 'story' : 'daily';
    _changed();
  }

  Future<void> setAllowProactive(bool value) async {
    data.allowProactiveMessages = value;
    _changed();
    for (final event in data.proactiveEvents) {
      if (value && !event.delivered &&
          character(event.characterId)?.allowProactiveMessages == true) {
        await ProactiveNotificationService.schedule(event,
          displayName(event.characterId));
      } else {
        await ProactiveNotificationService.cancel(event.id);
      }
    }
  }

  Future<void> setCharacterProactive(String characterId, bool value) async {
    final c = character(characterId);
    if (c == null) return;
    c.allowProactiveMessages = value;
    _changed();
    for (final event in data.proactiveEvents.where((e) =>
        e.characterId == characterId && !e.delivered)) {
      if (value && data.allowProactiveMessages) {
        await ProactiveNotificationService.schedule(event, c.name);
      } else {
        await ProactiveNotificationService.cancel(event.id);
      }
    }
  }

  Future<void> addProactiveEvent(ProactiveEvent event) async {
    data.proactiveEvents.add(event);
    _changed();
    if (data.allowProactiveMessages &&
        character(event.characterId)?.allowProactiveMessages == true) {
      await ProactiveNotificationService.schedule(event,
        displayName(event.characterId));
    }
  }

  Future<void> removeProactiveEvent(String id) async {
    data.proactiveEvents.removeWhere((e) => e.id == id);
    _changed();
    await ProactiveNotificationService.cancel(id);
  }

  void clearLocalChatHistory() {
    if (busy.isNotEmpty) return;
    data.messages.clear();
    _changed();
  }

  void clearThreadHistory(String threadId) {
    if (busy.contains(threadId)) return;
    data.messages.removeWhere((m) => m.threadId == threadId);
    _changed();
  }

  /// Only when foreground / app opened. Never runs LLM requests autonomously
  /// while killed. Scheduled OS notification is a static event reminder.
  Future<void> processDueEvents() async {
    if (_proactiveRunning || !data.allowProactiveMessages) return;
    final now = DateTime.now();
    if (_lastProactiveCheck != null &&
        now.difference(_lastProactiveCheck!) < const Duration(seconds: 25)) return;
    _lastProactiveCheck = now;
    final candidates = data.proactiveEvents.where((e) => !e.delivered &&
      !e.dueAt.isAfter(now) && now.difference(e.dueAt) < const Duration(days: 3) &&
      (e.lastAttemptAt == null ||
        now.difference(e.lastAttemptAt!) > const Duration(minutes: 30))).toList();
    if (candidates.isEmpty) return;
    final ev = candidates.first;
    final c = character(ev.characterId);
    if (c == null || !c.allowProactiveMessages) return;
    final p = profile(c.apiProfileId);
    if (p == null) return;
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return;
    final thread = privateThread(c.id);
    if (busy.contains(thread)) return;
    _proactiveRunning = true;
    ev.lastAttemptAt = now;
    _changed();
    busy.add(thread); notifyListeners();
    final client = http.Client(); _clients[thread] = client;
    try {
      final previous = _turns(thread, c.id);
      final note = ModelTurn('user',
        '这是用户曾授权你在此时主动关心的待办事件。主题：「${ev.topic}」。'
        '原定日期：${ev.dueAt.year}-${ev.dueAt.month}-${ev.dueAt.day}。'
        '现在日期：${now.year}-${now.month}-${now.day}。'
        '你是${c.name}。请只生成一条贴合实际时间和上文的简短自然关心消息，'
        '不要假装对方已经参加比赛或你知道比赛结果，最多45字。'
        '不要引用角色档案或写括号动作。');
      final answer = await MultiModelApi.call(client: client,
        profile: p, apiKey: key, persona: c.persona, roleName: c.name,
        chatMode: 'daily', turns: [...previous, note]);
      if (answer.trim().isNotEmpty) {
        _addMessage(thread, c.id, answer.trim());
        ev.delivered = true;
        _changed();
      }
    } catch (_) {
      // Keep event pending; retry only after cooldown and once app is opened.
    } finally {
      client.close(); _clients.remove(thread);
      busy.remove(thread); _proactiveRunning = false; notifyListeners();
    }
  }

  void setChatStyle({double? opacity, int? mine, int? theirs, bool? showTime}) {
    if (opacity != null) data.chatBubbleOpacity = opacity.clamp(.35, 1.0).toDouble();
    if (mine != null) data.myBubbleColor = mine;
    if (theirs != null) data.aiBubbleColor = theirs;
    if (showTime != null) data.showChatTime = showTime;
    _changed();
  }

  void allowMoments(String id, bool value) {
    final c = character(id);
    if (c == null) return;
    c.allowMoments = value;
    _changed();
  }

  MomentEntry? moment(String id) {
    for (final m in data.moments) { if (m.id == id) return m; }
    return null;
  }

  bool toggleMyMomentLike(String momentId) {
    final m = moment(momentId);
    if (m == null) return false;
    if (m.likedBy.contains('me')) {
      m.likedBy = [...m.likedBy]..remove('me');
    } else {
      m.likedBy = [...m.likedBy, 'me'];
    }
    _changed();
    return true;
  }

  MomentComment? addMyMomentComment(String momentId, String text,
      {String? parentId}) {
    final m = moment(momentId);
    if (m == null || text.trim().isEmpty || text.trim().length > 300) return null;
    if (parentId != null && !m.comments.any((c) => c.id == parentId)) return null;
    final comment = MomentComment(id: newId(), authorId: 'me',
      text: text.trim(), createdAt: DateTime.now(), parentId: parentId);
    m.comments = [...m.comments, comment];
    _changed();
    return comment;
  }

  List<Character> socialAudience(MomentEntry m) => data.characters.where((c) =>
    c.id != m.characterId && areFriends(c.id, m.characterId)).toList();

  /// Manually invoked: each eligible AI decides whether to like or comment.
  /// Never loops on its own: maximum two model calls for a user action.
  Future<String?> inviteMomentInteractions(String momentId) async {
    final m = moment(momentId);
    if (m == null) return '动态已被删除。';
    final thread = 'moment_interact:$momentId';
    if (busy.contains(thread)) return '这条动态正在互动中。';
    final audience = socialAudience(m).where((c) => c.allowSocialInteractions &&
      !m.likedBy.contains(c.id) &&
      !m.comments.any((cm) => cm.authorId == c.id && cm.parentId == null))
      .take(2).toList();
    if (audience.isEmpty) return '没有可互动的 AI：请先设置角色好友关系、开启互动权限，或这些好友已经互动过。';
    busy.add(thread); notifyListeners();
    final failures = <String>[];
    try {
      for (final actor in audience) {
        final profileForActor = profile(actor.apiProfileId);
        if (profileForActor == null) {
          failures.add('${actor.name}未绑定模型'); continue;
        }
        final key = await getKey(profileForActor.id);
        if (key == null || key.isEmpty) {
          failures.add('${actor.name}未设置 API Key'); continue;
        }
        final client = http.Client();
        _clients[thread] = client;
        try {
          final answer = await MultiModelApi.call(client: client,
            profile: profileForActor, apiKey: key, persona: actor.persona,
            roleName: actor.name,
            turns: [ModelTurn('user', '''你看到朋友「${displayName(m.characterId)}」发了一条虚拟朋友圈：
「${m.text}」
你和他/她在本地社交世界里是朋友。根据你的性格选择一种真实自然的反应：
仅输出 LIKE 或 SKIP 或 COMMENT: 你的评论文字。
不要重复动态原文、不要解释格式，评论不超过60字。''')]);
          final choice = answer.trim();
          if (choice.toUpperCase().startsWith('LIKE')) {
            if (!m.likedBy.contains(actor.id)) m.likedBy = [...m.likedBy, actor.id];
            _changed();
          } else if (!choice.toUpperCase().startsWith('SKIP')) {
            // Most models follow COMMENT:, but some relay models answer with
            // a natural sentence or a full-width colon. Keep that usable.
            final text = choice.replaceFirst(RegExp(
              r'^(COMMENT\s*[:：]\s*|评论\s*[:：]\s*)', caseSensitive: false),
              '').replaceAll(RegExp(r'^`+|`+$'), '').trim();
            if (text.isNotEmpty) {
              m.comments = [...m.comments, MomentComment(
                id: newId(), authorId: actor.id,
                text: text.length > 160 ? text.substring(0, 160) : text,
                createdAt: DateTime.now())];
              _changed();
            }
          }
        } catch (e) { failures.add('${actor.name}：$e'); }
        finally { client.close(); _clients.remove(thread); }
      }
      return failures.isEmpty ? null : failures.join('\n');
    } finally { busy.remove(thread); notifyListeners(); }
  }

  /// User-triggered or explicitly opted-in after user comments.
  /// Owner responds first (if allowed), plus at most one mutual friend.
  Future<String?> replyToMomentComment(String momentId, String commentId) async {
    final m = moment(momentId);
    if (m == null) return '动态已被删除。';
    final target = m.comments.where((c) => c.id == commentId).firstOrNull;
    if (target == null) return '评论已不存在。';
    final thread = 'moment_reply:$momentId:$commentId';
    if (busy.contains(thread)) return '正在生成评论回复。';
    final owner = character(m.characterId);
    final candidates = <Character>[
      if (owner != null) owner,
      ...socialAudience(m),
    ].where((c) => c.allowSocialInteractions && c.id != target.authorId &&
      !m.comments.any((cm) => cm.parentId == target.id && cm.authorId == c.id))
      .take(2).toList();
    if (candidates.isEmpty) return '没有可回复的 AI：请为发布者或其好友打开朋友圈互动权限，或他们已经回复过。';
    busy.add(thread); notifyListeners();
    final failures = <String>[];
    try {
      for (final actor in candidates) {
        final p = profile(actor.apiProfileId);
        if (p == null) { failures.add('${actor.name}未绑定模型'); continue; }
        final key = await getKey(p.id);
        if (key == null || key.isEmpty) { failures.add('${actor.name}缺少 API Key'); continue; }
        final client = http.Client();
        _clients[thread] = client;
        try {
          final context = m.comments.reversed.take(8).toList().reversed
            .map((c) => '${displayName(c.authorId)}：${c.text}').join('\n');
          final answer = await MultiModelApi.call(client: client, profile: p,
            apiKey: key, persona: actor.persona, roleName: actor.name,
            turns: [ModelTurn('user', '''这是一条虚构的朋友圈动态。
发布者：${displayName(m.characterId)}
动态：${m.text}
最新评论：
$context
你要回复「${displayName(target.authorId)}」这句评论：「${target.text}」。
请用自己的人格和口吻说一句自然的中文回复，不要扮演其他人，不要重复档案，不超过70字。只输出回复正文。''')]);
          final text = answer.trim();
          if (text.isNotEmpty) {
            m.comments = [...m.comments, MomentComment(id: newId(),
              authorId: actor.id, text: text.length > 180 ? text.substring(0, 180) : text,
              parentId: target.id, createdAt: DateTime.now())];
            _changed();
          }
        } catch (e) { failures.add('${actor.name}：$e'); }
        finally { client.close(); _clients.remove(thread); }
      }
      return failures.isEmpty ? null : failures.join('\n');
    } finally { busy.remove(thread); notifyListeners(); }
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

  void setDesktopIcon(String id, String relativePath) {
    data.desktopIcons = {...data.desktopIcons, id: relativePath};
    _changed();
  }

  void clearDesktopIcon(String id) {
    data.desktopIcons = {...data.desktopIcons}..remove(id);
    _changed();
  }

  void _partial(String thread, String sender, String text) {
    partialReplies[thread] = text;
    partialSenders[thread] = sender;
    final now = DateTime.now();
    final last = _lastPartialPaint[thread];
    if (last == null || now.difference(last).inMilliseconds >= 90) {
      _lastPartialPaint[thread] = now;
      notifyListeners();
    }
  }

  void _clearPartial(String thread) {
    partialReplies.remove(thread);
    partialSenders.remove(thread);
    _lastPartialPaint.remove(thread);
    notifyListeners();
  }

  void stop(String threadId) {
    _stopped.add(threadId);
    _clients.remove(threadId)?.close();
    _clearPartial(threadId);
  }

  List<ModelTurn> _turns(String threadId, String aiId, {bool group = false}) {
    final entries = threadMessages(threadId)
        .where((m) => m.senderId != 'system' && !m.recalled).toList();
    final recent = entries.length > 12 ? entries.sublist(entries.length - 12) : entries;
    return recent.map((entry) {
      var content = _entryContext(entry);
      // Old V3.3 roleplay paragraphs can prime the model to continue acting.
      // Keep a concise context representation in daily-chat mode.
      if (data.chatMode == 'daily' && entry.senderId == aiId) {
        content = content.replaceAll(RegExp(r'（[^）]{0,400}）'), '')
          .replaceAll(RegExp(r'\([^)]{0,400}\)'), '').trim();
        if (content.length > 450) content = content.substring(0, 450);
      }
      return ModelTurn(entry.senderId == aiId ? 'assistant' : 'user',
        group ? '${displayName(entry.senderId)}：$content' : content);
    }).where((turn) => turn.text.trim().isNotEmpty).toList();
  }

  String _entryContext(ChatEntry entry) {
    if (entry.quotedText == null || entry.quotedText!.isEmpty) return entry.text;
    return '引用「${entry.quotedSender ?? '对方'}：${entry.quotedText}」\n${entry.text}';
  }

  void editMessage(String threadId, String messageId, String newText) {
    if (busy.contains(threadId) || newText.trim().isEmpty) return;
    final index = data.messages.indexWhere(
      (m) => m.id == messageId && m.threadId == threadId);
    if (index < 0) return;
    final target = data.messages[index];
    if (target.senderId == 'system' || target.recalled) return;
    target.text = newText.trim();
    target.editedAt = DateTime.now();
    // Editing an old user message invalidates generated replies after it.
    if (target.senderId == 'me') {
      data.messages.removeWhere((m) => m.threadId == threadId &&
        m.createdAt.isAfter(target.createdAt));
    }
    _changed();
  }

  /// Local-only recall: no remote endpoint, no retroactive AI unlearning.
  void recallMyMessage(String threadId, String messageId) {
    if (busy.contains(threadId)) return;
    final m = data.messages.where((e) => e.id == messageId && e.threadId == threadId)
      .firstOrNull;
    if (m == null || m.senderId != 'me' || m.recalled) return;
    m.text = ''; m.quotedText = null; m.quotedSender = null; m.recalled = true;
    _changed();
  }

  void deleteLocalMessages(String threadId, Set<String> messageIds) {
    if (busy.contains(threadId)) return;
    data.messages.removeWhere((m) => m.threadId == threadId && messageIds.contains(m.id));
    _changed();
  }

  void forwardLocalMessages(String fromThread, String toThread, List<String> messageIds) {
    if (busy.contains(toThread)) return;
    final selected = threadMessages(fromThread)
      .where((m) => messageIds.contains(m.id) && !m.recalled).toList();
    if (selected.isEmpty) return;
    final text = selected.map((m) => '${displayName(m.senderId)}：${m.text}').join('\n');
    _addMessage(toThread, 'me', text.length > 5000 ? text.substring(0,5000) : text,
      forwardedFrom: selected.length == 1 ? displayName(selected.first.senderId) : '聊天记录');
  }

  /// Re-answer the last private user turn without adding another user bubble.
  /// Keep the previous reply until a replacement successfully arrives.
  Future<String?> regeneratePrivate(Character c) async {
    final thread = privateThread(c.id);
    if (busy.contains(thread)) return '回复正在生成中。';
    final entries = threadMessages(thread);
    final lastUser = entries.lastIndexWhere((m) => m.senderId == 'me');
    if (lastUser < 0) return '请先发送一条消息。';
    final p = profile(c.apiProfileId);
    if (p == null) return '请先绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '请先填写 API Key。';
    final prior = entries.sublist(0, lastUser + 1);
    final recent = prior.length > 12 ? prior.sublist(prior.length - 12) : prior;
    final turns = recent.where((m) => !m.recalled).map((m) => ModelTurn(
      m.senderId == c.id ? 'assistant' : 'user', _entryContext(m))).toList();
    busy.add(thread); _stopped.remove(thread); notifyListeners();
    final client = http.Client(); _clients[thread] = client;
    try {
      final reply = await MultiModelApi.call(client: client, profile: p,
        apiKey: key, persona: c.persona, roleName: c.name, turns: turns,
        chatMode: data.chatMode,
        onText: (text) { if (!_stopped.contains(thread)) _partial(thread,c.id,text); });
      if (!_stopped.contains(thread)) {
        final lastUserAt = prior.last.createdAt;
        data.messages.removeWhere((m) => m.threadId == thread &&
          m.createdAt.isAfter(lastUserAt));
        _addMessage(thread, c.id, reply);
      }
      return null;
    } catch (e) { return _stopped.contains(thread) ? null : '$e'; }
    finally { client.close(); _clients.remove(thread); _clearPartial(thread);
      busy.remove(thread); _stopped.remove(thread); notifyListeners(); }
  }

  void _addMessage(String thread, String sender, String text,
      {String? quotedText, String? quotedSender, String? forwardedFrom}) {
    data.messages.add(ChatEntry(id: newId(), threadId: thread, senderId: sender,
      text: text, createdAt: DateTime.now(), quotedText: quotedText,
      quotedSender: quotedSender, forwardedFrom: forwardedFrom));
    _changed();
  }

  Future<String?> sendPrivate(Character c, String text, {ChatEntry? quote}) async {
    final thread = privateThread(c.id);
    if (busy.contains(thread)) return '上一条回复仍在生成中。';
    final p = profile(c.apiProfileId);
    if (p == null) return '请先在好友资料中绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '此 API 配置没有密钥，请先补充密钥。';
    _addMessage(thread, 'me', text,
      quotedText: quote?.text, quotedSender: quote == null ? null : displayName(quote.senderId));
    _stopped.remove(thread);
    busy.add(thread);
    notifyListeners();
    final client = http.Client();
    _clients[thread] = client;
    try {
      final answer = await MultiModelApi.call(client: client, profile: p,
        apiKey: key, persona: c.persona, roleName: c.name,
        chatMode: data.chatMode, turns: _turns(thread, c.id),
        onText: (text) {
          if (!_stopped.contains(thread)) _partial(thread, c.id, text);
        });
      if (!_stopped.contains(thread)) _addMessage(thread, c.id, answer);
      return null;
    } catch (e) {
      if (_stopped.contains(thread)) return null;
      return '$e';
    } finally {
      client.close();
      _clients.remove(thread);
      _clearPartial(thread);
      busy.remove(thread);
      _stopped.remove(thread);
      notifyListeners();
    }
  }

  Future<String?> sendGroup(ChatGroup group, String text, {ChatEntry? quote}) async {
    final thread = groupThread(group.id);
    if (busy.contains(thread)) return '当前群聊正在生成回复。';
    _addMessage(thread, 'me', text,
      quotedText: quote?.text, quotedSender: quote == null ? null : displayName(quote.senderId));
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
            roleName: c.name, chatMode: data.chatMode,
            turns: _turns(thread, c.id, group: true), group: true,
            onText: (text) {
              if (!_stopped.contains(thread)) _partial(thread, c.id, text);
            });
          if (!_stopped.contains(thread)) {
            _addMessage(thread, c.id, answer);
            replied++;
          }
        } catch (e) {
          if (!_stopped.contains(thread)) failures.add('${c.name}: $e');
        } finally {
          client.close();
          _clearPartial(thread);
          if (identical(_clients[thread], client)) _clients.remove(thread);
        }
      }
      return failures.isEmpty ? null : failures.join('\n');
    } finally {
      _clients.remove(thread)?.close();
      _clearPartial(thread);
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
        profile: p, apiKey: key, persona: c.persona, roleName: c.name,
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
    music.dispose();
    super.dispose();
  }
}

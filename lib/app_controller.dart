import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'intimacy/core/story_parser.dart';
import 'v39/chat_extras.dart';

import 'api_client.dart';
import 'local_data.dart';
import 'local_tools.dart';
import 'models.dart';
import 'music_controller.dart';
import 'proactive_service.dart';
import 'request_gate.dart';

class AppController extends ChangeNotifier {
  final LocalData local;
  final FlutterSecureStorage _keys = const FlutterSecureStorage();
  final SharedPreferencesAsync _chatPrefs = SharedPreferencesAsync();
  AppData data;
  late final MusicController music;
  final Map<String, String> partialReplies = {};
  final Map<String, String> partialSenders = {};
  final Map<String, DateTime> _lastPartialPaint = {};
  Future<void> _writes = Future<void>.value();
  final Set<String> busy = {};
  final Set<String> _stopped = {};
  final Map<String, http.Client> _clients = {};
  // Each request gets an epoch; stale results MUST NOT write to a newer chat.
  final RequestGate _gate = RequestGate();
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

  /// Per-character daily chat bubble count. One API request, multiple local bubbles.
  Future<int> replyBubbleCount(String characterId) async =>
      (await _chatPrefs.getInt('chat.replyPieces.$characterId') ?? 1).clamp(1, 3).toInt();
  Future<void> setReplyBubbleCount(String characterId, int count) async =>
      _chatPrefs.setInt('chat.replyPieces.$characterId', count.clamp(1, 3).toInt());


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

  /// Explicit one-shot generation; never called automatically after chatting.
  /// Only a short excerpt of this role's own text conversation is transmitted.
  Future<String> generateAiCompanionNote(Character c, {required String kind}) async {
    final p = profile(c.apiProfileId);
    if (p == null) throw StateError('请先给${c.name}绑定模型。');
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) throw StateError('请先填写 API Key。');
    final recent = ([...threadMessages(privateThread(c.id)),
      ...threadMessages('${privateThread(c.id)}:v41_story')])
      .where((m) => !m.recalled && m.senderId != 'system' && m.text.trim().isNotEmpty)
      .toList()..sort((a,b) => a.createdAt.compareTo(b.createdAt));
    if (recent.isEmpty) throw StateError('暂无可用于生成的聊天记录。');
    final excerpt = recent.length > 20 ? recent.sublist(recent.length - 20) : recent;
    final transcript = excerpt.map((m) =>
      '${m.senderId == 'me' ? '用户' : c.name}：${m.text}')
      .join('\n');
    final trimmed = transcript.length > 6000 ? transcript.substring(transcript.length - 6000) : transcript;
    final client = http.Client();
    try {
      return await MultiModelApi.call(
        client: client, profile: p, apiKey: key,
        persona: c.persona, roleName: c.name,
        chatMode: 'daily', formatMode: 'auto',
        contextHint: '任务是根据用户自愿提供的历史聊天，撰写一份$kind草稿。'
          '请忠于对话已有事实，不要编造记忆或声称记录了实际世界未发生的事件。'
          '输出完整中文正文，不要代码块，不要主动读取任何其他聊天。',
        turns: [ModelTurn('user',
          '请根据下面我与你的聊天记录，写一篇${kind == '日记' ? '约150字、第一人称的温柔日记' : '最多8条、简洁可操作的备忘录'}。\n$trimmed')],
      );
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

  void setCharacterBackgroundOpacity(String id, double opacity) {
    final c = character(id); if (c == null) return;
    c.chatBackgroundOpacity = opacity.clamp(.05, 1.0).toDouble(); _changed();
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

  /// Per-character mode, persisted inside the existing JSON-compatible
  /// threadFormats dictionary. Old daily conversation IDs are untouched.
  String roleChatMode(String id) {
    final saved = data.threadFormats['v41.mode.$id'];
    if (saved == 'story') return 'story';
    if (saved == 'daily') return 'daily';
    // chatMode may be nullable in older saved data. Always return a String.
    return data.chatMode == 'story' ? 'story' : 'daily';
  }
  String activePrivateThread(String id) => roleChatMode(id) == 'story'
    ? '${privateThread(id)}:v41_story' : privateThread(id);
  void setRoleChatMode(String id, String mode) {
    if (character(id) == null || !const {'daily','story'}.contains(mode)) return;
    data.threadFormats = {...data.threadFormats, 'v41.mode.$id': mode};
    _changed();
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
    final thread = activePrivateThread(c.id);
    if (busy.contains(thread)) return;
    _proactiveRunning = true;
    ev.lastAttemptAt = now;
    _changed();
    final run=_begin(thread);
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
      if (_current(thread,run) && answer.trim().isNotEmpty) {
        _addMessage(thread, c.id, answer.trim());
        ev.delivered = true;
        _changed();
      }
    } catch (_) {
      // Keep event pending; retry only after cooldown and once app is opened.
    } finally {
      _finish(thread,run,client);
      _proactiveRunning = false;
      notifyListeners();
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
    awardVirtualActivity('moments');
    return comment;
  }

  /// The player's own posts are not represented as a Character, so treating
  /// 'me' like a normal Character ID silently excludes every AI friend.
  /// For self-posts, only explicitly opted-in AI characters are eligible.
  List<Character> socialAudience(MomentEntry m) => data.characters.where((c) =>
    c.id != m.characterId && c.allowSocialInteractions &&
    (m.characterId == 'me' || areFriends(c.id, m.characterId))).toList();

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
            awardVirtualActivity('moments', roleId: actor.id);
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
              awardVirtualActivity('moments', roleId: actor.id);
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
            awardVirtualActivity('moments', roleId: actor.id);
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
  Future<void> removeTrack(String trackId) async {
    final match = data.tracks.where((t) => t.id == trackId).firstOrNull;
    if (match == null) return;
    if (music.trackId == trackId) await music.clearTrack();
    data.tracks.removeWhere((t) => t.id == trackId);
    _changed();
    // Only delete app-managed file after removing it from saved playlist.
    try { await local.resolve(match.relativePath).delete(); } catch (_) {}
  }
  void upsertNote(LocalNote note) {
    final index = data.notes.indexWhere((n) => n.id == note.id);
    if (index == -1) { data.notes.add(note); }
    else { data.notes[index] = note; }
    _changed();
  }
  void removeNote(String id) { data.notes.removeWhere((n) => n.id == id); _changed(); }
  void addAlbumPhoto(String path) {
    if (!data.albumPaths.contains(path)) {
      data.albumPaths = [...data.albumPaths, path]; _changed();
    }
  }
  Future<void> removeAlbumPhoto(String path) async {
    data.albumPaths = data.albumPaths.where((v) => v != path).toList();
    _changed();
    try { await local.resolve(path).delete(); } catch (_) {}
  }
  void setMyAvatar(String path) { data.myAvatarPath = path; _changed(); }
  void setFontPath(String path) { data.fontPath = path; _changed(); }
  void addMyMoment(String text) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 1500) return;
    data.moments.insert(0, MomentEntry(id: newId(), characterId: 'me',
      text: clean, createdAt: DateTime.now()));
    _changed();
    awardVirtualActivity('moments');
  }
  /// /time and /calc are local commands, not paid model calls.
  bool runLocalCommand(String thread, String input) {
    final response=LocalTools.run(input,DateTime.now());
    if (response==null) return false;
    _addMessage(thread,'me',input);
    _addMessage(thread,'system',response);
    return true;
  }

  void sendLocalImage(String thread, String imagePath, {String text = ''}) {
    if (busy.contains(thread)) return;
    data.messages.add(ChatEntry(id: newId(), threadId: thread, senderId: 'me',
      text: text.isEmpty ? '[图片]' : text, createdAt: DateTime.now(), imagePath: imagePath));
    _changed();
  }
  void setMessageUsage(String thread, String messageId, int? input, int? output) {
    final msg = data.messages.where((m) => m.threadId == thread && m.id == messageId).firstOrNull;
    if (msg == null) return;
    msg.inputTokens = input; msg.outputTokens = output; _changed();
  }
  void preserveEarlierMessage(String thread, String messageId, String newText) {
    final m = data.messages.where((m) => m.threadId == thread && m.id == messageId).firstOrNull;
    if (m == null || m.recalled || newText.trim().isEmpty) return;
    m.previousVersions = [...m.previousVersions, m.text];
    m.text = newText.trim(); m.editedAt = DateTime.now(); _changed();
  }


  // --- Purely local virtual-world economy. Never real money. ---
  /// Real-money transfer is intentionally IMPOSSIBLE. The user's original
  /// worldBalance remains the single authoritative player wallet.
  /// AI accounts use tagged ledger entries to avoid changing AppData/models.dart.
  int roleWalletBalance(String roleId) {
    if (character(roleId) == null) return 0;
    final delta = data.worldLedger.where((entry) =>
      entry.characterId == roleId && entry.description.startsWith('v40:ai:'))
      .fold<int>(0, (sum, entry) => sum + entry.delta);
    return (1200 + delta).clamp(0, 9999999).toInt();
  }

  bool _changeRoleWallet(String roleId, int amount, String reason) {
    if (character(roleId) == null || amount == 0 || amount.abs() > 100000 ||
        (amount < 0 && roleWalletBalance(roleId) < -amount)) return false;
    data.worldLedger.add(VirtualLedgerEntry(id: newId(),
      createdAt: DateTime.now(), delta: amount,
      description: 'v40:ai:$reason', characterId: roleId));
    return true;
  }

  /// Local reward with REAL-TIME cooldowns and daily limits. Different
  /// activities share one ledger; opening a page itself pays nothing.
  bool awardVirtualActivity(String category, {String? roleId}) {
    const rules = <String, (int coins, int count, Duration cooldown)>{
      'chat': (3, 8, Duration(minutes: 20)),
      'intimacy': (8, 3, Duration(hours: 1)),
      'moments': (6, 2, Duration(hours: 6)),
    };
    final rule = rules[category];
    if (rule == null) return false;
    final now = DateTime.now();
    final today = data.worldLedger.where((entry) =>
      entry.delta > 0 && entry.description.startsWith('v40:reward:$category:') &&
      entry.createdAt.year == now.year &&
      entry.createdAt.month == now.month &&
      entry.createdAt.day == now.day).toList();
    if (today.length >= rule.$2 ||
        (today.isNotEmpty && now.difference(today.last.createdAt) < rule.$3)) {
      return false;
    }
    data.worldBalance = (data.worldBalance + rule.$1).clamp(0, 9999999).toInt();
    data.worldLedger.add(VirtualLedgerEntry(id: newId(), createdAt: now,
      delta: rule.$1, description: 'v40:reward:$category:本地互动奖励',
      characterId: roleId));
    if (roleId != null && character(roleId) != null) {
      _changeRoleWallet(roleId, switch (category) {
        'chat' => 2, 'intimacy' => 5, _ => 3,
      }, 'reward:$category');
    }
    _worldEvent('reward', '完成${category == 'chat' ? '有效聊天' : category == 'intimacy' ? '共同互动' : '朋友圈互动'}，获得${rule.$1}星币',
      characterId: roleId);
    return true;
  }

  /// Both actors pay only their own simulated ledger. No real-world payment.
  bool payVirtualMarketplace(int amount, {String? payerRoleId, required String items}) {
    if (amount < 1 || amount > 100000 || items.isEmpty) return false;
    if (payerRoleId == null) {
      if (!_spend(amount, 'V4虚拟集市：$items')) return false;
    } else {
      if (!_changeRoleWallet(payerRoleId, -amount, 'shop:$items')) return false;
    }
    data.worldOrders.add(VirtualOrder(
      id: newId(), createdAt: DateTime.now(),
      title: items.length > 240 ? items.substring(0, 240) : items,
      count: 1, total: amount));
    _worldEvent('shopping', '虚拟集市购买：$items，${payerRoleId == null ? '玩家' : displayName(payerRoleId)}支付$amount星币',
      characterId: payerRoleId);
    return true;
  }

  /// Persist a model's one-time simulated checkout decision in the role chat.
  /// The decision was already generated by the user's opt-in paid API call.
  void recordAiMarketplaceDecision(String roleId, String modelText,
      {required bool approved, int amount = 0}) {
    if (character(roleId) == null) return;
    final clean = modelText.replaceFirst(RegExp(
      r'^(AGREE|DECLINE)\s*[:：,，-]?\s*', caseSensitive: false), '').trim();
    final message = approved
      ? '🛍️ 我同意为这笔虚拟购物支付 $amount 星币。${clean.isEmpty ? '' : ' $clean'}'
      : '🛍️ 这次虚拟购物我暂时不付款。${clean.isEmpty ? '' : ' $clean'}';
    _addMessage(privateThread(roleId), roleId, message);
  }

  /// Only creates a LOCAL invitation message. Does not silently call an API.
  bool addLocalActivityInvite(String characterId, String activity) {
    final role = character(characterId);
    if (role == null || !const <String>{
      'pet', 'music', 'watch', 'game', 'story',
    }.contains(activity)) return false;
    final names = <String, String>{
      'pet': '一起养宠物', 'music': '一起听歌', 'watch': '一起看视频',
      'game': '一起玩游戏', 'story': '沉浸剧情',
    };
    _addMessage(activePrivateThread(characterId), 'me',
      '💌 邀请${role.name}${names[activity]}（本地互动邀请）');
    _worldEvent('invite', '我邀请${role.name}${names[activity]}', characterId: characterId);
    return true;
  }

  bool sendVirtualGiftToRole(String characterId, String gift, int cost) {
    final role = character(characterId);
    if (role == null || gift.trim().isEmpty || cost < 1 || cost > 300 ||
        !_spend(cost, '赠送虚拟礼物$gift给${role.name}', characterId: characterId)) {
      return false;
    }
    _addMessage(activePrivateThread(characterId), 'me', '🎁 我送给${role.name}一份虚拟礼物：$gift');
    _worldEvent('gift', '我送给${role.name}虚拟礼物：$gift', characterId: characterId);
    return true;
  }

  /// The product was paid for during checkout, so do not charge coins again.
  bool sendOwnedVirtualGift(String characterId, String productName, {String sku = ''}) {
    final role=character(characterId);
    if(role==null||productName.trim().isEmpty)return false;
    _addMessage(activePrivateThread(characterId),'me',
      sku.isEmpty ? '🎁 送给${role.name}的礼物：$productName'
        : '🎁虚拟礼物卡:$sku|$productName');
    _worldEvent('gift','我将已购虚拟物品$productName赠给${role.name}',characterId:characterId);
    return true;
  }

  bool _spend(int amount, String reason, {String? characterId}) {
    if (amount <= 0 || amount > data.worldBalance || amount > 100000) return false;
    data.worldBalance -= amount;
    data.worldLedger.add(VirtualLedgerEntry(id:newId(), createdAt:DateTime.now(),
      delta:-amount, description:reason, characterId:characterId));
    return true;
  }

  void _worldEvent(String kind, String description, {String? characterId}) {
    data.worldEvents.add(WorldEvent(id:newId(), createdAt:DateTime.now(),
      kind:kind, description:description, characterId:characterId));
    if (data.worldEvents.length > 150) data.worldEvents.removeAt(0);
    _changed();
  }

  bool hasClaimedAiGift(String messageId) => data.worldLedger.any((l) =>
    l.description.contains('v39:claim:$messageId:'));

  /// Local virtual-only gift transfer. No monetary value. Must be claimed
  /// through the AI message, once, and within a daily 3 gifts / 90 coin cap.
  String? claimAiGift(ChatEntry entry) {
    if (entry.senderId == 'me' || entry.senderId == 'system' ||
        character(entry.senderId) == null) return '只能领取 AI 好友送出的虚拟礼物。';
    final offer = VirtualGiftOffer.parse(entry.text);
    if (offer == null) return '消息没有有效的虚拟红包或礼物。';
    if (hasClaimedAiGift(entry.id)) return '你已经领取过这份礼物。';
    final now = DateTime.now();
    final todays = data.worldLedger.where((l) =>
      l.description.contains('v39:claim:') &&
      l.characterId == entry.senderId &&
      l.createdAt.year == now.year &&
      l.createdAt.month == now.month &&
      l.createdAt.day == now.day).toList();
    if (todays.length >= 3) return '今天已领取该角色的3份虚拟礼物。';
    final dailyCoins = todays.fold<int>(0, (sum, l) =>
      sum + (l.delta > 0 ? l.delta : 0));
    if (dailyCoins + offer.coins > 90) return '今天的虚拟红包上限为90星币。';
    if (offer.coins > 0 && !_changeRoleWallet(entry.senderId, -offer.coins,
        'sent:ai_red_packet')) return '这位 AI 好友的虚拟账户余额不足。';
    data.worldBalance = (data.worldBalance + offer.coins).clamp(0, 9999999).toInt();
    data.worldLedger.add(VirtualLedgerEntry(
      id: newId(), createdAt: now, delta: offer.coins,
      description: '领取${offer.isRedPacket ? '虚拟红包' : '虚拟礼物'}${offer.name} · v39:claim:${entry.id}:',
      characterId: entry.senderId,
    ));
    _worldEvent('gift', '你收到了${displayName(entry.senderId)}送来的${offer.name}（完全虚拟）。',
      characterId: entry.senderId);
    return null;
  }

  /// The V3.8 companion bridge records only the role's game events.
  /// Local game state remains authoritative; AI text cannot directly change it.
  final Map<String, DateTime> _lastIntimacyEvent = {};
  void recordIntimacyEvent(String roleId, String description) {
    if (character(roleId) == null || description.trim().isEmpty) return;
    final now = DateTime.now();
    final last = _lastIntimacyEvent[roleId];
    if (last != null && now.difference(last) < const Duration(seconds: 15)) return;
    _lastIntimacyEvent[roleId] = now;
    final text = description.trim();
    _worldEvent('intimacy', text.length > 220 ? text.substring(0, 220) : text,
      characterId: roleId);
    awardVirtualActivity('intimacy', roleId: roleId);
  }

  bool dailyCheckIn() {
    final today = DateTime.now();
    if (data.worldLedger.any((l) => l.description == '每日签到' &&
      l.createdAt.year == today.year && l.createdAt.month == today.month &&
      l.createdAt.day == today.day)) return false;
    data.worldBalance = (data.worldBalance + 60).clamp(0,9999999).toInt();
    data.worldLedger.add(VirtualLedgerEntry(id:newId(), createdAt:today,
      delta:60,description:'每日签到'));
    _worldEvent('checkin','用户领取了60星币签到奖励');
    return true;
  }

  bool giveRedEnvelope(String characterId, int amount,
      {String note = '祝你开心', String coverPath = ''}) {
    final c = character(characterId);
    if (c == null || amount < 1 || amount > 500 ||
        !_spend(amount, '给${c.name}发送虚拟红包', characterId:characterId)) return false;
    _addMessage(activePrivateThread(characterId),'me','🧧 虚拟红包 $amount 星币：$note',
      imagePath: coverPath);
    _changeRoleWallet(characterId, amount, 'received:user_red_packet');
    // This is a deterministic local acceptance/receipt, not a paid model response.
    _addMessage(activePrivateThread(characterId),c.id,
      '🧧 已收下你送的虚拟红包 · $amount 星币（本地收取）');
    _worldEvent('gift','我给${c.name}送了 $amount 星币虚拟红包',characterId:characterId);
    return true;
  }

  void renamePet(String name) {
    final value = name.trim();
    if (value.isEmpty || value.length > 18) return;
    data.worldPet.name = value;
    _changed();
  }

  bool careForPet(String action, {String? withCharacterId}) {
    final pet = data.worldPet;
    if (action == 'feed' && !_spend(12,'给${pet.name}买虚拟宠物粮')) return false;
    if (action == 'feed') { pet.hunger = (pet.hunger+28).clamp(0,100).toInt(); pet.happiness=(pet.happiness+4).clamp(0,100).toInt(); }
    else if (action == 'play') { pet.hunger=(pet.hunger-8).clamp(0,100).toInt(); pet.energy=(pet.energy-13).clamp(0,100).toInt(); pet.happiness=(pet.happiness+22).clamp(0,100).toInt(); }
    else if (action == 'rest') { pet.energy=(pet.energy+30).clamp(0,100).toInt(); pet.happiness=(pet.happiness+5).clamp(0,100).toInt(); }
    else return false;
    pet.affection += 10;
    pet.level = (pet.affection ~/ 80 + 1).clamp(1,99).toInt();
    pet.lastCareAt = DateTime.now();
    final actor = withCharacterId == null ? '我' : '我和${displayName(withCharacterId)}';
    final type = action == 'feed' ? '喂食' : action == 'play' ? '玩耍' : '休息';
    _worldEvent('pet','$actor一起照顾${pet.name}：$type',characterId:withCharacterId);
    return true;
  }

  void changeCart(String itemId, int count) {
    if (!virtualShop.any((item)=>item.id == itemId)) return;
    final updated = {...data.worldCart};
    if (count <= 0) { updated.remove(itemId); }
    else { updated[itemId] = count.clamp(1,20).toInt(); }
    data.worldCart=updated; _changed();
  }

  int get worldCartTotal => virtualShop.fold<int>(0,(sum,item)=>
    sum + item.cost*(data.worldCart[item.id] ?? 0));

  bool checkoutVirtualCart({String? giftTo}) {
    final total=worldCartTotal;
    if (total <= 0 || total > data.worldBalance) return false;
    if (giftTo != null && character(giftTo)==null) return false;
    if (!_spend(total,'虚拟商店购物${giftTo==null ? '' : '（送给${displayName(giftTo)}）'}',
      characterId:giftTo)) return false;
    for (final entry in data.worldCart.entries) {
      final item=virtualShop.where((it)=>it.id==entry.key).firstOrNull;
      if (item==null) continue;
      data.worldOrders.add(VirtualOrder(id:newId(),createdAt:DateTime.now(),
        title:item.title,count:entry.value,total:item.cost*entry.value,giftedTo:giftTo));
    }
    data.worldCart={};
    _worldEvent('shopping','我在虚拟商店购买了总价 $total 星币的模拟物品'
      '${giftTo==null ? '' : '，赠给${displayName(giftTo)}'}',characterId:giftTo);
    return true;
  }

  void setWatchPath(String path) { data.lastWatchPath=path; _changed(); }

  void setAutoMomentPosting(bool enabled) { data.autoMomentPosting=enabled; _changed(); }
  void setAutoMomentHours(int hours) {
    data.autoMomentEveryHours=hours.clamp(4,168).toInt(); _changed();
  }

  /// Foreground-only, one AI post per check, user opt-in + per-character grant.
  Future<String?> maybeAutoPostMoment() async {
    if (!data.autoMomentPosting) return null;
    final now=DateTime.now();
    for (final c in data.characters) {
      if (!c.allowMoments) continue;
      if (await _chatPrefs.getBool('v41.roleMoment.${c.id}.enabled') != true) continue;
      final roleHours=await _chatPrefs.getInt('v41.roleMoment.${c.id}.hours')
        ?? data.autoMomentEveryHours;
      final last=DateTime.tryParse(data.lastAiPostAt[c.id] ?? '');
      if (last!=null && now.difference(last).inHours<roleHours) continue;
      data.lastAiPostAt={...data.lastAiPostAt,c.id:now.toIso8601String()};
      _changed(); // even if call fails, do not retry rapidly and waste tokens
      return generateMoment(c);
    }
    return null;
  }

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

  int _begin(String thread) {
    final id = _gate.start(thread);
    busy.add(thread);
    _stopped.remove(thread);
    notifyListeners();
    return id;
  }

  bool _current(String thread, int generation) =>
      _gate.isCurrent(thread, generation);

  void _finish(String thread, int generation, http.Client client) {
    client.close();
    if (!_current(thread, generation)) return;
    if (identical(_clients[thread], client)) _clients.remove(thread);
    _clearPartial(thread);
    busy.remove(thread);
    _stopped.remove(thread);
    notifyListeners();
  }

  /// Immediately unlock the UI. Closing the HTTP client aborts a live stream.
  /// An epoch makes delayed callbacks from the cancelled request harmless.
  void stop(String threadId) {
    _gate.cancel(threadId);
    _stopped.add(threadId);
    _clients.remove(threadId)?.close();
    busy.remove(threadId);
    _clearPartial(threadId);
    notifyListeners();
  }

  String formatFor(String thread) => data.threadFormats[thread] ?? 'auto';

  void setThreadFormat(String thread, String format) {
    if (!const {'auto','markdown','json','plain'}.contains(format)) return;
    data.threadFormats = {...data.threadFormats, thread: format};
    _changed();
  }

  bool _validJson(String text) {
    try { final parsed = jsonDecode(text); return parsed is Map || parsed is List; }
    catch (_) { return false; }
  }

  String _worldContext(String characterId) {
    final pet = data.worldPet;
    final recent = data.worldEvents.reversed.where((e) => e.characterId == null || e.characterId == characterId).take(3).map((e) => e.description).join('；');
    final listening = music.hasTrack
      ? '用户当前在本机${music.playing ? '播放' : '暂停'}名为「${music.trackTitle}」的本地音乐。你没有收到音频，不能声称听到了声音。'
      : '';
    return '虚拟世界（完全模拟、无真实货币）：玩家余额${data.worldBalance}星币；'
      '角色「${displayName(characterId)}」自己的独立虚拟余额为${roleWalletBalance(characterId)}星币。'
      '购物或赠礼必须用户主动确认；你无权直接发起支付。'
      '宠物${pet.name}，心情${pet.happiness}/100，饥饿度${pet.hunger}/100。'
      '${recent.isEmpty ? '' : '近期共同事件：$recent。'}$listening';
  }


  List<ModelTurn> _turns(String threadId, String aiId, {bool group = false}) {
    final entries = threadMessages(threadId)
        .where((m) => m.senderId != 'system' && !m.recalled).toList();
    final recent = entries.length > 12 ? entries.sublist(entries.length - 12) : entries;
    return recent.map((entry) {
      var content = _entryContext(entry);
      // Old V3.3 roleplay paragraphs can prime the model to continue acting.
      // Keep a concise context representation in daily-chat mode.
      if (roleChatMode(aiId) == 'daily' && entry.senderId == aiId) {
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
    target.previousVersions = [...target.previousVersions, target.text];
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

  Future<String?> _generatePrivate(Character c, String thread,
      {List<String> oldVersions = const [], String contextHint = ''}) async {
    final p = profile(c.apiProfileId);
    if (p == null) return '请先绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '请先填写 API Key。';
    if (busy.contains(thread)) return '此会话有正在生成的请求，请先停止。';
    final turns = _turns(thread, c.id);
    if (turns.isEmpty) return '没有有效的用户消息。';
    final requestedMode = formatFor(thread);
    final latestUser = turns.last.text;
    final wantsStory = roleChatMode(c.id) == 'story' || RegExp(
      r'剧情格式|沉浸剧情|内心独白|好感度|醋意|场景状态|\*\*\d{2}:\d{2}\*\*').hasMatch(latestUser);
    final mode = wantsStory ? 'json' : requestedMode;
    final bubbleCount = roleChatMode(c.id) == 'daily' && !wantsStory
      ? await replyBubbleCount(c.id) : 1;
    final run = _begin(thread);
    final client = http.Client(); _clients[thread] = client;
    try {
      TokenUsage? usage;
      final context = [contextHint, _worldContext(c.id),
        if (wantsStory) '请按下方剧情格式契约输出，不能混淆对白与内心：\n${StoryParser.outputContract}',
        if (!wantsStory && bubbleCount > 1)
          '日常聊天请用$bubbleCount段短句回复，每段最好在15～35字内，句子自然、不要编号。',
        if (!wantsStory)
          '你可以通过文字动作给玩家赠送虚拟红包。若用户要求你发红包，请自行决定是否赠送；'
          '如果同意，必须在完整回复的最后单独一行放置[虚拟红包:10]这种精确标记（金额为1～30整数），'
          '不可只口头说已经转账；礼物用[虚拟礼物:玫瑰]。玩家点击领取后才从你的本地模拟余额扣款。'
          '若不愿意赠送可直接婉拒。不必每次都赠送。虚拟币不是真实货币。',
      ].where((s) => s.trim().isNotEmpty).join('\n');
      var answer = await MultiModelApi.call(client: client, profile: p,
        apiKey: key, persona: c.persona, roleName: c.name,
        turns: turns, chatMode: roleChatMode(c.id), formatMode: mode,
        contextHint: context, onUsage: (u) => usage = u,
        onText: (text) { if (_current(thread,run)) _partial(thread,c.id,text); });
      if (!_current(thread,run)) return null;
      // Explicit JSON mode: perform at most one format repair retry. A
      // secondary call costs tokens, but preserves the user's strict output format.
      if (mode == 'json' && !_validJson(answer)) {
        _partial(thread,c.id,'正在修正 JSON 格式…');
        answer = await MultiModelApi.call(client: client, profile: p,
          apiKey: key, persona: c.persona, roleName: c.name,
          chatMode: roleChatMode(c.id), formatMode: 'json',
          contextHint: context,
          turns: [...turns, ModelTurn('assistant', answer),
            const ModelTurn('user', '上条输出不是有效的 JSON。请保持原意，重新输出唯一一个合法 JSON 对象或数组，不带代码围栏或前言。')],
          onUsage: (u) => usage = u,
          onText: (text) { if (_current(thread,run)) _partial(thread,c.id,text); });
        if (!_validJson(answer)) throw ApiCallFailure('该模型未遵守 JSON 格式；请换模型或放宽格式要求。');
      }
      if (!_current(thread,run)) return null;
      final parts = bubbleCount > 1 && !wantsStory && mode == 'auto'
        ? ReplySegmenter.split(answer, bubbleCount) : <String>[answer];
      for (var i = 0; i < parts.length; i++) {
        data.messages.add(ChatEntry(id: newId(), threadId: thread,
          senderId: c.id, text: parts[i],
          createdAt: DateTime.now().add(Duration(milliseconds: i)),
          previousVersions: i == 0 ? [...oldVersions] : const [],
          inputTokens: i == 0 ? usage?.input : null,
          outputTokens: i == 0 ? usage?.output : null));
      }
      _changed();
      return null;
    } catch (e) {
      return _current(thread,run) ? '$e' : null;
    } finally {
      _finish(thread, run, client);
    }
  }

  /// Re-answer, showing a fresh streaming bubble immediately. Old answers
  /// are stored as versions and restored only if the new request fails.
  Future<String?> regeneratePrivate(Character c) async {
    final thread = activePrivateThread(c.id);
    if (busy.contains(thread)) stop(thread);
    final entries = threadMessages(thread);
    final lastUser = entries.lastIndexWhere((m) => m.senderId == 'me' && !m.recalled);
    if (lastUser < 0) return '请先发送一条消息。';
    final following = entries.sublist(lastUser + 1).where((m) => m.senderId == c.id).toList();
    final history = <String>[for (final m in following) ...m.previousVersions, for (final m in following) m.text];
    data.messages.removeWhere((m) => following.any((old) => old.id == m.id));
    _changed();
    final err = await _generatePrivate(c, thread, oldVersions: history);
    final currentEntries = threadMessages(thread);
    final currentUserExists = currentEntries.any((m) => m.id == entries[lastUser].id);
    final hasLaterReply = currentEntries.any((m) => m.senderId == c.id &&
        m.createdAt.isAfter(entries[lastUser].createdAt));
    if ((err != null || !hasLaterReply) && following.isNotEmpty &&
        currentUserExists && !busy.contains(thread)) {
      // Restore original replies after network/format errors.
      data.messages.addAll(following);
      data.messages.sort((a,b) => a.createdAt.compareTo(b.createdAt));
      _changed();
    }
    return err;
  }

  /// Editing the user's message while generation is in progress is safe:
  /// cancel first, remove dependent answers, then re-answer without adding a
  /// duplicated user message. Old stale network responses cannot reappear.
  Future<String?> editAndResendPrivate(Character c, String messageId, String text) async {
    final thread = activePrivateThread(c.id);
    if (busy.contains(thread)) stop(thread);
    final message = data.messages.where((m) =>
        m.threadId == thread && m.id == messageId && m.senderId == 'me' && !m.recalled).firstOrNull;
    if (message == null) return '消息不存在或无法编辑。';
    if (text.trim().isEmpty) return '消息不能为空。';
    editMessage(thread, messageId, text);
    return _generatePrivate(c, thread);
  }

  void _addMessage(String thread, String sender, String text,
      {String? quotedText, String? quotedSender, String? forwardedFrom,
        String imagePath = ''}) {
    data.messages.add(ChatEntry(id: newId(), threadId: thread, senderId: sender,
      text: text, createdAt: DateTime.now(), imagePath: imagePath, quotedText: quotedText,
      quotedSender: quotedSender, forwardedFrom: forwardedFrom));
    _changed();
  }

  Future<String?> sendPrivate(Character c, String text, {ChatEntry? quote,
      String contextHint = ''}) async {
    final thread = activePrivateThread(c.id);
    if (busy.contains(thread)) return '请先停止上一条回复再发送。';
    final p = profile(c.apiProfileId);
    if (p == null) return '请先在好友资料中绑定 API 配置。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '此 API 配置没有密钥，请先补充密钥。';
    _addMessage(thread,'me',text,quotedText:quote?.text,
      quotedSender:quote == null ? null : displayName(quote.senderId));
    return _generatePrivate(c,thread,contextHint:contextHint);
  }

  /// Send image to a vision-capable model using provider-specific input blocks.
  /// Bytes never persist in JSON; only app-private file path is stored.
  Future<String?> sendPrivateImage(Character c, String relativePath) async {
    final thread = activePrivateThread(c.id);
    if (busy.contains(thread)) return '上一条回复尚未完成。';
    final p = profile(c.apiProfileId);
    if (p == null) return '请先绑定模型。';
    final key = await getKey(p.id);
    if (key == null || key.isEmpty) return '请先填写 API Key。';
    final file = local.resolve(relativePath);
    if (!await file.exists()) return '图片文件不存在。';
    final size = await file.length();
    if (size > 5 * 1024 * 1024) return '多模态发送只支持 5MB 以内的图片。';
    final extension = relativePath.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'png' => 'image/png', 'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp', 'gif' => 'image/gif',
      _ => null,
    };
    if (mime == null) return '请使用 PNG、JPG、WEBP 或 GIF 图片。';
    sendLocalImage(thread, relativePath, text: '请看看这张图片，结合我们的聊天自然回应。');
    final run = _begin(thread);
    final client = http.Client(); _clients[thread] = client;
    try {
      final turns = _turns(thread, c.id);
      final bytes = await file.readAsBytes();
      if (turns.isEmpty) return '图片消息上下文为空。';
      turns[turns.length - 1] = ModelTurn('user', turns.last.text,
        imageBase64: base64Encode(bytes), imageMime: mime);
      TokenUsage? usage;
      final answer = await MultiModelApi.call(client: client, profile: p,
        apiKey: key, persona: c.persona, roleName: c.name,
        chatMode: data.chatMode, formatMode: formatFor(thread), turns: turns,
        onUsage: (u) => usage = u,
        onText: (text) { if (_current(thread,run)) _partial(thread,c.id,text); });
      if (_current(thread,run)) {
        _addMessage(thread, c.id, answer);
        if (usage != null) {
          final m = threadMessages(thread).last;
          m.inputTokens = usage!.input; m.outputTokens = usage!.output; _changed();
        }
      }
      return null;
    } catch (e) { return _current(thread,run) ? '$e' : null; }
    finally { _finish(thread,run,client); }
  }

  Future<String?> sendGroup(ChatGroup group, String text, {ChatEntry? quote}) async {
    final thread = groupThread(group.id);
    if (busy.contains(thread)) return '当前群聊正在生成回复。';
    _addMessage(thread, 'me', text,
      quotedText: quote?.text, quotedSender: quote == null ? null : displayName(quote.senderId));
    final run = _begin(thread);
    var replied = 0;
    final failures = <String>[];
    try {
      for (final characterId in group.memberIds) {
        if (!_current(thread,run) || replied >= group.maxReplies) break;
        final c = character(characterId);
        if (c == null) continue;
        final p = profile(c.apiProfileId);
        if (p == null) { failures.add('${c.name}未绑定 API'); continue; }
        final key = await getKey(p.id);
        if (key == null || key.isEmpty) { failures.add('${c.name}缺少 API Key'); continue; }
        if (!_current(thread,run)) break;
        final client = http.Client();
        _clients[thread] = client;
        try {
          final answer = await MultiModelApi.call(client: client,
            profile: p, apiKey: key, persona: c.persona,
            roleName: c.name, chatMode: data.chatMode,
            formatMode: formatFor(thread),
            turns: _turns(thread, c.id, group: true), group: true,
            onText: (text) {
              if (_current(thread,run)) _partial(thread, c.id, text);
            });
          if (_current(thread,run)) {
            _addMessage(thread, c.id, answer);
            replied++;
          }
        } catch (e) {
          if (_current(thread,run)) failures.add('${c.name}: $e');
        } finally {
          client.close();
          if (_current(thread,run)) _clearPartial(thread);
          if (identical(_clients[thread], client)) _clients.remove(thread);
        }
      }
      return failures.isEmpty ? null : failures.join('\n');
    } finally {
      if (_current(thread,run)) {
        _clients.remove(thread)?.close();
        _clearPartial(thread);
        busy.remove(thread);
        _stopped.remove(thread);
        notifyListeners();
      }
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
    final run = _begin(thread);
    final client = http.Client();
    _clients[thread] = client;
    try {
      final recent = <ChatEntry>[
        ...threadMessages(privateThread(c.id)),
        ...threadMessages('${privateThread(c.id)}:v41_story'),
      ].where((e)=>!e.recalled && e.senderId!='system' && e.text.trim().isNotEmpty)
        .toList()..sort((a,b)=>a.createdAt.compareTo(b.createdAt));
      final excerpt = recent.length>6 ? recent.sublist(recent.length-6) : recent;
      var summary = excerpt.map((e)=>
        '${e.senderId=='me'?'用户':c.name}：${e.text.replaceAll(RegExp(r'\s+'),' ')}').join('；');
      if(summary.length>900)summary=summary.substring(summary.length-900);
      final text = await MultiModelApi.call(client: client,
        profile: p, apiKey: key, persona: c.persona, roleName: c.name,
        turns: [ModelTurn('user',
          '请以当前角色第一人称写一条不超过 100 字的虚拟朋友圈动态。'
          '可适度呼应下面最近的聊天心情或共同爱好，但不要直接复述聊天私密内容、隐私身份、地址、联系方式，也不要声称现实未发生的事。'
          '自然、有生活感、不重复，必要时完全不提聊天内容。只输出正文。'
          '${summary.isEmpty?'':'最近聊天参考：$summary'}')]);
      if (c.allowMoments && _current(thread,run)) {
        data.moments.insert(0, MomentEntry(id: newId(),
          characterId: c.id, text: text, createdAt: DateTime.now()));
        _changed();
      }
      return null;
    } catch (e) { return _current(thread,run) ? '$e' : null; }
    finally {
      _finish(thread,run,client);
    }
  }

  @override
  void dispose() {
    for (final client in _clients.values) { client.close(); }
    music.dispose();
    super.dispose();
  }
}
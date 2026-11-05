import 'dart:convert';

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

Map<String, dynamic> mapJson(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> listJson(Object? value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

class ProviderPreset {
  final String id;
  final String label;
  final String baseUrl;
  final String exampleModel;
  const ProviderPreset(this.id, this.label, this.baseUrl, this.exampleModel);
}

const presets = [
  ProviderPreset('openai', 'OpenAI / GPT', 'https://api.openai.com/v1', 'gpt-4.1-mini'),
  ProviderPreset('anthropic', 'Claude', 'https://api.anthropic.com/v1', 'claude-sonnet-4-5'),
  ProviderPreset('gemini', 'Gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash'),
  ProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat'),
  ProviderPreset('glm', 'GLM / 智谱', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4.5'),
  ProviderPreset('custom', '中转站 / OpenAI 兼容', 'https://example.com/v1', 'model-id'),
];
ProviderPreset providerFor(String id) => presets.firstWhere(
  (p) => p.id == id, orElse: () => presets.last,
);

class ApiProfile {
  String id;
  String label;
  String provider;
  String baseUrl;
  String modelId;
  String anthropicVersion;
  String workspaceId;
  bool streaming;
  String authMode; // bearer / x-api-key (custom relays only)
  String apiProtocol; // chat / responses; custom relay only
  ApiProfile({required this.id, required this.label, required this.provider,
    required this.baseUrl, required this.modelId, this.anthropicVersion = '2026-10-21',
    this.workspaceId = '', this.streaming = true, this.authMode = 'bearer',
    this.apiProtocol = 'chat'});
  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
    id: '${j['id'] ?? newId()}', label: '${j['label'] ?? ''}',
    provider: '${j['provider'] ?? 'custom'}',
    baseUrl: '${j['baseUrl'] ?? ''}', modelId: '${j['modelId'] ?? ''}',
    anthropicVersion: '${j['anthropicVersion'] ?? '2026-10-21'}',
    workspaceId: '${j['workspaceId'] ?? ''}',
    streaming: j['streaming'] != false,
    authMode: '${j['authMode'] ?? 'bearer'}',
    apiProtocol: '${j['apiProtocol'] ?? 'chat'}');
  Map<String, dynamic> toJson() => {'id': id, 'label': label,
    'provider': provider, 'baseUrl': baseUrl, 'modelId': modelId,
    'anthropicVersion': anthropicVersion, 'workspaceId': workspaceId,
    'streaming': streaming, 'authMode': authMode,
    'apiProtocol': apiProtocol}; // API Key NEVER written here.
}

class Character {
  String id;
  String name;
  String persona;
  String? apiProfileId;
  bool allowMoments;
  bool allowSocialInteractions; // separately authorized; defaults OFF
  bool allowProactiveMessages; // separately authorized; defaults OFF
  List<String> friendIds; // reciprocal, local AI-to-AI friendships
  int avatarColor;
  String avatarPath; // app-private relative image path
  String intro; // short public profile description, not the persona file
  String chatBackgroundPath; // app-private image for this private conversation
  Character({required this.id, required this.name, required this.persona,
    this.apiProfileId, this.allowMoments = false,
    this.allowSocialInteractions = false, this.allowProactiveMessages = false,
    this.friendIds = const [],
    this.avatarColor = 0xFFB67BB8,
    this.avatarPath = '', this.intro = '', this.chatBackgroundPath = ''});
  factory Character.fromJson(Map<String, dynamic> j) => Character(
    id: '${j['id'] ?? newId()}', name: '${j['name'] ?? '未命名'}',
    persona: '${j['persona'] ?? ''}', apiProfileId: j['apiProfileId'] as String?,
    allowMoments: j['allowMoments'] == true,
    allowSocialInteractions: j['allowSocialInteractions'] == true,
    allowProactiveMessages: j['allowProactiveMessages'] == true,
    friendIds: (j['friendIds'] as List? ?? []).map((v) => '$v').toList(),
    avatarColor: (j['avatarColor'] as num?)?.toInt() ?? 0xFFB67BB8,
    avatarPath: '${j['avatarPath'] ?? ''}',
    intro: '${j['intro'] ?? ''}',
    chatBackgroundPath: '${j['chatBackgroundPath'] ?? ''}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'persona': persona,
    'apiProfileId': apiProfileId, 'allowMoments': allowMoments,
    'allowSocialInteractions': allowSocialInteractions,
    'allowProactiveMessages': allowProactiveMessages, 'friendIds': friendIds,
    'avatarColor': avatarColor, 'avatarPath': avatarPath,
    'intro': intro, 'chatBackgroundPath': chatBackgroundPath};
}

class ChatGroup {
  String id;
  String name;
  List<String> memberIds;
  int maxReplies;
  ChatGroup({required this.id, required this.name, required this.memberIds,
    this.maxReplies = 3});
  factory ChatGroup.fromJson(Map<String, dynamic> j) => ChatGroup(
    id: '${j['id'] ?? newId()}', name: '${j['name'] ?? ''}',
    memberIds: (j['memberIds'] as List? ?? []).map((v) => '$v').toList(),
    maxReplies: ((j['maxReplies'] as num?)?.toInt() ?? 3).clamp(1, 6).toInt());
  Map<String, dynamic> toJson() => {'id': id, 'name': name,
    'memberIds': memberIds, 'maxReplies': maxReplies};
}

class ChatEntry {
  String id;
  String threadId;
  String senderId; // 'me', 'system', or character ID
  String text;
  DateTime createdAt;
  String? quotedText;
  String? quotedSender;
  String? forwardedFrom;
  DateTime? editedAt;
  bool recalled;
  ChatEntry({required this.id, required this.threadId, required this.senderId,
    required this.text, required this.createdAt, this.quotedText,
    this.quotedSender, this.forwardedFrom, this.editedAt,
    this.recalled = false});
  factory ChatEntry.fromJson(Map<String, dynamic> j) => ChatEntry(
    id: '${j['id'] ?? newId()}', threadId: '${j['threadId'] ?? ''}',
    senderId: '${j['senderId'] ?? ''}', text: '${j['text'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
    quotedText: j['quotedText'] as String?,
    quotedSender: j['quotedSender'] as String?,
    forwardedFrom: j['forwardedFrom'] as String?,
    editedAt: DateTime.tryParse('${j['editedAt'] ?? ''}'),
    recalled: j['recalled'] == true);
  Map<String, dynamic> toJson() => {'id': id, 'threadId': threadId,
    'senderId': senderId, 'text': text, 'createdAt': createdAt.toIso8601String(),
    'quotedText': quotedText, 'quotedSender': quotedSender,
    'forwardedFrom': forwardedFrom, 'editedAt': editedAt?.toIso8601String(),
    'recalled': recalled};
}

class MomentComment {
  String id;
  String authorId; // 'me' or a Character ID
  String text;
  String? parentId; // optional reply-to; referential id within the same moment
  DateTime createdAt;
  MomentComment({required this.id, required this.authorId,
    required this.text, required this.createdAt, this.parentId});
  factory MomentComment.fromJson(Map<String, dynamic> j) => MomentComment(
    id: '${j['id'] ?? newId()}', authorId: '${j['authorId'] ?? 'me'}',
    text: '${j['text'] ?? ''}', parentId: j['parentId'] as String?,
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now());
  Map<String, dynamic> toJson() => {'id': id, 'authorId': authorId,
    'text': text, 'parentId': parentId, 'createdAt': createdAt.toIso8601String()};
}

class MomentEntry {
  String id;
  String characterId;
  String text;
  DateTime createdAt;
  List<String> likedBy; // 'me' and Character IDs
  List<MomentComment> comments;
  MomentEntry({required this.id, required this.characterId, required this.text,
    required this.createdAt, this.likedBy = const [], this.comments = const []});
  factory MomentEntry.fromJson(Map<String, dynamic> j) => MomentEntry(
    id: '${j['id'] ?? newId()}', characterId: '${j['characterId'] ?? ''}',
    text: '${j['text'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
    likedBy: (j['likedBy'] as List? ?? []).map((v) => '$v').toList(),
    comments: listJson(j['comments']).map(MomentComment.fromJson).toList());
  Map<String, dynamic> toJson() => {'id': id, 'characterId': characterId,
    'text': text, 'createdAt': createdAt.toIso8601String(),
    'likedBy': likedBy, 'comments': comments.map((c) => c.toJson()).toList()};
}

class LocalTrack {
  String id;
  String title;
  String relativePath; // copied to app's own private documents directory
  LocalTrack({required this.id, required this.title, required this.relativePath});
  factory LocalTrack.fromJson(Map<String, dynamic> j) => LocalTrack(
    id: '${j['id'] ?? newId()}', title: '${j['title'] ?? ''}',
    relativePath: '${j['relativePath'] ?? ''}');
  Map<String, dynamic> toJson() => {'id': id, 'title': title,
    'relativePath': relativePath};
}

/// An opt-in, locally stored upcoming event. The phone schedules a generic
/// notification; a real AI response is generated only when the app is opened.
class ProactiveEvent {
  String id;
  String characterId;
  String topic;
  DateTime dueAt;
  bool delivered;
  DateTime? lastAttemptAt;
  ProactiveEvent({required this.id, required this.characterId,
    required this.topic, required this.dueAt,
    this.delivered = false, this.lastAttemptAt});
  factory ProactiveEvent.fromJson(Map<String, dynamic> j) => ProactiveEvent(
    id: '${j['id'] ?? newId()}', characterId: '${j['characterId'] ?? ''}',
    topic: '${j['topic'] ?? ''}',
    dueAt: DateTime.tryParse('${j['dueAt'] ?? ''}') ?? DateTime.now(),
    delivered: j['delivered'] == true,
    lastAttemptAt: DateTime.tryParse('${j['lastAttemptAt'] ?? ''}'));
  Map<String, dynamic> toJson() => {'id': id, 'characterId': characterId,
    'topic': topic, 'dueAt': dueAt.toIso8601String(),
    'delivered': delivered, 'lastAttemptAt': lastAttemptAt?.toIso8601String()};
}

const List<String> defaultDesktopOrder = ['chat', 'api', 'music', 'settings'];

List<String> normalizeDesktopOrder(Object? raw) {
  final incoming = raw is List ? raw.map((v) => '$v') : const <String>[];
  final result = <String>[];
  for (final key in incoming) {
    if (defaultDesktopOrder.contains(key) && !result.contains(key)) result.add(key);
  }
  for (final key in defaultDesktopOrder) {
    if (!result.contains(key)) result.add(key);
  }
  return result;
}

class AppData {
  List<ApiProfile> profiles;
  List<Character> characters;
  List<ChatGroup> groups;
  List<ChatEntry> messages;
  List<MomentEntry> moments;
  List<LocalTrack> tracks;
  bool darkMode;
  int themeColor;
  double fontScale;
  String wallpaperPath;
  Map<String, String> desktopIcons;
  List<String> desktopOrder; // user-set icon position, preserved between launches
  bool autoMomentReplies; // only for user comments; defaults OFF
  bool autoMomentInteractions; // foreground only; defaults OFF
  DateTime? lastAutoInteractionAt;
  double chatBubbleOpacity;
  int myBubbleColor;
  int aiBubbleColor;
  bool showChatTime;
  String chatMode; // daily / story
  bool allowProactiveMessages;
  List<ProactiveEvent> proactiveEvents;
  AppData({required this.profiles, required this.characters, required this.groups,
    required this.messages, required this.moments, required this.tracks,
    this.darkMode = false, this.themeColor = 0xFF8870B5, this.fontScale = 1,
    this.wallpaperPath = '', this.desktopIcons = const {},
    this.desktopOrder = defaultDesktopOrder,
    this.autoMomentReplies = false, this.autoMomentInteractions = false,
    this.lastAutoInteractionAt, this.chatBubbleOpacity = 1.0,
    this.myBubbleColor = 0xFFB8EC9C, this.aiBubbleColor = 0xFFFFFFFF,
    this.showChatTime = false, this.chatMode = 'daily',
    this.allowProactiveMessages = false, this.proactiveEvents = const []});
  factory AppData.initial() => AppData(
    profiles: [], characters: [
      Character(id: 'sample_xiaoman', name: '小满',
        persona: '你叫小满，性格温柔、开朗，说话自然、亲近，但不油腻。'
          '你会记住本次聊天的事情，不凭空声称自己在现实世界做过的事。'
          '用简短自然的中文回复。', avatarColor: 0xFFF0A5A4),
      Character(id: 'sample_aze', name: '阿泽',
        persona: '你叫阿泽，性格沉稳、理性，偶尔冷幽默。'
          '说话简洁，乐于倾听，不随意断言现实事实。', avatarColor: 0xFF8BA9D1),
    ], groups: [], messages: [], moments: [], tracks: [],
    proactiveEvents: []);
  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
    profiles: listJson(j['profiles']).map(ApiProfile.fromJson).toList(),
    characters: listJson(j['characters']).map(Character.fromJson).toList(),
    groups: listJson(j['groups']).map(ChatGroup.fromJson).toList(),
    messages: listJson(j['messages']).map(ChatEntry.fromJson).toList(),
    moments: listJson(j['moments']).map(MomentEntry.fromJson).toList(),
    tracks: listJson(j['tracks']).map(LocalTrack.fromJson).toList(),
    darkMode: j['darkMode'] == true,
    themeColor: (j['themeColor'] as num?)?.toInt() ?? 0xFF8870B5,
    fontScale: (j['fontScale'] as num?)?.toDouble() ?? 1,
    wallpaperPath: '${j['wallpaperPath'] ?? ''}',
    desktopIcons: mapJson(j['desktopIcons']).map((k, v) => MapEntry(k, '$v')),
    desktopOrder: normalizeDesktopOrder(j['desktopOrder']),
    autoMomentReplies: j['autoMomentReplies'] == true,
    autoMomentInteractions: j['autoMomentInteractions'] == true,
    lastAutoInteractionAt: DateTime.tryParse('${j['lastAutoInteractionAt'] ?? ''}'),
    chatBubbleOpacity: ((j['chatBubbleOpacity'] as num?)?.toDouble() ?? 1.0).clamp(.35, 1.0).toDouble(),
    myBubbleColor: (j['myBubbleColor'] as num?)?.toInt() ?? 0xFFB8EC9C,
    aiBubbleColor: (j['aiBubbleColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
    showChatTime: j['showChatTime'] == true,
    chatMode: j['chatMode'] == 'story' ? 'story' : 'daily',
    allowProactiveMessages: j['allowProactiveMessages'] == true,
    proactiveEvents: listJson(j['proactiveEvents'])
      .map(ProactiveEvent.fromJson).toList());
  Map<String, dynamic> toJson() => {
    'version': 6,
    'profiles': profiles.map((v) => v.toJson()).toList(),
    'characters': characters.map((v) => v.toJson()).toList(),
    'groups': groups.map((v) => v.toJson()).toList(),
    'messages': messages.map((v) => v.toJson()).toList(),
    'moments': moments.map((v) => v.toJson()).toList(),
    'tracks': tracks.map((v) => v.toJson()).toList(),
    'darkMode': darkMode, 'themeColor': themeColor,
    'fontScale': fontScale, 'wallpaperPath': wallpaperPath,
    'desktopIcons': desktopIcons, 'desktopOrder': desktopOrder,
    'autoMomentReplies': autoMomentReplies,
    'autoMomentInteractions': autoMomentInteractions,
    'lastAutoInteractionAt': lastAutoInteractionAt?.toIso8601String(),
    'chatBubbleOpacity': chatBubbleOpacity,
    'myBubbleColor': myBubbleColor, 'aiBubbleColor': aiBubbleColor,
    'showChatTime': showChatTime, 'chatMode': chatMode,
    'allowProactiveMessages': allowProactiveMessages,
    'proactiveEvents': proactiveEvents.map((e) => e.toJson()).toList(),
  };
  String serialize() => jsonEncode(toJson());
}

String privateThread(String id) => 'private:$id';
String groupThread(String id) => 'group:$id';

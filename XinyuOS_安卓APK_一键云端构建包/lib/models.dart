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
  ProviderPreset('custom', '自定义兼容接口', 'https://example.com/v1', 'model-id'),
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
  ApiProfile({required this.id, required this.label, required this.provider,
    required this.baseUrl, required this.modelId, this.anthropicVersion = '2026-10-21',
    this.workspaceId = ''});
  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
    id: '${j['id'] ?? newId()}', label: '${j['label'] ?? ''}',
    provider: '${j['provider'] ?? 'custom'}',
    baseUrl: '${j['baseUrl'] ?? ''}', modelId: '${j['modelId'] ?? ''}',
    anthropicVersion: '${j['anthropicVersion'] ?? '2026-10-21'}',
    workspaceId: '${j['workspaceId'] ?? ''}');
  Map<String, dynamic> toJson() => {'id': id, 'label': label,
    'provider': provider, 'baseUrl': baseUrl, 'modelId': modelId,
    'anthropicVersion': anthropicVersion, 'workspaceId': workspaceId}; // API Key NEVER written here.
}

class Character {
  String id;
  String name;
  String persona;
  String? apiProfileId;
  bool allowMoments;
  int avatarColor;
  Character({required this.id, required this.name, required this.persona,
    this.apiProfileId, this.allowMoments = false, this.avatarColor = 0xFFB67BB8});
  factory Character.fromJson(Map<String, dynamic> j) => Character(
    id: '${j['id'] ?? newId()}', name: '${j['name'] ?? '未命名'}',
    persona: '${j['persona'] ?? ''}', apiProfileId: j['apiProfileId'] as String?,
    allowMoments: j['allowMoments'] == true,
    avatarColor: (j['avatarColor'] as num?)?.toInt() ?? 0xFFB67BB8);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'persona': persona,
    'apiProfileId': apiProfileId, 'allowMoments': allowMoments,
    'avatarColor': avatarColor};
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
  ChatEntry({required this.id, required this.threadId, required this.senderId,
    required this.text, required this.createdAt});
  factory ChatEntry.fromJson(Map<String, dynamic> j) => ChatEntry(
    id: '${j['id'] ?? newId()}', threadId: '${j['threadId'] ?? ''}',
    senderId: '${j['senderId'] ?? ''}', text: '${j['text'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now());
  Map<String, dynamic> toJson() => {'id': id, 'threadId': threadId,
    'senderId': senderId, 'text': text, 'createdAt': createdAt.toIso8601String()};
}

class MomentEntry {
  String id;
  String characterId;
  String text;
  DateTime createdAt;
  MomentEntry({required this.id, required this.characterId, required this.text,
    required this.createdAt});
  factory MomentEntry.fromJson(Map<String, dynamic> j) => MomentEntry(
    id: '${j['id'] ?? newId()}', characterId: '${j['characterId'] ?? ''}',
    text: '${j['text'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now());
  Map<String, dynamic> toJson() => {'id': id, 'characterId': characterId,
    'text': text, 'createdAt': createdAt.toIso8601String()};
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
  AppData({required this.profiles, required this.characters, required this.groups,
    required this.messages, required this.moments, required this.tracks,
    this.darkMode = false, this.themeColor = 0xFF8870B5, this.fontScale = 1,
    this.wallpaperPath = ''});
  factory AppData.initial() => AppData(
    profiles: [], characters: [
      Character(id: 'sample_xiaoman', name: '小满',
        persona: '你叫小满，性格温柔、开朗，说话自然、亲近，但不油腻。'
          '你会记住本次聊天的事情，不凭空声称自己在现实世界做过的事。'
          '用简短自然的中文回复。', avatarColor: 0xFFF0A5A4),
      Character(id: 'sample_aze', name: '阿泽',
        persona: '你叫阿泽，性格沉稳、理性，偶尔冷幽默。'
          '说话简洁，乐于倾听，不随意断言现实事实。', avatarColor: 0xFF8BA9D1),
    ], groups: [], messages: [], moments: [], tracks: []);
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
    wallpaperPath: '${j['wallpaperPath'] ?? ''}');
  Map<String, dynamic> toJson() => {
    'version': 3,
    'profiles': profiles.map((v) => v.toJson()).toList(),
    'characters': characters.map((v) => v.toJson()).toList(),
    'groups': groups.map((v) => v.toJson()).toList(),
    'messages': messages.map((v) => v.toJson()).toList(),
    'moments': moments.map((v) => v.toJson()).toList(),
    'tracks': tracks.map((v) => v.toJson()).toList(),
    'darkMode': darkMode, 'themeColor': themeColor,
    'fontScale': fontScale, 'wallpaperPath': wallpaperPath,
  };
  String serialize() => jsonEncode(toJson());
}

String privateThread(String id) => 'private:$id';
String groupThread(String id) => 'group:$id';

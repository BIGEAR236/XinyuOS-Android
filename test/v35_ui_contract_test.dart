import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/models.dart';

void main() {
  test('旧存档升级时默认保留四个桌面图标顺序', () {
    final original = AppData.initial();
    final legacy = original.toJson()..remove('desktopOrder');
    final recovered = AppData.fromJson(legacy);
    expect(recovered.desktopOrder, defaultDesktopOrder);
    expect(recovered.characters.first.chatBackgroundPath, isEmpty);
  });

  test('拖动顺序可安全去重与补全，并能持久化', () {
    expect(normalizeDesktopOrder(['music', 'music', 'junk', 'chat']),
      ['music', 'chat', 'api', 'settings', 'album', 'memo', 'diary', 'world', 'wallet', 'pet', 'shop', 'watch']);
    final app = AppData.initial();
    app.desktopOrder = ['settings', 'chat', 'music', 'api'];
    final decoded = AppData.fromJson(mapJson(jsonDecode(app.serialize())));
    expect(decoded.desktopOrder, normalizeDesktopOrder(app.desktopOrder));
  });

  test('独立个人介绍、头像、模型、聊天背景序列化不损伤剧本或授权', () {
    final c = Character(id: 'character123', name: '小满',
      persona: '（抬眼）好久不见。', intro: '多年未见的朋友',
      avatarPath: 'avatars/avatar.png',
      chatBackgroundPath: 'chat_backgrounds/sakura.jpg',
      apiProfileId: 'api1', allowProactiveMessages: true,
      allowMoments: true, allowSocialInteractions: true);
    final restored = Character.fromJson(mapJson(jsonDecode(jsonEncode(c.toJson()))));
    expect(restored.persona, c.persona);
    expect(restored.intro, c.intro);
    expect(restored.chatBackgroundPath, c.chatBackgroundPath);
    expect(restored.avatarPath, c.avatarPath);
    expect(restored.apiProfileId, 'api1');
    expect(restored.allowProactiveMessages, true);
    expect(restored.allowMoments, true);
    expect(restored.allowSocialInteractions, true);
  });

  test('沉浸剧情模式以及消息编辑、引用、撤回字段原样保留', () {
    final app = AppData.initial();
    app.chatMode = 'story';
    app.messages.add(ChatEntry(id: 'message1',
      threadId: 'private:sample_xiaoman', senderId: 'me', text: '下周有比赛',
      createdAt: DateTime(2026, 11, 5), quotedText: '你好',
      editedAt: DateTime(2026, 11, 5, 18)));
    final restored = AppData.fromJson(mapJson(jsonDecode(app.serialize())));
    expect(restored.chatMode, 'story');
    expect(restored.messages.single.quotedText, '你好');
    expect(restored.messages.single.editedAt, isNotNull);
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/api_client.dart';
import 'package:xinyu_os/models.dart';

void main() {
  test('日常聊天禁止照搬剧本，沉浸剧情保留故事风格', () {
    const persona = '姓名：小满\n性格：温柔\n（他抬眼看着你）\n第一幕：旧日相逢';
    final daily = MultiModelApi.systemPrompt(persona, roleName: '小满');
    expect(daily, contains('我叫小满'));
    expect(daily, contains('禁止使用括号描写动作'));
    expect(daily, isNot(contains('（他抬眼看着你）')));
    final story = MultiModelApi.systemPrompt(persona, roleName: '小满', chatMode: 'story');
    expect(story, contains('允许适量动作和环境描写'));
    expect(story, contains('（他抬眼看着你）'));
  });

  test('消息引用、转发、编辑、撤回序列化兼容 V3.3', () {
    final old = ChatEntry.fromJson({
      'id': 'old', 'threadId': 'private:a', 'senderId': 'me',
      'text': '你好', 'createdAt': '2026-11-05T10:00:00.000',
    });
    expect(old.recalled, isFalse);
    expect(old.quotedText, isNull);
    final newMsg = ChatEntry(id: 'new', threadId: 'private:a',
      senderId: 'me', text: '好呀', createdAt: DateTime(2026, 11, 5),
      quotedText: '明天见', quotedSender: '小满',
      forwardedFrom: '阿泽', editedAt: DateTime(2026, 11, 5), recalled: false);
    final decoded = ChatEntry.fromJson(mapJson(jsonDecode(jsonEncode(newMsg.toJson()))));
    expect(decoded.quotedText, '明天见');
    expect(decoded.forwardedFrom, '阿泽');
    expect(decoded.editedAt, isNotNull);
  });

  test('旧角色默认无主动关怀权限；事件与配置本地持久化', () {
    final app = AppData.initial();
    expect(app.allowProactiveMessages, false);
    expect(app.chatMode, 'daily');
    expect(app.characters.first.allowProactiveMessages, false);
    app.chatMode = 'story';
    app.allowProactiveMessages = true;
    app.characters.first.allowProactiveMessages = true;
    app.proactiveEvents.add(ProactiveEvent(id: 'ev1',
      characterId: app.characters.first.id, topic: '下周的比赛',
      dueAt: DateTime(2026, 11, 12, 18, 0)));
    final restored = AppData.fromJson(mapJson(jsonDecode(app.serialize())));
    expect(restored.chatMode, 'story');
    expect(restored.allowProactiveMessages, true);
    expect(restored.proactiveEvents.single.topic, '下周的比赛');
    expect(restored.characters.first.allowProactiveMessages, true);
  });
}

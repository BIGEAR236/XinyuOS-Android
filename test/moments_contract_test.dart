import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/api_client.dart';
import 'package:xinyu_os/models.dart';

void main() {
  test('既有朋友圈无需迁移，旧字段默认不互动', () {
    final legacy = MomentEntry.fromJson({
      'id': 'm1', 'characterId': 'a', 'text': '今天心情不错',
      'createdAt': '2026-11-05T12:00:00.000',
    });
    expect(legacy.comments, isEmpty);
    expect(legacy.likedBy, isEmpty);
    final oldCharacter = Character.fromJson({
      'id': 'a', 'name': '小满', 'persona': '温柔', 'allowMoments': true,
    });
    expect(oldCharacter.allowMoments, isTrue);
    expect(oldCharacter.allowSocialInteractions, isFalse);
    expect(oldCharacter.friendIds, isEmpty);
  });

  test('评论、回复关系与点赞可以本地 JSON 往返持久化', () {
    final app = AppData.initial();
    app.autoMomentReplies = true;
    app.showChatTime = true;
    app.chatBubbleOpacity = .6;
    app.moments.add(MomentEntry(id: 'post1', characterId: 'sample_xiaoman',
      text: '咖啡不错', createdAt: DateTime(2026, 11, 5),
      likedBy: ['me', 'sample_aze'], comments: [
        MomentComment(id: 'c1', authorId: 'me', text: '哪家的？',
          createdAt: DateTime(2026, 11, 5)),
        MomentComment(id: 'c2', authorId: 'sample_xiaoman',
          text: '街角的呀', parentId: 'c1',
          createdAt: DateTime(2026, 11, 5)),
      ]));
    app.characters.first.allowSocialInteractions = true;
    app.characters.first.friendIds = ['sample_aze'];
    final recovered = AppData.fromJson(mapJson(jsonDecode(app.serialize())));
    expect(recovered.autoMomentReplies, isTrue);
    expect(recovered.showChatTime, isTrue);
    expect(recovered.chatBubbleOpacity, .6);
    expect(recovered.moments.single.likedBy, ['me', 'sample_aze']);
    expect(recovered.moments.single.comments.last.parentId, 'c1');
    expect(recovered.characters.first.allowSocialInteractions, isTrue);
    expect(recovered.characters.first.friendIds, ['sample_aze']);
  });

  test('模型列表兼容 OpenAI 和 Gemini 等格式', () {
    const openaiModels = '{"data":[{"id":"gpt-a"},{"id":"relay-b"}]}';
    const geminiModels = '{"models":[{"name":"models/gemini-a"}]}';
    expect(MultiModelApi.parseModelList(openaiModels), ['gpt-a', 'relay-b']);
    expect(MultiModelApi.parseModelList(geminiModels), ['gemini-a']);
  });

  test('中转站支持 Responses API 的独立路径与参数', () {
    final profile = ApiProfile(id: 'p1', label: '中转', provider: 'custom',
      baseUrl: 'https://relay.example/v1', modelId: 'relay-model',
      apiProtocol: 'responses', streaming: false);
    final request = MultiModelApi.buildRequest(profile: profile,
      apiKey: 'FAKE_TEST_KEY', persona: '温柔',
      turns: const [ModelTurn('user', '你好')]);
    expect(request.uri.toString(), 'https://relay.example/v1/responses');
    expect(request.payload.containsKey('input'), true);
    expect(request.payload.containsKey('messages'), false);
    expect(MultiModelApi.modelListEndpoint(profile).toString(),
      'https://relay.example/v1/models');
    expect(MultiModelApi.parseResponse('responses', jsonEncode({
      'output': [{'content': [{'type': 'output_text', 'text': '你好'}]}]
    })), '你好');
    const stream = 'data: {"type":"response.output_text.delta","delta":"你好"}\n\n';
    expect(MultiModelApi.parseSseText('responses', stream), '你好');
  });
}

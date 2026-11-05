import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/models.dart';
import 'package:xinyu_os/api_client.dart';

void main() {
  test('new fields migrate safely from legacy data', () {
    final old = AppData.initial().toJson();
    old.remove('notes'); old.remove('albumPaths');
    old.remove('myAvatarPath'); old.remove('fontPath');
    final loaded = AppData.fromJson(old);
    expect(loaded.notes, isEmpty);
    expect(loaded.albumPaths, isEmpty);
    expect(loaded.myAvatarPath, isEmpty);
    expect(loaded.desktopOrder, contains('diary'));
  });

  test('message history, image reference and exact reported usage survive JSON', () {
    final m = ChatEntry(id: 'm', threadId: 'private:c', senderId: 'c',
      text: '新版', createdAt: DateTime(2026,11,5),
      previousVersions: ['旧版'], imagePath: 'chat_images/demo.png',
      inputTokens: 24, outputTokens: 8);
    final decoded = ChatEntry.fromJson(mapJson(jsonDecode(jsonEncode(m.toJson()))));
    expect(decoded.previousVersions, ['旧版']);
    expect(decoded.imagePath, m.imagePath);
    expect(decoded.inputTokens, 24);
    expect(decoded.outputTokens, 8);
  });

  test('OpenAI-compatible vision request embeds image only in the current turn', () {
    final p = ApiProfile(id: 'test', label: 'relay', provider: 'custom',
      baseUrl: 'https://example.com/v1', modelId: 'vision', streaming: false);
    final r = MultiModelApi.buildRequest(profile: p, apiKey: 'test-key',
      persona: '测试', turns: [const ModelTurn('user','这是什么？',
        imageBase64: 'YWJj', imageMime: 'image/png')]);
    final messages = r.payload['messages'] as List;
    final last = messages.last as Map;
    final content = last['content'] as List;
    expect(content.last['type'], 'image_url');
    expect(content.last['image_url']['url'], contains('image/png;base64,YWJj'));
    expect(jsonEncode(r.payload), isNot(contains('api_key')));
  });

  test('provider returned token usage is used, missing usage is not invented', () {
    final u = MultiModelApi.usageFromResponse('openai', {
      'usage': {'prompt_tokens': 45, 'completion_tokens': 22}});
    expect(u?.input, 45); expect(u?.output, 22);
    expect(MultiModelApi.usageFromResponse('openai', {}), isNull);
  });
}

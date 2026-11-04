import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/api_client.dart';
import 'package:xinyu_os/models.dart';

ApiProfile p(String provider) {
  final preset = providerFor(provider);
  return ApiProfile(id: 'test', label: preset.label,
    provider: provider, baseUrl: preset.baseUrl, modelId: preset.exampleModel);
}

void main() {
  const turns = [ModelTurn('user', '你好')];

  test('本地数据快照永远不包含 API Key', () {
    final data = AppData.initial();
    data.profiles.add(p('openai'));
    final json = data.serialize();
    expect(json, isNot(contains('Bearer ')));
    expect(json, isNot(contains('sk-test-secret')));
    expect(data.characters.every((c) => !c.allowMoments), isTrue);
  });

  test('OpenAI Chat Completions 的路径和 Bearer', () {
    final req = MultiModelApi.buildRequest(profile: p('openai'),
      apiKey: 'TEST_KEY', persona: '温柔', turns: turns);
    expect(req.uri.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(req.headers['Authorization'], 'Bearer TEST_KEY');
    expect((req.payload['messages'] as List).first['role'], 'system');
  });

  test('DeepSeek 和 GLM 兼容接口', () {
    for (final id in ['deepseek', 'glm']) {
      final req = MultiModelApi.buildRequest(profile: p(id),
        apiKey: 'TEST_KEY', persona: '理性', turns: turns);
      expect(req.uri.path, endsWith('/chat/completions'));
      expect(req.headers['Authorization'], 'Bearer TEST_KEY');
      expect(req.payload['model'], isNotEmpty);
    }
  });

  test('Claude: Messages API 和 API 版本', () {
    final req = MultiModelApi.buildRequest(profile: p('anthropic'),
      apiKey: 'TEST_KEY', persona: '小满', turns: turns);
    expect(req.uri.toString(), 'https://api.anthropic.com/v1/messages');
    expect(req.headers['anthropic-version'], isNotEmpty);
    expect(req.headers['x-api-key'], 'TEST_KEY');
    expect(req.payload['system'], contains('小满'));
    expect(req.payload['max_tokens'], 512);
  });

  test('Gemini: 原生 generateContent 格式', () {
    final req = MultiModelApi.buildRequest(profile: p('gemini'),
      apiKey: 'TEST_KEY', persona: '小满', turns: turns);
    expect(req.uri.path, contains(':generateContent'));
    expect(req.headers['x-goog-api-key'], 'TEST_KEY');
    expect(req.payload['systemInstruction'], isA<Map>());
    expect((req.payload['contents'] as List).first['role'], 'user');
  });

  test('拒绝非 HTTPS 服务商地址', () {
    final test = p('custom')..baseUrl = 'http://not-secure.example/v1';
    expect(() => MultiModelApi.buildRequest(profile: test,
      apiKey: 'SECRET', persona: '', turns: turns),
      throwsA(isA<ApiCallFailure>()));
  });

  test('从五类模型回复中提取正文', () {
    final compat = jsonEncode({'choices': [{'message': {'content': '兼容回复'}}]});
    expect(MultiModelApi.parseResponse('openai', compat), '兼容回复');
    expect(MultiModelApi.parseResponse('deepseek', compat), '兼容回复');
    expect(MultiModelApi.parseResponse('glm', compat), '兼容回复');
    expect(MultiModelApi.parseResponse('anthropic', jsonEncode({
      'content': [{'type': 'text', 'text': 'Claude 回复'}]})), 'Claude 回复');
    expect(MultiModelApi.parseResponse('gemini', jsonEncode({
      'candidates': [{'content': {'parts': [{'text': 'Gemini 回复'}]}}]})), 'Gemini 回复');
  });

  test('解析空回复会给出错误，而不是伪造成功内容', () {
    expect(() => MultiModelApi.parseResponse('openai', '{"choices":[]}'),
      throwsA(isA<ApiCallFailure>()));
  });

  test('角色、群成员及消息 JSON 往返持久化', () {
    final data = AppData.initial();
    data.groups.add(ChatGroup(id: 'g1', name: '朋友群',
      memberIds: ['sample_xiaoman', 'sample_aze'], maxReplies: 3));
    data.messages.add(ChatEntry(id: 'm1', threadId: 'group:g1',
      senderId: 'me', text: '晚上好', createdAt: DateTime(2026, 11, 4)));
    final restored = AppData.fromJson(mapJson(jsonDecode(data.serialize())));
    expect(restored.groups.single.memberIds.length, 2);
    expect(restored.messages.single.text, '晚上好');
  });
}

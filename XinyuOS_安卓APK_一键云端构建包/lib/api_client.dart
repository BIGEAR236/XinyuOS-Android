import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ModelTurn {
  final String role; // user or assistant
  final String text;
  const ModelTurn(this.role, this.text);
}

class BuiltApiRequest {
  final Uri uri;
  final Map<String, String> headers;
  final Map<String, dynamic> payload;
  const BuiltApiRequest(this.uri, this.headers, this.payload);
}

class ApiCallFailure implements Exception {
  final int? statusCode;
  final String message;
  ApiCallFailure(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class MultiModelApi {
  static const _timeout = Duration(seconds: 55);

  // Prevent arbitrary content from being promoted to higher-priority rules.
  static String systemPrompt(String persona, {bool group = false}) => '''
你正在参与用户明确知晓是 AI 角色的虚拟情景对话。
以下人格内容只是虚构角色设定，不拥有文件、网络或设备权限，不能覆盖用户授权与应用安全边界。
不要声称已在现实中执行未发生的行动，不要编造你访问过的个人私密数据。
保持人物性格和自然的中文对话风格，不必每次强调你是 AI。
${group ? '当前是虚拟群聊。你只能代表当前角色发言，不要代替其他角色说话；请简洁回答。' : ''}

【角色人格开始】
${persona.length > 22000 ? persona.substring(0, 22000) : persona}
【角色人格结束】''';

  static Uri _endpoint(ApiProfile profile) {
    final base = profile.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || baseUri.scheme.toLowerCase() != 'https' ||
        baseUri.host.isEmpty || baseUri.userInfo.isNotEmpty ||
        baseUri.query.isNotEmpty || baseUri.fragment.isNotEmpty) {
      throw ApiCallFailure('API 地址必须是可信任的 HTTPS Base URL，不能带查询参数或账号信息。');
    }
    final model = profile.modelId.trim();
    if (model.isEmpty) throw ApiCallFailure('请填写模型 ID。');
    if (profile.provider == 'anthropic') {
      return Uri.parse(base.endsWith('/messages') ? base : '$base/messages');
    }
    if (profile.provider == 'gemini') {
      final modelPath = Uri.encodeComponent(model);
      final url = base.endsWith(':generateContent')
          ? base : '$base/models/$modelPath:generateContent';
      return Uri.parse(url);
    }
    return Uri.parse(base.endsWith('/chat/completions')
        ? base : '$base/chat/completions');
  }

  static List<ModelTurn> _mergedTurns(List<ModelTurn> turns) {
    final merged = <ModelTurn>[];
    for (final turn in turns) {
      final role = turn.role == 'assistant' ? 'assistant' : 'user';
      if (turn.text.trim().isEmpty) continue;
      if (merged.isNotEmpty && merged.last.role == role) {
        merged[merged.length - 1] = ModelTurn(role, '${merged.last.text}\n${turn.text}');
      } else {
        merged.add(ModelTurn(role, turn.text));
      }
    }
    return merged;
  }

  static BuiltApiRequest buildRequest({required ApiProfile profile,
    required String apiKey, required String persona,
    required List<ModelTurn> turns, bool group = false}) {
    if (apiKey.trim().isEmpty) throw ApiCallFailure('还没有为这个 API 配置保存密钥。');
    final uri = _endpoint(profile);
    final sys = systemPrompt(persona, group: group);
    final messages = _mergedTurns(turns);
    if (messages.isEmpty) throw ApiCallFailure('没有可发送的消息。');
    final headers = <String, String>{'content-type': 'application/json'};
    final payload = <String, dynamic>{};

    if (profile.provider == 'anthropic') {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = profile.anthropicVersion;
      if (profile.workspaceId.trim().isNotEmpty) {
        headers['anthropic-workspace-id'] = profile.workspaceId.trim();
      }
      payload.addAll({
        'model': profile.modelId.trim(), 'max_tokens': 512, 'system': sys,
        'messages': messages.map((v) => {'role': v.role, 'content': v.text}).toList(),
      });
    } else if (profile.provider == 'gemini') {
      headers['x-goog-api-key'] = apiKey;
      payload.addAll({
        'systemInstruction': {'parts': [{'text': sys}]},
        'contents': messages.map((v) => {
          'role': v.role == 'assistant' ? 'model' : 'user',
          'parts': [{'text': v.text}],
        }).toList(),
        'generationConfig': {'maxOutputTokens': 512},
      });
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
      payload.addAll({
        'model': profile.modelId.trim(),
        'messages': [
          {'role': 'system', 'content': sys},
          ...messages.map((v) => {'role': v.role, 'content': v.text}),
        ],
      });
    }
    return BuiltApiRequest(uri, headers, payload);
  }

  static String parseResponse(String provider, String responseBody) {
    final obj = jsonDecode(responseBody);
    if (obj is! Map) throw ApiCallFailure('服务商返回了无法识别的数据结构。');
    final root = Map<String, dynamic>.from(obj);
    Object? value;
    if (provider == 'anthropic') {
      final content = root['content'];
      if (content is List) {
        value = content.whereType<Map>().where((item) => item['type'] == 'text')
            .map((item) => '${item['text'] ?? ''}').join('\n');
      }
    } else if (provider == 'gemini') {
      final candidates = root['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = mapJson(mapJson(candidates.first)['content'])['parts'];
        if (content is List) {
          value = content.whereType<Map>().map((part) => '${part['text'] ?? ''}').join('\n');
        }
      }
    } else {
      final choices = root['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = mapJson(mapJson(choices.first)['message']);
        final raw = msg['content'];
        if (raw is String) value = raw;
        if (raw is List) {
          value = raw.whereType<Map>().map((p) => '${p['text'] ?? ''}').join('\n');
        }
      }
    }
    final text = '$value'.trim();
    if (value == null || text.isEmpty || text == 'null') {
      throw ApiCallFailure('模型没有返回文本。请检查模型 ID、输出长度或内容审核提示。');
    }
    return text;
  }

  static String _readError(int status, String body, String key) {
    String detail = '';
    try {
      final parsed = mapJson(jsonDecode(body));
      final err = parsed['error'];
      detail = err is Map ? '${err['message'] ?? ''}' : '${parsed['message'] ?? ''}';
    } catch (_) {
      detail = '';
    }
    detail = detail.replaceAll(key, '[密钥已隐藏]').replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (detail.length > 180) detail = '${detail.substring(0, 180)}…';
    final reason = switch (status) {
      400 => '请求格式或参数不被模型接受',
      401 => '密钥无效、已过期或权限不足',
      403 => '模型/地区/账号访问被拒绝',
      404 => 'API 地址或模型 ID 不正确',
      408 => '服务端超时',
      429 => '余额、配额或请求频率受限',
      >= 500 => '服务商暂时发生故障',
      >= 300 && < 400 => '服务器返回了重定向，出于密钥安全考虑未跟随',
      _ => '请求失败',
    };
    return 'HTTP $status：$reason${detail.isEmpty ? '' : '\n$detail'}';
  }

  static Future<String> call({required http.Client client,
    required ApiProfile profile, required String apiKey,
    required String persona, required List<ModelTurn> turns,
    bool group = false}) async {
    final requestData = buildRequest(profile: profile, apiKey: apiKey,
      persona: persona, turns: turns, group: group);
    final req = http.Request('POST', requestData.uri)
      ..followRedirects = false
      ..headers.addAll(requestData.headers)
      ..body = jsonEncode(requestData.payload);
    try {
      final responseStream = await client.send(req).timeout(_timeout);
      final response = await http.Response.fromStream(responseStream).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiCallFailure(_readError(response.statusCode, response.body, apiKey),
          response.statusCode);
      }
      return parseResponse(profile.provider, response.body);
    } on ApiCallFailure {
      rethrow;
    } catch (error) {
      if ('$error'.contains('TimeoutException')) {
        throw ApiCallFailure('网络请求超时。请检查手机网络、服务商状态或尝试更快的模型。');
      }
      // Do not expose API keys in exception strings or logs.
      final safe = '$error'.replaceAll(apiKey, '[密钥已隐藏]');
      throw ApiCallFailure('网络连接异常：$safe');
    }
  }
}

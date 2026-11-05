import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ModelTurn {
  final String role;
  final String text;
  final String? imageBase64;
  final String? imageMime;
  const ModelTurn(this.role, this.text, {this.imageBase64, this.imageMime});
}

class TokenUsage {
  final int? input;
  final int? output;
  const TokenUsage(this.input, this.output);
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

/// Mobile HTTP transport. All keys remain on the device; the configured
/// model provider / relay receives the key and conversation as intended.
class MultiModelApi {
  static const _connectTimeout = Duration(seconds: 30);
  static const _receiveTimeout = Duration(seconds: 60);
  static const int personaLimit = 8000;

  /// Keep free-form imported files separate from chat instructions. A long
  /// screenplay is source material, not a transcript that the AI must replay.
  static String _profileExcerpt(String raw, {required bool story}) {
    final input = raw.trim();
    if (story) return input.length > 6500 ? input.substring(0, 6500) : input;
    final lines = input.split(RegExp(r'[\r\n]+'));
    final fields = <String>[];
    final field = RegExp(r'(姓名|名字|昵称|身份|性格|语气|口头禅|背景|职业|年龄|关系|爱好|喜好|经历|特点)');
    for (final line in lines) {
      final t = line.trim();
      if (t.length < 3 || t.length > 210) continue;
      if (t.startsWith('（') || t.startsWith('(') || t.startsWith('【剧情') ||
          t.startsWith('「') || t.startsWith('“') || t.contains('：「')) continue;
      if (field.hasMatch(t)) fields.add(t);
      if (fields.join('\n').length >= 1300) break;
    }
    final summary = fields.isEmpty ? input.substring(0,
      input.length > 1100 ? 1100 : input.length) : fields.join('\n');
    return summary.length > 1800 ? summary.substring(0, 1800) : summary;
  }

  static String systemPrompt(String persona, {bool group = false,
      String roleName = '', String chatMode = 'daily'}) {
    final story = chatMode == 'story';
    final name = roleName.trim();
    final setting = _profileExcerpt(persona, story: story);
    return '''你是一个供用户互动的虚构 AI 角色，唯一角色名字是「${name.isEmpty ? '未命名' : name}」。
你必须优先回答用户当前的问题。角色设定是背景资料，不是需要续写的历史聊天记录。
【最高优先级的日常交流规则】
- 问「你是谁」「你叫什么」：直接回答「我叫${name.isEmpty ? '…' : name}」并最多补充一句，不复述剧本文字。
- 用户只问一句话，你也先用一两句自然回复；除非用户希望听故事，否则不输出长段落。
- 不要背诵设定文件，不复述上传文档中的原始台词、戏剧旁白、章节标题、角色扮演脚本或示例对话。
- 即使背景材料中包含与用户不同的关系和地点，也不要假装它们真的发生过；聊天只引用实际本次会话确认的信息。
- 不得声称读取未经提供的个人信息、执行过不存在的现实动作，或突破应用工具权限。
${story ? '- 用户已选择沉浸剧情模式：允许适量动作和环境描写，但依然要回应问题，不复制档案。' : '- 用户已选择日常聊天模式：禁止使用括号描写动作、小说式独白、旁白、场景切换或长篇回忆。保持像即时通讯一样自然的口语。'}
${group ? '- 你正在群聊，只代表本角色说话，不替其他成员回答。' : ''}
【角色背景参考，非待续写文本】
$setting
【结束】''';
  }

  static bool _isClaude(String provider) => provider == 'anthropic';
  static bool _isGemini(String provider) => provider == 'gemini';
  static bool _isResponses(String provider) => provider == 'responses';

  static Uri _endpoint(ApiProfile profile) {
    final base = profile.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw ApiCallFailure('接口地址必须是可信 HTTPS URL，不支持在地址中附带密钥或查询参数。');
    }
    if (profile.modelId.trim().isEmpty) throw ApiCallFailure('模型 ID 不能为空。');
    final lower = uri.path.toLowerCase();
    if (profile.provider == 'custom' && profile.apiProtocol == 'responses') {
      if (lower.endsWith('/responses')) return uri;
      if (lower.endsWith('/chat/completions')) {
        return Uri.parse('${base.substring(0, base.length - '/chat/completions'.length)}/responses');
      }
      return Uri.parse('$base/responses');
    }
    if (_isClaude(profile.provider)) {
      if (lower.endsWith('/messages')) return uri;
      return Uri.parse('$base/messages');
    }
    if (_isGemini(profile.provider)) {
      final model = Uri.encodeComponent(profile.modelId.trim());
      final target = profile.streaming ? ':streamGenerateContent' : ':generateContent';
      if (lower.endsWith(':generatecontent') || lower.endsWith(':streamgeneratecontent')) {
        final prefix = base.substring(0, base.lastIndexOf(':'));
        return Uri.parse('$prefix$target${profile.streaming ? '?alt=sse' : ''}');
      }
      return Uri.parse('$base/models/$model$target${profile.streaming ? '?alt=sse' : ''}');
    }
    // The most common reason for relay failures is doubling /v1 or
    // /chat/completions. Accept a full endpoint or an API base URL.
    if (lower.endsWith('/responses')) {
      throw ApiCallFailure('当前中转站模式使用 Chat Completions，不是 Responses API。请填写 /v1 或完整 /chat/completions 地址。');
    }
    if (lower.endsWith('/chat/completions')) return uri;
    return Uri.parse('$base/chat/completions');
  }

  static Uri previewEndpoint(ApiProfile profile) => _endpoint(profile);

  /// GET /models where supported. A relay may reject it; the user can still
  /// type an exact model ID in the API editor.
  static Uri modelListEndpoint(ApiProfile profile) {
    // Listing models should not require that the user already knows a model ID.
    final lookupProfile = ApiProfile(id: profile.id, label: profile.label,
      provider: profile.provider, baseUrl: profile.baseUrl,
      modelId: profile.modelId.trim().isEmpty ? '_list' : profile.modelId,
      anthropicVersion: profile.anthropicVersion,
      workspaceId: profile.workspaceId, streaming: false,
      authMode: profile.authMode, apiProtocol: profile.apiProtocol);
    final endpoint = _endpoint(lookupProfile);
    final base = endpoint.toString();
    final lower = endpoint.path.toLowerCase();
    if (profile.provider == 'gemini') {
      return Uri.parse('${profile.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/models?pageSize=1000');
    }
    if (lower.endsWith('/chat/completions')) {
      return Uri.parse('${base.substring(0, base.length - '/chat/completions'.length)}/models');
    }
    if (lower.endsWith('/responses')) {
      return Uri.parse('${base.substring(0, base.length - '/responses'.length)}/models');
    }
    if (lower.endsWith('/messages')) {
      return Uri.parse('${base.substring(0, base.length - '/messages'.length)}/models');
    }
    return Uri.parse('$base/models');
  }

  static List<String> parseModelList(String body) {
    final root = mapJson(jsonDecode(body));
    final items = root['data'] ?? root['models'] ?? mapJson(root['result'])['data'];
    if (items is! List) throw ApiCallFailure('服务商没有返回标准的模型列表，请手动填写模型 ID。');
    final ids = <String>{};
    for (final item in items) {
      if (item is String && item.trim().isNotEmpty) { ids.add(item.trim()); continue; }
      if (item is! Map) continue;
      final m = mapJson(item);
      final raw = '${m['id'] ?? m['name'] ?? m['model'] ?? ''}'.trim();
      if (raw.isEmpty) continue;
      ids.add(raw.startsWith('models/') ? raw.substring('models/'.length) : raw);
    }
    return ids.toList()..sort();
  }

  static Future<List<String>> listModels({required http.Client client,
    required ApiProfile profile, required String apiKey}) async {
    if (apiKey.trim().isEmpty) throw ApiCallFailure('请先填写 API Key。');
    final uri = modelListEndpoint(profile);
    final headers = <String, String>{'accept': 'application/json'};
    if (_isClaude(profile.provider)) {
      headers['x-api-key'] = apiKey.trim();
      headers['anthropic-version'] = profile.anthropicVersion;
    } else if (_isGemini(profile.provider)) {
      headers['x-goog-api-key'] = apiKey.trim();
    } else if (profile.provider == 'custom' && profile.authMode == 'x-api-key') {
      headers['x-api-key'] = apiKey.trim();
    } else {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    try {
      final req = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      final res = await client.send(req).timeout(_connectTimeout);
      final response = await http.Response.fromStream(res).timeout(_receiveTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 404 || response.statusCode == 405) {
          throw ApiCallFailure('模型列表接口 /models 返回 HTTP ${response.statusCode}。'
            '该中转站可能不提供列出模型服务；仍可手动填写模型 ID。',
            response.statusCode);
        }
        throw ApiCallFailure(_readError(response.statusCode, response.body, apiKey), response.statusCode);
      }
      final models = parseModelList(response.body);
      if (models.isEmpty) throw ApiCallFailure('模型列表为空；可能需要手动输入模型名称。');
      return models;
    } on ApiCallFailure catch (e) {
      throw ApiCallFailure(e.message.replaceAll(apiKey, '[密钥已隐藏]'), e.statusCode);
    } on TimeoutException {
      throw ApiCallFailure('获取模型列表超时，可以手动填写模型 ID。');
    } catch (e) {
      throw ApiCallFailure('无法获取模型列表：${'$e'.replaceAll(apiKey, '[密钥已隐藏]')}');
    }
  }

  static List<ModelTurn> _mergedTurns(List<ModelTurn> turns) {
    final merged = <ModelTurn>[];
    for (final turn in turns) {
      final role = turn.role == 'assistant' ? 'assistant' : 'user';
      if (turn.text.trim().isEmpty && turn.imageBase64 == null) continue;
      if (merged.isNotEmpty && merged.last.role == role &&
          merged.last.imageBase64 == null && turn.imageBase64 == null) {
        merged[merged.length - 1] = ModelTurn(role, '${merged.last.text}\n${turn.text}');
      } else {
        merged.add(ModelTurn(role, turn.text));
      }
    }
    return merged;
  }

  static BuiltApiRequest buildRequest({required ApiProfile profile,
    required String apiKey, required String persona,
    required List<ModelTurn> turns, bool group = false,
    String roleName = '', String chatMode = 'daily'}) {
    if (apiKey.trim().isEmpty) throw ApiCallFailure('缺少 API Key，请先保存密钥。');
    final uri = _endpoint(profile);
    final system = systemPrompt(persona, group: group, roleName: roleName, chatMode: chatMode);
    final messages = _mergedTurns(turns);
    if (messages.isEmpty) throw ApiCallFailure('没有可发送的消息。');
    List<Object> chatParts(ModelTurn m) => [
      {'type': 'text', 'text': m.text},
      if (m.imageBase64 != null)
        {'type': 'image_url', 'image_url': {
          'url': 'data:${m.imageMime ?? 'image/jpeg'};base64,${m.imageBase64}',
          'detail': 'low',
        }},
    ];
    List<Object> claudeParts(ModelTurn m) => [
      if (m.imageBase64 != null)
        {'type': 'image', 'source': {'type': 'base64',
          'media_type': m.imageMime ?? 'image/jpeg', 'data': m.imageBase64}},
      {'type': 'text', 'text': m.text},
    ];
    List<Object> geminiParts(ModelTurn m) => [
      if (m.imageBase64 != null)
        {'inlineData': {'mimeType': m.imageMime ?? 'image/jpeg', 'data': m.imageBase64}},
      {'text': m.text},
    ];
    final headers = <String, String>{'content-type': 'application/json'};
    final payload = <String, dynamic>{};
    if (profile.streaming) headers['accept'] = 'text/event-stream';
    if (_isClaude(profile.provider)) {
      headers['x-api-key'] = apiKey.trim();
      headers['anthropic-version'] = profile.anthropicVersion;
      if (profile.workspaceId.trim().isNotEmpty) {
        headers['anthropic-workspace-id'] = profile.workspaceId.trim();
      }
      payload.addAll({
        'model': profile.modelId.trim(), 'max_tokens': 512,
        'system': system,
        'messages': messages.map((m) => {'role': m.role,
          'content': m.imageBase64 == null ? m.text : claudeParts(m)}).toList(),
        'stream': profile.streaming,
      });
    } else if (_isGemini(profile.provider)) {
      headers['x-goog-api-key'] = apiKey.trim();
      payload.addAll({
        'systemInstruction': {'parts': [{'text': system}]},
        'contents': messages.map((m) => {
          'role': m.role == 'assistant' ? 'model' : 'user',
          'parts': geminiParts(m),
        }).toList(),
        'generationConfig': {'maxOutputTokens': 512},
      });
    } else {
      if (profile.provider == 'custom' && profile.authMode == 'x-api-key') {
        headers['x-api-key'] = apiKey.trim();
      } else {
        headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }
      if (profile.provider == 'custom' && profile.apiProtocol == 'responses') {
        payload.addAll({
          'model': profile.modelId.trim(),
          'instructions': system,
          'input': messages.map((m) => {'role': m.role,
            'content': m.imageBase64 == null ? m.text : [
              {'type': 'input_text', 'text': m.text},
              {'type': 'input_image', 'image_url':
                'data:${m.imageMime ?? 'image/jpeg'};base64,${m.imageBase64}'},
            ]}).toList(),
          'stream': profile.streaming,
          'max_output_tokens': 512,
        });
      } else { payload.addAll({
        'model': profile.modelId.trim(),
        'messages': [
          {'role': 'system', 'content': system},
          ...messages.map((m) => {'role': m.role,
            'content': m.imageBase64 == null ? m.text : chatParts(m)}),
        ],
        'stream': profile.streaming,
        if (profile.provider == 'openai' && profile.streaming)
          'stream_options': {'include_usage': true},
      }); }
    }
    return BuiltApiRequest(uri, headers, payload);
  }

  static String _extractText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content.whereType<Map>().map((m) => '${m['text'] ?? ''}').join('\n');
    }
    return '';
  }

  static String parseResponse(String provider, String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map) throw ApiCallFailure('模型响应不是 JSON 对象。');
    final root = mapJson(decoded);
    String text = '';
    if (_isResponses(provider)) {
      text = '${root['output_text'] ?? ''}';
      if (text.isEmpty && root['output'] is List) {
        final outputs = (root['output'] as List).whereType<Map>();
        text = outputs.map((m) => _extractText(mapJson(m)['content'])).
          where((t) => t.isNotEmpty).join('\n');
      }
    } else if (_isClaude(provider)) {
      text = _extractText(root['content']);
    } else if (_isGemini(provider)) {
      final candidates = root['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final parts = mapJson(mapJson(candidates.first)['content'])['parts'];
        text = _extractText(parts);
      }
    } else {
      final choices = root['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = mapJson(choices.first);
        text = _extractText(mapJson(first['message'])['content']);
      }
    }
    text = text.trim();
    if (text.isEmpty) throw ApiCallFailure('模型未返回文字。可尝试关闭流式输出，或检查服务商协议与模型 ID。');
    return text;
  }

  static TokenUsage? usageFromResponse(String provider, Object? value) {
    final root = mapJson(value);
    final usage = mapJson(root['usage']);
    final gemini = mapJson(root['usageMetadata']);
    int? getCount(Object? v) => v is num ? v.toInt() : null;
    final input = getCount(usage['prompt_tokens'] ?? usage['input_tokens'] ??
        gemini['promptTokenCount']);
    final output = getCount(usage['completion_tokens'] ?? usage['output_tokens'] ??
        gemini['candidatesTokenCount']);
    if (input == null && output == null) return null;
    return TokenUsage(input, output);
  }

  static String _readError(int status, String body, String apiKey) {
    String detail = '';
    try {
      final root = mapJson(jsonDecode(body));
      final error = root['error'];
      detail = error is Map ? '${error['message'] ?? ''}' : '${root['message'] ?? ''}';
    } catch (_) {/* service sometimes returns HTML */}
    detail = detail.replaceAll(apiKey, '[密钥已隐藏]')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (detail.length > 220) detail = '${detail.substring(0, 220)}…';
    final reason = switch (status) {
      400 => '请求协议或参数不兼容；中转站请尝试切换流式模式',
      401 => '密钥无效或请求头格式不符',
      402 => '额度不足或支付方式异常',
      403 => '服务商拒绝访问，检查模型权限和地区限制',
      404 => '接口路径或模型 ID 错误；检查 /v1/chat/completions',
      408 => '上游超时',
      422 => '请求字段无法被上游接受',
      429 => '配额不足或触发频率限制',
      500 => '服务商内部错误',
      502 || 503 || 504 => '中转站或上游模型暂时不可用',
      >= 300 && < 400 => '被重定向到其他地址（密钥请求不会自动跟随）',
      _ => '服务商请求失败',
    };
    return 'HTTP $status：$reason${detail.isEmpty ? '' : '\n$detail'}';
  }

  static String? _sseFragment(String provider, Map<String, dynamic> event) {
    if (event['error'] != null) {
      final err = event['error'];
      final msg = err is Map ? '${err['message'] ?? err}' : '$err';
      throw ApiCallFailure('服务商流式返回错误：$msg');
    }
    if (_isResponses(provider)) {
      if (event['type'] == 'response.output_text.delta') return '${event['delta'] ?? ''}';
      if (event['type'] == 'response.failed') throw ApiCallFailure('Responses API 返回失败');
      return null;
    }
    if (_isClaude(provider)) {
      if (event['type'] == 'error') {
        throw ApiCallFailure('Claude 流式连接失败：${event['error']}');
      }
      if (event['type'] == 'content_block_delta') {
        return '${mapJson(event['delta'])['text'] ?? ''}';
      }
      return null;
    }
    if (_isGemini(provider)) {
      final candidates = event['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final parts = mapJson(mapJson(candidates.first)['content'])['parts'];
        return _extractText(parts);
      }
      return null;
    }
    final choices = event['choices'];
    if (choices is List && choices.isNotEmpty) {
      final c = mapJson(choices.first);
      final delta = mapJson(c['delta']);
      final fragment = _extractText(delta['content']);
      if (fragment.isNotEmpty) return fragment;
      // A few relays return a complete message even in SSE mode.
      final full = _extractText(mapJson(c['message'])['content']);
      if (full.isNotEmpty) return full;
    }
    return null;
  }

  /// Non-UI helper used by both the streaming transport and unit tests.
  static String parseSseText(String provider, String raw,
      {void Function(String)? onText}) {
    final result = StringBuffer();
    String cumulative = '';
    for (final line in const LineSplitter().convert(raw)) {
      if (!line.startsWith('data:')) continue;
      final content = line.substring(5).trim();
      if (content == '[DONE]') break;
      if (content.isEmpty) continue;
      final data = jsonDecode(content);
      if (data is! Map) continue;
      final next = _sseFragment(provider, mapJson(data));
      if (next == null || next.isEmpty) continue;
      if (_isGemini(provider)) {
        // Some Gemini gateways send cumulative snapshots rather than deltas.
        if (next.startsWith(cumulative)) {
          cumulative = next;
        } else {
          cumulative += next;
        }
      } else {
        cumulative += next;
      }
      result.clear();
      result.write(cumulative);
      onText?.call(cumulative);
    }
    if (cumulative.trim().isEmpty) throw ApiCallFailure('没有从流式数据中解析到文本，尝试关闭流式输出。');
    return result.toString().trim();
  }

  static Future<String> _streamResponse(String provider,
      Stream<List<int>> stream, {void Function(String)? onText,
      void Function(TokenUsage)? onUsage}) async {
    final output = StringBuffer();
    String lastGemini = '';
    await for (final line in stream.transform(utf8.decoder)
        .transform(const LineSplitter()).timeout(_receiveTimeout)) {
      if (!line.startsWith('data:')) continue;
      final content = line.substring(5).trim();
      if (content.isEmpty) continue;
      if (content == '[DONE]') break;
      final decoded = jsonDecode(content);
      if (decoded is! Map) continue;
      final usage = usageFromResponse(provider, decoded);
      if (usage != null) onUsage?.call(usage);
      final piece = _sseFragment(provider, mapJson(decoded));
      if (piece == null || piece.isEmpty) continue;
      if (_isGemini(provider)) {
        if (piece.startsWith(lastGemini)) {
          output.write(piece.substring(lastGemini.length));
          lastGemini = piece;
        } else {
          output.write(piece);
          lastGemini += piece;
        }
      } else {
        output.write(piece);
      }
      onText?.call(output.toString());
    }
    final text = output.toString().trim();
    if (text.isEmpty) throw ApiCallFailure('流式连接已完成，但没有收到正文；可以关闭流式模式再测试。');
    return text;
  }

  static Future<String> call({required http.Client client,
    required ApiProfile profile, required String apiKey,
    required String persona, required List<ModelTurn> turns,
    String roleName = '', bool group = false, String chatMode = 'daily',
    void Function(String)? onText,
    void Function(TokenUsage)? onUsage}) async {
    final request = buildRequest(profile: profile, apiKey: apiKey,
      persona: persona, turns: turns, roleName: roleName, group: group,
      chatMode: chatMode);
    final parseFormat = profile.provider == 'custom' && profile.apiProtocol == 'responses'
      ? 'responses' : profile.provider;
    final req = http.Request('POST', request.uri)
      ..followRedirects = false
      ..headers.addAll(request.headers)
      ..body = jsonEncode(request.payload);
    try {
      final streamed = await client.send(req).timeout(_connectTimeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final bad = await http.Response.fromStream(streamed).timeout(_receiveTimeout);
        throw ApiCallFailure(_readError(bad.statusCode, bad.body, apiKey), bad.statusCode);
      }
      final contentType = streamed.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/event-stream')) {
        return await _streamResponse(parseFormat, streamed.stream, onText: onText, onUsage: onUsage);
      }
      final response = await http.Response.fromStream(streamed).timeout(_receiveTimeout);
      if (response.body.trimLeft().startsWith('data:')) {
        return parseSseText(parseFormat, response.body, onText: onText);
      }
      final text = parseResponse(parseFormat, response.body);
      try {
        final usage = usageFromResponse(parseFormat, jsonDecode(response.body));
        if (usage != null) onUsage?.call(usage);
      } catch (_) { /* usage metadata is optional */ }
      onText?.call(text);
      return text;
    } on ApiCallFailure catch (failure) {
      // Relays sometimes echo request fields in their error messages.
      throw ApiCallFailure(failure.message.replaceAll(apiKey, '[密钥已隐藏]'),
        failure.statusCode);
    } on TimeoutException {
      throw ApiCallFailure('模型响应超时，请尝试更快的模型、减少上下文或检查中转站网络。');
    } catch (error) {
      final safe = '$error'.replaceAll(apiKey, '[密钥已隐藏]');
      throw ApiCallFailure('网络或协议异常：$safe');
    }
  }
}

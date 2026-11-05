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

  /// The handset's clock is an app-owned trusted signal. The model is not
  /// allowed to manufacture real-time observations it has not been given.
  static String clockContext(DateTime now) {
    final local = now.toLocal();
    String pad(int v) => v.toString().padLeft(2, '0');
    const days = ['周一','周二','周三','周四','周五','周六','周日'];
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${days[local.weekday - 1]} ${pad(local.hour)}:${pad(local.minute)} '
      '(UTC$sign${pad(minutes ~/ 60)}:${pad(minutes % 60)}；${local.timeZoneName})';
  }

  static String formatDirective(String mode) => switch (mode) {
    'json' => '本会话要求输出严格合法的 JSON（无 Markdown 围栏、无额外解释）。如需给字段请输出 JSON 对象。',
    'markdown' => '按 Markdown 输出，支持标题、列表、表格和带语言名的三反引号代码块。不要转义 Markdown 标记。',
    'plain' => '仅输出纯文本，不要使用 Markdown 标记、代码围栏或 JSON 包装。',
    _ => '自动格式：用户在最新消息里明确要求 JSON、Markdown、表格、代码块、步骤或指定字段时，优先严格遵循该格式；未提出时自然聊天。',
  };

  static String systemPrompt(String persona, {bool group = false,
      String roleName = '', String chatMode = 'daily',
      String formatMode = 'auto', DateTime? now, String contextHint = ''}) {
    final story = chatMode == 'story';
    final name = roleName.trim();
    final setting = _profileExcerpt(persona, story: story);
    final currentTime = clockContext(now ?? DateTime.now());
    return '''你在心屿 OS 里扮演一个明确标识为 AI 的虚构角色，名字是「${name.isEmpty ? '未命名' : name}」。
【时间与真实工具上下文】
本机当前时间：$currentTime。
这是手机提供的时钟，不是你的训练截止日。涉及日期、下周、星期几、多久后，应以此时钟为基础计算；不了解天气、新闻和真实交易等实时信息时不要编造。不可声称执行了未提供的工具或访问了现实账户。
${contextHint.trim().isEmpty ? '' : '本次活动上下文（由本机应用提供，不表示你亲眼看见场景）：\n$contextHint'}
【回复原则】
- 先理解并回应用户最新消息。被问到姓名时可简短回答「我叫${name.isEmpty ? '…' : name}」。角色档案是身份与剧情设定，不能当成当前对话的原文进行复制。
- 用户明确提出的输出结构、格式、字段、字数、示例或代码要求，优先于角色的文风倾向；不要因为沉浸剧情而破坏 JSON、表格或代码块。
- 不要背诵设定文件。可以保持角色口吻，但不要泄露不相关人格档案或把设定文本当作上一轮用户消息。
- 角色不能假称知道用户真实位置、现实世界事实或没有共享过的隐私数据。
${story ? '- 沉浸剧情模式：允许适量动作和环境描写，也可表达情绪。用户要求格式化输出时减少不必要的旁白。' : '- 日常聊天模式：默认简短自然，禁止使用括号描写动作，不强行加旁白；用户要求详细答复或长格式时可以展开。'}
${group ? '- 群聊：只代表该角色发言，不代替其他群成员说话。' : ''}
【本会话格式规则】
${formatDirective(formatMode)}
【角色设定/剧情参考，不能作为最近聊天记录】
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
        // Preserve the image attached to the current turn. Dropping these
        // fields silently converts a vision request into text-only input.
        merged.add(ModelTurn(role, turn.text,
          imageBase64: turn.imageBase64, imageMime: turn.imageMime));
      }
    }
    return merged;
  }

  static BuiltApiRequest buildRequest({required ApiProfile profile,
    required String apiKey, required String persona,
    required List<ModelTurn> turns, bool group = false,
    String roleName = '', String chatMode = 'daily',
    String formatMode = 'auto', DateTime? now, String contextHint = ''}) {
    if (apiKey.trim().isEmpty) throw ApiCallFailure('缺少 API Key，请先保存密钥。');
    final uri = _endpoint(profile);
    final system = systemPrompt(persona, group: group, roleName: roleName,
      chatMode: chatMode, formatMode: formatMode, now: now,
      contextHint: contextHint);
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
        'model': profile.modelId.trim(), 'max_tokens': (formatMode == 'json' || formatMode == 'markdown') ? 1600 : 512,
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
        'generationConfig': {'maxOutputTokens': (formatMode == 'json' || formatMode == 'markdown') ? 1600 : 512},
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
          'max_output_tokens': (formatMode == 'json' || formatMode == 'markdown') ? 1600 : 512,
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
    String formatMode = 'auto', DateTime? now, String contextHint = '',
    void Function(String)? onText,
    void Function(TokenUsage)? onUsage}) async {
    final request = buildRequest(profile: profile, apiKey: apiKey,
      persona: persona, turns: turns, roleName: roleName, group: group,
      chatMode: chatMode, formatMode: formatMode, now: now,
      contextHint: contextHint);
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

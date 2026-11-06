import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Inject your EXISTING per-character adapter here to reuse persona & secure keys.
abstract class RoleResponder {
  Future<String> respond({required String roleId, required String roleName,
    required String persona, required String event, required String userMessage});
}

/// OpenAI-compatible Chat Completions bridge for standalone testing.
/// API key stays in memory, never saved in preferences or printed to logs.
class CompatibleResponder implements RoleResponder {
  final String endpoint, model, apiKey;
  const CompatibleResponder({required this.endpoint, required this.model, required this.apiKey});
  @override
  Future<String> respond({required String roleId, required String roleName,
    required String persona, required String event, required String userMessage}) async {
    final uri = Uri.parse(endpoint.endsWith('/chat/completions') ? endpoint :
      '${endpoint.replaceAll(RegExp(r'/$'), '')}/chat/completions');
    if (uri.scheme != 'https') throw StateError('正式环境只允许 HTTPS 接口');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'stream': false,
        'max_tokens': 160,
        'messages': [
          {'role':'system', 'content': '你扮演$roleName。角色文件是人物背景，不得逐字复述。$persona\n你在虚拟陪伴互动场景中。只回复1至2句简短、贴合当下事件的自然中文，不能声称真的看到了未发送的画面。请勿索取真实支付信息。现在时间：${DateTime.now().toLocal()}。'},
          {'role':'user', 'content': '游戏真实事件：$event\n用户说：$userMessage'},
        ],
      })));
      final res = await req.close().timeout(const Duration(seconds: 40));
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) throw StateError('API HTTP ${res.statusCode}: ${body.length > 160 ? body.substring(0,160) : body}');
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      final content = (choices?.isNotEmpty ?? false) ? (choices!.first['message']['content']) : null;
      if (content is String && content.isNotEmpty) return content;
      throw StateError('接口未返回可读取的文字内容');
    } finally {
      client.close(force: true);
    }
  }
}

class CompanionLine {
  final String text, source;
  final bool isUser;
  const CompanionLine(this.text, this.source, {this.isUser = false});
}

class CompanionController extends ChangeNotifier {
  final String roleId, roleName;
  String persona;
  RoleResponder? responder;
  final lines = <CompanionLine>[];
  bool busy = false;
  bool gameAiEnabled = false; // OFF by default: game moves are local and free.
  final void Function(String roleId, String description)? onLocalEvent;
  void setGameAiEnabled(bool enabled) { gameAiEnabled = enabled; notifyListeners(); }
  void gameEvent(String description) {
    lastEvent = description;
    onLocalEvent?.call(roleId, description);
    if (gameAiEnabled) {
      event(description); // May cost provider tokens; ordinary cooldown still applies.
    } else {
      notifyListeners(); // No network request; game state remains local.
    }
  }
  DateTime? lastAuto;
  String lastEvent = '在亲密互动空间休息';
  CompanionController({required this.roleId, required this.roleName, this.persona='', this.responder, this.onLocalEvent});
  String get sourceLabel => responder == null ? '离线示例·非真实 AI' : 'API 实时互动';
  void setResponder(RoleResponder? value) { responder = value; notifyListeners(); }
  String mock(String event) {
    if (event.contains('棋') || event.contains('掷') || event.contains('星币')) return '哎呀，这一手挺有想法！要不我们再试一局？';
    if (event.contains('唱') || event.contains('歌曲')) return '这段旋律还不错，你最喜欢哪一句？';
    if (event.contains('视频') || event.contains('播放')) return '我们一起看吧！你觉得刚刚那段怎么样？';
    if (event.contains('蛋')) return '它刚才是不是动了一下？我们再陪它一会儿。';
    if (event.contains('喂')) return '它吃得好开心呀，今天我们照顾得不错！';
    return '能一起做这件事真好，你还想怎么继续？';
  }

  /// Automatic comments are rate-limited and non-recursive. User text is always allowed.
  Future<void> event(String description, {bool automatic = true, String message = ''}) async {
    lastEvent = description;
    if (busy) return;
    final now = DateTime.now();
    if (automatic && lastAuto != null && now.difference(lastAuto!).inSeconds < 8) return;
    if (automatic) lastAuto = now;
    if (message.trim().isNotEmpty) lines.add(CompanionLine(message, '你', isUser:true));
    busy = true; notifyListeners();
    try {
      final output = responder == null ? mock(description) : await responder!.respond(
        roleId: roleId, roleName: roleName, persona: persona,
        event: description, userMessage: message,
      );
      lines.add(CompanionLine(output, roleName));
    } catch (e) {
      lines.add(CompanionLine('模型请求失败：$e', '连接诊断'));
    } finally {
      if (lines.length > 28) lines.removeRange(0, lines.length - 28);
      busy = false; notifyListeners();
    }
  }
}

/// Format-preserving story replies for the roleplay chat page.
/// This is independent of the short game commentary protocol above.
class StoryApiClient {
  final String endpoint, model, apiKey;
  const StoryApiClient({required this.endpoint,required this.model,required this.apiKey});
  Future<String> generate({required String roleName,required String persona,
    required String userMessage,required String formatContract,
    String virtualPlace='角色当前场景'}) async {
    final uri=Uri.parse(endpoint.endsWith('/chat/completions')?endpoint:
      '${endpoint.replaceAll(RegExp(r'/$'),'')}/chat/completions');
    if(uri.scheme!='https')throw StateError('需要 HTTPS 中转地址');
    final client=HttpClient()..connectionTimeout=const Duration(seconds:12);
    try{
      final request=await client.postUrl(uri).timeout(const Duration(seconds:15));
      request.headers.set(HttpHeaders.authorizationHeader,'Bearer $apiKey');
      request.headers.set(HttpHeaders.contentTypeHeader,'application/json');
      request.add(utf8.encode(jsonEncode({
        'model':model,'stream':false,'max_tokens':850,
        'messages':[
          {'role':'system','content':'你正在扮演$roleName。人物背景如下（仅用于性格和故事，不可复述整份档案）：\n$persona\n\n输出契约：$formatContract'},
          {'role':'user','content':'当前现实手机时间：${DateTime.now().toLocal()}；当前虚拟场景：$virtualPlace。\n用户消息：$userMessage'},
        ],
      })));
      final response=await request.close().timeout(const Duration(seconds:45));
      final raw=await utf8.decoder.bind(response).join();
      if(response.statusCode!=200)throw StateError('HTTP ${response.statusCode}: ${raw.length>200?raw.substring(0,200):raw}');
      final data=jsonDecode(raw) as Map<String,dynamic>;
      final choices=data['choices'] as List?;
      final content=(choices!=null && choices.isNotEmpty)?(choices.first['message']['content']):null;
      if(content is String && content.trim().isNotEmpty)return content;
      throw StateError('模型未返回可识别的文本');
    }finally{client.close(force:true);}
  }
}

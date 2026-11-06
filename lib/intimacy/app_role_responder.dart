import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../app_controller.dart';
import '../models.dart';
import 'core/companion.dart';

/// Uses the EXISTING multi-provider adapter and existing encrypted API key store.
/// No API key is embedded in the APK or persisted into companion preferences.
class AppRoleResponder implements RoleResponder {
  final AppController app;
  final Map<String, List<ModelTurn>> _localTurns = {};
  AppRoleResponder(this.app);

  @override
  Future<String> respond({
    required String roleId,
    required String roleName,
    required String persona,
    required String event,
    required String userMessage,
  }) async {
    final role = app.character(roleId);
    if (role == null) throw StateError('角色已不存在，请返回通讯录检查。');
    final profile = app.profile(role.apiProfileId);
    if (profile == null) throw StateError('请先进入角色资料 → 模型绑定，选择 API 配置。');
    final apiKey = await app.getKey(profile.id);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('尚未设置 API Key，请到 API 连接台填写并测试。');
    }
    final scripted = event.startsWith('剧情专用输出契约');
    final incoming = scripted
        ? '当前任务：根据用户当前输入，严格按以下结构化格式输出，不需要其他解释。\n$event\n用户输入：$userMessage'
        : '本地虚拟互动事件（仅作为已发生的游戏事件，不代表现实世界）：$event\n'
          '用户刚刚说：${userMessage.isEmpty ? '（用户当前没有补充文字）' : userMessage}';
    final sessionKey = scripted ? '$roleId:story' : '$roleId:play';
    final history = _localTurns.putIfAbsent(sessionKey, () => <ModelTurn>[]);
    final turns = <ModelTurn>[
      ...(history.length > 8 ? history.sublist(history.length - 8) : history),
      ModelTurn('user', incoming),
    ];
    final client = http.Client();
    try {
      final answer = await MultiModelApi.call(
        client: client,
        profile: profile,
        apiKey: apiKey,
        persona: role.persona,
        roleName: role.name,
        chatMode: scripted ? 'story' : app.data.chatMode,
        formatMode: scripted ? 'json' : 'auto',
        contextHint: scripted
            ? '这是专门的剧情格式校验页面。优先遵循用户给定的结构要求，直接输出唯一一个 JSON 对象；动作、对白、内心必须分开。'
            : '你正在与用户共同进行虚拟互动。依据已传入的真实游戏状态自然回应，尽量简短且具有角色性格；不要声称看到了没有传给你的画面、听到了音频或了解现实中未确认的事件。当前本机时间：${DateTime.now().toLocal()}。',
        turns: turns,
      );
      if (answer.trim().isEmpty) throw StateError('模型返回了空消息。');
      history
        ..add(ModelTurn('user', incoming))
        ..add(ModelTurn('assistant', answer));
      if (history.length > 10) history.removeRange(0, history.length - 10);
      if (!scripted) app.recordIntimacyEvent(roleId, event);
      return answer;
    } finally {
      client.close();
    }
  }
}

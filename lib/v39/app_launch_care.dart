import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_controller.dart';
import '../ui_chat.dart';

/// Call once from the ROOT page's first-frame callback (ui_shell or main).
/// Unlike a chat-only popup, this is intended for the app's launch screen.
class AppLaunchCarePrompt {
  static final _prefs = SharedPreferencesAsync();
  static Future<void> checkAndShow(BuildContext context, AppController controller) async {
    if (!controller.data.allowProactiveMessages) return;
    final now = DateTime.now();
    final eligible = controller.data.proactiveEvents.where((e) {
      final role = controller.character(e.characterId);
      return role != null && role.allowProactiveMessages &&
        !e.dueAt.isAfter(now) && now.difference(e.dueAt) <= const Duration(days: 3);
    }).toList();
    if (eligible.isEmpty || !context.mounted) return;
    eligible.sort((a, b) => b.dueAt.compareTo(a.dueAt));
    final event = eligible.first;
    final flag = 'v39.launchCare.${event.id}';
    if (await _prefs.getBool(flag) == true || !context.mounted) return;
    final role = controller.character(event.characterId);
    if (role == null) return;
    // Mark as shown once before opening the modal, so relaunches do not spam.
    await _prefs.setBool(flag, true);
    if (!context.mounted) return;
    final openChat = await showDialog<bool>(context: context,
      barrierDismissible: true, builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.favorite_rounded, color: Color(0xFFE17AA8), size: 42),
        title: Text('${role.name} 想关心你'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('💌 今天有一件事想提醒你：\n\n${event.topic}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('这是之前授权保存的关怀提醒。真正的 AI 消息是否生成，仍以原应用的提醒与模型设置为准。',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('稍后')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('打开聊天')),
        ],
      ));
    if (openChat == true && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) =>
        ChatScreen(controller: controller, friend: role)));
    }
  }
}

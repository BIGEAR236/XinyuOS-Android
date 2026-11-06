import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../models.dart';

/// Dedicated player-post comments screen. The existing MomentsTab can stay
/// unchanged; socialAudience('me') is fixed in AppController.
class MyMomentsInteractionPage extends StatelessWidget {
  final AppController controller;
  const MyMomentsInteractionPage({super.key, required this.controller});

  Future<void> invite(BuildContext context, MomentEntry moment) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('邀请 AI 点赞或评论？'),
        content: const Text('最多邀请两位开启了朋友圈互动权限的 AI 好友。每位会发起一次付费模型请求。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始邀请')),
        ]));
    if (confirm != true) return;
    final result = await controller.inviteMomentInteractions(moment.id);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result ?? '邀请已完成，查看评论或点赞记录。')));
  }

  Future<void> reply(BuildContext context, MomentEntry moment, String commentId) async {
    final text = TextEditingController();
    try {
      final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('回复这条评论'),
        content: TextField(controller: text, maxLines: 3,
          decoration: const InputDecoration(hintText: '写一段回复…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, text.text), child: const Text('回复')),
        ]));
      if (value != null && value.trim().isNotEmpty) {
        controller.addMyMomentComment(moment.id, value, parentId: commentId);
      }
    } finally { text.dispose(); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller, builder: (context, _) {
      final posts = controller.data.moments.where((m) => m.characterId == 'me').toList().reversed.toList();
      return Scaffold(appBar: AppBar(title: const Text('我的朋友圈 · AI 评论')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const ListTile(title: Text('邀请角色参与我的朋友圈'),
            subtitle: Text('AI 只会在你主动点击邀请、并拥有互动权限时生成点赞或评论。')),
          if (posts.isEmpty) const ListTile(title: Text('还没有我的动态'),
            subtitle: Text('先去朋友圈发布一条动态，然后回到这里邀请 AI 评论。')),
          for (final m in posts) Card(child: Padding(
            padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.text, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Text('${m.likedBy.length} 赞 · ${m.comments.length} 评论',
                  style: Theme.of(context).textTheme.labelSmall),
                for (final comment in m.comments) ListTile(
                  contentPadding: EdgeInsets.zero, dense: true,
                  title: Text('${controller.displayName(comment.authorId)}：${comment.text}'),
                  subtitle: comment.parentId == null ? null : const Text('回复'),
                  trailing: comment.authorId == 'me' ? null :
                    TextButton(onPressed: () => reply(context, m, comment.id),
                      child: const Text('回复'))),
                OutlinedButton.icon(onPressed: () => invite(context, m),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('邀请 AI 评论 / 点赞')),
              ]))),
        ]));
    });
}

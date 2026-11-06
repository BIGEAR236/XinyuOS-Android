import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import 'marketplace_page.dart';

class XyWalletPage extends StatefulWidget {
  final AppController controller;
  const XyWalletPage({super.key, required this.controller});
  @override
  State<XyWalletPage> createState() => _XyWalletPageState();
}

class _XyWalletPageState extends State<XyWalletPage> {
  late Future<List<Map<String, dynamic>>> _orders = _readOrders();
  Future<List<Map<String, dynamic>>> _readOrders() async {
    try {
      final raw = await SharedPreferencesAsync().getString('v40.orders') ?? '[]';
      final result = jsonDecode(raw);
      if (result is List) {
        return result.whereType<Map>().map((item) =>
          item.map((k, v) => MapEntry('$k', v))).toList();
      }
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller, builder: (ctx, _) {
      final app = widget.controller;
      final ledger = app.data.worldLedger.reversed
        .where((e) => !e.description.startsWith('v40:ai:')).take(25).toList();
      return Scaffold(backgroundColor: const Color(0xFFFFFAFD),
        appBar: AppBar(title: const Text('我的 · 虚拟账户')),
        body: ListView(padding: const EdgeInsets.all(15), children: [
          Container(padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFFA38BC5), Color(0xFFDF9DB5)])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('我的星愿账户', style: TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 8),
              Text('${app.data.worldBalance} ⭐', style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('仅限心屿 OS 内的虚拟金币 · 无法兑换现金或支付真实商品',
                style: TextStyle(color: Colors.white, fontSize: 11)),
            ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () {
                final ok = app.dailyCheckIn();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? '今日签到成功 · +60 星币' : '今天已经签到过了')));
              }, icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('每日签到 +60'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(onPressed: () async {
              final role = await showModalBottomSheet<String?>(context: context,
                builder: (sheet) => SafeArea(child: ListView(
                  shrinkWrap: true, children: [
                    ListTile(title: const Text('为谁挑选虚拟商品？'),
                      onTap: () => Navigator.pop(sheet)),
                    ListTile(title: const Text('为自己购物'),
                      onTap: () => Navigator.pop(sheet, 'me')),
                    ...app.data.characters.map((c) => ListTile(
                      title: Text('和 ${c.name} 一起购物'),
                      onTap: () => Navigator.pop(sheet, c.id))),
                  ])));
              if (!context.mounted || role == null) return;
              await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                XyMarketplacePage(controller: app, roleId: role == 'me' ? null : role)));
              if (mounted) setState(() => _orders = _readOrders());
            }, icon: const Icon(Icons.storefront_outlined),
              label: const Text('进入星愿集市'))),
          ]),
          const SizedBox(height: 22),
          Text('AI 好友的虚拟账户', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('每位角色独立起始 1200 星币。AI 付账必须经你请求且模型同意。',
            style: TextStyle(fontSize: 12)),
          ...app.data.characters.map((role) => Card(
            elevation: 0, child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
              title: Text(role.name),
              subtitle: const Text('角色独立模拟账本'),
              trailing: Text('${app.roleWalletBalance(role.id)} ⭐',
                style: const TextStyle(fontWeight: FontWeight.bold))))),
          const SizedBox(height: 20),
          Text('收支记录', style: Theme.of(ctx).textTheme.titleMedium),
          const Text('通过签到、合理互动赚取金币。重复刷消息或落子不会无限领奖。',
            style: TextStyle(fontSize: 12)),
          if (ledger.isEmpty) const ListTile(title: Text('还没有账单')),
          ...ledger.map((entry) => ListTile(dense: true,
            title: Text(entry.description, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            subtitle: Text('${entry.createdAt.month}/${entry.createdAt.day} '
              '${entry.createdAt.hour.toString().padLeft(2, '0')}:'
              '${entry.createdAt.minute.toString().padLeft(2, '0')}'),
            trailing: Text('${entry.delta >= 0 ? '+' : ''}${entry.delta} ⭐',
              style: TextStyle(color: entry.delta >= 0
                ? const Color(0xFF278B71) : const Color(0xFFD06F79))))),
          const SizedBox(height: 20),
          Text('最近虚拟订单', style: Theme.of(ctx).textTheme.titleMedium),
          FutureBuilder<List<Map<String, dynamic>>>(future: _orders,
            builder: (ctx, data) {
              final orders = data.data ?? const <Map<String, dynamic>>[];
              if (orders.isEmpty) {
                if (app.data.worldOrders.isEmpty) {
                  return const ListTile(title: Text('暂无订单'));
                }
                return Column(children: app.data.worldOrders.reversed.take(12)
                  .map((order) => ListTile(title: Text(order.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('数量 ${order.count}'),
                    trailing: Text('${order.total} ⭐'))).toList());
              }
              return Column(children: orders.take(12).map((order) => ListTile(
                title: Text('${order['items'] ?? '虚拟商品'}', maxLines: 2,
                  overflow: TextOverflow.ellipsis),
                subtitle: Text('付款方：${order['payer'] == 'me' ? '我' : app.displayName('${order['payer']}')}'),
                trailing: Text('${order['total'] ?? 0} ⭐'))).toList());
            }),
          const SizedBox(height: 24),
        ]));
    });
}

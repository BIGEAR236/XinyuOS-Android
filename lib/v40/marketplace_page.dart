import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../intimacy/app_role_responder.dart';
import 'catalog.dart';
import '../v41/gift_inventory.dart';
import '../v42/product_illustration.dart';

/// This marketplace is entirely fictional: coins have no cash value,
/// there is no real checkout, shipping, bank transfer or affiliate storefront.
class XyMarketplacePage extends StatefulWidget {
  final AppController controller;
  final String? roleId;
  const XyMarketplacePage({super.key, required this.controller, this.roleId});
  @override
  State<XyMarketplacePage> createState() => _XyMarketplacePageState();
}

class _XyMarketplacePageState extends State<XyMarketplacePage> {
  final _preferences = SharedPreferencesAsync();
  final _search = TextEditingController();
  final _cart = <String, int>{};
  String _category = 'shoes';
  bool _busy = false;
  bool _cartLoaded = false;
  Future<void> _cartWrites = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    try {
      final raw = await _preferences.getString('v40.cart') ?? '{}';
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final item in decoded.entries) {
          final id = '${item.key}';
          final quantity = item.value;
          if (xyProductById.containsKey(id) && quantity is int && quantity > 0) {
            _cart[id] = quantity.clamp(1, 20).toInt();
          }
        }
      }
    } catch (_) { /* Damaged cart does not break the main app. */ }
    if (mounted) setState(() => _cartLoaded = true);
  }

  Future<void> _changeQuantity(String sku, int delta) async {
    if (!_cartLoaded || _busy || !xyProductById.containsKey(sku)) return;
    final next = (_cart[sku] ?? 0) + delta;
    setState(() {
      if (next <= 0) { _cart.remove(sku); }
      else { _cart[sku] = next.clamp(1, 20).toInt(); }
    });
    final snapshot = jsonEncode(_cart);
    _cartWrites = _cartWrites.catchError((Object _) {}).then((_) async {
      await _preferences.setString('v40.cart', snapshot);
    });
    try { await _cartWrites; }
    catch (e) { _notify('购物车保存失败：$e'); }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int get _total => _cart.entries.fold(0, (sum, entry) =>
    sum + (xyProductById[entry.key]?.cost ?? 0) * entry.value);
  int get _quantity => _cart.values.fold(0, (sum, value) => sum + value);

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Widget _photo(XyProduct product, {double? height}) =>
      XyProductArt(product: product, height: height);

  static IconData _categoryIcon(String cat) => switch (cat) {
    'shoes' => Icons.hiking_outlined,
    'clothes' => Icons.checkroom_outlined,
    _ => Icons.chair_alt_outlined,
  };

  Future<void> _details(XyProduct product) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16), child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
              ClipRRect(borderRadius: BorderRadius.circular(18),
                child: SizedBox(width: double.infinity, height: 230,
                  child: _photo(product, height: 230))),
              const SizedBox(height: 16),
              Text(product.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 7),
              Text('${product.cost} ⭐ 虚拟星币',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                  color: Color(0xFFAD6384))),
              const SizedBox(height: 7),
              Text(product.subtitle),
              const SizedBox(height: 10),
              const Text('商品插画与对应品类及配色一致；全部为虚拟商品，不会发货。',
                style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: () async {
                Navigator.pop(ctx);
                await _changeQuantity(product.id, 1);
              }, icon: const Icon(Icons.add_shopping_cart),
                label: const Text('加入购物车')),
            ])))));
  }

  Future<void> _showCart() async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (sheet) => StatefulBuilder(
        builder: (sheet, refresh) => SafeArea(child: FractionallySizedBox(
          heightFactor: .82, child: Column(children: [
            ListTile(title: const Text('我的虚拟购物车',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              subtitle: Text('$_quantity 件商品 · 总计 $_total ⭐'),
              trailing: const Icon(Icons.shopping_bag_outlined)),
            const Divider(height: 1),
            Expanded(child: _cart.isEmpty
              ? const Center(child: Text('还没有添加商品'))
              : ListView(children: _cart.entries.map((entry) {
                  final product = xyProductById[entry.key]!;
                  return ListTile(
                    leading: SizedBox(width: 48, height: 48,
                      child: ClipRRect(borderRadius: BorderRadius.circular(7),
                        child: _photo(product))),
                    title: Text(product.name),
                    subtitle: Text('${product.cost} ⭐ × ${entry.value}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _busy ? null : () async {
                          await _changeQuantity(product.id, -1);
                          refresh(() {});
                        }),
                      IconButton(icon: const Icon(Icons.add_circle_outline),
                        onPressed: _busy ? null : () async {
                          await _changeQuantity(product.id, 1);
                          refresh(() {});
                        }),
                    ]));
                }).toList())),
            Padding(padding: const EdgeInsets.all(16), child: FilledButton(
              onPressed: _cart.isEmpty || _busy ? null : () async {
                Navigator.pop(sheet); await _checkout();
              }, child: Text('去结算 · $_total ⭐'))),
          ])))));
  }

  Future<void> _checkout() async {
    if (_busy || _cart.isEmpty || _total <= 0) return;
    final total = _total;
    final role = widget.roleId == null ? null : widget.controller.character(widget.roleId!);
    final choice = await showDialog<String>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('虚拟订单结算'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('共 $_quantity 件虚拟商品，总计 $total 星币。'),
            Text('我的余额：${widget.controller.data.worldBalance} ⭐'),
            if (role != null)
              Text('${role.name}的余额：${widget.controller.roleWalletBalance(role.id)} ⭐'),
            const SizedBox(height: 10),
            const Text('所有支付均为本地模拟，不涉及银行卡、真实货币或快递。'),
            if (role != null) const Text('请求 AI 付款会调用一次付费模型，且必须由 AI 明确同意。',
              style: TextStyle(fontSize: 12)),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'me'), child: const Text('我来支付')),
          if (role != null) FilledButton(onPressed: () => Navigator.pop(ctx, 'ai'),
            child: Text('请${role.name}付账')),
        ]));
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    var paymentCommitted = false;
    String? approvedMessage;
    try {
      await _cartWrites; // Persist previous taps before initiating payment.
      var payer = 'me';
      if (choice == 'ai') {
        if (role == null) throw StateError('未选择 AI 好友');
        if (widget.controller.roleWalletBalance(role.id) < total) {
          throw StateError('${role.name}的虚拟余额不足');
        }
        final responder = AppRoleResponder(widget.controller);
        final response = await responder.respond(
          roleId: role.id, roleName: role.name, persona: role.persona,
          event: '用户请求你为虚拟购物车支付$total星币（非真实钱款）。'
            '你自己的本地模拟余额是${widget.controller.roleWalletBalance(role.id)}星币。'
            '如果愿意请以AGREE开头；不愿意以DECLINE开头。'
            '请你从角色性格和关系自行决定，只回答一种选择与简短理由。',
          userMessage: '你愿意帮我支付这笔$total星币的虚拟购物订单吗？');
        if (!RegExp(r'^AGREE(?=$|[\s:：,.，。-])',
            caseSensitive: false).hasMatch(response.trim())) {
          widget.controller.recordAiMarketplaceDecision(role.id, response,
            approved: false);
          _notify('${role.name}没有明确同意支付：$response');
          return;
        }
        approvedMessage = response;
        payer = role.id;
      }
      final purchasedSkuCounts=Map<String,int>.from(_cart);
      final summary = _cart.entries.map((e) =>
        '${xyProductById[e.key]!.name}×${e.value}').join('、');
      if (!widget.controller.payVirtualMarketplace(total,
          payerRoleId: payer == 'me' ? null : payer, items: summary)) {
        throw StateError('支付失败：虚拟余额不足');
      }
      paymentCommitted = true; // Order is already in AppData.worldOrders.
      if (role != null && approvedMessage != null) {
        widget.controller.recordAiMarketplaceDecision(role.id,
          approvedMessage, approved: true, amount: total);
      }
      _cart.clear(); // Prevent a second payment even if preference I/O fails.
      final saved = await _preferences.getString('v40.orders') ?? '[]';
      List orders;
      try {
        final previous = jsonDecode(saved);
        orders = previous is List ? previous : [];
      } catch (_) { orders = []; }
      await XyGiftInventory.add(purchasedSkuCounts);
      orders.insert(0, {
        'date': DateTime.now().toIso8601String(),
        'items': summary, 'total': total, 'payer': payer,
        'roleId': role?.id ?? '',
      });
      await _preferences.setString('v40.orders', jsonEncode(orders.take(100).toList()));
      await _preferences.setString('v40.cart', '{}');
      _notify('订单已完成 · ${payer == 'me' ? '由我' : role?.name ?? 'AI'}虚拟支付 $total ⭐');
    } catch (e) {
      if (paymentCommitted) {
        _notify('星币已扣除、订单已保存到主账本；购物车附加数据写入失败：$e。请勿重复付款。');
        try { await _preferences.setString('v40.cart', '{}'); } catch (_) {}
      } else {
        _notify('结算未成功：$e');
      }
    }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = xyProducts.where((p) => p.category == _category &&
      (query.isEmpty || p.name.toLowerCase().contains(query) ||
       p.subtitle.toLowerCase().contains(query))).toList();
    return Scaffold(backgroundColor: const Color(0xFFFFF9FC),
      appBar: AppBar(title: const Text('星愿集市'), actions: [
        IconButton(tooltip: '购物车', onPressed: _showCart,
          icon: Badge(label: Text('$_quantity'), isLabelVisible: _quantity > 0,
            child: const Icon(Icons.shopping_cart_outlined))),
      ]),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(17),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [
            Color(0xFFFBE0EB), Color(0xFFE6E4FA)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('买下一点喜欢的日常 ♡',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21)),
            const Text('300 件虚拟商品 · 对应品类的本地插画 · 不产生真实付款或配送',
              style: TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            TextField(controller: _search, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
                hintText: '搜索商品风格、颜色', isDense: true, filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none))),
          ])),
        SizedBox(height: 56, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          children: xyCategoryNames.entries.map((item) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text('${item.value} 100'),
              selected: _category == item.key,
              onSelected: (_) => setState(() => _category = item.key)))).toList())),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
            childAspectRatio: .72),
          itemCount: visible.length,
          itemBuilder: (ctx, i) {
            final p = visible[i];
            return Card(elevation: 0, color: Colors.white, clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: () => _details(p),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Stack(children:[
                      Positioned.fill(child:_photo(p)),
                      if((_cart[p.id]??0)>0) Positioned(top:6,right:6,child:Badge(
                        label:Text('已加 ${_cart[p.id]}'),child:const Icon(
                          Icons.shopping_bag,color:Color(0xFFAA6089)))),
                    ])),
                    Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Padding(padding: const EdgeInsets.fromLTRB(10, 0, 5, 5),
                      child: Row(children: [
                        Expanded(child: Text('${p.cost} ⭐',
                          style: const TextStyle(fontWeight: FontWeight.bold,
                            fontSize: 16, color: Color(0xFFB75983)))),
                        IconButton(tooltip: '加入购物车',
                          icon: const Icon(Icons.add_circle,
                            color: Color(0xFFB75983)),
                          onPressed: () async {
                            await _changeQuantity(p.id, 1);
                            _notify('已加入购物车 · 当前共 $_quantity 件');
                          }),
                      ])),
                  ])));
          })),
      ]));
  }
}

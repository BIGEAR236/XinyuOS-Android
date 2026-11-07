import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../v40/catalog.dart';

/// Virtual item ownership. Backed by the V4.0 order history once on upgrade;
/// new orders add SKU counts and gifting consumes exactly one unit.
class XyGiftInventory {
  static final _prefs=SharedPreferencesAsync();
  static Future<void> _pending=Future<void>.value();
  static Map<String,int> _decode(String? raw) {
    try{
      final data=jsonDecode(raw??'{}');
      if(data is! Map)return {};
      return {for(final e in data.entries)
        if(xyProductById.containsKey('${e.key}') && e.value is num &&
          (e.value as num).toInt()>0)
          '${e.key}':(e.value as num).toInt()};
    }catch(_){return {};}
  }
  static Future<Map<String,int>> load() async {
    await _pending;
    return _loadInternal();
  }
  static Future<Map<String,int>> _loadInternal() async {
    final bag=_decode(await _prefs.getString('v41.inventory'));
    if(await _prefs.getBool('v41.inventory.oldOrdersImported') == true)return bag;
    final nameToId={for(final p in xyProducts)p.name:p.id};
    try{
      final data=jsonDecode(await _prefs.getString('v40.orders')??'[]');
      if(data is List){
        for(final order in data){
          if(order is! Map)continue;
          for(final part in '${order['items']??''}'.split('、')){
            final mark=part.lastIndexOf('×');
            if(mark<1)continue;
            final id=nameToId[part.substring(0,mark)];
            final count=int.tryParse(part.substring(mark+1));
            if(id!=null&&count!=null&&count>0&&count<30){
              bag[id]=(bag[id]??0)+count;
            }
          }
        }
      }
    }catch(_){/* damaged older supplementary order log */}
    await _prefs.setString('v41.inventory',jsonEncode(bag));
    await _prefs.setBool('v41.inventory.oldOrdersImported',true);
    return bag;
  }
  static Future<void> add(Map<String,int> products) {
    final action=_pending.catchError((Object _) {}).then((_) async {
      final data=await _loadInternal();
      for(final entry in products.entries){
        if(!xyProductById.containsKey(entry.key)||entry.value<1)continue;
        data[entry.key]=(data[entry.key]??0)+entry.value;
      }
      await _prefs.setString('v41.inventory',jsonEncode(data));
    });
    _pending=action;
    return action;
  }
  static Future<bool> consume(String id) async {
    final action=_pending.catchError((Object _) {}).then((_) async {
      final data=await _loadInternal();
      if((data[id]??0)<1)return false;
      data[id]=data[id]!-1;
      if(data[id]==0)data.remove(id);
      await _prefs.setString('v41.inventory',jsonEncode(data));
      return true;
    });
    _pending=action.then<void>((_) {});
    return action;
  }
}

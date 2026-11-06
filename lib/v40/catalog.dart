import 'dart:convert';
import 'package:http/http.dart' as http;

/// 300 distinct VIRTUAL SKUs; no real brand, physical fulfillment or fiat price.
class XyProduct {
  final String id, category, categoryLabel, groupKey, name, photoQuery;
  final int cost, photoSlot;
  final String subtitle;
  const XyProduct({required this.id, required this.category,
    required this.categoryLabel, required this.groupKey, required this.name,
    required this.photoQuery, required this.photoSlot, required this.cost,
    required this.subtitle});
}

const xyCategoryNames = <String, String>{
  'shoes': '鞋靴', 'clothes': '服饰', 'home': '生活好物',
};

class _StockGroup {
  final String label, query;
  const _StockGroup(this.label, this.query);
}

const _shoes = <_StockGroup>[
  _StockGroup('轻盈跑鞋', 'running shoes'),
  _StockGroup('复古帆布鞋', 'canvas sneakers'),
  _StockGroup('日常板鞋', 'white sneakers shoes'),
  _StockGroup('休闲乐福鞋', 'loafers footwear'),
  _StockGroup('柔软室内拖', 'slippers shoes'),
  _StockGroup('长筒靴', 'leather boots fashion'),
  _StockGroup('小皮鞋', 'oxford leather shoes'),
  _StockGroup('夏日凉鞋', 'sandals footwear'),
  _StockGroup('轻便登山鞋', 'hiking boots shoes'),
  _StockGroup('温暖雪地靴', 'winter boots footwear'),
];
const _clothes = <_StockGroup>[
  _StockGroup('纯棉T恤', 'cotton t shirt fashion'),
  _StockGroup('宽松衬衫', 'button up shirt clothes'),
  _StockGroup('针织开衫', 'knitted cardigan clothing'),
  _StockGroup('牛仔裤', 'blue jeans clothing'),
  _StockGroup('百褶半裙', 'pleated skirt fashion'),
  _StockGroup('连衣裙', 'summer dress fashion'),
  _StockGroup('连帽卫衣', 'hoodie clothing'),
  _StockGroup('风衣外套', 'trench coat fashion'),
  _StockGroup('柔软毛衣', 'sweater knitwear'),
  _StockGroup('长款大衣', 'wool overcoat clothing'),
];
const _home = <_StockGroup>[
  _StockGroup('陶瓷咖啡杯', 'ceramic coffee mug'),
  _StockGroup('暖光台灯', 'desk lamp'),
  _StockGroup('纯棉抱枕', 'cushion pillow'),
  _StockGroup('香薰蜡烛', 'scented candles'),
  _StockGroup('保温水杯', 'thermos bottle'),
  _StockGroup('简约收纳盒', 'storage basket box'),
  _StockGroup('餐具套装', 'cutlery tableware'),
  _StockGroup('柔软毛毯', 'blanket textile'),
  _StockGroup('手账笔记本', 'notebook journal stationery'),
  _StockGroup('绿植花盆', 'potted houseplant'),
];
const _variants = <String>[
  '奶油白', '雾霾蓝', '焦糖棕', '森林绿', '晚霞粉',
  '暖砂杏', '经典黑', '薰衣草紫', '奶茶色', '晴空灰',
];

List<XyProduct> _makeCategory(String cat, List<_StockGroup> groups, int basePrice) {
  final output = <XyProduct>[];
  for (var group = 0; group < groups.length; group++) {
    for (var v = 0; v < _variants.length; v++) {
      output.add(XyProduct(
        id: 'xy4_${cat}_${group.toString().padLeft(2,'0')}_${v.toString().padLeft(2,'0')}',
        category: cat, categoryLabel: xyCategoryNames[cat]!,
        groupKey: '${cat}_$group',
        name: '${groups[group].label} · ${_variants[v]}',
        photoQuery: groups[group].query, photoSlot: v,
        cost: basePrice + group * 15 + v * 7 + ((group + v) % 3) * 5,
        subtitle: '虚拟${groups[group].label} · ${_variants[v]}配色 · 不寄送实物',
      ));
    }
  }
  return output;
}

final List<XyProduct> xyProducts = List<XyProduct>.unmodifiable([
  ..._makeCategory('shoes', _shoes, 110),
  ..._makeCategory('clothes', _clothes, 90),
  ..._makeCategory('home', _home, 65),
]);
final Map<String, XyProduct> xyProductById = {
  for (final p in xyProducts) p.id: p,
};

class XyCatalogPhoto {
  final String url, sourcePage, license, credit;
  const XyCatalogPhoto({required this.url, required this.sourcePage,
    required this.license, required this.credit});
}

/// Wikimedia Commons: fetch category-relevant photos LAZILY when the user browses.
/// The metadata is never treated as a real listing / purchased product photo.
/// A failed or unavailable photo uses a native icon placeholder.
class XyCommonsPhotos {
  final http.Client _client = http.Client();
  final Map<String, Future<List<XyCatalogPhoto>>> _cache = {};
  Future<void> _queue = Future<void>.value();

  Future<List<XyCatalogPhoto>> fetchFor(XyProduct product) =>
    _cache.putIfAbsent(product.groupKey, () {
      final completer = <List<XyCatalogPhoto>>[];
      // Serialize requests so rapidly scrolling the grid does not flood Commons.
      final task = _queue.then((_) async {
        try { completer.add(await _search(product.photoQuery)); }
        catch (_) { completer.add(const []); }
      });
      _queue = task;
      return task.then((_) => completer.first);
    });

  static bool _acceptedLicense(String value) {
    final s = value.toLowerCase();
    if (s.contains('nc') || s.contains('nd')) return false;
    return s.contains('cc0') || s.contains('cc by') ||
      s.contains('public domain') || s.contains('pd-');
  }

  Future<List<XyCatalogPhoto>> _search(String query) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query', 'generator': 'search',
      'gsrsearch': '$query filetype:bitmap',
      'gsrnamespace': '6', 'gsrlimit': '25', 'prop': 'imageinfo',
      'iiprop': 'url|extmetadata', 'iiurlwidth': '420',
      'iiextmetadatafilter': 'LicenseShortName|Artist|Credit',
      'format': 'json', 'formatversion': '2',
    });
    final response = await _client.get(uri, headers: {
      'User-Agent': 'XinyuOS-Android/4.0 (personal offline-first virtual app)',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || response.bodyBytes.length > 1200000) return [];
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) return [];
    final rawQuery = body['query'];
    if (rawQuery is! Map || rawQuery['pages'] is! List) return [];
    final result = <XyCatalogPhoto>[];
    for (final page in rawQuery['pages'] as List) {
      if (page is! Map || page['imageinfo'] is! List ||
          (page['imageinfo'] as List).isEmpty) continue;
      final info = (page['imageinfo'] as List).first;
      if (info is! Map) continue;
      final meta = info['extmetadata'];
      if (meta is! Map) continue;
      String metadata(String key) => meta[key] is Map ?
        '${(meta[key] as Map)['value'] ?? ''}' : '';
      final lic = metadata('LicenseShortName');
      final url = '${info['thumburl'] ?? ''}';
      final pageUrl = '${info['descriptionurl'] ?? ''}';
      if (!_acceptedLicense(lic) || !url.startsWith('https://') ||
          !pageUrl.startsWith('https://commons.wikimedia.org/')) continue;
      final rawCredit = metadata('Artist').isNotEmpty
        ? metadata('Artist') : metadata('Credit');
      final credit = rawCredit.replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&').replaceAll('&nbsp;', ' ').trim();
      result.add(XyCatalogPhoto(url: url, sourcePage: pageUrl,
        license: lic.replaceAll(RegExp(r'<[^>]*>'), ''),
        credit: credit.isEmpty ? '详见源文件页面' : credit));
    }
    return result;
  }

  void dispose() => _client.close();
}

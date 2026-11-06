import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/v40/catalog.dart';

void main() {
  test('virtual marketplace ships 100 unique shoes, 100 clothes, 100 home SKUs', () {
    expect(xyProducts.length, 300);
    expect(xyProductById.length, 300);
    for (final category in xyCategoryNames.keys) {
      expect(xyProducts.where((p) => p.category == category).length, 100);
    }
    expect(xyProducts.every((p) => p.cost >= 1 && p.cost <= 1000), isTrue);
    expect(xyProducts.every((p) => p.photoQuery.isNotEmpty &&
      p.name.isNotEmpty && p.subtitle.contains('虚拟')), isTrue);
    expect(xyProducts.map((p) => p.id).toSet().length, 300);
  });
}

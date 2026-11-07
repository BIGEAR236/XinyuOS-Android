import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/v40/catalog.dart';
import 'package:xinyu_os/v42/product_illustration.dart';

void main() {
  test('local catalog contains 100 products in each of three groups', () {
    for (final category in ['shoes','clothes','home']) {
      expect(xyProducts.where((p) => p.category == category).length, 100);
    }
    expect(xyProducts.map((p) => p.id).toSet().length, 300);
  });
  testWidgets('product illustration displays without a network image', (tester) async {
    final product = xyProducts.first;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 150, height: 150, child: XyProductArt(product: product)))));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Image), findsNothing);
  });
}

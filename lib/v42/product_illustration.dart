import 'package:flutter/material.dart';
import '../v40/catalog.dart';

/// Fully local vector thumbnails, deterministically keyed to product category,
/// actual shape group, and variant color. No unrelated web photos / license risk.
class XyProductArt extends StatelessWidget {
  final XyProduct product;
  final double? height;
  const XyProductArt({super.key, required this.product, this.height});
  @override Widget build(BuildContext context) => SizedBox(height: height,
    child: ClipRRect(borderRadius: BorderRadius.circular(12),
      child: CustomPaint(painter: _ProductPainter(product),
        child: const SizedBox.expand())));
}
class _ProductPainter extends CustomPainter {
  final XyProduct product;
  _ProductPainter(this.product);
  static const colors = <Color>[
    Color(0xFFF5EBDB),Color(0xFF9DBBD5),Color(0xFFA98065),
    Color(0xFF6F9E83),Color(0xFFDB98AB),Color(0xFFE9C7A0),
    Color(0xFF474C59),Color(0xFFA692CB),Color(0xFFCBB29F),Color(0xFFBAC4CC),
  ];
  @override void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final group = int.tryParse(product.groupKey.split('_').last) ?? 0;
    final variant = product.photoSlot % colors.length;
    final main = colors[variant];
    final shadow = Color.lerp(main, const Color(0xFF4B4558), .35)!;
    final shine = Color.lerp(main, Colors.white, .48)!;
    final outline = Paint()..color = const Color(0xFF5D5361)..style = PaintingStyle.stroke..strokeWidth = 1.4;
    final fill = Paint()..color = main;
    final accent = Paint()..color = shadow;
    final bright = Paint()..color = shine;
    canvas.drawRect(const Rect.fromLTWH(0,0,100,100),Paint()..color=const Color(0xFFF9F1F8));
    canvas.drawCircle(const Offset(52,40),40,Paint()..color=const Color(0x22C3B3D6));
    canvas.drawOval(const Rect.fromLTWH(18,81,64,8),Paint()..color=const Color(0x205A4E62));
    void rounded(Rect rect, Paint paint, [double radius=5]) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect,Radius.circular(radius)),paint);
    }
    void polygon(List<Offset> points, Paint paint) {
      final path=Path()..moveTo(points.first.dx,points.first.dy);
      for (final p in points.skip(1)) { path.lineTo(p.dx,p.dy); }
      path.close();canvas.drawPath(path,paint);
    }
    switch (product.category) {
      case 'shoes':
        if (group == 5 || group == 9 || group == 6) {
          polygon([const Offset(38,22),const Offset(60,22),const Offset(61,59),
            const Offset(80,68),const Offset(80,78),const Offset(26,78),const Offset(26,63),
            const Offset(38,58)],fill);
          rounded(const Rect.fromLTWH(25,75,56,7),accent,2);
          rounded(const Rect.fromLTWH(44,29,10,25),bright,3);
        } else if (group == 7 || group == 4) {
          rounded(const Rect.fromLTWH(15,65,75,13),accent,7);
          for(final x in [36.0,53.0,70.0]) rounded(Rect.fromLTWH(x,48,9,21),fill,4);
          rounded(const Rect.fromLTWH(15,74,75,5),bright,2);
        } else {
          polygon([const Offset(14,60),const Offset(35,44),const Offset(54,46),
            const Offset(69,62),const Offset(88,66),const Offset(90,75),
            const Offset(14,75)],fill);
          rounded(const Rect.fromLTWH(13,73,78,7),accent,3);
          for (final y in [53.0,59.0]) canvas.drawLine(Offset(43,y),Offset(65,y+2),outline);
          rounded(const Rect.fromLTWH(19,69,62,3),bright,1);
        }
      case 'clothes':
        if (group == 3) { // jeans
          polygon([const Offset(29,21),const Offset(70,21),const Offset(64,83),
            const Offset(51,83),const Offset(49,48),const Offset(46,83),
            const Offset(33,83)],fill);
          canvas.drawLine(const Offset(29,33),const Offset(70,33),outline);
        } else if (group == 4 || group == 5) { // skirt or dress
          polygon([const Offset(39,18),const Offset(61,18),const Offset(67,38),
            const Offset(81,79),const Offset(20,79),const Offset(33,38)],fill);
          canvas.drawLine(const Offset(32,44),const Offset(68,44),outline);
          if (group==5) {
            polygon([const Offset(39,18),const Offset(29,32),const Offset(34,44),
              const Offset(40,34),const Offset(62,34),const Offset(70,44),
              const Offset(75,32),const Offset(61,18)],bright);
          }
        } else {
          polygon([const Offset(36,18),const Offset(25,27),const Offset(12,48),
            const Offset(25,58),const Offset(34,43),const Offset(34,79),
            const Offset(69,79),const Offset(69,43),const Offset(79,58),
            const Offset(90,48),const Offset(76,27),const Offset(64,18)],fill);
          polygon([const Offset(36,18),const Offset(43,24),const Offset(57,24),
            const Offset(64,18)],accent);
          if (group==2 || group==8 || group==9) {
            for (final y in [39.0,49.0,59.0])
              canvas.drawLine(Offset(42,y),Offset(61,y),Paint()..color=shadow..strokeWidth=.8);
          }
          if (group==6) rounded(const Rect.fromLTWH(44,30,12,17),bright,5);
        }
      default: // 10 different household silhouettes
        switch(group) {
          case 0: case 4: // cup and thermos
            rounded(Rect.fromLTWH(30,30,39,47),fill,6);
            canvas.drawArc(const Rect.fromLTWH(59,40,25,23),-.9,3.4,false,
              Paint()..color=shadow..strokeWidth=6..style=PaintingStyle.stroke);
            rounded(const Rect.fromLTWH(34,32,30,6),bright,4);
          case 1: // lamp
            polygon([const Offset(39,20),const Offset(64,20),const Offset(74,49),
              const Offset(30,49)],fill);
            rounded(const Rect.fromLTWH(48,48,6,23),accent,1);
            rounded(const Rect.fromLTWH(31,72,42,7),fill,3);
          case 2: case 7: // pillow / blanket
            rounded(const Rect.fromLTWH(18,32,64,44),fill,11);
            rounded(const Rect.fromLTWH(25,38,50,30),bright,9);
            if(group==7) canvas.drawLine(const Offset(35,41),const Offset(64,65),outline);
          case 3: // candle
            rounded(const Rect.fromLTWH(36,39,29,37),fill,4);
            polygon([const Offset(51,18),const Offset(56,28),const Offset(51,39),
              const Offset(46,29)],Paint()..color=const Color(0xFFF4AE63));
            rounded(const Rect.fromLTWH(39,49,22,19),bright,3);
          case 5: // organizer
            rounded(const Rect.fromLTWH(20,37,63,39),fill,7);
            rounded(const Rect.fromLTWH(28,31,48,9),accent,3);
            rounded(const Rect.fromLTWH(45,50,13,3),bright,2);
          case 6: // cutlery
            rounded(const Rect.fromLTWH(28,30,7,49),accent,3);
            rounded(const Rect.fromLTWH(48,32,6,47),fill,3);
            rounded(const Rect.fromLTWH(67,30,6,49),accent,3);
            for(final x in [26.0,31.0,36.0]) canvas.drawLine(Offset(x,30),Offset(x,43),outline);
          case 8: // notebook
            rounded(const Rect.fromLTWH(25,21,51,59),fill,4);
            rounded(const Rect.fromLTWH(30,25,6,51),accent,1);
            for(final y in [42.0,51.0,60.0]) canvas.drawLine(Offset(44,y),Offset(67,y),outline);
          case 9: // plant
            rounded(const Rect.fromLTWH(33,53,37,25),fill,5);
            for(final p in [const Offset(30,45),const Offset(42,25),const Offset(57,22),const Offset(72,42)]) {
              canvas.drawOval(Rect.fromCenter(center:p,width:15,height:25),Paint()..color=const Color(0xFF7CA78B));
            }
        }
    }
    canvas.restore();
  }
  @override bool shouldRepaint(covariant _ProductPainter oldDelegate) => oldDelegate.product.id != product.id;
}

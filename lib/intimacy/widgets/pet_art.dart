import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/pet_engine.dart';

class CutePetArt extends StatefulWidget {
  final PetSpecies? species;
  final String mood;
  final bool egg;
  final String eggTheme;
  final List<List<List<double>>> strokes;
  /// Transient care feedback emoji (e.g. '💗') that floats up and fades.
  final String? badge;
  const CutePetArt({super.key, this.species, this.mood='开心', this.egg=false, this.eggTheme='云朵蛋', this.strokes=const [], this.badge});
  @override
  State<CutePetArt> createState() => _CutePetArtState();
}
class _CutePetArtState extends State<CutePetArt> with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  @override void initState() {
    super.initState();
    motion = AnimationController(vsync:this, duration:const Duration(milliseconds:1150))..repeat(reverse:true);
  }
  @override void dispose() { motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation:motion,
    builder:(context, child) => Transform.translate(
      offset:Offset(0,-5*math.sin(motion.value*math.pi)),
      child: Transform.rotate(
        angle: widget.egg ? math.sin(motion.value*math.pi*2)*0.025 : 0,
        child: child,
      ),
    ),
    child: SizedBox(width: 236, height: 236,
      child: Stack(children: [
        CustomPaint(
          painter:_CritterPainter(species:widget.species, mood:widget.mood, egg:widget.egg, eggTheme:widget.eggTheme, strokes:widget.strokes),
          size:const Size(236,236)),
        if (!widget.egg && widget.species != null) Positioned(
          right: 3, bottom: 4,
          child: Text(widget.species!.emoji, style:const TextStyle(fontSize: 33))),
        if (widget.badge != null) Positioned(
          left: 0, right: 0, top: 18,
          child: IgnorePointer(child: TweenAnimationBuilder<double>(
            key: ValueKey(widget.badge),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1150),
            builder: (context, t, child) => Opacity(
              opacity: (1 - t).clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(0, -38 * t), child: child)),
            child: Text(widget.badge!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 42))))),
      ])),
  );
}

const eggPalette = [Color(0xFFBC6599),Color(0xFF6B9FC9),Color(0xFFE2AC60),Color(0xFF83B294),Color(0xFF9468B4)];

class _CritterPainter extends CustomPainter {
  final PetSpecies? species; final String mood; final bool egg; final String eggTheme;
  final List<List<List<double>>> strokes;
  const _CritterPainter({this.species, required this.mood, required this.egg, this.eggTheme='云朵蛋', required this.strokes});
  @override void paint(Canvas c, Size size) {
    c.save(); c.scale(size.width/236, size.height/236);
    c.drawOval(const Rect.fromLTWH(24,211,190,17),Paint()..color=const Color(0x1C726680));
    if (egg) {
      final shape = Path()..moveTo(117,26)..cubicTo(78,27,55,87,53,143)..cubicTo(48,195,81,216,118,215)..cubicTo(161,214,187,192,180,145)..cubicTo(179,87,157,27,117,26)..close();
      final schemes=<String,List<Color>>{
        '云朵蛋':[const Color(0xFFFFE0E9),const Color(0xFFE4D7FF),const Color(0xFFB8E4E8)],
        '森林蛋':[const Color(0xFFFFE8C7),const Color(0xFFCAE7B8),const Color(0xFF9BC9A9)],
        '海洋蛋':[const Color(0xFFC1EBFA),const Color(0xFFA7D5F5),const Color(0xFF9CBDE6)],
        '星光蛋':[const Color(0xFFF6C8EE),const Color(0xFFB8B6F3),const Color(0xFF8CA0E4)],
        '梦幻蛋':[const Color(0xFFFFD1E4),const Color(0xFFFFE8B0),const Color(0xFFBCDDFF)],
      };
      c.drawPath(shape,Paint()..shader=LinearGradient(colors:schemes[eggTheme]??schemes['云朵蛋']!,begin:Alignment.topLeft,end:Alignment.bottomRight).createShader(const Rect.fromLTWH(45,25,145,190)));
      c.drawPath(shape,Paint()..color=Colors.white70..style=PaintingStyle.stroke..strokeWidth=3);
      c.drawOval(const Rect.fromLTWH(77,64,26,55),Paint()..color=Colors.white.withValues(alpha:0.36));
      _star(c,155,88,13,Colors.white70); _star(c,82,153,9,const Color(0xFFFFA9C8));
      for (final stroke in strokes) {
        if (stroke.length<2) continue;
        final p=Path()..moveTo(stroke.first[0]*236, stroke.first[1]*236);
        for (final pair in stroke.skip(1)) { p.lineTo(pair[0]*236,pair[1]*236); }
        final index=stroke.first.length>2?stroke.first[2].round().clamp(0,eggPalette.length-1).toInt():0;
        final width=stroke.first.length>3?stroke.first[3].clamp(2.0,14.0).toDouble():4.0;
        c.drawPath(p,Paint()..color=eggPalette[index]..style=PaintingStyle.stroke..strokeWidth=width..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round);
      }
      c.restore(); return;
    }
    final hex=species?.color ?? 'FFEDBDCE';
    final color=Color(int.parse(hex,radix:16));
    final tier = species?.rarity ?? 'white';
    if (tier != 'white') {
      final aura = tier == 'green' ? const Color(0xFF82BCA4) :
        tier == 'gold' ? const Color(0xFFF1C45B) : const Color(0xFFE76584);
      c.drawCircle(const Offset(117, 134), 94,
        Paint()..color=aura.withValues(alpha:.23)
          ..maskFilter=const MaskFilter.blur(BlurStyle.normal, 16));
      c.drawCircle(const Offset(117, 134), 88,
        Paint()..color=aura.withValues(alpha:.6)
          ..style=PaintingStyle.stroke..strokeWidth=2.8);
      if (tier == 'gold' || tier == 'red') {
        for (final pair in [const Offset(23,63),const Offset(204,83),
          const Offset(200,185),const Offset(37,188)]) {
          _star(c,pair.dx,pair.dy,tier=='red'?13:9,aura);
        }
      }
      if (tier == 'red') {
        final crown=Path()..moveTo(85,55)..lineTo(92,15)..lineTo(113,35)
          ..lineTo(131,11)..lineTo(147,34)..lineTo(156,15)..lineTo(161,55)..close();
        c.drawPath(crown,Paint()..color=const Color(0xFFE9B44E));
      }
    }
    final dark=Color.lerp(color,const Color(0xFF726D80),0.2)!;
    final ear=Paint()..color=color;
    final id=species?.id ?? 'cat';
    c.drawCircle(const Offset(117,143),72,Paint()..color=dark);
    c.drawCircle(const Offset(117,139),69,ear);
    if (['rabbit','cat','fox','dog','unicorn','deer','dragon'].contains(id)) {
      if (id=='rabbit') {
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(70,12,29,92),const Radius.circular(16)),ear);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(138,12,29,92),const Radius.circular(16)),ear);
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(80,21,11,70),const Radius.circular(8)),Paint()..color=const Color(0xFFFFA5BF));
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(146,21,11,70),const Radius.circular(8)),Paint()..color=const Color(0xFFFFA5BF));
      } else if (id=='dog') {
        c.drawOval(const Rect.fromLTWH(44,57,42,68), Paint()..color=dark);
        c.drawOval(const Rect.fromLTWH(150,57,42,68), Paint()..color=dark);
      } else {
        for (final x in [72.0,163.0]) {
          final p=Path()..moveTo(x-26,90)..lineTo(x-4,30)..lineTo(x+26,90)..close();
          c.drawPath(p,ear);
          c.drawPath(p,Paint()..color=const Color(0x44FFFFFF)..style=PaintingStyle.stroke..strokeWidth=3);
        }
      }
    }
    if (id=='panda') { for (final x in [64.0,170.0]) { c.drawCircle(Offset(x,79),25,Paint()..color=const Color(0xFF62657B)); } }
    if (id=='axolotl') {
      for (final s in [-1,1]) {
        for (var i=0;i<3;i++) { c.drawCircle(Offset(117+s*77,102+i*15),9,Paint()..color=const Color(0xFFFF8AB9)); }
      }
    }
    if (id=='jellyfish') {
      for(var i=0;i<5;i++) { c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(67+i*23,172,12,45),const Radius.circular(7)),Paint()..color=dark); }
    }
    if (id=='unicorn') {
      final horn=Path()..moveTo(110,72)..lineTo(122,12)..lineTo(137,72)..close();
      c.drawPath(horn,Paint()..color=const Color(0xFFFFD67E));
    }
    if (id=='dragon') {
      for(var i=0;i<3;i++) { c.drawCircle(Offset(72+i*45,61),11,Paint()..color=const Color(0xFF89C3BA)); }
    }
    // Eyes and expression are state-driven rather than static imagery.
    for (final x in [91.0,146.0]) {
      if (mood=='疲惫' || mood=='困倦') {
        c.drawArc(Rect.fromCircle(center:Offset(x,132),radius:10),0,math.pi,false,Paint()..color=const Color(0xFF514F63)..strokeWidth=3.5..style=PaintingStyle.stroke);
      } else if (mood=='享受' || mood=='兴奋') {
        // Happy squinting crescents: the sharper arc reads as excitement.
        c.drawArc(Rect.fromCircle(center:Offset(x,131),radius:mood=='兴奋'?12:10),math.pi*1.12,math.pi*0.76,false,Paint()..color=const Color(0xFF45465B)..strokeWidth=3.6..style=PaintingStyle.stroke..strokeCap=StrokeCap.round);
      } else {
        c.drawOval(Rect.fromCenter(center:Offset(x,134),width:13,height:mood=='开心'?20:13),Paint()..color=const Color(0xFF45465B));
        c.drawCircle(Offset(x-2,129),3,Paint()..color=Colors.white);
      }
    }
    for(final x in [72.0,164.0]) { c.drawOval(Rect.fromLTWH(x,152,17,9),Paint()..color=Color(mood=='享受'||mood=='兴奋'?0xAAF78FB2:0x77F78FB2)); }
    c.drawOval(const Rect.fromLTWH(80,195,35,19),ear); c.drawOval(const Rect.fromLTWH(124,195,35,19),ear);
    if (mood=='开心') { _star(c,184,69,10,const Color(0xFFFFE1A4)); }
    if (mood=='兴奋') { _star(c,42,71,9,const Color(0xFFFFC94D)); _star(c,196,113,8,const Color(0xFFFFC94D)); }
    if (mood=='享受') {
      // Content closed-mouth smile with a little heart.
      c.drawArc(const Rect.fromLTWH(103,151,30,14),0.25,math.pi-0.5,false,Paint()..color=const Color(0xFF6A5667)..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..strokeWidth=2.9);
      _heart(c,205,84,9,const Color(0xFFF78FB2));
    } else {
      c.drawArc(const Rect.fromLTWH(107,147,24,19),0.15,math.pi-0.3,false,Paint()..color=const Color(0xFF6A5667)..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..strokeWidth=2.9);
    }
    if (mood=='困倦') {
      c.drawOval(const Rect.fromLTWH(108,152,20,16),Paint()..color=const Color(0xFF8A7392)); // yawning mouth
      c.drawOval(const Rect.fromLTWH(174,98,10,4),Paint()..color=const Color(0xFF9FB4C9));
      c.drawOval(const Rect.fromLTWH(184,110,10,4),Paint()..color=const Color(0xFF9FB4C9));
    }
    c.restore();
  }
  void _star(Canvas c, double x,double y,double radius,Color color) {
    final p=Path()..moveTo(x,y-radius)..lineTo(x+radius*.3,y-radius*.3)..lineTo(x+radius,y)..lineTo(x+radius*.3,y+radius*.3)..lineTo(x,y+radius)..lineTo(x-radius*.3,y+radius*.3)..lineTo(x-radius,y)..lineTo(x-radius*.3,y-radius*.3)..close();
    c.drawPath(p,Paint()..color=color);
  }
  void _heart(Canvas c, double x,double y,double r,Color color) {
    final p=Path()..moveTo(x,y+r*.9)
      ..cubicTo(x-r*1.4,y-r*.1,x-r*.7,y-r*1.1,x,y-r*.35)
      ..cubicTo(x+r*.7,y-r*1.1,x+r*1.4,y-r*.1,x,y+r*.9)..close();
    c.drawPath(p,Paint()..color=color);
  }
  @override bool shouldRepaint(covariant _CritterPainter old) => true;
}

class EggPaintBoard extends StatefulWidget {
  final List<List<List<double>>> strokes;
  final ValueChanged<List<List<List<double>>>> onChanged;
  final int colorIndex;
  final double brushWidth;
  const EggPaintBoard({super.key,required this.strokes,required this.onChanged,this.colorIndex=0,this.brushWidth=4});
  @override State<EggPaintBoard> createState()=>_EggPaintBoardState();
}
class _EggPaintBoardState extends State<EggPaintBoard> {
  void add(Offset p, Size size, {bool start=false}) {
    final x=(p.dx/size.width).clamp(0.0,1.0).toDouble(), y=(p.dy/size.height).clamp(0.0,1.0).toDouble();
    // Keep paint inside egg silhouette's broad bounds.
    if (x<.2 || x>.8 || y<.1 || y>.94) return;
    if(start || widget.strokes.isEmpty) widget.strokes.add([]);
    widget.strokes.last.add([x,y,widget.colorIndex.toDouble(),widget.brushWidth]);
    widget.onChanged(widget.strokes);
    setState((){});
  }
  @override Widget build(BuildContext context)=> LayoutBuilder(builder:(context, box) {
    final side=math.min(box.maxWidth,280.0);
    return GestureDetector(
      onPanStart:(d)=>add(d.localPosition,Size(side,side),start:true),
      onPanUpdate:(d)=>add(d.localPosition,Size(side,side)),
      child:SizedBox(width:side,height:side,child:CustomPaint(painter:_CritterPainter(egg:true,mood:'开心',strokes:widget.strokes))),
    );
  });
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// GPU-cheap, offline 2D motion for an uploaded portrait: breathing float,
/// a gentle head sway, and a rhythmic lower-face stretch while talking that
/// reads as mouth movement. This is still NOT face reenactment, viseme
/// lip-sync or eye blinking — those are reserved for the planned DUIX SDK
/// upgrade, which renders a real talking-head video locally on the device.
class XyAnimatedPortrait extends StatefulWidget {
  final String path;
  final bool talking;
  final double width;
  final double height;
  const XyAnimatedPortrait({super.key, required this.path,
    this.talking = false, this.width = 190, this.height = 230});
  @override State<XyAnimatedPortrait> createState() => _XyAnimatedPortraitState();
}

class _XyAnimatedPortraitState extends State<XyAnimatedPortrait>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this, duration: const Duration(seconds: 6))..repeat();
  /// The mouth zone starts roughly below the nose line of a portrait.
  static const _mouthTop = 0.58;

  @override void dispose() { motion.dispose(); super.dispose(); }

  Widget _photo(double w, double h) =>
    widget.path.isNotEmpty && File(widget.path).existsSync()
      ? Image.file(File(widget.path), fit: BoxFit.cover,
          width: w, height: h,
          errorBuilder: (_, _, _) => const Icon(Icons.face_3, size: 80))
      : const Icon(Icons.face_3, size: 84, color: Color(0xFF9B76A7));

  @override Widget build(BuildContext context) {
    final w = widget.width, h = widget.height;
    return AnimatedBuilder(animation: motion, builder: (context, _) {
      final t = motion.value * 2 * math.pi;
      final breath = math.sin(t);                       // slow up/down float
      final sway = math.sin(t * .5 + 1.2) * .013;       // head sway ±0.75°
      // Talking envelope: mixed sines through abs() give an organic,
      // jaw-like open/close rhythm without any audio feedback channel.
      final mouth = widget.talking
        ? .25 + .75 * (math.sin(t * 8.4) * .55 + math.sin(t * 15.2) * .3
            + math.sin(t * 23.1) * .15).abs().clamp(0.0, 1.0).toDouble()
        : 0.0;
      final stretch = 1 + mouth * .09;                  // lower-face scaleY
      Widget fullPhoto({Alignment alignment = Alignment.topCenter}) =>
        OverflowBox(maxWidth: w, maxHeight: h, alignment: alignment,
          child: SizedBox(width: w, height: h, child: _photo(w, h)));
      return Transform.rotate(angle: sway, child: Transform.translate(
        offset: Offset(0, breath * 4), child: Container(width: w, height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(25),
            color: const Color(0xFFEBD9F2), boxShadow: const [BoxShadow(
              color: Color(0x257A558B), blurRadius: 24, offset: Offset(0, 10))]),
          child: Stack(fit: StackFit.expand, children: [
            // Upper face: shows the top 58% of the same photo, static so
            // the seam with the animated lower half never tears.
            Positioned(top: 0, left: 0, right: 0, height: h * _mouthTop,
              child: ClipRect(child: fullPhoto(alignment: Alignment.topCenter))),
            // Lower face: the bottom 42% of the photo, vertically stretched
            // around an anchor exactly ON the seam (Alignment y = 0.16 ==
            // 58% of the image height), so lips move while the join stays.
            Positioned(top: h * _mouthTop, left: 0, right: 0,
              height: h * (1 - _mouthTop),
              child: ClipRect(child: Transform.scale(
                scaleY: stretch,
                alignment: const Alignment(0, _mouthTop * 2 - 1),
                child: fullPhoto(alignment: Alignment.bottomCenter)))),
            if (widget.talking) Positioned(right: 9, bottom: 10,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54,
                  borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.graphic_eq, size: 18, color: Colors.white),
                  Text('正在说话', style: TextStyle(color: Colors.white, fontSize: 10)),
                ]))),
          ]))));
    });
  }
}

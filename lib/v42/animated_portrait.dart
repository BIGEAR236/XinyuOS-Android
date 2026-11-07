import 'dart:io';
import 'package:flutter/material.dart';

/// GPU-cheap, offline 2D motion. The photo is gently moved and scaled;
/// this is NOT face reenactment, actual blinking or lip synchronization.
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
    vsync: this, duration: const Duration(milliseconds: 2100))..repeat(reverse: true);
  @override void dispose() { motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion, builder: (context, _) {
      final fraction = motion.value;
      return Transform.translate(offset: Offset(0, (fraction - .5) * 7),
        child: Transform.scale(scale: .985 + fraction * (widget.talking ? .038 : .025),
          child: Container(width: widget.width, height: widget.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(25),
              color: const Color(0xFFEBD9F2), boxShadow: const [BoxShadow(
                color: Color(0x257A558B), blurRadius: 24, offset: Offset(0, 10))]),
            child: Stack(fit: StackFit.expand, children: [
              widget.path.isNotEmpty && File(widget.path).existsSync()
                ? Image.file(File(widget.path), fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.face_3, size: 80))
                : const Icon(Icons.face_3, size: 84, color: Color(0xFF9B76A7)),
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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Explicit 4x5 desktop cells. Empty spaces are real drop targets, not a Wrap.
/// Swap existing items or drag an app to an empty position; saves across starts.
class XyDesktopSlots {
  static final preferences = SharedPreferencesAsync();
  static const prefKey = 'v41.desktop.slots';
  static const visible = ['chat','api','music','video','settings','memo','diary','album'];
  static List<String> defaultSlots() => [
    'chat','api','music','video',
    'settings','memo','diary','album',
    ...List<String>.filled(12, ''),
  ];
  static final current = ValueNotifier<List<String>>(defaultSlots());
  static Future<void> load() async {
    try {
      final saved = await preferences.getStringList(prefKey);
      if (saved == null || saved.length != 20) return;
      final valid = saved.where((key) => visible.contains(key)).toList();
      if (valid.length != visible.length || valid.toSet().length != visible.length) return;
      current.value = saved;
    } catch (_) { /* preserve a usable desktop */ }
  }
  static Future<void> move(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= 20 || to >= 20) return;
    final updated = [...current.value];
    final temp = updated[from]; updated[from] = updated[to]; updated[to] = temp;
    current.value = updated;
    await preferences.setStringList(prefKey, updated);
  }
  static Future<void> reset() async {
    current.value = defaultSlots();
    await preferences.setStringList(prefKey, current.value);
  }
}

class XyDesktopGrid extends StatelessWidget {
  final Widget Function(String key) tileBuilder;
  final double scale;
  const XyDesktopGrid({super.key, required this.tileBuilder,this.scale=1.0});
  @override Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: XyDesktopSlots.current, builder: (context, slots, _) =>
    GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:scale>1.35?2:scale>1.10?3:4, mainAxisSpacing: 6, crossAxisSpacing: 5,
        childAspectRatio: .82),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final key = slots[index];
        return DragTarget<int>(
          onWillAcceptWithDetails: (d) => d.data != index,
          onAcceptWithDetails: (d) => XyDesktopSlots.move(d.data, index),
          builder: (context, incoming, rejected) => Container(
            decoration: BoxDecoration(
              color: incoming.isNotEmpty ? Colors.white30 : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: incoming.isNotEmpty ? Border.all(color: Colors.white70) : null),
            alignment: Alignment.topCenter,
            child: key.isEmpty
              ? const SizedBox.expand() // Blank, freely placeable cell.
              : LongPressDraggable<int>(data: index, maxSimultaneousDrags: 1,
                feedback: Material(type: MaterialType.transparency,
                  child: Opacity(opacity: .9,child: tileBuilder(key))),
                childWhenDragging: const SizedBox.shrink(),
                child: tileBuilder(key))),
        );
      }));
}

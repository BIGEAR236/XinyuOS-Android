import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-installation desktop icon size. This does NOT change Android launcher icons
/// or the app data schema, and survives subsequent app restarts.
class DesktopIconScale {
  static const prefKey = 'desktop.iconScale.v39';
  static final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  static final ValueNotifier<double> current = ValueNotifier<double>(1.0);

  static double normalize(double scale) => scale.clamp(0.7, 1.5).toDouble();

  static Future<double> load() async => normalize(
    await prefs.getDouble(prefKey) ?? 1.0);

  /// Call before runApp so that the home screen uses the saved scale immediately.
  static Future<void> initialize() async {
    try {
      current.value = await load();
    } catch (_) {
      // Preference failure must not prevent the virtual phone from launching.
      current.value = 1.0;
    }
  }

  static Future<void> save(double scale) async {
    final next = normalize(scale);
    await prefs.setDouble(prefKey, next);
    current.value = next; // Immediately redraw the already-mounted desktop.
  }
}

class DesktopIconSizeDialog extends StatefulWidget {
  const DesktopIconSizeDialog({super.key});
  @override
  State<DesktopIconSizeDialog> createState() => _DesktopIconSizeDialogState();
}

class _DesktopIconSizeDialogState extends State<DesktopIconSizeDialog> {
  late double scale;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    scale = DesktopIconScale.current.value;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义桌面图标大小'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.apps_rounded, size: 52 * scale),
        const SizedBox(width: 15),
        Text('${(scale * 100).round()}%',
          style: Theme.of(context).textTheme.headlineSmall),
      ]),
      const SizedBox(height: 10),
      Slider(value: scale, min: 0.7, max: 1.5, divisions: 16,
        label: '${(scale * 100).round()}%',
        onChanged: saving ? null : (value) => setState(() => scale = value)),
      const Text('70%～150% · 调整心屿虚拟桌面图标，不修改手机系统图标。',
        textAlign: TextAlign.center),
    ]),
    actions: [
      TextButton(onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('取消')),
      TextButton(onPressed: saving ? null : () => setState(() => scale = 1.0),
        child: const Text('恢复 100%')),
      FilledButton(onPressed: saving ? null : () async {
        setState(() => saving = true);
        try {
          await DesktopIconScale.save(scale);
          if (context.mounted) Navigator.pop(context, scale);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('保存图标大小失败：$error')));
            setState(() => saving = false);
          }
        }
      }, child: const Text('保存')),
    ],
  );
}

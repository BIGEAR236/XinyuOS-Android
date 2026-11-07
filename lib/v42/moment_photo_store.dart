import 'package:shared_preferences/shared_preferences.dart';

/// Per-moment photo reference, kept apart from legacy MomentEntry JSON to
/// avoid changing persisted model schema and breaking previous saved moments.
class XyMomentPhotoStore {
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static String _key(String momentId) => 'v42.momentPhoto.${Uri.encodeComponent(momentId)}';
  static Future<String> get(String id) async => await _prefs.getString(_key(id)) ?? '';
  static Future<void> set(String id, String relativePath) async {
    if (relativePath.isEmpty) { await _prefs.remove(_key(id)); }
    else { await _prefs.setString(_key(id), relativePath); }
  }
}

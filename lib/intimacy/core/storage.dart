import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pet_engine.dart';

class CompanionStorage {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  Future<PetState> getPet(String roleId) async {
    final raw = await prefs.getString('intimacy.pet.$roleId');
    if (raw == null) return PetState();
    try { return PetState.fromJson(jsonDecode(raw) as Map<String,dynamic>); }
    catch (_) { return PetState(); }
  }
  Future<void> setPet(String roleId, PetState pet) => prefs.setString('intimacy.pet.$roleId',jsonEncode(pet.toJson()));
}

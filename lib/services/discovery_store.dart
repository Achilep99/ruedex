import 'package:shared_preferences/shared_preferences.dart';

class DiscoveryStore {
  static const _key = 'discovered_street_ids';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<Set<String>> loadDiscoveredIds() async {
    final ids = await _preferences.getStringList(_key) ?? const <String>[];
    return ids.toSet();
  }

  Future<void> addDiscovery(String streetId) async {
    final ids = await loadDiscoveredIds();
    ids.add(streetId);
    final sortedIds = ids.toList()..sort();
    await _preferences.setStringList(_key, sortedIds);
  }

  Future<void> clear() async {
    await _preferences.remove(_key);
  }
}

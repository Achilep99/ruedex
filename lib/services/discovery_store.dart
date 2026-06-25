import 'package:shared_preferences/shared_preferences.dart';

class DiscoveryStore {
  static const _key = 'discovered_street_ids';
  static const _datePrefix = 'discovered_at_';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<Set<String>> loadDiscoveredIds() async {
    final ids = await _preferences.getStringList(_key) ?? const <String>[];
    return ids.toSet();
  }

  Future<DateTime?> discoveryDate(String streetId) async {
    final value = await _preferences.getString('$_datePrefix$streetId');
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<bool> addDiscovery(String streetId) async {
    final ids = await loadDiscoveredIds();
    final isNew = ids.add(streetId);
    if (!isNew) return false;
    final sortedIds = ids.toList()..sort();
    await _preferences.setStringList(_key, sortedIds);
    await _preferences.setString('$_datePrefix$streetId', DateTime.now().toIso8601String());
    return true;
  }

  Future<void> clear() async {
    final ids = await loadDiscoveredIds();
    for (final id in ids) {
      await _preferences.remove('$_datePrefix$id');
    }
    await _preferences.remove(_key);
  }
}

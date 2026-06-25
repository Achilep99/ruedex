import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class AppSettingsStore {
  static const _developerModeKey = 'developer_mode_enabled';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<bool> loadDeveloperMode() async {
    if (!AppConfig.developerToolsAvailable) {
      return false;
    }
    return await _preferences.getBool(_developerModeKey) ?? true;
  }

  Future<void> setDeveloperMode(bool enabled) async {
    if (!AppConfig.developerToolsAvailable) {
      return;
    }
    await _preferences.setBool(_developerModeKey, enabled);
  }
}

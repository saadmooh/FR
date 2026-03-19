import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsRepository {
  static const String _apiKeyKey = 'ai_api_key';
  static const String _providerKey = 'ai_provider';
  static const String _localeKey = 'locale';

  final SharedPreferences _prefs;

  AppSettingsRepository(this._prefs);

  String? getApiKey() {
    return _prefs.getString(_apiKeyKey);
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString(_apiKeyKey, key);
  }

  String getProvider() {
    return _prefs.getString(_providerKey) ?? 'google';
  }

  Future<void> setProvider(String provider) async {
    await _prefs.setString(_providerKey, provider);
  }

  bool hasApiKey() {
    final key = getApiKey();
    return key != null && key.isNotEmpty;
  }

  String? getLocale() {
    return _prefs.getString(_localeKey);
  }

  Future<void> setLocale(String locale) async {
    await _prefs.setString(_localeKey, locale);
  }
}

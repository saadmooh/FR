import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_credential_store.dart';
import 'reminder_repository.dart';
import 'free_time_repository.dart';

class AppSettingsRepository {
  static const String _apiKeyKey = 'ai_api_key';
  static const String _providerKey = 'ai_provider';
  static const String _modelKey = 'ai_model';
  static const String _localeKey = 'locale';

  final SharedPreferences _prefs;
  ReminderRepository? _reminderRepository;
  FreeTimeRepository? _freeTimeRepository;

  AppSettingsRepository(this._prefs);

  void setRepositories(
    ReminderRepository reminderRepo,
    FreeTimeRepository freeTimeRepo,
  ) {
    _reminderRepository = reminderRepo;
    _freeTimeRepository = freeTimeRepo;
  }

  ReminderRepository getReminderRepository() {
    return _reminderRepository!;
  }

  FreeTimeRepository getFreeTimeRepository() {
    return _freeTimeRepository!;
  }

  String? getApiKey() {
    return _prefs.getString(_apiKeyKey);
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString(_apiKeyKey, key);
    // Mirror into secure storage so background isolates can read it without
    // passing the key through WorkManager inputData.
    await ApiCredentialStore.saveApiKey(key);
  }

  String getProvider() {
    return _prefs.getString(_providerKey) ?? 'google';
  }

  Future<void> setProvider(String provider) async {
    await _prefs.setString(_providerKey, provider);
  }

  String getModel() {
    return _prefs.getString(_modelKey) ?? '';
  }

  Future<void> setModel(String model) async {
    await _prefs.setString(_modelKey, model);
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

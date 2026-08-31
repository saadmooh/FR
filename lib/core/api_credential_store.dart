import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the AI API key in platform secure storage so it is not written into
/// WorkManager `inputData` (persisted by JobScheduler unencrypted) nor kept
/// as plaintext in SharedPreferences.
///
/// SharedPreferences is retained only as a read fallback for installs that
/// already have a stored key.
class ApiCredentialStore {
  static const String _secureKey = 'ai_api_key';
  static const String _prefsKey = 'ai_api_key';

  static final FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Mirrors the API key into secure storage. The prefs copy is written by
  /// [AppSettingsRepository] and kept for backwards compatibility.
  static Future<void> saveApiKey(String key) async {
    if (key.isEmpty) return;
    try {
      await _storage.write(key: _secureKey, value: key);
    } catch (e) {
      debugPrint('Failed to store API key securely: $e');
    }
  }

  /// Reads the API key from secure storage, falling back to the legacy
  /// SharedPreferences value.
  static Future<String?> readApiKey() async {
    try {
      final secure = await _storage.read(key: _secureKey);
      if (secure != null && secure.isNotEmpty) {
        return secure;
      }
    } catch (e) {
      debugPrint('Failed to read API key from secure storage: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey);
    } catch (_) {
      return null;
    }
  }
}
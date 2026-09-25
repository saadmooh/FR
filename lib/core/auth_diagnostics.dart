import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';
import 'ui_messenger.dart';

const _logKey = 'auth_diag_log';
const _errKey = 'auth_diag_last_remote_error';
const _maxEntries = 100;

Future<void> authDiag(
  String event, {
  Map<String, dynamic>? details,
  String isolate = 'main',
  bool remote = true,
}) async {
  final timestamp = DateTime.now().toIso8601String();
  final remoteDetails = <String, dynamic>{
    ...?details,
    'isolate': isolate,
    'appVersion': 'unknown',
    'ts': timestamp,
  };

  showUiLog('🔥 [AUTH-DIAG] $event | $remoteDetails');
  showUiLog(
    '🔥 [AUTH-DIAG] $event | uid=${details?['uid'] ?? details?['currentUser']}',
  );

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_logKey) ?? [];
    existing.add(jsonEncode({'event': event, 'details': remoteDetails}));
    while (existing.length > _maxEntries) {
      existing.removeAt(0);
    }
    await prefs.setStringList(_logKey, existing);
  } catch (e) {
    showUiLog('[AUTH-DIAG] local write failed: $e');
  }

  if (!remote || !AppConfig.isSupabaseConfigured) return;

  try {
    SupabaseClient client;
    try {
      client = Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      client = Supabase.instance.client;
    }
    // فقط الأعمدة المعروفة: event و details
    await client.from('debug_logs').insert([
      {'event': 'auth_$event', 'details': remoteDetails},
    ]);
  } catch (e) {
    showUiLog('[AUTH-DIAG] remote failed: $e');
    try {
      await prefs?.setString(_errKey, '$event: $e');
    } catch (_) {}
  }
}

Future<List<String>> authDiagLoadLogs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_logKey) ?? [];
  } catch (_) {
    return [];
  }
}

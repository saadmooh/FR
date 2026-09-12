import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';

class ProxyConfigService {
  static ProxyConfigService? _instance;
  static ProxyConfigService get instance => _instance ??= ProxyConfigService._();
  ProxyConfigService._();

  // Cache per importance level
  final Map<String, int> _cachedLimits = {};
  final Map<String, DateTime> _lastFetchTimes = {};
  static const Duration _cacheDuration = Duration(hours: 1);

  static const Map<String, int> _defaultLimits = {
    'Day': 5,
    'Week': 10,
    'Month': 20,
  };
  static const String _configTable = 'proxy_config';
  static const Map<String, String> _limitKeys = {
    'Day': 'monthly_reschedule_limit_day',
    'Week': 'monthly_reschedule_limit_week',
    'Month': 'monthly_reschedule_limit_month',
  };

  /// Fetches the monthly reschedule limit for a specific importance level.
  /// Returns cached value if available and not expired, otherwise fetches from Supabase.
  /// Falls back to defaults (Day: 5, Week: 10, Month: 20) if fetch fails.
  Future<int> getMonthlyRescheduleLimit(String importance) async {
    final key = _limitKeys[importance] ?? _limitKeys['Week']!;
    final defaultLimit = _defaultLimits[importance] ?? _defaultLimits['Week']!;

    // Return cached value if still valid
    if (_cachedLimits[key] != null &&
        _lastFetchTimes[key] != null &&
        DateTime.now().difference(_lastFetchTimes[key]!) < _cacheDuration) {
      return _cachedLimits[key]!;
    }

    // Not configured - return default
    if (!AppConfig.isSupabaseConfigured) {
      debugPrint('[ProxyConfigService] Supabase not configured, using default limit for $importance');
      return defaultLimit;
    }

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from(_configTable)
          .select('value')
          .eq('key', key)
          .maybeSingle();

      if (response != null && response['value'] != null) {
        final limit = (response['value'] as num).toInt();
        if (limit > 0) {
          _cachedLimits[key] = limit;
          _lastFetchTimes[key] = DateTime.now();
          debugPrint('[ProxyConfigService] Fetched reschedule limit for $importance: $limit');
          return limit;
        }
      }

      debugPrint('[ProxyConfigService] Config not found for $importance, using default');
      return defaultLimit;
    } catch (e) {
      debugPrint('[ProxyConfigService] Failed to fetch config for $importance: $e, using default');
      return defaultLimit;
    }
  }

  /// Clears the cache to force a fresh fetch on next call.
  void clearCache() {
    _cachedLimits.clear();
    _lastFetchTimes.clear();
  }

  /// Pre-fetches all configs (call during app init).
  Future<void> prefetch() async {
    for (final importance in _defaultLimits.keys) {
      await getMonthlyRescheduleLimit(importance);
    }
  }
}
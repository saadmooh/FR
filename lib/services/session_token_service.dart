import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import 'integrity_service.dart';

class SessionTokenException implements Exception {
  final int status;
  final String code;
  final String message;

  const SessionTokenException(this.status, this.code, this.message);

  @override
  String toString() => 'SessionTokenException($code): $message';
}

/// Obtains and caches the short-lived Pro session JWT issued by the
/// session-token edge function. Stored in flutter_secure_storage together
/// with its expiry; renewed silently when close to expiry or forced after a
/// 403 from ai-proxy.
class SessionTokenService {
  SessionTokenService._();

  static final SessionTokenService instance = SessionTokenService._();

  static const String _tokenKey = 'pro_session_jwt';
  static const String _expiryKey = 'pro_session_jwt_exp_ms';
  static const Duration _renewWindow = Duration(minutes: 10);

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late final IntegrityService _integrity = IntegrityService(
    cloudProjectNumber: AppConfig.cloudProjectNumber ?? 0,
    enabled: AppConfig.cloudProjectNumber != null,
  );

  String? _cachedToken;
  DateTime? _expiresAt;
  Future<String?>? _inFlight;

  bool get isConfigured =>
      _integrity.enabled && AppConfig.isSupabaseConfigured;

  /// Returns a still-valid token, transparently requesting a new one when
  /// missing, expired or inside the renewal window. Returns null when Play
  /// Integrity is unavailable (debug builds) — the caller proceeds without
  /// the header and the server decides.
  Future<String?> getValidToken({bool forceRefresh = false}) async {
    if (!isConfigured) return null;

    if (_cachedToken == null || _expiresAt == null) {
      await _loadFromStorage();
    }

    final usable = !forceRefresh &&
        _cachedToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!.subtract(_renewWindow));
    if (usable) return _cachedToken;

    if (_inFlight != null) return _inFlight;
    final completer = Completer<String?>();
    _inFlight = completer.future;
    try {
      final token = await _requestNewToken();
      completer.complete(token);
      return token;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inFlight = null;
    }
  }

  /// Called right after a successful purchase/restore. The RevenueCat webhook
  /// may lag a few seconds behind, so subscription-not-active responses are
  /// retried with backoff before giving up.
  Future<void> refresh() async {
    if (!isConfigured) return;
    await getValidToken(forceRefresh: true);
  }

  /// Clears the cached/stored token (logout, account switch).
  Future<void> clear() async {
    _cachedToken = null;
    _expiresAt = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _expiryKey);
    } catch (e) {
      debugPrint('SessionToken: failed to clear storage: $e');
    }
  }

  Future<String?> _requestNewToken() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const SessionTokenException(401, 'UNAUTHENTICATED', 'يجب تسجيل الدخول أولاً');
    }

    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw const SessionTokenException(
        401,
        'FIREBASE_TOKEN_UNAVAILABLE',
        'تعذر الحصول على رمز الهوية',
      );
    }

    Object? lastError;
    for (int attempt = 1; attempt <= 3; attempt++) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nonce = _integrity.generateNonce(
        prompt: 'session-token',
        userId: user.uid,
        timestamp: timestamp,
      );
      final integrityToken = await _integrity.requestIntegrityToken(nonce: nonce);

      try {
        final response = await Supabase.instance.client.functions.invoke(
          'session-token',
          headers: {'Authorization': 'Bearer $idToken'},
          body: <String, dynamic>{
            'integrityToken': integrityToken,
            'nonce': nonce,
          },
        );
        final data = response.data;
        final token = data is Map<String, dynamic> ? data['token'] as String? : null;
        if (token == null || token.isEmpty) {
          throw const SessionTokenException(
            -1,
            'BAD_RESPONSE',
            'استجابة غير صالحة من الخادم',
          );
        }
        await _store(token);
        debugPrint('SessionToken: renewed, expires at $_expiresAt');
        return token;
      } on FunctionException catch (e) {
        lastError = _mapFunctionException(e);
        final mapped = lastError as SessionTokenException;
        final webhookLag = mapped.status == 403 &&
            mapped.code == 'SUBSCRIPTION_NOT_ACTIVE';
        if (!webhookLag || attempt == 3) throw mapped;
        debugPrint('SessionToken: webhook lag (attempt $attempt), retrying...');
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
    throw lastError ?? const SessionTokenException(-1, 'UNKNOWN', 'حدث خطأ غير متوقع');
  }

  Future<void> _store(String token) async {
    _cachedToken = token;
    _expiresAt = _extractExpiry(token);
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(
        key: _expiryKey,
        value: _expiresAt?.millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      debugPrint('SessionToken: failed to persist token: $e');
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final expMs = int.tryParse(await _storage.read(key: _expiryKey) ?? '');
      if (token != null && token.isNotEmpty && expMs != null) {
        _cachedToken = token;
        _expiresAt = DateTime.fromMillisecondsSinceEpoch(expMs);
      }
    } catch (e) {
      debugPrint('SessionToken: failed to read stored token: $e');
    }
  }

  DateTime? _extractExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      }
    } catch (e) {
      debugPrint('SessionToken: failed to parse expiry: $e');
    }
    return null;
  }

  SessionTokenException _mapFunctionException(FunctionException e) {
    var code = 'SESSION_SERVER_ERROR';
    var message = 'حدث خطأ أثناء التحقق من الاشتراك';

    dynamic details = e.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } catch (_) {}
    }
    if (details is Map<String, dynamic>) {
      final error = details['error'];
      if (error is Map<String, dynamic>) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
      }
    }
    return SessionTokenException(e.status, code, message);
  }
}

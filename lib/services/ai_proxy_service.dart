import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../core/app_config.dart';
import '../models/ai_proxy_response.dart';
import '../models/integrity_diagnostic.dart';
import 'integrity_service.dart';

class AiProxyService {
  final IntegrityService _integrity;
  final bool strictIntegrityCheck;
  final bool _isSupabaseAvailable;
  IntegrityDiagnostic? _lastIntegrityDiagnostic;

  AiProxyService({
    IntegrityService? integrity,
    this.strictIntegrityCheck = true,
    bool? isSupabaseAvailable,
  }) : _integrity = integrity ?? IntegrityService(),
       _isSupabaseAvailable =
           isSupabaseAvailable ?? AppConfig.isSupabaseConfigured;

  IntegrityDiagnostic? get lastIntegrityDiagnostic => _lastIntegrityDiagnostic;

  factory AiProxyService.fromConfig({bool? strictIntegrityCheck}) {
    final cloudProjectNumber = AppConfig.cloudProjectNumber;
    return AiProxyService(
      integrity: IntegrityService(
        cloudProjectNumber: cloudProjectNumber ?? 0,
        enabled: cloudProjectNumber != null,
      ),
      strictIntegrityCheck:
          strictIntegrityCheck ?? AppConfig.strictIntegrityCheck,
      isSupabaseAvailable: AppConfig.isSupabaseConfigured,
    );
  }

  Future<AiProxyResponse> sendPrompt({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
  }) async {
    if (!_isSupabaseAvailable) {
      throw const AiProxyException(
        503,
        'SUPABASE_NOT_CONFIGURED',
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.',
      );
    }

    final client = Supabase.instance.client;
    var session = client.auth.currentSession;

    // If Supabase session is missing/expired, try to refresh from Firebase user
    if (session == null) {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        try {
          final idToken = await firebaseUser.getIdToken();
          if (idToken != null) {
            await client.auth.signInWithIdToken(
              provider: OAuthProvider('custom:firebase'),
              idToken: idToken,
            );
            session = client.auth.currentSession;
            debugPrint('Supabase session refreshed from Firebase user');
          }
        } catch (e) {
          debugPrint('Failed to refresh Supabase session: $e');
        }
      }
    }

    if (session == null) {
      throw const AiProxyException(
        401,
        'UNAUTHENTICATED',
        'يجب تسجيل الدخول أولاً',
      );
    }

    final userId = session.user.id;

    // NOTE: timestamp, nonce and the Play Integrity token are generated PER
    // attempt. The request is sent with a single-use nonce (claimed in the
    // `used_nonces` table server-side), so a network-error retry must use a
    // FRESH nonce — reusing the same one would be rejected as NONCE_REPLAY
    // even on a legitimate retry.
    for (int attempt = 0; attempt < 2; attempt++) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nonce = _integrity.generateNonce(
        prompt: prompt,
        userId: userId,
        timestamp: timestamp,
      );
      String? integrityToken;
      bool integrityFailed = false;
      try {
        integrityToken = await _integrity.requestIntegrityToken(nonce: nonce);
      } on IntegrityException catch (e) {
        debugPrint('Integrity token unavailable: $e');
        integrityFailed = true;
        _lastIntegrityDiagnostic = e.diagnostic;
        if (strictIntegrityCheck) {
          throw AiProxyException(
            403,
            e.code,
            'فشل التحقق من التطبيق (${e.code}): ${e.message}',
            diagnostic: e.diagnostic,
          );
        }
      }

      final body = <String, dynamic>{
        'prompt': prompt,
        'timestamp': timestamp,
        if (conversationHistory != null && conversationHistory.isNotEmpty)
          'conversationHistory': conversationHistory,
      };
      final headers = <String, String>{};
      if (integrityToken != null && !integrityFailed) {
        headers['X-Integrity-Token'] = integrityToken;
        headers['X-Request-Nonce'] = nonce;
      }
      // Send debug build header to allow server-side bypass when strict check is off
      if (!strictIntegrityCheck) {
        headers['X-Debug-Build'] = 'true';
      }
      // Add debug header for diagnostics
      headers['X-Debug-Integrity'] = 'true';

      try {
        final response = await client.functions.invoke(
          'ai-proxy',
          headers: headers,
          body: body,
        );
        final data = response.data;
        if (data is Map<String, dynamic>) {
          // Check if response contains diagnostic info
          if (data['diagnostic'] is Map<String, dynamic>) {
            _lastIntegrityDiagnostic = IntegrityDiagnostic.fromJson(
              data['diagnostic'],
            );
          }
          return AiProxyResponse.fromJson(data);
        }
        throw const AiProxyException(
          -1,
          'BAD_RESPONSE',
          'استجابة غير صالحة من الخادم',
        );
      } on FunctionException catch (e) {
        throw _mapHttpException(e);
      } on SocketException {
        if (attempt == 0) continue;
        throw const AiProxyException(
          -1,
          'NETWORK_ERROR',
          'تعذر الاتصال بالخادم، تحقق من اتصالك بالإنترنت',
          isRetryable: true,
        );
      } on http.ClientException {
        if (attempt == 0) continue;
        throw const AiProxyException(
          -1,
          'NETWORK_ERROR',
          'تعذر الاتصال بالخادم، تحقق من اتصالك بالإنترنت',
          isRetryable: true,
        );
      } on TimeoutException {
        if (attempt == 0) continue;
        throw const AiProxyException(
          -1,
          'TIMEOUT',
          'انتهت مهلة الطلب، حاول مرة أخرى',
          isRetryable: true,
        );
      }
    }
    throw const AiProxyException(-1, 'UNKNOWN', 'حدث خطأ غير متوقع');
  }

  AiProxyException _mapHttpException(FunctionException e) {
    var code = 'UPSTREAM_ERROR';
    var message = 'حدث خطأ، حاول مرة أخرى';

    dynamic details = e.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } catch (_) {}
    }
    IntegrityDiagnostic? diagnostic;
    if (details is Map<String, dynamic>) {
      final error = details['error'];
      if (error is Map<String, dynamic>) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
        // Extract diagnostic from error.diagnostic (backend puts it there)
        dynamic diagnosticData = error['diagnostic'];
        // Fallback to details.diagnostic if not in error
        diagnosticData ??= details['diagnostic'];
        if (diagnosticData is Map<String, dynamic>) {
          try {
            diagnostic = IntegrityDiagnostic.fromJson(diagnosticData);
          } catch (e) {
            debugPrint(
              'INTEGRITY_TRACE_BACKEND_RESPONSE: Failed to parse IntegrityDiagnostic: $e',
            );
          }
        }
      } else {
        // No error object, check details directly
        if (details['diagnostic'] is Map<String, dynamic>) {
          try {
            diagnostic = IntegrityDiagnostic.fromJson(details['diagnostic']);
          } catch (e) {
            debugPrint(
              'INTEGRITY_TRACE_BACKEND_RESPONSE: Failed to parse IntegrityDiagnostic: $e',
            );
          }
        }
      }
    }

    debugPrint(
      'INTEGRITY_TRACE_BACKEND_RESPONSE: code=$code, diagnosticPresent=${diagnostic != null}',
    );

    switch (code) {
      case 'UNAUTHENTICATED':
        return const AiProxyException(
          401,
          'UNAUTHENTICATED',
          'يجب تسجيل الدخول أولاً',
        );
      case 'INTEGRITY_MISSING':
        if (!strictIntegrityCheck) {
          return AiProxyException(
            e.status,
            code,
            'Integrity not available in debug build',
          );
        }
        return AiProxyException(
          403,
          code,
          'فشل التحقق من التطبيق ($code): $message',
          diagnostic: diagnostic,
        );
      case 'INTEGRITY_FAILED':
        return AiProxyException(
          403,
          code,
          'فشل التحقق من التطبيق ($code): $message',
          diagnostic: diagnostic,
        );
      case 'RATE_LIMIT_MINUTE':
        return const AiProxyException(
          429,
          'RATE_LIMIT_MINUTE',
          'وصلت إلى الحد الأقصى، حاول بعد دقيقة',
        );
      case 'RATE_LIMIT_MONTH':
        return const AiProxyException(
          429,
          'RATE_LIMIT_MONTH',
          'وصلت إلى الحد الشهري، حاول الشهر القادم',
        );
      default:
        return AiProxyException(
          e.status,
          code,
          message,
          diagnostic: diagnostic,
        );
    }
  }
}

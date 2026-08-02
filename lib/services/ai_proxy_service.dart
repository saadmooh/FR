import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../models/ai_proxy_response.dart';
import 'integrity_service.dart';

class AiProxyService {
  final IntegrityService _integrity;
  final bool strictIntegrityCheck;
  final bool _isSupabaseAvailable;

  AiProxyService({
    IntegrityService? integrity,
    this.strictIntegrityCheck = true,
    bool? isSupabaseAvailable,
  })  : _integrity = integrity ?? IntegrityService(),
        _isSupabaseAvailable = isSupabaseAvailable ?? AppConfig.isSupabaseConfigured;

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
    final session = client.auth.currentSession;
    if (session == null) {
      throw const AiProxyException(
        401,
        'UNAUTHENTICATED',
        'يجب تسجيل الدخول أولاً',
      );
    }

    final nonce = _integrity.generateNonce(prompt);
    String? integrityToken;
    try {
      integrityToken = await _integrity.requestIntegrityToken(nonce: nonce);
    } on IntegrityException catch (e) {
      debugPrint('Integrity token unavailable: $e');
      if (strictIntegrityCheck) {
        throw AiProxyException(
          403,
          e.code,
          'فشل التحقق من التطبيق، تأكد من تثبيته من متجر Play',
        );
      }
    }

    final body = <String, dynamic>{
      'prompt': prompt,
      if (conversationHistory != null && conversationHistory.isNotEmpty)
        'conversationHistory': conversationHistory,
    };
    final headers = <String, String>{
      if (integrityToken != null) 'X-Integrity-Token': integrityToken,
      if (integrityToken != null) 'X-Request-Nonce': nonce,
    };

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await client.functions.invoke(
          'ai-proxy',
          headers: headers,
          body: body,
        );
        final data = response.data;
        if (data is Map<String, dynamic>) {
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
    if (details is Map<String, dynamic>) {
      final error = details['error'];
      if (error is Map<String, dynamic>) {
        code = error['code'] as String? ?? code;
        message = error['message'] as String? ?? message;
      }
    }

    switch (code) {
      case 'UNAUTHENTICATED':
        return const AiProxyException(
          401,
          'UNAUTHENTICATED',
          'يجب تسجيل الدخول أولاً',
        );
      case 'INTEGRITY_MISSING':
      case 'INTEGRITY_FAILED':
        return AiProxyException(
          403,
          code,
          'فشل التحقق من التطبيق، قم بتحديث التطبيق من متجر Play',
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
        return AiProxyException(e.status, code, message);
    }
  }
}

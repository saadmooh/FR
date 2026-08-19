import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_play_integrity_wrapper/flutter_play_integrity_wrapper.dart';

import '../models/integrity_diagnostic.dart';

class IntegrityException implements Exception {
  final String code;
  final String message;
  final IntegrityDiagnostic? diagnostic;

  const IntegrityException(this.code, this.message, {this.diagnostic});

  @override
  String toString() => 'IntegrityException($code): $message';
}

class IntegrityService {
  final FlutterPlayIntegrityWrapper _wrapper;
  final int cloudProjectNumber;
  final bool enabled;

  IntegrityService({this.cloudProjectNumber = 0, this.enabled = true})
    : _wrapper = FlutterPlayIntegrityWrapper();

  String generateNonce({
    required String prompt,
    required String userId,
    required int timestamp,
  }) {
    final input = utf8.encode('$prompt|$userId|$timestamp');
    final hash = sha256.convert(input);
    // Play Integrity's setNonce() decoder is URL-safe Base64 (alphabet
    // A-Za-z0-9-_), NOT standard (which uses + /). Standard Base64 with + or /
    // gets silently mis-decoded by Play Services, so the nonce echoed back in
    // the token never matches the header. Use base64url (URL-safe, no padding).
    // A 30-byte (multiple of 3) payload yields a clean 40-char string with no
    // padding and no ambiguity.
    final bytes = hash.bytes.length >= 30 ? hash.bytes.sublist(0, 30) : hash.bytes;
    return base64UrlEncode(bytes);
  }

  Future<String> requestIntegrityToken({required String nonce}) async {
    final diagnostic = IntegrityDiagnostic(
      stage: 'request_start',
      cloudProjectNumber: cloudProjectNumber,
      nonceLength: nonce.length,
    );
    _logDiagnostic(diagnostic);

    if (!enabled || cloudProjectNumber <= 0) {
      final disabledDiag = IntegrityDiagnostic(
        stage: 'token_request_failed',
        code: 'INTEGRITY_DISABLED',
        message: 'Play Integrity is not configured for this build',
        cloudProjectNumber: cloudProjectNumber,
      );
      _logDiagnostic(disabledDiag);
      throw IntegrityException(
        'INTEGRITY_DISABLED',
        'Play Integrity is not configured for this build',
        diagnostic: disabledDiag,
      );
    }
    try {
      final requestDiag = IntegrityDiagnostic(
        stage: 'token_request',
        nonceLength: nonce.length,
      );
      _logDiagnostic(requestDiag);

      final token = await _wrapper.requestIntegrityToken(
        cloudProjectNumber: cloudProjectNumber.toString(),
        nonce: nonce,
      );
      if (token == null || token.isEmpty) {
        final emptyDiag = IntegrityDiagnostic(
          stage: 'token_request_failed',
          code: 'EMPTY_TOKEN',
          message: 'Empty integrity token',
          tokenReceived: false,
        );
        _logDiagnostic(emptyDiag);
        throw IntegrityException(
          'EMPTY_TOKEN',
          'Empty integrity token',
          diagnostic: emptyDiag,
        );
      }
      final successDiag = IntegrityDiagnostic(
        stage: 'token_received',
        tokenReceived: true,
        tokenLength: token.length,
      );
      _logDiagnostic(successDiag);
      return token;
    } on PlayIntegrityException catch (e) {
      final failedDiag = IntegrityDiagnostic(
        stage: 'token_request_failed',
        code: e.code,
        message: e.message,
        details: e.details,
      );
      _logDiagnostic(failedDiag);
      throw IntegrityException(e.code, e.message, diagnostic: failedDiag);
    } catch (e) {
      final errorDiag = IntegrityDiagnostic(
        stage: 'unexpected_error',
        code: 'UNKNOWN',
        message: e.toString(),
        errorType: e.runtimeType.toString(),
      );
      _logDiagnostic(errorDiag);
      throw IntegrityException('UNKNOWN', e.toString(), diagnostic: errorDiag);
    }
  }

  void _logDiagnostic(IntegrityDiagnostic diagnostic) {
    debugPrint('INTEGRITY_DIAGNOSTIC: ${diagnostic.toJson()}');
  }
}

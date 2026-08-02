import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class IntegrityException implements Exception {
  final String code;
  final String message;

  const IntegrityException(this.code, this.message);

  @override
  String toString() => 'IntegrityException($code): $message';
}

class IntegrityService {
  static const MethodChannel _channel =
      MethodChannel('com.saadmohammed2000.flex_reminder/play_integrity');

  final int cloudProjectNumber;
  final bool enabled;

  IntegrityService({this.cloudProjectNumber = 0, this.enabled = true});

  /// Generates a per-request nonce: base64(SHA-256(prompt || 16 random bytes)).
  String generateNonce(String prompt) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = sha256.convert([...utf8.encode(prompt), ...salt]);
    return base64Encode(hash.bytes);
  }

  Future<String> requestIntegrityToken({required String nonce}) async {
    if (!enabled || cloudProjectNumber <= 0) {
      throw const IntegrityException(
        'INTEGRITY_DISABLED',
        'Play Integrity is not configured for this build',
      );
    }
    try {
      final token = await _channel.invokeMethod<String>('requestIntegrityToken', {
        'nonce': nonce,
        'cloudProjectNumber': cloudProjectNumber,
      });
      if (token == null || token.isEmpty) {
        throw const IntegrityException('EMPTY_TOKEN', 'Empty integrity token');
      }
      return token;
    } on PlatformException catch (e) {
      throw IntegrityException(
        e.code,
        e.message ?? 'Play Integrity request failed',
      );
    } on MissingPluginException {
      throw const IntegrityException(
        'PLUGIN_MISSING',
        'Play Integrity is not available on this platform',
      );
    }
  }
}

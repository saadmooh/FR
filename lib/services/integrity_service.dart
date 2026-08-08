import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

  /// Generates a per-request nonce: base64url(SHA-256(prompt || 16 random bytes)).
  String generateNonce(String prompt) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = sha256.convert([...utf8.encode(prompt), ...salt]);
    return base64UrlEncode(hash.bytes);
  }

  Future<String> requestIntegrityToken({required String nonce}) async {
    debugPrint('IntegrityService: enabled=$enabled, cloudProjectNumber=$cloudProjectNumber');
    if (!enabled || cloudProjectNumber <= 0) {
      debugPrint('IntegrityService: INTEGRITY_DISABLED - not configured');
      throw const IntegrityException(
        'INTEGRITY_DISABLED',
        'Play Integrity is not configured for this build',
      );
    }
    try {
      debugPrint('IntegrityService: requesting token with nonce length=${nonce.length}');
      final token = await _channel.invokeMethod<String>('requestIntegrityToken', {
        'nonce': nonce,
        'cloudProjectNumber': cloudProjectNumber,
      });
      if (token == null || token.isEmpty) {
        debugPrint('IntegrityService: EMPTY_TOKEN');
        throw const IntegrityException('EMPTY_TOKEN', 'Empty integrity token');
      }
      debugPrint('IntegrityService: token received, length=${token.length}');
      return token;
    } on PlatformException catch (e) {
      debugPrint('IntegrityService: PlatformException code=${e.code}, message=${e.message}, details=${e.details}');
      throw IntegrityException(
        e.code,
        '${e.message ?? "Play Integrity request failed"} (details: ${e.details})',
      );
    } on MissingPluginException {
      debugPrint('IntegrityService: PLUGIN_MISSING');
      throw const IntegrityException(
        'PLUGIN_MISSING',
        'Play Integrity is not available on this platform',
      );
    }
  }
}

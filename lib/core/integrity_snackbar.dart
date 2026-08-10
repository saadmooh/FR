import 'package:flutter/material.dart';

class IntegritySnackBar {
  static GlobalKey<ScaffoldMessengerState>? _messengerKey;

  static void setMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _messengerKey = key;
  }

  static ScaffoldMessengerState? get _messenger {
    return _messengerKey?.currentState;
  }

  static void show({
    required String title,
    required String stage,
    required String source,
    required String code,
    required String message,
    String? details,
    required String tokenStatus,
    required String backendStatus,
    int? httpStatus,
    String? tokenLength,
    int durationSeconds = 15,
  }) {
    final messenger = _messenger;
    if (messenger == null) {
      debugPrint('IntegritySnackBar: No messenger key set');
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln(title);
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');
    buffer.writeln('Stage: $stage');
    buffer.writeln('Source: $source');
    buffer.writeln('Code: $code');
    buffer.writeln('Message: $message');
    if (details != null && details.isNotEmpty) {
      buffer.writeln('Details: $details');
    }
    buffer.writeln('');
    buffer.writeln('Token: $tokenStatus');
    if (tokenLength != null) {
      buffer.writeln('Token Length: $tokenLength');
    }
    buffer.writeln('Backend: $backendStatus');
    if (httpStatus != null) {
      buffer.writeln('HTTP: $httpStatus');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    final isSuccess = source == 'SUCCESS';
    final backgroundColor = isSuccess ? Colors.green : Colors.red;

    messenger.showSnackBar(
      SnackBar(
        content: SingleChildScrollView(
          child: SelectableText(
            buffer.toString(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        duration: Duration(seconds: durationSeconds),
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  static void showClientError({
    required String code,
    required String message,
    String? details,
    int? tokenLength,
  }) {
    show(
      title: '🔴 PLAY INTEGRITY',
      stage: 'TOKEN_REQUEST_FAILED',
      source: 'CLIENT',
      code: code,
      message: message,
      details: details,
      tokenStatus: 'NOT RECEIVED',
      backendStatus: 'NOT SENT',
      tokenLength: tokenLength?.toString(),
    );
  }

  static void showBackendError({
    required int httpStatus,
    required String code,
    required String message,
    String? tokenLength,
    String? details,
  }) {
    show(
      title: '🔴 PLAY INTEGRITY',
      stage: 'BACKEND_RESPONSE',
      source: 'BACKEND',
      code: code,
      message: message,
      details: details,
      tokenStatus: 'RECEIVED',
      backendStatus: 'SENT',
      httpStatus: httpStatus,
      tokenLength: tokenLength,
    );
  }

  static void showBackendConnectionError({
    required String error,
    String? tokenLength,
  }) {
    show(
      title: '🔴 PLAY INTEGRITY',
      stage: 'BACKEND_REQUEST_FAILED',
      source: 'BACKEND_CONNECTION',
      code: 'NETWORK_ERROR',
      message: 'Failed to reach backend',
      details: error,
      tokenStatus: 'RECEIVED',
      backendStatus: 'REQUEST FAILED',
      tokenLength: tokenLength,
    );
  }

  static void showSuccess({
    String? tokenLength,
    int httpStatus = 200,
  }) {
    show(
      title: '🟢 PLAY INTEGRITY',
      stage: 'SUCCESS',
      source: 'SUCCESS',
      code: 'OK',
      message: 'Integrity check passed',
      tokenStatus: 'RECEIVED',
      backendStatus: 'SENT',
      httpStatus: httpStatus,
      tokenLength: tokenLength,
    );
  }
}
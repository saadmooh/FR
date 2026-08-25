import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const bool uiLogsEnabled = true;

final List<String> _pending = [];

void showUiLog(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  debugPrint('[UI-LOG] $message');
  if (!uiLogsEnabled) return;
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) {
    _pending.add(message);
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 12)),
      duration: duration,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Shows messages that arrived before MaterialApp was mounted (e.g. during
/// startup initialization). Call once after the first frame.
void flushPendingUiLogs() {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null || _pending.isEmpty) return;
  final queued = List<String>.from(_pending);
  _pending.clear();
  for (final message in queued) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

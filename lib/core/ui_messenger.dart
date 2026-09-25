import 'package:flutter/material.dart';

import 'app_theme.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const bool uiLogsEnabled = true;

/// Global snackbar switch. While false, no snackbar is shown anywhere in the
/// app (direct calls go through [showAppSnackBar], shared helpers are gated
/// here as well).
const bool snackBarsEnabled = false;

/// Shows [snackbar] on the nearest scaffold messenger.
///
/// No-op while [snackBarsEnabled] is false — the single choke point that
/// lets the whole app's snackbar feedback be switched off in one place.
void showAppSnackBar(BuildContext context, SnackBar snackbar) {
  if (!snackBarsEnabled) return;
  ScaffoldMessenger.of(context).showSnackBar(snackbar);
}

final List<String> _pending = [];

void showUiLog(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  debugPrint('[UI-LOG] $message');
  if (!uiLogsEnabled || !snackBarsEnabled) return;
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

/// Shows concise, user-facing authentication feedback.
///
/// Internal diagnostics continue to use [showUiLog] and are not shown as
/// snackbars, so enabling auth feedback does not flood the UI with debug logs.
void showAuthSnackBar(
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
  debugPrint('[AUTH-SNACKBAR] $message');
  if (!snackBarsEnabled) return;
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        duration: duration,
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
}

/// Shows messages that arrived before MaterialApp was mounted (e.g. during
/// startup initialization). Call once after the first frame.
void flushPendingUiLogs() {
  if (!snackBarsEnabled) {
    _pending.clear();
    return;
  }
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

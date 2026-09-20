import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../core/init_error.dart';
import '../core/auth_diagnostics.dart';
import 'auth_diagnostics_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  Future<void> _handleLongPress(BuildContext context) async {
    final entries = await authDiagLoadLogs();
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AuthDiagnosticsScreen(entries: entries),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = initError;
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: () => _handleLongPress(context),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Bookmark Reminder',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.whiteTextPrimary,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              if (error != null) ...[
                const SizedBox(height: 24),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

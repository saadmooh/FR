import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../core/app_theme.dart';
import '../core/translations.dart';
import '../core/locale_manager.dart';
import '../core/ui_messenger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  String get _locale => LocaleManager.instance.getLocale();

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService().signInWithGoogle();
      if (!mounted) return;

      if (user != null) {
        showAuthSnackBar(Translations.signInSuccess(_locale));
        context.go('/reminders');
      } else {
        showAuthSnackBar(Translations.signInFailed(_locale), isError: true);
      }
    } catch (_) {
      if (mounted) {
        showAuthSnackBar(Translations.signInFailed(_locale), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                Translations.signInTitle(_locale),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.whiteTextPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                Translations.signInSubtitle(_locale),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.whiteTextSecondary,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata, size: 28),
                  label: Text(Translations.signInWithGoogle(_locale)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.whiteTextPrimary,
                    side: const BorderSide(color: AppColors.whiteBorder),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                Translations.signInTerms(_locale),
                style: TextStyle(
                  color: AppColors.whiteTextSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

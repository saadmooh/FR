import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/revenuecat_service.dart';
import '../core/app_theme.dart';
import '../core/translations.dart';
import '../core/locale_manager.dart';
import 'paywall_screen.dart';

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
    final user = await AuthService().signInWithGoogle();
    setState(() => _isLoading = false);
    if (user != null && mounted) {
      if (!RevenueCatService().isPremium) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Translations.signInFailed(_locale)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
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
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(25),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(
                  Icons.bookmark_outline,
                  size: 40,
                  color: AppColors.accent,
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

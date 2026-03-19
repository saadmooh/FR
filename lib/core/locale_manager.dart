import 'package:flutter/material.dart';
import '../repositories/app_settings_repository.dart';

class LocaleManager {
  static LocaleManager? _instance;
  static LocaleManager get instance => _instance ??= LocaleManager._();

  LocaleManager._();

  late AppSettingsRepository _settingsRepository;
  String _currentLocale = 'en';

  final ValueNotifier<String> localeNotifier = ValueNotifier<String>('en');

  String get currentLocale => _currentLocale;

  Locale get currentAppLocale {
    switch (_currentLocale) {
      case 'ar':
        return const Locale('ar');
      case 'fr':
        return const Locale('fr');
      default:
        return const Locale('en');
    }
  }

  TextDirection get textDirection {
    return _currentLocale == 'ar' ? TextDirection.rtl : TextDirection.ltr;
  }

  bool get isRtl => _currentLocale == 'ar';

  void initialize(AppSettingsRepository settingsRepository) {
    try {
      _settingsRepository = settingsRepository;
      final savedLocale = settingsRepository.getLocale();
      _currentLocale = savedLocale ?? 'en';
      localeNotifier.value = _currentLocale;
    } catch (e) {
      _currentLocale = 'en';
      localeNotifier.value = 'en';
    }
  }

  Future<void> setLocale(String localeCode) async {
    if (_currentLocale == localeCode) return;

    _currentLocale = localeCode;
    localeNotifier.value = localeCode;

    try {
      await _settingsRepository.setLocale(localeCode);
    } catch (e) {
      // Continue even if save fails
    }
  }

  String getLocale() {
    return _currentLocale;
  }

  String getCategory(String? en, String? ar, String? fr) {
    switch (_currentLocale) {
      case 'ar':
        return ar ?? en ?? 'أخرى';
      case 'fr':
        return fr ?? en ?? 'Autre';
      default:
        return en ?? 'Other';
    }
  }

  String getComplexity(String? en, String? ar, String? fr) {
    switch (_currentLocale) {
      case 'ar':
        return ar ?? en ?? 'متوسط';
      case 'fr':
        return fr ?? en ?? 'Moyen';
      default:
        return en ?? 'Medium';
    }
  }

  String getImportance(String importance) {
    switch (_currentLocale) {
      case 'ar':
        return importance == 'Day'
            ? 'اليوم'
            : importance == 'Week'
            ? 'هذا الأسبوع'
            : 'هذا الشهر';
      case 'fr':
        return importance == 'Day'
            ? "Aujourd'hui"
            : importance == 'Week'
            ? 'Cette semaine'
            : 'Ce mois';
      default:
        return importance;
    }
  }

  String getExplanation(String? en, String? ar, String? fr) {
    switch (_currentLocale) {
      case 'ar':
        return ar ?? en ?? '';
      case 'fr':
        return fr ?? en ?? '';
      default:
        return en ?? '';
    }
  }

  static List<Locale> get supportedLocales => const [
    Locale('en'),
    Locale('ar'),
    Locale('fr'),
  ];

  static String getLanguageName(String localeCode) {
    switch (localeCode) {
      case 'ar':
        return 'العربية';
      case 'fr':
        return 'Français';
      default:
        return 'English';
    }
  }

  static SupportedLanguage getLanguage(String localeCode) {
    switch (localeCode) {
      case 'ar':
        return SupportedLanguage.arabic;
      case 'fr':
        return SupportedLanguage.french;
      default:
        return SupportedLanguage.english;
    }
  }
}

enum SupportedLanguage {
  english('en'),
  arabic('ar'),
  french('fr');

  final String code;

  const SupportedLanguage(this.code);
}

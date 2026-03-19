import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0E1A);
  static const surface = Color(0xFF131929);
  static const surfaceLight = Color(0xFF1C2438);
  static const accent = Color(0xFF00D4C8);
  static const accentDim = Color(0x2900D4C8);
  static const textPrimary = Color(0xFFEEF2FF);
  static const textSecondary = Color(0xFF8892AA);
  static const success = Color(0xFF4CAF82);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const read = Color(0xFF2A3545);

  static const whiteBackground = Color(0xFFFFFFFF);
  static const whiteSurface = Color(0xFFF8FAFC);
  static const whiteCard = Color(0xFFFFFFFF);
  static const whiteTextPrimary = Color(0xFF1E293B);
  static const whiteTextSecondary = Color(0xFF64748B);
  static const whiteBorder = Color(0xFFE2E8F0);
  static const whiteAccent = Color(0xFF00D4C8);
}

TextStyle get spaceGrotesk => GoogleFonts.spaceGrotesk();
TextStyle get dmSans => GoogleFonts.dmSans();
TextStyle get jetBrainsMono => GoogleFonts.jetBrainsMono();

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    cardTheme: const CardThemeData(color: AppColors.surface, elevation: 0),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.accent),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.background,
      elevation: 8,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 20,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

ThemeData buildWhiteTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.whiteBackground,
    colorScheme: const ColorScheme.light(
      primary: AppColors.whiteAccent,
      surface: AppColors.whiteSurface,
    ),
    cardTheme: CardThemeData(
      color: AppColors.whiteCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: const BorderSide(color: AppColors.whiteBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.whiteBackground,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.whiteTextPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.whiteAccent),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.whiteAccent,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.whiteSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: AppColors.whiteBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: AppColors.whiteAccent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.whiteTextSecondary),
      hintStyle: const TextStyle(color: AppColors.whiteTextSecondary),
    ),
  );
}

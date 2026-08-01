import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0E1A);
  static const surface = Color(0xFF131929);
  static const surfaceLight = Color(0xFF1C2438);
  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0x2922C55E);
  static const textPrimary = Color(0xFFEEF2FF);
  static const textSecondary = Color(0xFF8892AA);
  static const success = Color(0xFF4CAF82);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const read = Color(0xFF2A3545);

  static const whiteBackground = Color(0xFFFFFFFF);
  static const whiteSurface = Color(0xFFFAFAFA);
  static const whiteCard = Color(0xFFFFFFFF);
  static const whiteTextPrimary = Color(0xFF1A1A1A);
  static const whiteTextSecondary = Color(0xFF757575);
  static const whiteBorder = Color(0xFFE0E0E0);
  static const whiteAccent = Color(0xFF22C55E);
  static const whiteShadow = Color(0x0A000000);
  static const whiteErrorBg = Color(0xFFFFEBEE);
  static const whiteWarningBg = Color(0xFFFFF3E0);
  static const whiteSuccessBg = Color(0xFFE8F5E9);
}

TextStyle get spaceGrotesk => GoogleFonts.spaceGrotesk();
TextStyle get dmSans => GoogleFonts.dmSans();
TextStyle get jetBrainsMono => GoogleFonts.jetBrainsMono();

final TextTheme lightTextTheme = TextTheme(
  headlineLarge: GoogleFonts.spaceGrotesk(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.whiteTextPrimary,
  ),
  headlineMedium: GoogleFonts.spaceGrotesk(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.whiteTextPrimary,
  ),
  headlineSmall: GoogleFonts.spaceGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteTextPrimary,
  ),
  titleLarge: GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteTextPrimary,
  ),
  titleMedium: GoogleFonts.spaceGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteTextPrimary,
  ),
  titleSmall: GoogleFonts.spaceGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteTextPrimary,
  ),
  bodyLarge: GoogleFonts.dmSans(
    fontSize: 16,
    color: AppColors.whiteTextPrimary,
  ),
  bodyMedium: GoogleFonts.dmSans(
    fontSize: 14,
    color: AppColors.whiteTextPrimary,
  ),
  bodySmall: GoogleFonts.dmSans(
    fontSize: 12,
    color: AppColors.whiteTextSecondary,
  ),
  labelLarge: GoogleFonts.dmSans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.whiteTextPrimary,
  ),
  labelMedium: GoogleFonts.dmSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.whiteTextSecondary,
  ),
);

final TextTheme darkTextTheme = TextTheme(
  headlineLarge: GoogleFonts.spaceGrotesk(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  ),
  headlineMedium: GoogleFonts.spaceGrotesk(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  ),
  headlineSmall: GoogleFonts.spaceGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  titleLarge: GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  titleMedium: GoogleFonts.spaceGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  titleSmall: GoogleFonts.spaceGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  bodyLarge: GoogleFonts.dmSans(
    fontSize: 16,
    color: AppColors.textPrimary,
  ),
  bodyMedium: GoogleFonts.dmSans(
    fontSize: 14,
    color: AppColors.textPrimary,
  ),
  bodySmall: GoogleFonts.dmSans(
    fontSize: 12,
    color: AppColors.textSecondary,
  ),
  labelLarge: GoogleFonts.dmSans(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  labelMedium: GoogleFonts.dmSans(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  ),
);

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: false,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    textTheme: darkTextTheme,
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
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
      foregroundColor: AppColors.accent,
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
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
    ),
  );
}

ThemeData buildWhiteTheme() {
  return ThemeData(
    brightness: Brightness.light,
    useMaterial3: false,
    scaffoldBackgroundColor: AppColors.whiteBackground,
    colorScheme: const ColorScheme.light(
      primary: AppColors.whiteAccent,
      surface: AppColors.whiteSurface,
    ),
    textTheme: lightTextTheme,
    cardTheme: const CardThemeData(
      color: AppColors.whiteCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.whiteBorder),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.whiteBackground,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.whiteTextPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.whiteAccent),
      foregroundColor: AppColors.whiteTextPrimary,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.whiteAccent,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.whiteSurface,
      selectedItemColor: AppColors.whiteAccent,
      unselectedItemColor: AppColors.whiteTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
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
      prefixIconColor: AppColors.whiteTextSecondary,
      suffixIconColor: AppColors.whiteTextSecondary,
    ),
  );
}

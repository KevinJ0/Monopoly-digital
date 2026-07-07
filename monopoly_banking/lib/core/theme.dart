import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:monopoly_banking/core/constants.dart';

ThemeData monopolyTheme() {
  final textTheme = GoogleFonts.fredokaTextTheme(
    ThemeData.dark().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBgDark,
    colorScheme: const ColorScheme.dark(
      primary: kGreen,
      secondary: kGold,
      surface: kBgCard,
    ),
    textTheme: textTheme.copyWith(
      displayLarge: GoogleFonts.fredoka(
        color: Colors.white,
        fontSize: 42,
        fontWeight: FontWeight.w900,
        letterSpacing: 8,
      ),
      displayMedium: GoogleFonts.fredoka(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
      headlineLarge: GoogleFonts.fredoka(
        color: kGold,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: GoogleFonts.fredoka(
        color: kTextPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.fredoka(
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.fredoka(
        color: kTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.nunito(
        color: kTextPrimary,
        fontSize: 16,
      ),
      bodyMedium: GoogleFonts.nunito(
        color: kTextPrimary,
        fontSize: 14,
      ),
      bodySmall: GoogleFonts.nunito(
        color: kTextSecondary,
        fontSize: 12,
      ),
      labelLarge: GoogleFonts.fredoka(
        color: kTextSecondary,
        fontSize: 12,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.nunito(
        color: kTextSecondary,
        fontSize: 10,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBgDark,
      elevation: 0,
      iconTheme: const IconThemeData(color: kTextSecondary),
      titleTextStyle: GoogleFonts.fredoka(
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.nunito(
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.nunito(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kRed),
      ),
      labelStyle: GoogleFonts.nunito(color: kTextSecondary),
      hintStyle: GoogleFonts.nunito(color: kBorder),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kBgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: GoogleFonts.fredoka(
        color: kTextPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kBgCard,
      labelStyle: GoogleFonts.nunito(color: kTextPrimary, fontSize: 12),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:money_manager/core/constants.dart';

const _fredoka = 'Fredoka';
const _nunito = 'Nunito';

ThemeData moneyManagerTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBgDark,
    colorScheme: const ColorScheme.dark(
      primary: kGreen,
      secondary: kGold,
      surface: kBgCard,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontFamily: _fredoka,
        color: Colors.white,
        fontSize: 42,
        fontWeight: FontWeight.w900,
        letterSpacing: 8,
      ),
      displayMedium: TextStyle(
        fontFamily: _fredoka,
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
      ),
      headlineLarge: TextStyle(
        fontFamily: _fredoka,
        color: kGold,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: TextStyle(
        fontFamily: _fredoka,
        color: kTextPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        fontFamily: _fredoka,
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontFamily: _fredoka,
        color: kTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: _nunito,
        color: kTextPrimary,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        fontFamily: _nunito,
        color: kTextPrimary,
        fontSize: 14,
      ),
      bodySmall: TextStyle(
        fontFamily: _nunito,
        color: kTextSecondary,
        fontSize: 12,
      ),
      labelLarge: TextStyle(
        fontFamily: _fredoka,
        color: kTextSecondary,
        fontSize: 12,
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        fontFamily: _nunito,
        color: kTextSecondary,
        fontSize: 10,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBgDark,
      elevation: 0,
      iconTheme: IconThemeData(color: kTextSecondary),
      titleTextStyle: TextStyle(
        fontFamily: _fredoka,
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _nunito,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: _nunito,
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
      labelStyle: const TextStyle(fontFamily: _nunito, color: kTextSecondary),
      hintStyle: const TextStyle(fontFamily: _nunito, color: kBorder),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kBgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      titleTextStyle: TextStyle(
        fontFamily: _fredoka,
        color: kTextPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kBgCard,
      labelStyle: const TextStyle(fontFamily: _nunito, color: kTextPrimary, fontSize: 12),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
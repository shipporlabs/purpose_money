import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  static const ink = Color(0xFF0E1A14);
  static const deep = Color(0xFF0B3D28);
  static const green = Color(0xFF0B5D3B);
  static const accent = Color(0xFFF2B33D);
  static const cream = Color(0xFFF7F5EF);
  static const line = Color(0xFFE6E3D8);
  static const muted = Color(0xFF4D5E55);
  static const mint = Color(0xFFDDE9E2);
  static const red = Color(0xFFB42318);
  static const redSoft = Color(0xFFFCE3DF);
  static const blue = Color(0xFF3B4A8C);
  static const amberSoft = Color(0xFFFCEBC4);
}

TextStyle display(double size, {Color color = Brand.ink, FontWeight weight = FontWeight.w800}) {
  try {
    return GoogleFonts.getFont('Bricolage Grotesque', fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.5, height: 1.05);
  } catch (_) {
    return TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.5, height: 1.05);
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: Brand.green, primary: Brand.deep, secondary: Brand.accent, surface: Colors.white),
    scaffoldBackgroundColor: Brand.cream,
  );
  final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: Brand.ink, displayColor: Brand.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.cream, foregroundColor: Brand.ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      titleTextStyle: display(22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.deep, foregroundColor: Colors.white, minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink, minimumSize: const Size(64, 52), side: const BorderSide(color: Brand.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Brand.green, width: 1.5)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Brand.line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white, indicatorColor: Brand.mint,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: Brand.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

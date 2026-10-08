import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette officielle de YDS Beauty : rose nude et or.
class NacreaColors {
  static const nude = Color(0xFFF6E7E4); // fonds doux
  static const page = Color(0xFFFBF6F4); // fond des écrans
  static const rosePoudre = Color(0xFFD9A5A0); // accents doux
  static const prune = Color(0xFF8E3B55); // couleur principale, boutons
  static const pruneFonce = Color(0xFF6F2C42);
  static const or = Color(0xFFC9A45C); // touches de luxe
  static const orTexte = Color(0xFF9A7A36); // or lisible sur fond clair
  static const chocolat = Color(0xFF2B1D22); // textes
  static const gris = Color(0xFF6E5F63); // textes secondaires
  static const bordure = Color(0xFFEBDAD6);
  static const erreur = Color(0xFFB3261E);
  static const succes = Color(0xFF2E7D4F);
}

class NacreaTheme {
  /// Police des titres : élégante, avec empattements.
  static TextStyle titre({double size = 32, Color color = NacreaColors.chocolat}) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.1,
      );

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NacreaColors.prune,
        primary: NacreaColors.prune,
        onPrimary: Colors.white,
        secondary: NacreaColors.or,
        onSecondary: NacreaColors.chocolat,
        surface: Colors.white,
        onSurface: NacreaColors.chocolat,
        error: NacreaColors.erreur,
      ),
      scaffoldBackgroundColor: NacreaColors.page,
    );

    final texte = GoogleFonts.montserratTextTheme(base.textTheme).apply(
      bodyColor: NacreaColors.chocolat,
      displayColor: NacreaColors.chocolat,
    );

    final arrondi = BorderRadius.circular(12);

    return base.copyWith(
      textTheme: texte,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: NacreaColors.chocolat,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: titre(size: 26),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NacreaColors.bordure),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle: const TextStyle(color: NacreaColors.gris),
        floatingLabelStyle: const TextStyle(color: NacreaColors.prune),
        border: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: const BorderSide(color: NacreaColors.bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: const BorderSide(color: NacreaColors.bordure),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: const BorderSide(color: NacreaColors.prune, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: NacreaColors.prune,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56), // gros boutons, faciles à toucher
          shape: RoundedRectangleBorder(borderRadius: arrondi),
          textStyle: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NacreaColors.prune,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: NacreaColors.prune),
          shape: RoundedRectangleBorder(borderRadius: arrondi),
          textStyle: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NacreaColors.prune,
          textStyle: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: NacreaColors.chocolat,
      ),
    );
  }
}

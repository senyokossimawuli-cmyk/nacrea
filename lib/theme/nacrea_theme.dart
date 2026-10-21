import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette officielle de YDS Beauty : rose nude et or.
/// Chaque couleur a sa version claire et sa version sombre ;
/// [NacreaColors.sombre] choisit laquelle est utilisée (voir mode_affichage.dart).
class NacreaColors {
  /// Mode sombre actif. Changé uniquement par ModeAffichage.
  static bool sombre = false;

  static Color _c(int clair, int fonce) => Color(sombre ? fonce : clair);

  static Color get nude => _c(0xFFF6E7E4, 0xFF34252B); // fonds doux
  static Color get page => _c(0xFFFBF6F4, 0xFF1A1215); // fond des écrans
  static Color get surface => _c(0xFFFFFFFF, 0xFF251A1F); // cartes, fenêtres, barres
  static Color get rosePoudre => _c(0xFFD9A5A0, 0xFFB98583); // accents doux
  static Color get prune => _c(0xFF8E3B55, 0xFFC9587E); // couleur principale, boutons
  static Color get pruneFonce => _c(0xFF6F2C42, 0xFF9E4262);
  static const or = Color(0xFFC9A45C); // touches de luxe
  static Color get orTexte => _c(0xFF9A7A36, 0xFFD9B66E); // or lisible sur le fond
  static Color get chocolat => _c(0xFF2B1D22, 0xFFF3E7E4); // textes
  static Color get gris => _c(0xFF6E5F63, 0xFFB8A8AC); // textes secondaires
  static Color get bordure => _c(0xFFEBDAD6, 0xFF45343B);
  static Color get erreur => _c(0xFFB3261E, 0xFFF28B82);
  static Color get succes => _c(0xFF2E7D4F, 0xFF6FCF97);

  // Fonds légers des messages et pastilles
  static Color get fondErreur => _c(0xFFFCEBEB, 0xFF3D2023);
  static Color get bordureErreur => _c(0xFFF2C9C9, 0xFF6B3036);
  static Color get fondOr => _c(0xFFF7EEDB, 0xFF3A3020);
  static Color get fondSucces => _c(0xFFE5F3EA, 0xFF1D3428);
}

class NacreaTheme {
  /// Police des titres : élégante, avec empattements.
  static TextStyle titre({double size = 32, Color? color}) => GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? NacreaColors.chocolat,
        height: 1.1,
      );

  /// Thème du mode en cours (clair ou sombre).
  static ThemeData actuel() {
    final sombre = NacreaColors.sombre;
    final base = ThemeData(
      useMaterial3: true,
      brightness: sombre ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8E3B55),
        brightness: sombre ? Brightness.dark : Brightness.light,
        primary: NacreaColors.prune,
        onPrimary: Colors.white,
        secondary: NacreaColors.or,
        onSecondary: const Color(0xFF2B1D22),
        surface: NacreaColors.surface,
        onSurface: NacreaColors.chocolat,
        surfaceContainerHighest: NacreaColors.nude,
        error: NacreaColors.erreur,
      ),
      scaffoldBackgroundColor: NacreaColors.page,
      canvasColor: NacreaColors.surface,
      dividerColor: NacreaColors.bordure,
    );

    final texte = GoogleFonts.montserratTextTheme(base.textTheme).apply(
      bodyColor: NacreaColors.chocolat,
      displayColor: NacreaColors.chocolat,
    );

    final arrondi = BorderRadius.circular(12);

    return base.copyWith(
      textTheme: texte,
      appBarTheme: AppBarTheme(
        backgroundColor: NacreaColors.surface,
        foregroundColor: NacreaColors.chocolat,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: titre(size: 26),
      ),
      cardTheme: CardThemeData(
        color: NacreaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: NacreaColors.bordure),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: NacreaColors.surface),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: NacreaColors.surface),
      popupMenuTheme: PopupMenuThemeData(color: NacreaColors.surface),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: NacreaColors.surface,
        indicatorColor: NacreaColors.nude,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: NacreaColors.surface,
        indicatorColor: NacreaColors.nude,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NacreaColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle: TextStyle(color: NacreaColors.gris),
        floatingLabelStyle: TextStyle(color: NacreaColors.prune),
        border: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: BorderSide(color: NacreaColors.bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: BorderSide(color: NacreaColors.bordure),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: arrondi,
          borderSide: BorderSide(color: NacreaColors.prune, width: 1.5),
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
          side: BorderSide(color: NacreaColors.prune),
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
      chipTheme: ChipThemeData(
        backgroundColor: NacreaColors.surface,
        selectedColor: NacreaColors.nude,
        side: BorderSide(color: NacreaColors.bordure),
        labelStyle: TextStyle(color: NacreaColors.chocolat),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: sombre ? const Color(0xFFF3E7E4) : const Color(0xFF2B1D22),
        contentTextStyle: TextStyle(color: sombre ? const Color(0xFF2B1D22) : Colors.white),
      ),
    );
  }

  /// Ancien nom, gardé pour ne rien casser.
  static ThemeData light() => actuel();
}

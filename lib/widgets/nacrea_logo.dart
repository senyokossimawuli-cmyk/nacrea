import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/nacrea_theme.dart';

/// Logo YDS Beauty : la perle, YDS, « Beauty » doré, le filet or et le slogan.
class NacreaLogo extends StatelessWidget {
  const NacreaLogo({
    super.key,
    this.taille = 56,
    this.surFondFonce = false,
    this.avecSlogan = true,
  });

  final double taille;
  final bool surFondFonce;
  final bool avecSlogan;

  @override
  Widget build(BuildContext context) {
    final couleurNom = surFondFonce ? NacreaColors.nude : NacreaColors.prune;
    final couleurE = surFondFonce ? NacreaColors.or : NacreaColors.orTexte;
    final couleurSlogan = surFondFonce ? NacreaColors.nude : NacreaColors.chocolat;
    final styleNom = GoogleFonts.cormorantGaramond(
      fontSize: taille,
      fontWeight: FontWeight.w600,
      letterSpacing: taille * 0.16,
      height: 1,
      color: couleurNom,
    );

    return Semantics(
      label: 'YDS Beauty',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: taille * 0.2,
            height: taille * 0.2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: surFondFonce ? NacreaColors.nude : Colors.white,
              border: Border.all(color: NacreaColors.or, width: 1.5),
            ),
          ),
          SizedBox(height: taille * 0.2),
          Padding(
            // compense l'espacement des lettres pour bien centrer le mot
            padding: EdgeInsets.only(left: taille * 0.16),
            child: Text('YDS', style: styleNom),
          ),
          SizedBox(height: taille * 0.06),
          Text(
            'Beauty',
            style: GoogleFonts.cormorantGaramond(
              fontSize: taille * 0.62,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              letterSpacing: taille * 0.04,
              height: 1,
              color: couleurE,
            ),
          ),
          if (avecSlogan) ...[
            SizedBox(height: taille * 0.22),
            Container(width: taille * 0.9, height: 1.5, color: NacreaColors.or),
            SizedBox(height: taille * 0.22),
            Text(
              'GESTION DE BOUTIQUES BEAUTÉ',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: (taille * 0.17).clamp(10.0, 14.0).toDouble(),
                fontWeight: FontWeight.w500,
                letterSpacing: 3,
                color: couleurSlogan,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

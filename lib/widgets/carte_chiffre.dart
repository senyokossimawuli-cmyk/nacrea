import 'package:flutter/material.dart';

import '../theme/nacrea_theme.dart';

/// Petite carte « titre + gros chiffre » (accueil, dépenses, rapports).
class CarteChiffre extends StatelessWidget {
  const CarteChiffre({
    super.key,
    required this.titre,
    required this.valeur,
    this.sousTitre,
    this.couleur,
    this.fond,
    this.largeurMin = 150,
  });
  final String titre;
  final String valeur;
  final String? sousTitre;
  final Color? couleur;
  final Color? fond;
  final double largeurMin;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: largeurMin),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: fond ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NacreaColors.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titre, style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
          const SizedBox(height: 4),
          Text(valeur,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: couleur ?? NacreaColors.chocolat)),
          if (sousTitre != null) ...[
            const SizedBox(height: 2),
            Text(sousTitre!, style: const TextStyle(color: NacreaColors.gris, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

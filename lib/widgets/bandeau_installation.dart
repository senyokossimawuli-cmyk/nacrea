import 'package:flutter/material.dart';

import '../services/appareil.dart' as appareil;
import '../theme/nacrea_theme.dart';

/// Sur iPhone (dans Safari) : explique comment installer YDS Beauty sur l'écran d'accueil.
class BandeauInstallation extends StatelessWidget {
  const BandeauInstallation({super.key});

  @override
  Widget build(BuildContext context) {
    if (!appareil.proposerInstallationIphone) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NacreaColors.nude,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NacreaColors.or),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.install_mobile_outlined, color: NacreaColors.prune),
          SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(height: 1.45, color: NacreaColors.chocolat),
                children: [
                  TextSpan(text: 'Installez YDS Beauty sur votre iPhone\n', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: 'Touchez le bouton Partager '),
                  WidgetSpan(child: Icon(Icons.ios_share, size: 18, color: NacreaColors.prune)),
                  TextSpan(text: ' en bas de Safari, puis « Sur l\'écran d\'accueil ». '
                      'YDS Beauty s\'ouvrira alors comme une vraie appli, même sans internet.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

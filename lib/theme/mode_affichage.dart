import 'package:flutter/material.dart';

import '../services/appareil.dart' as appareil;
import 'nacrea_theme.dart';

/// Clair, sombre, ou comme le téléphone / le PC.
enum ModeAffichage {
  clair('Clair', Icons.light_mode_outlined),
  sombre('Sombre', Icons.dark_mode_outlined),
  auto('Automatique', Icons.brightness_auto_outlined);

  const ModeAffichage(this.libelle, this.icone);
  final String libelle;
  final IconData icone;
}

/// Mode d'affichage choisi, gardé sur l'appareil.
class Affichage {
  static final mode = ValueNotifier<ModeAffichage>(ModeAffichage.clair);
  static const _cle = 'mode-affichage';

  static Future<void> charger() async {
    final texte = await appareil.lireDonnee(_cle);
    mode.value = ModeAffichage.values.firstWhere((m) => m.name == texte?.trim(), orElse: () => ModeAffichage.clair);
  }

  static Future<void> choisir(ModeAffichage m) async {
    mode.value = m;
    try {
      await appareil.ecrireDonnee(_cle, m.name);
    } catch (_) {}
  }

  /// Sombre ou non, selon le choix et le réglage de l'appareil.
  static bool estSombre() => switch (mode.value) {
        ModeAffichage.clair => false,
        ModeAffichage.sombre => true,
        ModeAffichage.auto =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      };
}

/// Bouton soleil / lune pour changer le mode d'affichage.
class BoutonModeAffichage extends StatelessWidget {
  const BoutonModeAffichage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ModeAffichage>(
      valueListenable: Affichage.mode,
      builder: (context, actuel, _) => PopupMenuButton<ModeAffichage>(
        tooltip: 'Affichage clair ou sombre',
        icon: Icon(NacreaColors.sombre ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
        initialValue: actuel,
        onSelected: Affichage.choisir,
        itemBuilder: (_) => [
          for (final m in ModeAffichage.values)
            PopupMenuItem(
              value: m,
              child: Row(
                children: [
                  Icon(m.icone, color: m == actuel ? NacreaColors.prune : null),
                  const SizedBox(width: 12),
                  Text(m.libelle,
                      style: TextStyle(fontWeight: m == actuel ? FontWeight.w700 : FontWeight.w400)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

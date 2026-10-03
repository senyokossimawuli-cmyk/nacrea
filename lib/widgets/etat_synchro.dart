import 'dart:async';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';

import '../data/base_locale.dart';
import '../theme/nacrea_theme.dart';

/// Petit indicateur en haut de l'écran : en ligne, hors ligne, envois en attente.
class EtatSynchro extends StatefulWidget {
  const EtatSynchro({super.key, this.compact = false});
  final bool compact;

  @override
  State<EtatSynchro> createState() => _EtatSynchroState();
}

class _EtatSynchroState extends State<EtatSynchro> {
  int _enAttente = 0;
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _compter();
    _minuterie = Timer.periodic(const Duration(seconds: 3), (_) => _compter());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _compter() async {
    try {
      final n = await changementsEnAttente();
      if (mounted && n != _enAttente) setState(() => _enAttente = n);
    } catch (_) {
      // La base peut être en cours de fermeture (déconnexion) : on ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snap) {
        final s = snap.data!;
        final enLigne = s.connected;
        final (IconData icone, Color couleur, String texte) = !enLigne
            ? (
                Icons.cloud_off_outlined,
                NacreaColors.orTexte,
                _enAttente > 0 ? 'Hors ligne · $_enAttente en attente' : 'Hors ligne',
              )
            : (s.uploading || s.downloading || _enAttente > 0)
                ? (Icons.cloud_sync_outlined, NacreaColors.gris, 'Synchronisation…')
                : (Icons.cloud_done_outlined, NacreaColors.succes, 'À jour');

        final explication = !enLigne
            ? 'Pas de connexion : vous pouvez continuer à vendre. '
                'Tout sera envoyé automatiquement au retour d\'internet.'
            : 'Les données de cet appareil sont synchronisées avec le serveur.';

        return Tooltip(
          message: explication,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: enLigne ? Colors.transparent : const Color(0xFFF7EEDB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 20, color: couleur),
                if (!widget.compact || !enLigne) ...[
                  const SizedBox(width: 6),
                  Text(texte,
                      style: TextStyle(fontSize: 13, color: couleur, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

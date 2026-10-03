import 'package:flutter/material.dart';

import '../../data/ventes_repo.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

/// Données d'un ticket de caisse à afficher.
class Ticket {
  Ticket({
    required this.boutique,
    required this.numero,
    required this.date,
    required this.lignes,
    required this.sousTotal,
    required this.remise,
    required this.total,
    required this.paiements,
    this.recuEspeces,
    this.monnaie = 0,
    this.vendeuse,
    this.annule = false,
  });

  final String boutique;
  final String numero;
  final DateTime date;
  final List<LigneVente> lignes;
  final int sousTotal;
  final int remise;
  final int total;
  final Map<String, int> paiements;
  final int? recuEspeces;
  final int monnaie;
  final String? vendeuse;
  final bool annule;
}

/// Affiche le ticket ; renvoie quand la caissière clique sur le bouton.
Future<void> afficherTicket(BuildContext context, Ticket t, {String bouton = 'Nouvelle vente'}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(child: TicketVue(ticket: t)),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        SizedBox(
          width: 332,
          child: FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(bouton),
          ),
        ),
      ],
    ),
  );
}

class TicketVue extends StatelessWidget {
  const TicketVue({super.key, required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    const petit = TextStyle(fontSize: 13, color: NacreaColors.gris);
    Widget ligne(String a, String b, {bool fort = false, Color? couleur}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(a,
                    style: TextStyle(
                        fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                        fontSize: fort ? 18 : 14,
                        color: couleur)),
              ),
              Text(b,
                  style: TextStyle(
                      fontWeight: fort ? FontWeight.w700 : FontWeight.w500,
                      fontSize: fort ? 18 : 14,
                      color: couleur)),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t.annule)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFFCEBEB),
            child: const Text('VENTE ANNULÉE',
                textAlign: TextAlign.center,
                style: TextStyle(color: NacreaColors.erreur, fontWeight: FontWeight.w700)),
          ),
        Text(t.boutique, textAlign: TextAlign.center, style: NacreaTheme.titre(size: 26)),
        const SizedBox(height: 4),
        Text(
          'Ticket ${t.numero} · ${dateCourte(t.date)} à '
          '${t.date.hour.toString().padLeft(2, '0')}h${t.date.minute.toString().padLeft(2, '0')}',
          textAlign: TextAlign.center,
          style: petit,
        ),
        if (t.vendeuse != null)
          Text('Servi par ${t.vendeuse}', textAlign: TextAlign.center, style: petit),
        const Divider(height: 28, color: NacreaColors.bordure),
        for (final l in t.lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Expanded(child: Text('${l.quantite} × ${fcfa(l.prixUnitaire)}', style: petit)),
                    Text(fcfa(l.total)),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 24, color: NacreaColors.bordure),
        if (t.remise > 0) ...[
          ligne('Sous-total', fcfa(t.sousTotal)),
          ligne('Remise', '- ${fcfa(t.remise)}', couleur: NacreaColors.orTexte),
        ],
        ligne('TOTAL', fcfa(t.total), fort: true, couleur: NacreaColors.prune),
        const SizedBox(height: 8),
        for (final p in t.paiements.entries) ligne(MoyenPaiement.libelleDe(p.key), fcfa(p.value)),
        if (t.recuEspeces != null) ...[
          ligne('Reçu en espèces', fcfa(t.recuEspeces!)),
          ligne('Monnaie rendue', fcfa(t.monnaie)),
        ],
        const SizedBox(height: 16),
        const Text('Merci de votre visite !',
            textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
      ],
    );
  }
}

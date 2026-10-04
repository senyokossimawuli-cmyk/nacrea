import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/base_locale.dart';
import '../theme/nacrea_theme.dart';
import '../utils/format.dart';

/// Abonnement d'une boutique, lu sur l'appareil.
///
/// Le statut est recalculé ici à partir de la date de fin : ainsi, même sans
/// internet, une boutique dont l'abonnement est terminé depuis plus de
/// 7 jours est bloquée, comme le fait le serveur.
class EtatAbonnement {
  EtatAbonnement({required this.statutServeur, this.fin, this.prixMensuel = 22000});
  final String statutServeur; // trial, active, late, suspended
  final DateTime? fin;
  final int prixMensuel;

  String get statut {
    if (statutServeur == 'suspended') return 'suspended';
    final f = fin;
    if (f == null) return statutServeur;
    final maintenant = DateTime.now();
    if (maintenant.isAfter(f.add(const Duration(days: NacreaConfig.joursDeGrace)))) return 'suspended';
    if (maintenant.isAfter(f)) return 'late';
    return statutServeur;
  }

  bool get suspendu => statut == 'suspended';
  bool get enRetard => statut == 'late';
  bool get essai => statut == 'trial';

  /// Jours avant la fin (négatif si dépassée).
  int? get joursRestants => fin == null ? null : fin!.difference(DateTime.now()).inHours ~/ 24;

  /// Date à laquelle la caisse sera bloquée si rien n'est payé.
  DateTime? get blocageLe => fin?.add(const Duration(days: NacreaConfig.joursDeGrace));

  static Stream<EtatAbonnement?> surveiller(String boutiqueId) => db
      .watch(
        'SELECT status, current_period_end, monthly_price FROM subscriptions WHERE shop_id = ? LIMIT 1',
        parameters: [boutiqueId],
        triggerOnTables: const ['subscriptions'],
      )
      .map((l) => l.isEmpty
          ? null
          : EtatAbonnement(
              statutServeur: l.first['status'] as String? ?? 'trial',
              fin: DateTime.tryParse(l.first['current_period_end'] as String? ?? '')?.toLocal(),
              prixMensuel: (l.first['monthly_price'] as int?) ?? 22000,
            ));
}

Future<void> contacterNacrea(BuildContext context, String message) async {
  final numero = NacreaConfig.supportWhatsApp.replaceAll(RegExp(r'\D'), '');
  final lien = Uri.parse(numero.isEmpty
      ? 'https://wa.me/?text=${Uri.encodeComponent(message)}'
      : 'https://wa.me/$numero?text=${Uri.encodeComponent(message)}');
  final ok = await launchUrl(lien, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')));
  }
}

/// Écran affiché à la place de la caisse quand l'abonnement est suspendu.
class CaisseBloquee extends StatelessWidget {
  const CaisseBloquee({super.key, required this.nomBoutique, required this.patronne});
  final String nomBoutique;
  final bool patronne;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: NacreaColors.prune),
              const SizedBox(height: 16),
              Text('Caisse en pause', style: NacreaTheme.titre(size: 32), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                patronne
                    ? 'L\'abonnement Nacréa de « $nomBoutique » n\'est pas à jour. '
                        'Vos données sont en sécurité et restent consultables. '
                        'Réglez votre abonnement pour reprendre les ventes.'
                    : 'L\'abonnement de la boutique n\'est pas à jour. Prévenez la patronne : '
                        'les ventes reprendront dès que l\'abonnement sera réglé.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              if (patronne) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 300,
                  child: FilledButton.icon(
                    onPressed: () => contacterNacrea(
                      context,
                      'Bonjour Nacréa, je souhaite régler l\'abonnement de ma boutique « $nomBoutique ».',
                    ),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Contacter Nacréa'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau d'avertissement : abonnement en retard, ou essai qui se termine bientôt.
class BandeauAbonnement extends StatelessWidget {
  const BandeauAbonnement({super.key, required this.etat, required this.nomBoutique, required this.patronne});
  final EtatAbonnement etat;
  final String nomBoutique;
  final bool patronne;

  /// Rien à afficher ?
  static bool utile(EtatAbonnement? e) =>
      e != null && (e.enRetard || ((e.essai || e.statut == 'active') && (e.joursRestants ?? 99) <= 3));

  @override
  Widget build(BuildContext context) {
    final String texte;
    if (etat.enRetard) {
      final le = etat.blocageLe;
      texte = patronne
          ? 'Abonnement en retard : la caisse sera bloquée${le == null ? ' bientôt' : ' le ${dateCourte(le)}'}. '
              'Réglez ${fcfa(etat.prixMensuel)} pour continuer.'
          : 'L\'abonnement de la boutique est en retard. Prévenez la patronne.';
    } else {
      final j = etat.joursRestants ?? 0;
      final quand = j <= 0 ? 'aujourd\'hui' : (j == 1 ? 'demain' : 'dans $j jours');
      texte = etat.essai
          ? 'Votre essai gratuit se termine $quand. Abonnement : ${fcfa(etat.prixMensuel)} par mois.'
          : 'Votre abonnement se termine $quand.';
    }
    return Material(
      color: etat.enRetard ? const Color(0xFFFCEBEB) : const Color(0xFFF7EEDB),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(etat.enRetard ? Icons.warning_amber_rounded : Icons.schedule,
                color: etat.enRetard ? NacreaColors.erreur : NacreaColors.orTexte),
            const SizedBox(width: 12),
            Expanded(child: Text(texte)),
            if (patronne)
              TextButton(
                onPressed: () => contacterNacrea(
                  context,
                  'Bonjour Nacréa, je souhaite régler l\'abonnement de ma boutique « $nomBoutique ».',
                ),
                child: const Text('Payer'),
              ),
          ],
        ),
      ),
    );
  }
}

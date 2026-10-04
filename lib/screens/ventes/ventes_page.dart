import 'package:flutter/material.dart';

import '../../data/produits_repo.dart';
import '../../data/ventes_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../caisse/recu_dialog.dart';
import '../caisse/session_caisse.dart';
import '../../data/caisse_repo.dart';

/// Ventes d'une journée : totaux, répartition par paiement et liste des reçus.
class VentesPage extends StatefulWidget {
  const VentesPage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<VentesPage> createState() => _VentesPageState();
}

class _VentesPageState extends State<VentesPage> {
  late final _repo = VentesRepo(boutique: widget.boutique, compteId: widget.membre.compteId);
  DateTime _jour = DateTime.now();
  // En direct : une vente faite à la caisse (ou dans une autre boutique) apparaît seule.
  late Stream<List<Vente>> _ventes = _repo.surveillerVentes(_jour);

  bool get _aujourdhui {
    final n = DateTime.now();
    return _jour.year == n.year && _jour.month == n.month && _jour.day == n.day;
  }

  void _changerJour(int delta) {
    setState(() {
      _jour = _jour.add(Duration(days: delta));
      _ventes = _repo.surveillerVentes(_jour);
    });
  }

  void _recharger() => setState(() => _ventes = _repo.surveillerVentes(_jour));

  Future<void> _ouvrir(Vente v) async {
    final ticket = Recu(
      boutique: widget.boutique.nom,
      adresse: widget.boutique.adresse,
      telephoneBoutique: widget.boutique.telephone,
      numero: v.ticket,
      date: v.date,
      lignes: v.lignes,
      sousTotal: v.sousTotal,
      remise: v.remise,
      total: v.total,
      paiements: v.paiements,
      vendeuse: v.vendeuse,
      annule: v.annulee,
    );
    final peutAnnuler = widget.membre.estPatronne && !v.annulee;

    final annuler = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(width: 380, child: SingleChildScrollView(child: RecuVue(recu: ticket))),
        actions: [
          if (!v.annulee) ...[
            TextButton.icon(
              onPressed: () => imprimerRecu(ctx, ticket),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimer'),
            ),
            TextButton.icon(
              onPressed: () => envoyerRecuWhatsApp(ctx, ticket),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
          ],
          if (peutAnnuler)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: NacreaColors.erreur),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Annuler la vente'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fermer')),
        ],
      ),
    );
    if (annuler != true || !mounted) return;

    final motif = TextEditingController();
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Annuler le reçu n° ${v.ticket} ?'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Les produits seront remis en stock. La vente restera visible, marquée « annulée ».'),
              const SizedBox(height: 16),
              TextField(
                controller: motif,
                decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: NacreaColors.erreur),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    try {
      await _repo.annuler(v.id, motif: motif.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Reçu n° ${v.ticket} annulé, stock remis en place.')));
      _recharger();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vente>>(
      stream: _ventes,
      builder: (context, snap) {
        final chargement = !snap.hasData && !snap.hasError;
        final ventes = snap.data ?? const <Vente>[];
        final valides = ventes.where((v) => !v.annulee).toList();
        final ca = valides.fold(0, (s, v) => s + v.total);
        final parMoyen = <String, int>{};
        for (final v in valides) {
          for (final p in v.paiements.entries) {
            parMoyen[p.key] = (parMoyen[p.key] ?? 0) + p.value;
          }
        }

        return RefreshIndicator(
          color: NacreaColors.prune,
          onRefresh: () async {
            _recharger();
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text('Ventes', style: NacreaTheme.titre(size: 36)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Jour précédent',
                        onPressed: () => _changerJour(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(_aujourdhui ? 'Aujourd\'hui' : dateCourte(_jour),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      IconButton(
                        tooltip: 'Jour suivant',
                        onPressed: _aujourdhui ? null : () => _changerJour(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snap.hasError)
                Text(messageErreur(snap.error!), style: const TextStyle(color: NacreaColors.erreur))
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Chiffre(titre: 'Chiffre d\'affaires', valeur: fcfa(ca), principal: true),
                    _Chiffre(titre: 'Reçus', valeur: '${valides.length}'),
                    _Chiffre(
                      titre: 'Panier moyen',
                      valeur: valides.isEmpty ? '—' : fcfa((ca / valides.length).round()),
                    ),
                    for (final m in MoyenPaiement.values)
                      _Chiffre(titre: m.libelle, valeur: fcfa(parMoyen[m.code] ?? 0)),
                  ],
                ),
                const SizedBox(height: 24),
                if (chargement)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                  )
                else if (ventes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Aucune vente ce jour-là.', style: TextStyle(color: NacreaColors.gris)),
                    ),
                  )
                else
                  for (final v in ventes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _LigneVente(vente: v, quandTouche: () => _ouvrir(v)),
                    ),
                const SizedBox(height: 24),
                _SessionsDuJour(
                  key: ValueKey('sessions-${dateCourte(_jour)}'),
                  repo: CaisseRepo(boutiqueId: widget.boutique.id, compteId: widget.membre.compteId),
                  jour: _jour,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.titre, required this.valeur, this.principal = false});
  final String titre;
  final String valeur;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: principal ? 260 : 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: principal ? NacreaColors.prune : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: principal ? NacreaColors.prune : NacreaColors.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre,
              style: TextStyle(
                  fontSize: 13, color: principal ? NacreaColors.nude : NacreaColors.gris)),
          const SizedBox(height: 6),
          Text(valeur,
              style: TextStyle(
                fontSize: principal ? 26 : 20,
                fontWeight: FontWeight.w700,
                color: principal ? Colors.white : NacreaColors.chocolat,
              )),
        ],
      ),
    );
  }
}

class _LigneVente extends StatelessWidget {
  const _LigneVente({required this.vente, required this.quandTouche});
  final Vente vente;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    final v = vente;
    final heure = '${v.date.hour.toString().padLeft(2, '0')}h${v.date.minute.toString().padLeft(2, '0')}';
    final moyens = v.paiements.keys.map(MoyenPaiement.libelleDe).join(' + ');
    final barre = v.annulee ? TextDecoration.lineThrough : TextDecoration.none;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: quandTouche,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(heure, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reçu n° ${v.ticket} · ${v.nbArticles} article${v.nbArticles > 1 ? 's' : ''}',
                        style: TextStyle(fontWeight: FontWeight.w600, decoration: barre)),
                    Text('$moyens · ${v.vendeuse}',
                        style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
                  ],
                ),
              ),
              if (v.annulee)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBEB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Annulée',
                      style: TextStyle(
                          color: NacreaColors.erreur, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              Text(fcfa(v.total),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, decoration: barre)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ouvertures et clôtures de caisse de la journée, avec leur écart.
class _SessionsDuJour extends StatefulWidget {
  const _SessionsDuJour({super.key, required this.repo, required this.jour});
  final CaisseRepo repo;
  final DateTime jour;

  @override
  State<_SessionsDuJour> createState() => _SessionsDuJourState();
}

class _SessionsDuJourState extends State<_SessionsDuJour> {
  late final _sessions = widget.repo.surveillerDuJour(widget.jour);

  String _h(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SessionCaisse>>(
      stream: _sessions,
      builder: (context, snap) {
        final sessions = snap.data ?? const <SessionCaisse>[];
        if (sessions.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Caisse', style: NacreaTheme.titre(size: 26)),
            const SizedBox(height: 12),
            for (final s in sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(s.ouverte ? Icons.lock_open : Icons.lock_outline,
                            color: s.ouverte ? NacreaColors.succes : NacreaColors.gris),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.ouverte
                                    ? 'Ouverte à ${_h(s.ouverteLe)} · en cours'
                                    : 'De ${_h(s.ouverteLe)} à ${_h(s.fermeeLe!)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                [
                                  'Fond ${fcfa(s.fond)}',
                                  if (s.attendu != null) 'Attendu ${fcfa(s.attendu!)}',
                                  if (s.compte != null) 'Compté ${fcfa(s.compte!)}',
                                  if (s.fermeePar != null) 'Clôturée par ${s.fermeePar}',
                                ].join(' · '),
                                style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                              ),
                              if ((s.note ?? '').isNotEmpty)
                                Text('« ${s.note} »',
                                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        if (s.ecart != null)
                          Builder(builder: (_) {
                            final (texte, couleur) = libelleEcart(s.ecart!);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: couleur.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(texte,
                                  style: TextStyle(color: couleur, fontWeight: FontWeight.w700, fontSize: 13)),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

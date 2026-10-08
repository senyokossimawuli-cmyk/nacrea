import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/depenses_repo.dart' show libelleCategorie;
import '../../data/produits_repo.dart';
import '../../data/rapports_repo.dart';
import '../../data/stock_repo.dart' show MotifAjustement;
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../utils/periode.dart';
import '../../widgets/carte_chiffre.dart';

/// Rapports de la patronne : chiffre d'affaires, marge, dépenses et vrai bénéfice.
class RapportsPage extends StatefulWidget {
  const RapportsPage({super.key, required this.membre, required this.boutique, required this.boutiques});
  final Membre membre;
  final Boutique boutique;
  final List<Boutique> boutiques;

  @override
  State<RapportsPage> createState() => _RapportsPageState();
}

class _RapportsPageState extends State<RapportsPage> {
  late final _repo = RapportsRepo(compteId: widget.membre.compteId);
  Periode _periode = Periode.mois;
  late bool _toutes = widget.boutiques.length > 1;
  late Future<Rapport> _rapport = _calculer();

  Future<Rapport> _calculer() {
    final (debut, fin) = _periode.bornes;
    return _repo.calculer(boutiqueId: _toutes ? null : widget.boutique.id, debut: debut, fin: fin);
  }

  void _changer({Periode? periode, bool? toutes}) => setState(() {
        _periode = periode ?? _periode;
        _toutes = toutes ?? _toutes;
        _rapport = _calculer();
      });

  String get _perimetre => _toutes ? 'toutes les boutiques' : widget.boutique.nom;

  String _titrePeriode() {
    final (debut, fin) = _periode.bornes;
    return switch (_periode) {
      Periode.mois || Periode.moisDernier => nomMois(debut),
      Periode.aujourdhui => dateCourte(debut),
      _ => '${dateCourte(debut)} au ${dateCourte(fin)}',
    };
  }

  Future<void> _envoyerResume(Rapport r) async {
    final texte = [
      'YDS Beauty · ${widget.membre.nomCompte}',
      'Rapport ${_periode.libelle.toLowerCase()} (${_titrePeriode()}) · $_perimetre',
      '',
      'Ventes : ${r.nbVentes}',
      "Chiffre d'affaires : ${fcfa(r.chiffreAffaires)}",
      if (r.retours > 0) 'Retours remboursés : ${fcfa(r.retours)}',
      'Coût des produits vendus : ${fcfa(r.coutNet)}',
      'Marge : ${fcfa(r.margeBrute)}',
      'Dépenses : ${fcfa(r.totalDepenses)}',
      if (r.ecartsStock != 0) 'Pertes et écarts de stock : ${fcfa(r.ecartsStock)}',
      'Bénéfice : ${fcfa(r.benefice)}',
      if (r.creditsEnCours > 0) 'Crédits clientes à récupérer : ${fcfa(r.creditsEnCours)}',
    ].join('\n').replaceAll(' ', ' ');
    final ok = await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texte)}'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return RefreshIndicator(
      color: NacreaColors.prune,
      onRefresh: () async {
        _changer();
        await _rapport;
      },
      child: ListView(
        padding: EdgeInsets.all(etroit ? 16 : 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: FutureBuilder<Rapport>(
                future: _rapport,
                builder: (context, snap) {
                  final r = snap.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Rapports', style: NacreaTheme.titre(size: etroit ? 30 : 36)),
                              Text('${_titrePeriode()} · $_perimetre',
                                  style: const TextStyle(color: NacreaColors.gris)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Actualiser',
                                onPressed: () => _changer(),
                                icon: const Icon(Icons.refresh, color: NacreaColors.prune),
                              ),
                              if (r != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                  onPressed: () => _envoyerResume(r),
                                  icon: const Icon(Icons.share_outlined),
                                  label: const Text('Envoyer le résumé'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in Periode.values)
                            ChoiceChip(
                              label: Text(p.libelle),
                              selected: p == _periode,
                              onSelected: (_) => _changer(periode: p),
                            ),
                          if (widget.boutiques.length > 1)
                            FilterChip(
                              avatar: const Icon(Icons.storefront_outlined, size: 18),
                              label: const Text('Toutes les boutiques'),
                              selected: _toutes,
                              onSelected: (v) => _changer(toutes: v),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (snap.hasError)
                        Text(messageErreur(snap.error!), style: const TextStyle(color: NacreaColors.erreur))
                      else if (r == null)
                        const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                        )
                      else
                        ..._contenu(r, etroit),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contenu(Rapport r, bool etroit) {
    final positif = r.benefice >= 0;
    return [
      // ---------- Le vrai bénéfice ----------
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(positif ? 'Bénéfice' : 'Perte', style: const TextStyle(color: NacreaColors.gris, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                fcfa(r.benefice),
                style: NacreaTheme.titre(
                  size: etroit ? 38 : 46,
                  color: positif ? NacreaColors.succes : NacreaColors.erreur,
                ),
              ),
              const SizedBox(height: 16),
              _ligne("Chiffre d'affaires", fcfa(r.chiffreAffaires)),
              if (r.retours > 0) _ligne('Retours remboursés', '- ${fcfa(r.retours)}'),
              _ligne('Coût des produits vendus', '- ${fcfa(r.coutNet)}'),
              const Divider(color: NacreaColors.bordure),
              _ligne('Marge', '${fcfa(r.margeBrute)}  (${(r.tauxMarge * 100).round()} %)', fort: true),
              _ligne('Dépenses', '- ${fcfa(r.totalDepenses)}'),
              if (r.ecartsStock != 0)
                _ligne(
                  r.ecartsStock < 0 ? 'Pertes de stock (casse, vol, inventaire…)' : 'Écarts de stock (en plus)',
                  '${r.ecartsStock < 0 ? '- ' : '+ '}${fcfa(r.ecartsStock.abs())}',
                ),
              const Divider(color: NacreaColors.bordure),
              _ligne(positif ? 'Bénéfice' : 'Perte', fcfa(r.benefice), fort: true),
              if (r.coutMarchandises == 0 && r.chiffreAffaires > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Le coût des produits est à 0 : indiquez les prix d\'achat de vos produits '
                    'pour obtenir le vrai bénéfice.',
                    style: TextStyle(color: NacreaColors.orTexte, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          CarteChiffre(titre: 'Ventes', valeur: '${r.nbVentes}'),
          CarteChiffre(titre: 'Panier moyen', valeur: fcfa(r.panierMoyen)),
          if (r.remises > 0) CarteChiffre(titre: 'Remises accordées', valeur: fcfa(r.remises)),
          CarteChiffre(titre: 'Valeur du stock', valeur: fcfa(r.valeurStock), sousTitre: 'aujourd\'hui, au prix d\'achat'),
          CarteChiffre(
            titre: 'Crédits à récupérer',
            valeur: fcfa(r.creditsEnCours),
            sousTitre: 'toutes les clientes',
            couleur: r.creditsEnCours > 0 ? NacreaColors.erreur : null,
          ),
        ],
      ),
      const SizedBox(height: 16),
      // ---------- Courbe des ventes ----------
      _section(
        r.parMois ? 'Ventes par mois' : 'Ventes par jour',
        r.chiffreAffaires == 0
            ? const Text('Aucune vente sur cette période.', style: TextStyle(color: NacreaColors.gris))
            : _Barres(points: r.courbe, parMois: r.parMois),
      ),
      // ---------- Encaissements ----------
      _section(
        'Comment les clientes ont payé',
        Column(
          children: [
            for (final (code, nom) in const [
              ('cash', 'Espèces'),
              ('mobile_money', 'Mobile Money'),
              ('card', 'Carte'),
              ('credit', 'À crédit'),
            ])
              if ((r.parMoyen[code] ?? 0) > 0) _ligne(nom, fcfa(r.parMoyen[code]!)),
            if (r.remboursements > 0) _ligne('Dettes remboursées par les clientes', '+ ${fcfa(r.remboursements)}'),
            if (r.parMoyen.isEmpty && r.remboursements == 0)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Rien sur cette période.', style: TextStyle(color: NacreaColors.gris)),
              ),
          ],
        ),
      ),
      // ---------- Dépenses ----------
      _section(
        'Dépenses par catégorie',
        r.depenses.isEmpty
            ? const Text('Aucune dépense notée sur cette période.', style: TextStyle(color: NacreaColors.gris))
            : _BarresHorizontales(valeurs: {
                for (final e in r.depenses.entries) libelleCategorie(e.key): e.value,
              }),
      ),
      // ---------- Pertes de stock ----------
      if (r.ecartsParMotif.values.any((v) => v < 0))
        _section(
          'Pertes de stock',
          _BarresHorizontales(valeurs: {
            for (final e in r.ecartsParMotif.entries)
              if (e.value < 0) MotifAjustement.depuis(e.key).libelle: -e.value,
          }),
        ),
      // ---------- Par boutique ----------
      if (_toutes && r.parBoutique.length > 1)
        _section("Chiffre d'affaires par boutique", _BarresHorizontales(valeurs: r.parBoutique)),
      // ---------- Meilleurs produits ----------
      _section(
        'Produits les plus vendus',
        r.topProduits.isEmpty
            ? const Text('Aucune vente sur cette période.', style: TextStyle(color: NacreaColors.gris))
            : Column(
                children: [
                  for (final (i, p) in r.topProduits.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text('${i + 1}', style: const TextStyle(color: NacreaColors.gris, fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('${p.quantite} vendu${p.quantite > 1 ? 's' : ''} · marge ${fcfa(p.marge)}',
                                    style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
                              ],
                            ),
                          ),
                          Text(fcfa(p.chiffre), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ];
  }

  Widget _ligne(String titre, String valeur, {bool fort = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(titre,
                  style: TextStyle(fontWeight: fort ? FontWeight.w700 : FontWeight.w400, fontSize: fort ? 16 : 15)),
            ),
            Text(valeur, style: TextStyle(fontWeight: fort ? FontWeight.w700 : FontWeight.w600, fontSize: fort ? 16 : 15)),
          ],
        ),
      );

  Widget _section(String titre, Widget contenu) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(titre, style: NacreaTheme.titre(size: 22)),
                const SizedBox(height: 14),
                contenu,
              ],
            ),
          ),
        ),
      );
}

const _moisCourts = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// Barres verticales d'une seule série (ventes par jour ou par mois).
/// Toucher une barre affiche sa date et son montant.
class _Barres extends StatefulWidget {
  const _Barres({required this.points, required this.parMois});
  final List<PointCourbe> points;
  final bool parMois;

  @override
  State<_Barres> createState() => _BarresState();
}

class _BarresState extends State<_Barres> {
  int? _choisi;

  String _libelle(PointCourbe p, {bool long = false}) {
    final morceaux = p.cle.split('-').map(int.parse).toList();
    if (widget.parMois) return '${_moisCourts[morceaux[1] - 1]}${long ? ' ${morceaux[0]}' : ''}';
    return long ? dateCourte(DateTime(morceaux[0], morceaux[1], morceaux[2])) : '${morceaux[2]}';
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final max = points.fold(0, (m, p) => math.max(m, p.montant));
    final indexMax = points.indexWhere((p) => p.montant == max);
    final choisi = _choisi ?? indexMax;
    // Une étiquette sous l'axe tous les N points, pour ne pas se chevaucher.
    final pas = math.max(1, (points.length / 8).ceil());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Valeur de la barre touchée (par défaut : le meilleur jour)
        Text.rich(TextSpan(children: [
          TextSpan(
            text: fcfa(points[choisi].montant),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: NacreaColors.chocolat),
          ),
          TextSpan(
            text: '  ${_libelle(points[choisi], long: true)}${_choisi == null ? ' · meilleur ${widget.parMois ? 'mois' : 'jour'}' : ''}',
            style: const TextStyle(color: NacreaColors.gris),
          ),
        ])),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: LayoutBuilder(builder: (context, c) {
            final largeur = c.maxWidth / points.length;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, p) in points.indexed)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _choisi = i),
                    child: SizedBox(
                      width: largeur,
                      height: 160,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          // 2 px d'écart entre les barres ; barres fines (36 px au plus)
                          width: math.min(36, math.max(2, largeur - 2)),
                          height: max == 0 ? 0 : math.max(p.montant > 0 ? 3 : 0, 160 * p.montant / max),
                          decoration: BoxDecoration(
                            color: i == choisi ? NacreaColors.prune : NacreaColors.rosePoudre,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
        const Divider(height: 1, color: NacreaColors.bordure),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, p) in points.indexed)
              Expanded(
                child: Text(
                  i % pas == 0 ? _libelle(p) : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(color: NacreaColors.gris, fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Barres horizontales triées (dépenses par catégorie, ventes par boutique).
class _BarresHorizontales extends StatelessWidget {
  const _BarresHorizontales({required this.valeurs});
  final Map<String, int> valeurs;

  @override
  Widget build(BuildContext context) {
    final triees = valeurs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = triees.isEmpty ? 0 : triees.first.value;
    return Column(
      children: [
        for (final e in triees)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(fcfa(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 8,
                      width: max == 0 ? 0 : math.max(4, c.maxWidth * e.value / max),
                      decoration: BoxDecoration(
                        color: NacreaColors.prune,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/accueil_repo.dart';
import '../data/base_locale.dart';
import '../data/produits_repo.dart';
import '../data/rapports_repo.dart';
import '../services/abonnement.dart';
import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../utils/format.dart';
import '../utils/periode.dart';
import '../widgets/carte_chiffre.dart';

/// Une boutique et son abonnement, tels qu'affichés sur l'accueil.
class _BoutiqueAbo {
  _BoutiqueAbo(this.boutique, this.statut, this.finPeriode, this.prixMensuel);
  final Boutique boutique;
  final String? statut;
  final DateTime? finPeriode;
  final int prixMensuel;
}

/// Tableau de bord de la patronne : chiffres du jour, ventes de la semaine,
/// meilleurs produits, alertes, caisses, dernières ventes et boutiques.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.membre, required this.boutiques, this.quandAller});
  final Membre membre;
  final List<Boutique> boutiques;

  /// Ouvre une autre page du menu : 'caisse', 'produits', 'ventes', 'clientes', 'rapports'…
  final void Function(String page)? quandAller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// Lu sur l'appareil (fonctionne hors ligne) et mis à jour en direct.
  late final Stream<List<_BoutiqueAbo>> _boutiques = db
      .watch(
        'SELECT s.id, s.name, s.address, s.phone, a.status, a.current_period_end, a.monthly_price '
        'FROM shops s LEFT JOIN subscriptions a ON a.shop_id = s.id '
        'ORDER BY julianday(s.created_at)',
        triggerOnTables: const ['shops', 'subscriptions'],
      )
      .map((lignes) => [
            for (final l in lignes)
              _BoutiqueAbo(
                Boutique(
                  id: l['id'] as String,
                  nom: l['name'] as String? ?? '',
                  adresse: l['address'] as String?,
                  telephone: l['phone'] as String?,
                ),
                l['status'] as String?,
                DateTime.tryParse(l['current_period_end'] as String? ?? '')?.toLocal(),
                (l['monthly_price'] as int?) ?? 22000,
              ),
          ]);

  late final Stream<Accueil> _accueil = AccueilRepo(compteId: widget.membre.compteId).surveiller();

  void _aller(String page) => widget.quandAller?.call(page);

  Future<void> _ajouter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _BoutiqueDialog(compteId: widget.membre.compteId),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau point de vente créé.')),
      );
    }
  }

  Future<void> _modifier(Boutique b) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _BoutiqueDialog(compteId: widget.membre.compteId, boutique: b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membre;
    final largeur = MediaQuery.sizeOf(context).width;
    final etroit = largeur < 600;
    return ListView(
      padding: EdgeInsets.all(etroit ? 16 : 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EnTeteAccueil(nom: m.nom, entreprise: m.nomCompte, quandAller: _aller),
                const SizedBox(height: 24),
                StreamBuilder<Accueil>(
                  stream: _accueil,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text(messageErreur(snap.error!), style: TextStyle(color: NacreaColors.erreur));
                    }
                    if (!snap.hasData) {
                      return SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                      );
                    }
                    return TableauAccueil(a: snap.data!, quandAller: _aller);
                  },
                ),
                const SizedBox(height: 28),
                // ---------- Boutiques ----------
                StreamBuilder<List<_BoutiqueAbo>>(
                  stream: _boutiques,
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final liste = snap.data!;
                    final total = liste.fold<int>(0, (s, b) => s + b.prixMensuel);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            Text(liste.length > 1 ? 'Vos ${liste.length} boutiques' : 'Votre boutique',
                                style: NacreaTheme.titre(size: 26)),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: _ajouter,
                              icon: const Icon(Icons.add_business_outlined),
                              label: const Text('Ajouter un point de vente'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final b in liste)
                              _CarteBoutique(
                                b,
                                avecAbonnement: true,
                                largeur: etroit ? double.infinity : 300,
                                quandTouche: () => _modifier(b.boutique),
                              ),
                          ],
                        ),
                        if (liste.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Abonnement : ${liste.length} boutique${liste.length > 1 ? 's' : ''} · '
                            '${fcfa(total)} par mois',
                            style: TextStyle(color: NacreaColors.gris, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Morceaux du tableau de bord
// =====================================================================

class _Raccourci extends StatelessWidget {
  const _Raccourci({required this.icone, required this.texte, required this.quandTouche, this.principal = false});
  final IconData icone;
  final String texte;
  final VoidCallback quandTouche;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final style = principal
        ? FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18))
        : OutlinedButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 16));
    return principal
        ? FilledButton.icon(style: style, onPressed: quandTouche, icon: Icon(icone), label: Text(texte))
        : OutlinedButton.icon(style: style, onPressed: quandTouche, icon: Icon(icone), label: Text(texte));
  }
}

/// Une carte titrée du tableau de bord.
class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.child, this.icone, this.action});
  final String titre;
  final IconData? icone;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icone != null) ...[
                  Icon(icone, size: 20, color: NacreaColors.prune),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(titre, style: NacreaTheme.titre(size: 22))),
                ?action,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Bonjour, date et raccourcis.
class EnTeteAccueil extends StatelessWidget {
  const EnTeteAccueil({super.key, required this.nom, required this.entreprise, required this.quandAller});
  final String nom, entreprise;
  final void Function(String) quandAller;

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    final maintenant = DateTime.now();
    final salut = maintenant.hour >= 18 ? 'Bonsoir' : 'Bonjour';
    final date = dateLongue(maintenant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$salut, $nom', style: NacreaTheme.titre(size: etroit ? 32 : 40)),
        const SizedBox(height: 6),
        Text(
          '${date[0].toUpperCase()}${date.substring(1)} · $entreprise',
          style: TextStyle(fontSize: 15, color: NacreaColors.gris),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Raccourci(
              icone: Icons.point_of_sale,
              texte: 'Nouvelle vente',
              principal: true,
              quandTouche: () => quandAller('caisse'),
            ),
            _Raccourci(
              icone: Icons.move_to_inbox_outlined,
              texte: 'Entrée de stock',
              quandTouche: () => quandAller('produits'),
            ),
            _Raccourci(
              icone: Icons.add_box_outlined,
              texte: 'Ajouter un produit',
              quandTouche: () => quandAller('produits'),
            ),
            _Raccourci(
              icone: Icons.insights_outlined,
              texte: 'Rapports',
              quandTouche: () => quandAller('rapports'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Chiffres, graphique, alertes, top produits, caisses et dernières ventes.
class TableauAccueil extends StatelessWidget {
  const TableauAccueil({super.key, required this.a, required this.quandAller});
  final Accueil a;
  final void Function(String) quandAller;

  /// Deux blocs côte à côte sur PC, l'un sous l'autre sur téléphone.
  Widget _paire(bool large, Widget gauche, Widget droite) => large
      ? IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: gauche), const SizedBox(width: 16), Expanded(child: droite)],
          ),
        )
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [gauche, const SizedBox(height: 16), droite]);

  @override
  Widget build(BuildContext context) {
    final jour = a.jour;
    final largeur = MediaQuery.sizeOf(context).width;
    final etroit = largeur < 600;
    final large = largeur >= 900;
    final largeurCarte = etroit ? (largeur - 32 - 12) / 2 : 200.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------- Chiffres du jour ----------
        Text('Aujourd\'hui', style: NacreaTheme.titre(size: 26)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: largeurCarte,
              child: _CarteComparee(
                titre: 'Ventes',
                valeur: jour.chiffreNet,
                hier: a.hier.chiffreNet,
                montant: true,
              ),
            ),
            SizedBox(
              width: largeurCarte,
              child: _CarteComparee(
                titre: jour.benefice >= 0 ? 'Bénéfice' : 'Perte',
                valeur: jour.benefice,
                hier: a.hier.benefice,
                montant: true,
                couleur: jour.benefice >= 0 ? NacreaColors.succes : NacreaColors.erreur,
              ),
            ),
            SizedBox(
              width: largeurCarte,
              child: _CarteComparee(titre: 'Tickets', valeur: jour.nbVentes, hier: a.hier.nbVentes),
            ),
            SizedBox(
              width: largeurCarte,
              child: CarteChiffre(
                titre: 'Ventes du mois',
                valeur: fcfa(a.mois.chiffreNet),
                sousTitre: 'bénéfice ${fcfa(a.mois.benefice)}',
                largeurMin: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _paire(
          large,
          _Bloc(
            titre: 'Ventes des 7 derniers jours',
            icone: Icons.bar_chart,
            action: Text(fcfa(a.semaine.chiffreNet), style: const TextStyle(fontWeight: FontWeight.w700)),
            child: _Graphique7Jours(points: a.semaine.courbe),
          ),
          _Bloc(
            titre: 'À surveiller',
            icone: Icons.notifications_active_outlined,
            child: _Alertes(a: a, quandAller: quandAller),
          ),
        ),
        const SizedBox(height: 16),
        _paire(
          large,
          _Bloc(
            titre: 'Top 5 du mois',
            icone: Icons.emoji_events_outlined,
            child: _TopProduits(produits: a.mois.topProduits.take(5).toList()),
          ),
          _Bloc(
            titre: 'Caisse et dernières ventes',
            icone: Icons.point_of_sale_outlined,
            action: TextButton(onPressed: () => quandAller('ventes'), child: const Text('Tout voir')),
            child: _CaissesEtVentes(a: a),
          ),
        ),
      ],
    );
  }
}

/// Chiffre du jour comparé à la veille.
class _CarteComparee extends StatelessWidget {
  const _CarteComparee(
      {required this.titre, required this.valeur, required this.hier, this.montant = false, this.couleur});
  final String titre;
  final int valeur, hier;
  final bool montant;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final String comparaison;
    Color couleurComp = NacreaColors.gris;
    IconData? fleche;
    if (hier == 0) {
      comparaison = valeur == 0 ? 'comme hier' : 'hier : 0';
    } else {
      final pct = ((valeur - hier) * 100 / hier.abs()).round();
      if (pct == 0) {
        comparaison = 'comme hier';
      } else {
        comparaison = '${pct > 0 ? '+' : ''}$pct % vs hier';
        couleurComp = pct > 0 ? NacreaColors.succes : NacreaColors.erreur;
        fleche = pct > 0 ? Icons.arrow_upward : Icons.arrow_downward;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: NacreaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NacreaColors.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: TextStyle(color: NacreaColors.gris, fontSize: 13)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(montant ? fcfa(valeur) : '$valeur',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: couleur ?? NacreaColors.chocolat)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (fleche != null) Icon(fleche, size: 14, color: couleurComp),
              const SizedBox(width: 2),
              Flexible(
                child: Text(comparaison,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: couleurComp, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Graphique7Jours extends StatelessWidget {
  const _Graphique7Jours({required this.points});
  final List<PointCourbe> points;

  String _court(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(v >= 10000000 ? 0 : 1)} M';
    if (v >= 1000) return '${(v / 1000).round()} k';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final max = points.fold<int>(0, (m, p) => p.montant > m ? p.montant : m);
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < points.length; i++)
            Expanded(
              child: Builder(builder: (context) {
                final p = points[i];
                final date = DateTime.tryParse(p.cle) ?? DateTime.now();
                final aujourdhui = i == points.length - 1;
                final hauteur = max == 0 ? 0.0 : 110 * p.montant / max;
                return Tooltip(
                  message: '${dateCourte(date)} : ${fcfa(p.montant)}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(p.montant == 0 ? '' : _court(p.montant),
                            style: TextStyle(fontSize: 11, color: NacreaColors.gris)),
                        const SizedBox(height: 4),
                        Container(
                          height: hauteur < 4 ? 4 : hauteur,
                          decoration: BoxDecoration(
                            color: aujourdhui
                                ? NacreaColors.prune
                                : (p.montant == 0 ? NacreaColors.bordure : NacreaColors.rosePoudre),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(aujourdhui ? 'Auj.' : initialeJour(date),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: aujourdhui ? FontWeight.w700 : FontWeight.w500,
                                color: aujourdhui ? NacreaColors.prune : NacreaColors.gris)),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _Alertes extends StatelessWidget {
  const _Alertes({required this.a, required this.quandAller});
  final Accueil a;
  final void Function(String) quandAller;

  String _noms(List<ProduitAlerte> l) {
    final premiers = l.take(3).map((p) => p.boutique == null ? p.nom : '${p.nom} (${p.boutique})').join(', ');
    return l.length > 3 ? '$premiers et ${l.length - 3} autre${l.length - 3 > 1 ? 's' : ''}' : premiers;
  }

  @override
  Widget build(BuildContext context) {
    final aujourdhui = DateTime.now();
    final perimes = a.peremptions.where((p) => p.peremption != null && p.peremption!.isBefore(aujourdhui)).length;
    final lignes = <Widget>[
      if (a.stockBas.isNotEmpty)
        _LigneAlerte(
          icone: Icons.inventory_outlined,
          couleur: NacreaColors.erreur,
          fond: NacreaColors.fondErreur,
          titre: '${a.stockBas.length} produit${a.stockBas.length > 1 ? 's' : ''} en stock bas',
          detail: _noms(a.stockBas),
          quandTouche: () => quandAller('produits'),
        ),
      if (a.peremptions.isNotEmpty)
        _LigneAlerte(
          icone: Icons.event_busy_outlined,
          couleur: NacreaColors.orTexte,
          fond: NacreaColors.fondOr,
          titre: perimes > 0
              ? '$perimes produit${perimes > 1 ? 's' : ''} périmé${perimes > 1 ? 's' : ''}, '
                  '${a.peremptions.length - perimes} bientôt'
              : '${a.peremptions.length} produit${a.peremptions.length > 1 ? 's' : ''} à écouler (péremption < 30 jours)',
          detail: _noms(a.peremptions),
          quandTouche: () => quandAller('produits'),
        ),
      if (a.mois.creditsEnCours > 0)
        _LigneAlerte(
          icone: Icons.favorite_border,
          couleur: NacreaColors.prune,
          fond: NacreaColors.nude,
          titre: 'Crédits clientes : ${fcfa(a.mois.creditsEnCours)}',
          detail: 'À relancer depuis la page Clientes',
          quandTouche: () => quandAller('clientes'),
        ),
    ];
    if (lignes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: NacreaColors.succes),
            const SizedBox(height: 8),
            Text('Tout va bien : rien à signaler.', style: TextStyle(color: NacreaColors.gris)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lignes) Padding(padding: const EdgeInsets.only(bottom: 8), child: l),
      ],
    );
  }
}

class _LigneAlerte extends StatelessWidget {
  const _LigneAlerte({
    required this.icone,
    required this.couleur,
    required this.fond,
    required this.titre,
    required this.detail,
    required this.quandTouche,
  });
  final IconData icone;
  final Color couleur, fond;
  final String titre, detail;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: quandTouche,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: couleur),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: TextStyle(fontWeight: FontWeight.w700, color: NacreaColors.chocolat)),
                    const SizedBox(height: 2),
                    Text(detail, style: TextStyle(fontSize: 13, color: NacreaColors.gris)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: NacreaColors.gris),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopProduits extends StatelessWidget {
  const _TopProduits({required this.produits});
  final List<ProduitVendu> produits;

  @override
  Widget build(BuildContext context) {
    if (produits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Aucune vente ce mois-ci pour l\'instant.',
            textAlign: TextAlign.center, style: TextStyle(color: NacreaColors.gris)),
      );
    }
    final max = produits.first.quantite == 0 ? 1 : produits.first.quantite;
    return Column(
      children: [
        for (var i = 0; i < produits.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == 0 ? NacreaColors.or : NacreaColors.nude,
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: i == 0 ? const Color(0xFF2B1D22) : NacreaColors.chocolat)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(produits[i].nom,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: produits[i].quantite / max,
                          minHeight: 6,
                          color: NacreaColors.rosePoudre,
                          backgroundColor: NacreaColors.nude,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${produits[i].quantite} vendu${produits[i].quantite > 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(fcfa(produits[i].chiffre), style: TextStyle(fontSize: 12, color: NacreaColors.gris)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CaissesEtVentes extends StatelessWidget {
  const _CaissesEtVentes({required this.a});
  final Accueil a;

  String _heure(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final aujourdhui = DateTime.now();
    String quand(DateTime d) =>
        d.year == aujourdhui.year && d.month == aujourdhui.month && d.day == aujourdhui.day
            ? _heure(d)
            : '${dateCourte(d).substring(0, 5)} ${_heure(d)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in a.caisses)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.ouverte ? NacreaColors.fondSucces : NacreaColors.nude,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.ouverte ? Icons.lock_open : Icons.lock_outline,
                        size: 16, color: c.ouverte ? NacreaColors.succes : NacreaColors.gris),
                    const SizedBox(width: 6),
                    Text(
                      '${a.caisses.length > 1 ? '${c.boutique} : ' : ''}'
                      '${c.ouverte ? 'caisse ouverte depuis ${quand(c.ouverteLe!)}' : 'caisse fermée'}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ouverte ? NacreaColors.succes : NacreaColors.gris),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (a.dernieresVentes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Pas encore de vente.', textAlign: TextAlign.center, style: TextStyle(color: NacreaColors.gris)),
          )
        else
          for (final v in a.dernieresVentes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 20, color: NacreaColors.gris),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.cliente ?? 'Ticket ${v.ticket}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text([quand(v.date), if (v.boutique != null) v.boutique!].join(' · '),
                            style: TextStyle(fontSize: 12, color: NacreaColors.gris)),
                      ],
                    ),
                  ),
                  Text(fcfa(v.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
      ],
    );
  }
}

class _CarteBoutique extends StatelessWidget {
  const _CarteBoutique(this.b, {required this.avecAbonnement, required this.largeur, this.quandTouche});
  final _BoutiqueAbo b;
  final bool avecAbonnement;
  final double largeur;
  final VoidCallback? quandTouche;

  @override
  Widget build(BuildContext context) {
    // Statut recalculé sur l'appareil (essai terminé → en retard, puis suspendu).
    final effectif = b.statut == null
        ? null
        : EtatAbonnement(statutServeur: b.statut!, fin: b.finPeriode).statut;
    final (texte, couleur, fond) = _statut(effectif, b.finPeriode);
    final boutique = b.boutique;
    return SizedBox(
      width: largeur,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: quandTouche,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_outlined, color: NacreaColors.prune, size: 28),
                    const Spacer(),
                    if (quandTouche != null)
                      Icon(Icons.edit_outlined, color: NacreaColors.gris, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                Text(boutique.nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (boutique.adresse?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(boutique.adresse!, style: TextStyle(color: NacreaColors.gris)),
                ],
                if (boutique.telephone?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(boutique.telephone!, style: TextStyle(color: NacreaColors.gris)),
                ],
                if (avecAbonnement) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
                    child: Text(texte,
                        style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static (String, Color, Color) _statut(String? statut, DateTime? fin) {
    final date = fin == null ? '' : ' jusqu\'au ${dateCourte(fin)}';
    switch (statut) {
      case 'trial':
        return ('Essai gratuit$date', NacreaColors.orTexte, NacreaColors.fondOr);
      case 'active':
        return ('Abonnement actif$date', NacreaColors.succes, NacreaColors.fondSucces);
      case 'late':
        return ('Paiement en retard', NacreaColors.erreur, NacreaColors.fondErreur);
      case 'suspended':
        return ('Suspendu (lecture seule)', NacreaColors.erreur, NacreaColors.fondErreur);
      default:
        return ('Abonnement en préparation…', NacreaColors.gris, NacreaColors.nude);
    }
  }
}

/// Créer un point de vente (en ligne) ou modifier une boutique (fonctionne hors ligne).
class _BoutiqueDialog extends StatefulWidget {
  const _BoutiqueDialog({required this.compteId, this.boutique});
  final String compteId;
  final Boutique? boutique;

  @override
  State<_BoutiqueDialog> createState() => _BoutiqueDialogState();
}

class _BoutiqueDialogState extends State<_BoutiqueDialog> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.boutique?.nom);
  late final _adresse = TextEditingController(text: widget.boutique?.adresse);
  late final _telephone = TextEditingController(text: widget.boutique?.telephone);
  bool _chargement = false;
  String? _erreur;

  bool get _creation => widget.boutique == null;

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    _telephone.dispose();
    super.dispose();
  }

  String? _texte(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _valider() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      if (_creation) {
        // La création passe par le serveur : il prépare l'abonnement (14 jours d'essai).
        await Supabase.instance.client.from('shops').insert({
          'account_id': widget.compteId,
          'name': _nom.text.trim(),
          'address': _texte(_adresse),
          'phone': _texte(_telephone),
        });
      } else {
        await db.execute(
          'UPDATE shops SET name = ?, address = ?, phone = ? WHERE id = ?',
          [_nom.text.trim(), _texte(_adresse), _texte(_telephone), widget.boutique!.id],
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creation ? 'Nouveau point de vente' : 'Modifier la boutique',
          style: NacreaTheme.titre(size: 26)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_creation) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: NacreaColors.fondOr,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Chaque point de vente a son propre stock, sa caisse et ses ventes.\n'
                      'Abonnement : ${fcfa(22000)} par mois, après 14 jours d\'essai gratuit.',
                      style: TextStyle(color: NacreaColors.chocolat),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nom,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la boutique',
                    hintText: 'Boutique de Bè',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez le nom' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _adresse,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (facultatif)',
                    hintText: 'Quartier, rue, repère',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _telephone,
                  keyboardType: TextInputType.phone,
                  onFieldSubmitted: (_) => _valider(),
                  decoration: const InputDecoration(
                    labelText: 'Téléphone (facultatif)',
                    hintText: '+228 90 00 00 00',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'L\'adresse et le téléphone sont imprimés sur les reçus.',
                  style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!, style: TextStyle(color: NacreaColors.erreur)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _chargement ? null : () => Navigator.pop(context, false),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _chargement ? null : _valider,
                        child: _chargement
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(_creation ? 'Créer' : 'Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

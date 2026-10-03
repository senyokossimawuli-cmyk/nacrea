import 'package:flutter/material.dart';

import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import 'entree_stock_dialog.dart';
import 'produit_form.dart';

/// Vignette photo d'un produit (ou icône si pas de photo).
class PhotoProduit extends StatelessWidget {
  const PhotoProduit({super.key, this.url, this.taille = 56});
  final String? url;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final vide = Container(
      width: taille,
      height: taille,
      color: NacreaColors.nude,
      child: Icon(Icons.spa_outlined, color: NacreaColors.rosePoudre, size: taille * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url == null
          ? vide
          : Image.network(
              url!,
              width: taille,
              height: taille,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => vide,
            ),
    );
  }
}

enum _Filtre { tous, rupture, stockBas, peremption }

class ProduitsPage extends StatefulWidget {
  const ProduitsPage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<ProduitsPage> createState() => _ProduitsPageState();
}

class _ProduitsPageState extends State<ProduitsPage> {
  late final _repo = ProduitsRepo(compteId: widget.membre.compteId);
  // Liste en direct : se met à jour seule après une vente, une réception ou une synchronisation.
  late Stream<List<Produit>> _produits = _repo.surveillerProduits(widget.boutique.id);
  final _recherche = TextEditingController();
  _Filtre _filtre = _Filtre.tous;
  String? _categorie;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _recharger() => setState(() => _produits = _repo.surveillerProduits(widget.boutique.id));

  Future<void> _ouvrirFormulaire([Produit? produit]) async {
    final change = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProduitForm(
          repo: _repo,
          membre: widget.membre,
          boutique: widget.boutique,
          produit: produit,
        ),
      ),
    );
    if (change == true) _recharger();
  }

  Future<void> _ajouterStock(Produit p) async {
    final ok = await ouvrirEntreeStock(
      context,
      repo: _repo,
      boutique: widget.boutique,
      produit: p,
      peutVoirCouts: widget.membre.peutVoirCouts,
    );
    if (ok) {
      _recharger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stock ajouté pour ${p.nomComplet}')),
        );
      }
    }
  }

  List<Produit> _filtrer(List<Produit> tous) {
    final q = _recherche.text.trim().toLowerCase();
    return tous.where((p) {
      if (_categorie != null && p.categorieId != _categorie) return false;
      switch (_filtre) {
        case _Filtre.rupture:
          if (!p.enRupture) return false;
        case _Filtre.stockBas:
          if (!p.stockBas) return false;
        case _Filtre.peremption:
          if (!(p.peremptionProche || p.perime)) return false;
        case _Filtre.tous:
          break;
      }
      if (q.isEmpty) return true;
      return p.nom.toLowerCase().contains(q) ||
          (p.marque?.toLowerCase().contains(q) ?? false) ||
          (p.variante?.toLowerCase().contains(q) ?? false) ||
          (p.codeBarres?.contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Produit>>(
      stream: _produits,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(messageErreur(snap.error!)),
                const SizedBox(height: 12),
                TextButton(onPressed: _recharger, child: const Text('Réessayer')),
              ],
            ),
          );
        }
        final tous = snap.data!;
        if (tous.isEmpty) return _videAccueil();

        final visibles = _filtrer(tous);
        final categories = <String, String>{
          for (final p in tous)
            if (p.categorieId != null) p.categorieId!: p.categorieNom ?? '',
        };
        final nbRupture = tous.where((p) => p.enRupture).length;
        final nbBas = tous.where((p) => p.stockBas).length;
        final nbPeremption = tous.where((p) => p.peremptionProche || p.perime).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Produits', style: NacreaTheme.titre(size: 36)),
                      Text('${tous.length} produits · stock de ${widget.boutique.nom}',
                          style: const TextStyle(color: NacreaColors.gris)),
                    ],
                  ),
                  SizedBox(
                    width: 240,
                    child: FilledButton.icon(
                      onPressed: () => _ouvrirFormulaire(),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un produit'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _recherche,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher un nom, une marque, un code-barres…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _recherche.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_recherche.clear),
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  _puce('Tous', _filtre == _Filtre.tous && _categorie == null, () {
                    setState(() {
                      _filtre = _Filtre.tous;
                      _categorie = null;
                    });
                  }),
                  _puce('En rupture ($nbRupture)', _filtre == _Filtre.rupture,
                      () => setState(() => _filtre = _Filtre.rupture)),
                  _puce('Stock bas ($nbBas)', _filtre == _Filtre.stockBas,
                      () => setState(() => _filtre = _Filtre.stockBas)),
                  _puce('Péremption proche ($nbPeremption)', _filtre == _Filtre.peremption,
                      () => setState(() => _filtre = _Filtre.peremption)),
                  for (final c in categories.entries)
                    _puce(c.value, _categorie == c.key,
                        () => setState(() => _categorie = _categorie == c.key ? null : c.key)),
                ],
              ),
            ),
            Expanded(
              child: visibles.isEmpty
                  ? const Center(
                      child: Text('Aucun produit ne correspond.',
                          style: TextStyle(color: NacreaColors.gris)),
                    )
                  : RefreshIndicator(
                      color: NacreaColors.prune,
                      onRefresh: () async {
                        _recharger();
                        await Future<void>.delayed(const Duration(milliseconds: 300));
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: visibles.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _LigneProduit(
                          produit: visibles[i],
                          quandOuvert: () => _ouvrirFormulaire(visibles[i]),
                          quandStock: () => _ajouterStock(visibles[i]),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _puce(String texte, bool actif, VoidCallback quandTouche) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(texte),
        selected: actif,
        onSelected: (_) => quandTouche(),
        showCheckmark: false,
        selectedColor: NacreaColors.prune,
        backgroundColor: Colors.white,
        side: BorderSide(color: actif ? NacreaColors.prune : NacreaColors.bordure),
        labelStyle: TextStyle(
          color: actif ? Colors.white : NacreaColors.chocolat,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _videAccueil() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.spa_outlined, size: 56, color: NacreaColors.rosePoudre),
              const SizedBox(height: 16),
              Text('Ajoutez votre premier produit', style: NacreaTheme.titre(size: 30)),
              const SizedBox(height: 8),
              const Text(
                'Photo, prix et stock : votre catalogue se construit ici, '
                'puis il sera prêt pour la caisse.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NacreaColors.gris, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _ouvrirFormulaire(),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un produit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LigneProduit extends StatelessWidget {
  const _LigneProduit({required this.produit, required this.quandOuvert, required this.quandStock});
  final Produit produit;
  final VoidCallback quandOuvert;
  final VoidCallback quandStock;

  @override
  Widget build(BuildContext context) {
    final p = produit;
    final details = [p.marque, p.categorieNom].whereType<String>().where((s) => s.isNotEmpty);
    final large = MediaQuery.sizeOf(context).width >= 700;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: quandOuvert,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PhotoProduit(url: p.photoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nomComplet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (details.isNotEmpty)
                      Text(details.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: _badges(p)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fcfa(p.prixVente),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('Stock : ${milliers(p.stock)}',
                      style: TextStyle(
                        color: p.enRupture ? NacreaColors.erreur : NacreaColors.gris,
                        fontWeight: p.enRupture ? FontWeight.w600 : FontWeight.w400,
                      )),
                ],
              ),
              const SizedBox(width: 12),
              large
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: quandStock,
                      icon: const Icon(Icons.add_box_outlined, size: 20),
                      label: const Text('Stock'),
                    )
                  : IconButton(
                      tooltip: 'Ajouter du stock',
                      onPressed: quandStock,
                      icon: const Icon(Icons.add_box_outlined, color: NacreaColors.prune),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _badges(Produit p) {
    Widget badge(String t, Color c, Color f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: f, borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
        );
    const rouge = Color(0xFFFCEBEB);
    const ambre = Color(0xFFF7EEDB);
    return [
      if (p.enRupture) badge('Rupture', NacreaColors.erreur, rouge),
      if (p.stockBas) badge('Stock bas', NacreaColors.orTexte, ambre),
      if (p.perime) badge('Lot périmé', NacreaColors.erreur, rouge),
      if (p.peremptionProche)
        badge('Expire le ${dateCourte(p.prochainePeremption!)}', NacreaColors.orTexte, ambre),
    ];
  }
}

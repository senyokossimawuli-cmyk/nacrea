import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/produits_repo.dart';
import '../../data/ventes_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../produits/produits_page.dart';
import 'paiement_dialog.dart';
import 'ticket_dialog.dart';

/// Remise maximale qu'une employée peut accorder sans la patronne.
const remiseMaxEmployeePourcent = 10;

class CaissePage extends StatefulWidget {
  const CaissePage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<CaissePage> createState() => _CaissePageState();
}

class _CaissePageState extends State<CaissePage> {
  late final _produitsRepo = ProduitsRepo(compteId: widget.membre.compteId);
  late final _ventesRepo = VentesRepo(boutique: widget.boutique);
  late Future<List<Produit>> _produits = _produitsRepo.produitsAvecStock(widget.boutique.id);

  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode();
  final List<LignePanier> _panier = [];
  int _remise = 0;
  bool _enregistrement = false;

  @override
  void dispose() {
    _recherche.dispose();
    _focusRecherche.dispose();
    super.dispose();
  }

  int get _sousTotal => _panier.fold(0, (s, l) => s + l.total);
  int get _total => (_sousTotal - _remise).clamp(0, 1 << 31);
  int get _nbArticles => _panier.fold(0, (s, l) => s + l.quantite);

  void _message(String texte) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte), duration: const Duration(seconds: 2)));
  }

  void _ajouter(Produit p) {
    setState(() {
      final existante = _panier.where((l) => l.produit.id == p.id && !l.prixModifie);
      if (existante.isNotEmpty) {
        existante.first.quantite++;
      } else {
        _panier.add(LignePanier(produit: p));
      }
      _remise = _remise.clamp(0, _sousTotal);
    });
    final dansPanier = _panier.where((l) => l.produit.id == p.id).fold(0, (s, l) => s + l.quantite);
    if (dansPanier > p.stock) {
      _message('Attention : seulement ${p.stock < 0 ? 0 : p.stock} en stock pour ${p.nomComplet}.');
    }
    _recherche.clear();
    _focusRecherche.requestFocus();
  }

  /// Entrée dans la recherche : un code-barres exact ou un seul résultat → ajout direct.
  void _valider(List<Produit> tous) {
    final q = _recherche.text.trim();
    if (q.isEmpty) return;
    final parCode = tous.where((p) => p.codeBarres == q).toList();
    if (parCode.length == 1) return _ajouter(parCode.first);
    final resultats = _filtrer(tous);
    if (resultats.length == 1) return _ajouter(resultats.first);
    if (resultats.isEmpty) _message('Aucun produit trouvé pour « $q ».');
  }

  List<Produit> _filtrer(List<Produit> tous) {
    final q = _recherche.text.trim().toLowerCase();
    if (q.isEmpty) return tous;
    return tous
        .where((p) =>
            p.nom.toLowerCase().contains(q) ||
            (p.marque?.toLowerCase().contains(q) ?? false) ||
            (p.variante?.toLowerCase().contains(q) ?? false) ||
            (p.codeBarres?.contains(q) ?? false))
        .toList();
  }

  void _changerQuantite(LignePanier l, int delta) {
    setState(() {
      l.quantite += delta;
      if (l.quantite <= 0) _panier.remove(l);
      _remise = _remise.clamp(0, _sousTotal);
    });
  }

  Future<void> _modifierLigne(LignePanier l) async {
    final patronne = widget.membre.estPatronne;
    final qte = TextEditingController(text: '${l.quantite}');
    final prix = TextEditingController(text: '${l.prixUnitaire}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(l.produit.nomComplet),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: qte,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Quantité'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: prix,
                  enabled: patronne,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Prix unitaire', suffixText: 'FCFA'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: Text('Prix normal · ${fcfa(l.produit.prixVente)}'),
                      onPressed: () => setD(() => prix.text = '${l.produit.prixVente}'),
                    ),
                    if (l.produit.prixGros != null)
                      ActionChip(
                        label: Text('Prix de gros · ${fcfa(l.produit.prixGros!)}'),
                        onPressed: () => setD(() => prix.text = '${l.produit.prixGros}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Valider')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      final q = int.tryParse(qte.text) ?? l.quantite;
      final p = int.tryParse(prix.text) ?? l.prixUnitaire;
      if (q <= 0) {
        _panier.remove(l);
      } else {
        l.quantite = q;
        l.prixUnitaire = p;
      }
      _remise = _remise.clamp(0, _sousTotal);
    });
    _focusRecherche.requestFocus();
  }

  Future<void> _choisirRemise() async {
    final patronne = widget.membre.estPatronne;
    final champ = TextEditingController();
    var enPourcent = true;
    final valeur = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final saisi = int.tryParse(champ.text) ?? 0;
          final montant = enPourcent ? (_sousTotal * saisi / 100).round() : saisi;
          final pourcent = _sousTotal == 0 ? 0 : montant * 100 / _sousTotal;
          final tropElevee = !patronne && pourcent > remiseMaxEmployeePourcent;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Remise sur la vente'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('En %')),
                      ButtonSegment(value: false, label: Text('En FCFA')),
                    ],
                    selected: {enPourcent},
                    onSelectionChanged: (s) => setD(() => enPourcent = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: champ,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setD(() {}),
                    decoration: InputDecoration(
                      labelText: 'Remise',
                      suffixText: enPourcent ? '%' : 'FCFA',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Remise : ${fcfa(montant)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (tropElevee)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Au-delà de $remiseMaxEmployeePourcent %, la remise doit être faite par la patronne.',
                        style: TextStyle(color: NacreaColors.erreur),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(0), child: const Text('Aucune remise')),
              TextButton(
                onPressed: tropElevee || montant > _sousTotal ? null : () => Navigator.of(ctx).pop(montant),
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (valeur != null) setState(() => _remise = valeur);
    _focusRecherche.requestFocus();
  }

  Future<void> _encaisser() async {
    if (_panier.isEmpty || _enregistrement) return;
    final reglement = await ouvrirPaiement(context, _total);
    if (reglement == null || !mounted) return;

    setState(() => _enregistrement = true);
    try {
      final lignes = List<LignePanier>.of(_panier);
      final sousTotal = _sousTotal;
      final remise = _remise;
      final resultat = await _ventesRepo.enregistrer(
        panier: lignes,
        paiements: reglement.paiements,
        remise: remise,
      );
      if (!mounted) return;
      setState(() {
        _panier.clear();
        _remise = 0;
        _produits = _produitsRepo.produitsAvecStock(widget.boutique.id);
      });
      await afficherTicket(
        context,
        Ticket(
          boutique: widget.boutique.nom,
          numero: resultat.ticket,
          date: DateTime.now(),
          lignes: [
            for (final l in lignes)
              LigneVente(nom: l.produit.nomComplet, quantite: l.quantite, prixUnitaire: l.prixUnitaire, remise: 0),
          ],
          sousTotal: sousTotal,
          remise: remise,
          total: resultat.total,
          paiements: {for (final p in reglement.paiements) p.moyen.code: p.montant},
          recuEspeces: reglement.recuEspeces,
          monnaie: reglement.monnaie,
          vendeuse: widget.membre.nom,
        ),
      );
    } catch (e) {
      if (mounted) _message(messageErreur(e));
    } finally {
      if (mounted) {
        setState(() => _enregistrement = false);
        _focusRecherche.requestFocus();
      }
    }
  }

  // ---------------------------------------------------------------- Affichage

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Produit>>(
      future: _produits,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(messageErreur(snap.error!)),
                TextButton(
                  onPressed: () => setState(
                      () => _produits = _produitsRepo.produitsAvecStock(widget.boutique.id)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          );
        }
        final tous = snap.data;
        final large = MediaQuery.sizeOf(context).width >= 1000;
        final catalogue = _catalogue(tous);

        if (large) {
          return Row(
            children: [
              Expanded(child: catalogue),
              Container(
                width: 400,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(left: BorderSide(color: NacreaColors.bordure)),
                ),
                child: _panneauPanier(),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: catalogue),
            _barreBas(),
          ],
        );
      },
    );
  }

  Widget _catalogue(List<Produit>? tous) {
    final visibles = tous == null ? const <Produit>[] : _filtrer(tous);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: TextField(
            controller: _recherche,
            focusNode: _focusRecherche,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            // Garde le curseur dans la recherche après chaque scan.
            onEditingComplete: () {},
            onSubmitted: (_) {
              if (tous != null) _valider(tous);
            },
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              hintText: 'Scannez un code-barres ou cherchez un produit…',
              prefixIcon: const Icon(Icons.qr_code_scanner),
              suffixIcon: _recherche.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(_recherche.clear);
                        _focusRecherche.requestFocus();
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: tous == null
              ? const Center(child: CircularProgressIndicator(color: NacreaColors.prune))
              : visibles.isEmpty
                  ? Center(
                      child: Text(
                        tous.isEmpty
                            ? 'Ajoutez d\'abord des produits dans « Produits ».'
                            : 'Aucun produit trouvé.',
                        style: const TextStyle(color: NacreaColors.gris),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisExtent: 236,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: visibles.length,
                      itemBuilder: (_, i) => _TuileProduit(
                        produit: visibles[i],
                        quandTouche: () => _ajouter(visibles[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _barreBas() {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_nbArticles article${_nbArticles > 1 ? 's' : ''}',
                        style: const TextStyle(color: NacreaColors.gris)),
                    Text(fcfa(_total),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              SizedBox(
                width: 180,
                child: FilledButton(
                  onPressed: _panier.isEmpty
                      ? null
                      : () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.white,
                            builder: (_) => FractionallySizedBox(
                              heightFactor: 0.85,
                              child: StatefulBuilder(
                                builder: (ctx, setS) => _panneauPanier(rafraichir: () => setS(() {})),
                              ),
                            ),
                          ).then((_) => setState(() {})),
                  child: const Text('Voir le panier'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [rafraichir] sert quand le panier est affiché dans une feuille séparée (téléphone).
  Widget _panneauPanier({VoidCallback? rafraichir}) {
    void maj(VoidCallback f) {
      f();
      rafraichir?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
          child: Row(
            children: [
              Text('Panier', style: NacreaTheme.titre(size: 28)),
              const SizedBox(width: 8),
              if (_nbArticles > 0)
                Text('($_nbArticles)', style: const TextStyle(color: NacreaColors.gris)),
              const Spacer(),
              if (_panier.isNotEmpty)
                TextButton(
                  onPressed: () => maj(() => setState(() {
                        _panier.clear();
                        _remise = 0;
                      })),
                  child: const Text('Vider'),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: NacreaColors.bordure),
        Expanded(
          child: _panier.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Touchez un produit ou scannez son code-barres pour l\'ajouter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: NacreaColors.gris, height: 1.5),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _panier.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (_, i) {
                    final l = _panier[i];
                    return InkWell(
                      onTap: () async {
                        await _modifierLigne(l);
                        rafraichir?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.produit.nomComplet,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    '${fcfa(l.prixUnitaire)}${l.prixModifie ? ' (prix modifié)' : ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: l.prixModifie ? NacreaColors.orTexte : NacreaColors.gris,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _BoutonRond(
                              icone: Icons.remove,
                              aide: 'Retirer un',
                              quandTouche: () => maj(() => _changerQuantite(l, -1)),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text('${l.quantite}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            _BoutonRond(
                              icone: Icons.add,
                              aide: 'Ajouter un',
                              quandTouche: () => maj(() => _changerQuantite(l, 1)),
                            ),
                            SizedBox(
                              width: 92,
                              child: Text(fcfa(l.total),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: NacreaColors.page,
            border: Border(top: BorderSide(color: NacreaColors.bordure)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Sous-total'),
                  const Spacer(),
                  Text(fcfa(_sousTotal)),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: _panier.isEmpty
                        ? null
                        : () async {
                            await _choisirRemise();
                            rafraichir?.call();
                          },
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: Text(_remise > 0 ? 'Remise' : 'Ajouter une remise'),
                  ),
                  const Spacer(),
                  if (_remise > 0)
                    Text('- ${fcfa(_remise)}', style: const TextStyle(color: NacreaColors.orTexte)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Total', style: NacreaTheme.titre(size: 28)),
                  const Spacer(),
                  Text(fcfa(_total),
                      style: NacreaTheme.titre(size: 34, color: NacreaColors.prune)),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _panier.isEmpty || _enregistrement
                    ? null
                    : () async {
                        if (rafraichir != null) Navigator.of(context).pop();
                        await _encaisser();
                      },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                child: _enregistrement
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Encaisser', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TuileProduit extends StatelessWidget {
  const _TuileProduit({required this.produit, required this.quandTouche});
  final Produit produit;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    final p = produit;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: quandTouche,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 120,
              child: p.photoUrl == null
                  ? const ColoredBox(
                      color: NacreaColors.nude,
                      child: Icon(Icons.spa_outlined, color: NacreaColors.rosePoudre, size: 40),
                    )
                  : Image.network(
                      p.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const PhotoProduit(taille: 120),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nomComplet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2)),
                    const Spacer(),
                    Text(fcfa(p.prixVente),
                        style: const TextStyle(
                            color: NacreaColors.prune, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                      p.enRupture ? 'Rupture' : 'Stock : ${p.stock}',
                      style: TextStyle(
                        fontSize: 12,
                        color: p.enRupture ? NacreaColors.erreur : NacreaColors.gris,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icone, required this.aide, required this.quandTouche});
  final IconData icone;
  final String aide;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: aide,
      onPressed: quandTouche,
      icon: Icon(icone, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: NacreaColors.prune,
        side: const BorderSide(color: NacreaColors.bordure),
        minimumSize: const Size(40, 40),
      ),
    );
  }
}

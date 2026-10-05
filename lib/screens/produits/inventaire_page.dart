import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/produits_repo.dart';
import '../../data/stock_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/scanner_camera.dart';

enum _Filtre { tous, aCompter, comptes, ecarts }

/// Inventaire : on compte les produits en rayon, puis on valide.
/// Le comptage est gardé sur l'appareil (on peut fermer et reprendre plus tard).
class InventairePage extends StatefulWidget {
  const InventairePage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<InventairePage> createState() => _InventairePageState();
}

class _InventairePageState extends State<InventairePage> {
  late final _repo = StockRepo(boutiqueId: widget.boutique.id, compteId: widget.membre.compteId);
  late final Stream<List<LigneInventaire>> _lignes = _repo.surveillerInventaire();
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode();
  final Map<String, TextEditingController> _champs = {};
  _Filtre _filtre = _Filtre.tous;
  List<LigneInventaire> _dernieres = const [];

  @override
  void dispose() {
    _recherche.dispose();
    _focusRecherche.dispose();
    for (final c in _champs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Champ « compté » d'un produit (créé une fois ; un scan le met à jour directement).
  TextEditingController _champ(LigneInventaire l) =>
      _champs.putIfAbsent(l.produitId, () => TextEditingController(text: l.compte?.toString() ?? ''));

  void _message(String texte) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte), duration: const Duration(seconds: 2)));
  }

  /// Un scan = un article compté (+1).
  Future<void> _compterCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return;
    final l = _dernieres.where((x) => x.codeBarres?.trim() == c).firstOrNull;
    if (l == null) {
      _message('Code-barres inconnu ($c).');
      return;
    }
    final nouveau = (l.compte ?? 0) + 1;
    _champs[l.produitId]?.text = '$nouveau';
    await _repo.compter(l.produitId, nouveau);
    _message('${l.nom} : $nouveau');
  }

  Future<void> _scanner() async {
    final code = await scannerCodeBarres(context);
    if (code != null && mounted) await _compterCode(code);
  }

  Future<void> _abandonner() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Effacer le comptage ?'),
        content: const Text('Tout ce qui a été compté sera effacé. Le stock ne change pas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.abandonnerInventaire();
      for (final c in _champs.values) {
        c.clear();
      }
    }
  }

  Future<void> _valider(List<LigneInventaire> lignes) async {
    final comptees = lignes.where((l) => l.compteFait).toList();
    final ecarts = comptees.where((l) => l.ecart != 0).toList()
      ..sort((a, b) => a.valeurEcart.compareTo(b.valeurEcart));
    final total = ecarts.fold(0, (s, l) => s + l.valeurEcart);
    final couts = widget.membre.peutVoirCouts;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Valider l\'inventaire ?', style: NacreaTheme.titre(size: 26)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${comptees.length} produit${comptees.length > 1 ? 's' : ''} compté${comptees.length > 1 ? 's' : ''}, '
                    '${ecarts.length} avec un écart.'),
                if (couts && ecarts.isNotEmpty)
                  Text(
                    'Valeur des écarts : ${total > 0 ? '+' : ''}${fcfa(total)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: total < 0 ? NacreaColors.erreur : NacreaColors.succes,
                    ),
                  ),
                const SizedBox(height: 12),
                for (final l in ecarts.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(l.nom, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text('${l.attendu} → ${l.compte}  (${l.ecart > 0 ? '+' : ''}${l.ecart})',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: l.ecart < 0 ? NacreaColors.erreur : NacreaColors.succes,
                            )),
                      ],
                    ),
                  ),
                if (ecarts.length > 12) Text('… et ${ecarts.length - 12} autres', style: const TextStyle(color: NacreaColors.gris)),
                const SizedBox(height: 12),
                const Text(
                  'Le stock de ces produits sera remplacé par ce que vous avez compté. '
                  'Les produits non comptés ne changent pas.',
                  style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note (facultatif)', hintText: 'Inventaire de fin de mois'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer à compter')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final valeur = await _repo.validerInventaire(
        note: note.text,
        userId: Supabase.instance.client.auth.currentUser?.id ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(couts && valeur != 0
            ? 'Inventaire validé. Écart : ${valeur > 0 ? '+' : ''}${fcfa(valeur)}.'
            : 'Inventaire validé.'),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _message(messageErreur(e));
    }
  }

  Future<void> _historique() async {
    final inventaires = await _repo.inventaires();
    final ajustements = await _repo.historique();
    if (!mounted) return;
    final couts = widget.membre.peutVoirCouts;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, defilement) => ListView(
          controller: defilement,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Inventaires', style: NacreaTheme.titre(size: 24)),
            if (inventaires.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun inventaire validé.', style: TextStyle(color: NacreaColors.gris)),
              ),
            for (final i in inventaires)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fact_check_outlined, color: NacreaColors.prune),
                title: Text('${dateCourte(i.le)} · ${i.nbProduits} comptés, ${i.nbEcarts} écarts'),
                subtitle: i.note == null ? null : Text(i.note!),
                trailing: couts
                    ? Text(fcfa(i.valeur),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: i.valeur < 0 ? NacreaColors.erreur : NacreaColors.chocolat,
                        ))
                    : null,
              ),
            const SizedBox(height: 16),
            Text('Derniers ajustements', style: NacreaTheme.titre(size: 24)),
            if (ajustements.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucun ajustement.', style: TextStyle(color: NacreaColors.gris)),
              ),
            for (final a in ajustements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${a.quantite > 0 ? '+' : ''}${a.quantite} · ${a.produit}'),
                subtitle: Text([dateCourte(a.le), a.motif.libelle, if (a.note != null) a.note!].join(' · ')),
                trailing: couts
                    ? Text(fcfa(a.valeur),
                        style: TextStyle(color: a.valeur < 0 ? NacreaColors.erreur : NacreaColors.chocolat))
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final couts = widget.membre.peutVoirCouts;
    return Scaffold(
      appBar: AppBar(
        title: Text('Inventaire · ${widget.boutique.nom}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Historique', onPressed: _historique, icon: const Icon(Icons.history)),
          IconButton(tooltip: 'Effacer le comptage', onPressed: _abandonner, icon: const Icon(Icons.restart_alt)),
        ],
      ),
      body: StreamBuilder<List<LigneInventaire>>(
        stream: _lignes,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
          }
          final lignes = snap.data!;
          _dernieres = lignes;
          final q = _recherche.text.trim().toLowerCase();
          final visibles = lignes.where((l) {
            final ok = switch (_filtre) {
              _Filtre.tous => true,
              _Filtre.aCompter => !l.compteFait,
              _Filtre.comptes => l.compteFait,
              _Filtre.ecarts => l.compteFait && l.ecart != 0,
            };
            return ok && (q.isEmpty || l.nom.toLowerCase().contains(q) || (l.codeBarres?.contains(q) ?? false));
          }).toList();
          final comptees = lignes.where((l) => l.compteFait).toList();
          final ecarts = comptees.where((l) => l.ecart != 0).toList();
          final valeur = ecarts.fold(0, (s, l) => s + l.valeurEcart);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _recherche,
                  focusNode: _focusRecherche,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) async {
                    // Douchette : le code exact compte un article, puis on vide le champ.
                    if (lignes.any((l) => l.codeBarres?.trim() == v.trim())) {
                      await _compterCode(v);
                      _recherche.clear();
                      setState(() {});
                    }
                    _focusRecherche.requestFocus();
                  },
                  decoration: InputDecoration(
                    hintText: 'Scannez (1 scan = 1 article) ou cherchez un produit…',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: scanCameraDisponible
                        ? IconButton(
                            tooltip: 'Scanner avec la caméra',
                            icon: const Icon(Icons.photo_camera_outlined, color: NacreaColors.prune),
                            onPressed: _scanner,
                          )
                        : null,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (f, nom) in [
                      (_Filtre.tous, 'Tous (${lignes.length})'),
                      (_Filtre.aCompter, 'À compter (${lignes.length - comptees.length})'),
                      (_Filtre.comptes, 'Comptés (${comptees.length})'),
                      (_Filtre.ecarts, 'Écarts (${ecarts.length})'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(nom),
                          selected: _filtre == f,
                          onSelected: (_) => setState(() => _filtre = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visibles.isEmpty
                    ? const Center(child: Text('Aucun produit ici.', style: TextStyle(color: NacreaColors.gris)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: visibles.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: NacreaColors.bordure),
                        itemBuilder: (context, i) {
                          final l = visibles[i];
                          final champ = _champ(l);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(
                                        'Logiciel : ${l.attendu}'
                                        '${l.compteFait && l.ecart != 0 ? '  ·  écart ${l.ecart > 0 ? '+' : ''}${l.ecart}' : ''}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: l.compteFait && l.ecart != 0
                                              ? (l.ecart < 0 ? NacreaColors.erreur : NacreaColors.succes)
                                              : NacreaColors.gris,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 96,
                                  child: TextField(
                                    controller: champ,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      hintText: 'Compté',
                                      isDense: true,
                                      filled: true,
                                      fillColor: l.compteFait ? const Color(0xFFE5F3EA) : Colors.white,
                                    ),
                                    onChanged: (v) => _repo.compter(l.produitId, int.tryParse(v)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Material(
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${comptees.length} / ${lignes.length} comptés',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                '${ecarts.length} écart${ecarts.length > 1 ? 's' : ''}'
                                '${couts && ecarts.isNotEmpty ? ' · ${valeur > 0 ? '+' : ''}${fcfa(valeur)}' : ''}',
                                style: TextStyle(color: valeur < 0 ? NacreaColors.erreur : NacreaColors.gris),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: comptees.isEmpty ? null : () => _valider(lignes),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Valider'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/import_excel.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

/// Import de tous les produits en une fois depuis un tableau Excel (ou CSV).
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final _repo = ProduitsRepo(compteId: widget.membre.compteId);
  String? _fichier;
  List<LigneImport>? _lignes;
  List<Produit> _existants = [];
  bool _mettreAJour = true;
  bool _travail = false;
  int _fait = 0;
  String? _erreur;

  void _dire(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _telechargerModele() async {
    try {
      final chemin = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le modèle YDS Beauty',
        fileName: 'Modele-produits-YDS-Beauty.xlsx',
        bytes: modeleExcel(),
      );
      if (chemin != null && mounted) {
        _dire('Modèle enregistré. Ouvrez-le avec Excel, remplissez-le, puis importez-le ici.');
      }
    } catch (e) {
      if (mounted) _dire(messageErreur(e));
    }
  }

  Future<void> _choisir() async {
    setState(() => _erreur = null);
    try {
      final fichiers = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
      if (fichiers.isEmpty) return;
      final f = fichiers.first;
      final octets = await f.readAsBytes();
      final lignes = lireFichier(octets, f.name);
      final existants = await _repo.produitsAvecStock(widget.boutique.id);
      setState(() {
        _fichier = f.name;
        _lignes = lignes;
        _existants = existants;
      });
    } catch (e) {
      setState(() => _erreur = messageErreur(e));
    }
  }

  /// Produit déjà enregistré : même code-barres, sinon même nom + variante.
  Produit? _existant(LigneImport l) {
    String cle(String n, String? v) => '${n.trim().toLowerCase()}|${(v ?? '').trim().toLowerCase()}';
    for (final p in _existants) {
      if (l.codeBarres != null && p.codeBarres?.trim() == l.codeBarres) return p;
    }
    for (final p in _existants) {
      if (cle(p.nom, p.variante) == cle(l.nom, l.variante)) return p;
    }
    return null;
  }

  Future<void> _importer() async {
    final valides = _lignes!.where((l) => l.valide).toList();
    setState(() {
      _travail = true;
      _fait = 0;
      _erreur = null;
    });
    var crees = 0, majs = 0, ignores = 0;
    try {
      final categories = {for (final c in await _repo.categories()) c.nom.trim().toLowerCase(): c.id};
      for (final l in valides) {
        String? categorieId;
        if (l.categorie != null) {
          final k = l.categorie!.trim().toLowerCase();
          categorieId = categories[k] ??= (await _repo.creerCategorie(l.categorie!.trim())).id;
        }
        final ancien = _existant(l);
        if (ancien != null && !_mettreAJour) {
          ignores++;
        } else {
          final id = await _repo.enregistrer(Produit(
            id: ancien?.id,
            nom: l.nom,
            marque: l.marque ?? ancien?.marque,
            variante: l.variante ?? ancien?.variante,
            codeBarres: l.codeBarres ?? ancien?.codeBarres,
            photoUrl: ancien?.photoUrl,
            prixAchat: l.prixAchat ?? ancien?.prixAchat ?? 0,
            prixVente: l.prixVente ?? ancien?.prixVente ?? 0,
            prixGros: l.prixGros ?? ancien?.prixGros,
            stockMin: l.stockMin ?? ancien?.stockMin ?? 0,
            categorieId: categorieId ?? ancien?.categorieId,
          ));
          if ((l.stock ?? 0) > 0) {
            await _repo.entreeStock(
              boutiqueId: widget.boutique.id,
              produitId: id,
              quantite: l.stock!,
              prixAchat: l.prixAchat ?? ancien?.prixAchat ?? 0,
              peremption: l.peremption,
              motif: 'Import Excel',
            );
          }
          ancien == null ? crees++ : majs++;
        }
        if (mounted) setState(() => _fait++);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Import terminé'),
          content: Text([
            '$crees produit${crees > 1 ? 's' : ''} créé${crees > 1 ? 's' : ''}',
            if (majs > 0) '$majs mis à jour',
            if (ignores > 0) '$ignores déjà présents, laissés tels quels',
          ].join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voir mes produits'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = '${messageErreur(e)} ($_fait lignes importées avant l\'erreur)');
    } finally {
      if (mounted) setState(() => _travail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lignes = _lignes;
    return Scaffold(
      appBar: AppBar(title: const Text('Importer des produits')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tous vos produits en une fois', style: NacreaTheme.titre(size: 26)),
                          const SizedBox(height: 8),
                          const Text(
                            '1. Téléchargez le modèle Excel.\n'
                            '2. Remplissez une ligne par produit : nom, prix de vente, et si possible marque, '
                            'catégorie, code-barres, prix d\'achat, quantité en stock.\n'
                            '3. Importez le fichier : YDS Beauty crée les produits, les catégories et le stock.',
                            style: TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                                onPressed: _travail ? null : _telechargerModele,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Télécharger le modèle'),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                                onPressed: _travail ? null : _choisir,
                                icon: const Icon(Icons.upload_file_outlined),
                                label: Text(_fichier == null ? 'Choisir mon fichier Excel' : 'Choisir un autre fichier'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Les quantités en stock sont ajoutées au stock de cette boutique. '
                            'Accepte les fichiers .xlsx et .csv.',
                            style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
                  ],
                  if (lignes != null) ...[
                    const SizedBox(height: 16),
                    _apercu(lignes),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _apercu(List<LigneImport> lignes) {
    final valides = lignes.where((l) => l.valide).toList();
    final erreurs = lignes.where((l) => !l.valide).toList();
    final aMettreAJour = valides.where((l) => _existant(l) != null).length;
    final aCreer = valides.length - aMettreAJour;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_fichier ?? '', style: const TextStyle(color: NacreaColors.gris)),
            const SizedBox(height: 8),
            Text('$aCreer nouveau${aCreer > 1 ? 'x' : ''} produit${aCreer > 1 ? 's' : ''}'
                '${aMettreAJour > 0 ? ' · $aMettreAJour déjà dans YDS Beauty' : ''}'
                '${erreurs.isNotEmpty ? ' · ${erreurs.length} ligne${erreurs.length > 1 ? 's' : ''} à corriger' : ''}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (aMettreAJour > 0)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: NacreaColors.prune,
                value: _mettreAJour,
                onChanged: _travail ? null : (v) => setState(() => _mettreAJour = v),
                title: const Text('Mettre à jour les produits déjà présents (prix, catégorie…)'),
                subtitle: const Text('Reconnus par leur code-barres, sinon par leur nom et variante'),
              ),
            if (erreurs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFCEBEB), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ces lignes seront ignorées (corrigez-les dans Excel puis réimportez) :',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final l in erreurs.take(15))
                      Text('Ligne ${l.numero}${l.nom.isEmpty ? '' : ' (${l.nom})'} : ${l.erreurs.join(', ')}'),
                    if (erreurs.length > 15) Text('… et ${erreurs.length - 15} autres'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final l in valides.take(50))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_existant(l) == null ? Icons.add_circle_outline : Icons.sync,
                    color: _existant(l) == null ? NacreaColors.succes : NacreaColors.orTexte),
                title: Text([l.nom, if (l.variante != null) l.variante!].join(' · ')),
                subtitle: Text([
                  if (l.marque != null) l.marque!,
                  if (l.categorie != null) l.categorie!,
                  if (l.codeBarres != null) l.codeBarres!,
                  if ((l.stock ?? 0) > 0) 'stock +${l.stock}',
                ].join(' · ')),
                trailing: Text(fcfa(l.prixVente ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (valides.length > 50) Text('… et ${valides.length - 50} autres produits'),
            const SizedBox(height: 16),
            if (_travail) ...[
              LinearProgressIndicator(
                value: valides.isEmpty ? null : _fait / valides.length,
                color: NacreaColors.prune,
                backgroundColor: NacreaColors.nude,
              ),
              const SizedBox(height: 8),
              Text('Import en cours… $_fait / ${valides.length}', textAlign: TextAlign.center),
            ] else
              FilledButton.icon(
                onPressed: valides.isEmpty ? null : _importer,
                icon: const Icon(Icons.playlist_add_check),
                label: Text('Importer ${valides.length} produit${valides.length > 1 ? 's' : ''}'),
              ),
          ],
        ),
      ),
    );
  }
}

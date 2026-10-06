
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/fiche_code_barres.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/scanner_camera.dart';
import '../../data/stock_repo.dart';
import 'ajustement_dialog.dart';
import 'entree_stock_dialog.dart';
import 'produits_page.dart';

/// Ajout ou modification d'un produit. Renvoie `true` si quelque chose a changé.
class ProduitForm extends StatefulWidget {
  const ProduitForm({
    super.key,
    required this.repo,
    required this.membre,
    required this.boutique,
    this.produit,
    this.codeBarresInitial,
  });

  final ProduitsRepo repo;
  final Membre membre;
  final Boutique boutique;
  final Produit? produit;

  /// Code scanné avant d'ouvrir la fiche (nouveau produit) : la fiche se remplit toute seule.
  final String? codeBarresInitial;

  @override
  State<ProduitForm> createState() => _ProduitFormState();
}

class _ProduitFormState extends State<ProduitForm> {
  final _form = GlobalKey<FormState>();
  late final _p = widget.produit;
  late final _nom = TextEditingController(text: _p?.nom);
  late final _marque = TextEditingController(text: _p?.marque);
  late final _variante = TextEditingController(text: _p?.variante);
  late final _codeBarres = TextEditingController(text: _p?.codeBarres ?? widget.codeBarresInitial);
  late final _prixAchat = TextEditingController(text: _p?.prixAchat.toString() ?? '');
  late final _prixVente = TextEditingController(text: _p?.prixVente.toString() ?? '');
  late final _prixGros = TextEditingController(text: _p?.prixGros?.toString() ?? '');
  late final _stockMin = TextEditingController(text: _p?.stockMin.toString() ?? '');
  final _stockInitial = TextEditingController();
  DateTime? _peremptionInitiale;

  late String? _categorieId = _p?.categorieId;
  List<Categorie> _categories = [];
  late String? _photoUrl = _p?.photoUrl;
  bool _rechercheFiche = false;
  String? _infoFiche; // message sous le code-barres
  bool _infoAlerte = false;
  Uint8List? _nouvellePhoto;
  String _extensionPhoto = 'jpg';

  Future<List<Lot>>? _lots;
  bool _change = false;
  bool _chargement = false;
  String? _erreur;

  bool get _modification => _p != null;

  @override
  void initState() {
    super.initState();
    _chargerCategories();
    if (_modification) _lots = widget.repo.lots(widget.boutique.id, _p!.id!);
    if (!_modification && (widget.codeBarresInitial?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chercherFiche());
    }
  }

  Future<void> _scannerCode() async {
    final code = await scannerCodeBarres(context);
    if (code == null || !mounted) return;
    _codeBarres.text = code;
    await _chercherFiche();
  }

  /// Vérifie que le code n'est pas déjà utilisé, puis (nouveau produit) préremplit la fiche
  /// depuis le catalogue Nacréa ou Open Beauty Facts. Ne remplace jamais ce qui est déjà tapé.
  Future<void> _chercherFiche() async {
    final code = _codeBarres.text.trim();
    if (code.isEmpty || _rechercheFiche) return;
    setState(() {
      _rechercheFiche = true;
      _infoFiche = null;
    });
    try {
      final doublon = await widget.repo.produitAvecCode(code, sauf: _p?.id);
      if (doublon != null) {
        setState(() {
          _infoFiche = 'Ce code-barres est déjà utilisé par « $doublon ».';
          _infoAlerte = true;
        });
        return;
      }
      if (_modification) return;
      final fiche = await chercherFiche(code);
      if (!mounted) return;
      if (fiche == null) {
        setState(() {
          _infoFiche = 'Aucune fiche trouvée pour ce code (ou pas de connexion). '
              'Remplissez-la : elle servira aussi aux prochaines boutiques Nacréa.';
          _infoAlerte = false;
        });
        return;
      }
      setState(() {
        void remplir(TextEditingController c, String? v) {
          if (c.text.trim().isEmpty && v != null) c.text = v;
        }

        remplir(_nom, fiche.nom);
        remplir(_marque, fiche.marque);
        remplir(_variante, fiche.variante);
        if (_photoUrl == null && _nouvellePhoto == null) _photoUrl = fiche.photoUrl;
        _infoFiche = 'Fiche préremplie grâce ${fiche.source}. Vérifiez-la, puis indiquez vos prix.';
        _infoAlerte = false;
      });
    } catch (e) {
      if (mounted) setState(() => _infoFiche = messageErreur(e));
    } finally {
      if (mounted) setState(() => _rechercheFiche = false);
    }
  }

  Widget _champCodeBarres() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _codeBarres,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _chercherFiche(),
          decoration: InputDecoration(
            labelText: 'Code-barres',
            helperText: _modification
                ? 'Scannez-le ou tapez les chiffres'
                : 'Commencez par scanner : la fiche peut se remplir toute seule',
            prefixIcon: const Icon(Icons.qr_code_scanner),
            suffixIcon: _rechercheFiche
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NacreaColors.prune),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (scanCameraDisponible)
                        IconButton(
                          tooltip: 'Scanner avec la caméra',
                          icon: const Icon(Icons.photo_camera_outlined, color: NacreaColors.prune),
                          onPressed: _scannerCode,
                        ),
                      if (!_modification)
                        IconButton(
                          tooltip: 'Chercher la fiche',
                          icon: const Icon(Icons.travel_explore, color: NacreaColors.prune),
                          onPressed: _chercherFiche,
                        ),
                    ],
                  ),
          ),
        ),
        if (_infoFiche != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _infoAlerte ? const Color(0xFFFCEBEB) : const Color(0xFFF7EEDB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_infoAlerte ? Icons.warning_amber_rounded : Icons.auto_awesome_outlined,
                    size: 20, color: _infoAlerte ? NacreaColors.erreur : NacreaColors.orTexte),
                const SizedBox(width: 10),
                Expanded(child: Text(_infoFiche!)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    for (final c in [
      _nom, _marque, _variante, _codeBarres, _prixAchat, _prixVente, _prixGros, _stockMin,
      _stockInitial,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chargerCategories() async {
    try {
      final liste = await widget.repo.categories();
      if (mounted) setState(() => _categories = liste);
    } catch (_) {
      // La liste restera vide ; on peut quand même enregistrer le produit.
    }
  }

  Future<void> _nouvelleCategorie() async {
    final champ = TextEditingController();
    final nom = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Nouvelle catégorie'),
        content: TextField(
          controller: champ,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Soins du visage'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(champ.text), child: const Text('Créer')),
        ],
      ),
    );
    if (nom == null || nom.trim().isEmpty) return;
    try {
      final c = await widget.repo.creerCategorie(nom);
      setState(() {
        _categories = [..._categories, c]..sort((a, b) => a.nom.compareTo(b.nom));
        _categorieId = c.id;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    }
  }

  Future<void> _choisirPhoto(ImageSource source) async {
    try {
      final fichier = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      final nom = fichier.name;
      setState(() {
        _nouvellePhoto = octets;
        _extensionPhoto = nom.contains('.') ? nom.split('.').last : 'jpg';
      });
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Impossible d\'ouvrir la photo.');
    }
  }

  Future<void> _enregistrer() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      var photo = _photoUrl;
      var photoNonEnvoyee = false;
      if (_nouvellePhoto != null) {
        try {
          photo = await widget.repo.envoyerPhoto(_nouvellePhoto!, _extensionPhoto);
        } catch (_) {
          // Sans internet, la photo ne peut pas partir : le produit est enregistré quand même.
          photoNonEnvoyee = true;
        }
      }
      final prixAchat = int.tryParse(_prixAchat.text) ?? _p?.prixAchat ?? 0;
      final id = await widget.repo.enregistrer(Produit(
        id: _p?.id,
        nom: _nom.text.trim(),
        marque: _marque.text,
        variante: _variante.text,
        codeBarres: _codeBarres.text,
        photoUrl: photo,
        prixAchat: prixAchat,
        prixVente: int.parse(_prixVente.text),
        prixGros: int.tryParse(_prixGros.text),
        stockMin: int.tryParse(_stockMin.text) ?? 0,
        categorieId: _categorieId,
      ));

      final initial = int.tryParse(_stockInitial.text) ?? 0;
      if (!_modification && initial > 0) {
        await widget.repo.entreeStock(
          boutiqueId: widget.boutique.id,
          produitId: id,
          quantite: initial,
          prixAchat: prixAchat,
          peremption: _peremptionInitiale,
          motif: 'Stock initial',
        );
      }
      if (!mounted) return;
      if (photoNonEnvoyee) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Produit enregistré sans la photo (pas de connexion). '
              'Rouvrez le produit plus tard pour l\'ajouter.'),
          duration: Duration(seconds: 5),
        ));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _archiver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Retirer ce produit ?'),
        content: const Text(
          'Il n\'apparaîtra plus dans le catalogue ni à la caisse. '
          'L\'historique de ses ventes est conservé.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: NacreaColors.erreur),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.archiver(_p!.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    }
  }

  Future<void> _ajouterStock() async {
    final ok = await ouvrirEntreeStock(
      context,
      repo: widget.repo,
      boutique: widget.boutique,
      produit: _p!,
      peutVoirCouts: widget.membre.peutVoirCouts,
    );
    if (ok) {
      setState(() {
        _change = true;
        _lots = widget.repo.lots(widget.boutique.id, _p.id!);
      });
    }
  }

  Future<void> _ajuster() async {
    final ok = await ouvrirAjustement(
      context,
      repo: StockRepo(boutiqueId: widget.boutique.id, compteId: widget.repo.compteId),
      produit: _p!,
      peutVoirCouts: widget.membre.peutVoirCouts,
    );
    if (ok) {
      setState(() {
        _change = true;
        _lots = widget.repo.lots(widget.boutique.id, _p.id!);
      });
    }
  }

  // ---------- Champs ----------

  TextFormField _champTexte(TextEditingController c, String label,
      {String? aide, IconData? icone, bool obligatoire = false, TextCapitalization? majuscules}) {
    return TextFormField(
      controller: c,
      textCapitalization: majuscules ?? TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: aide,
        prefixIcon: icone == null ? null : Icon(icone),
      ),
      validator: obligatoire
          ? (v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null
          : null,
    );
  }

  /// Une employée peut créer un produit avec ses prix, mais pas modifier les prix ensuite.
  bool get _prixVerrouilles => _modification && !widget.membre.estPatronne;

  TextFormField _champPrix(TextEditingController c, String label, {bool obligatoire = false}) {
    return TextFormField(
      controller: c,
      enabled: !_prixVerrouilles,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'FCFA',
        helperText: _prixVerrouilles ? 'Modifiable seulement par la patronne' : null,
      ),
      validator: obligatoire
          ? (v) => (int.tryParse(v ?? '') == null) ? 'Indiquez un prix' : null
          : null,
    );
  }

  Widget _deuxColonnes(Widget a, Widget b) => LayoutBuilder(
        builder: (_, c) => c.maxWidth < 520
            ? Column(children: [a, const SizedBox(height: 16), b])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
              ),
      );

  Widget _section(String titre, List<Widget> enfants) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titre, style: NacreaTheme.titre(size: 24)),
              const SizedBox(height: 16),
              ...enfants,
            ],
          ),
        ),
      );

  Widget _blocPhoto() {
    final apercu = _nouvellePhoto != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_nouvellePhoto!, width: 140, height: 140, fit: BoxFit.cover),
          )
        : PhotoProduit(url: _photoUrl, taille: 140);
    final camera = ImagePicker().supportsImageSource(ImageSource.camera);

    return Wrap(
      spacing: 20,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        apercu,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => _choisirPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_photoUrl == null && _nouvellePhoto == null
                  ? 'Choisir une photo'
                  : 'Changer la photo'),
            ),
            if (camera)
              TextButton.icon(
                onPressed: () => _choisirPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Prendre une photo'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _blocLots() {
    return FutureBuilder<List<Lot>>(
      future: _lots,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
          );
        }
        final lots = snap.data ?? [];
        final total = lots.fold<int>(0, (s, l) => s + l.quantite);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${milliers(total)} en stock dans ${widget.boutique.nom}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (lots.isEmpty)
              const Text('Aucun lot en stock.', style: TextStyle(color: NacreaColors.gris))
            else
              for (final l in lots)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NacreaColors.page,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${milliers(l.quantite)} unités · reçu le ${dateCourte(l.recuLe)}',
                        ),
                      ),
                      Text(
                        l.peremption == null ? 'Sans péremption' : 'Expire le ${dateCourte(l.peremption!)}',
                        style: TextStyle(
                          color: (l.peremption != null && l.peremption!.isBefore(DateTime.now()))
                              ? NacreaColors.erreur
                              : NacreaColors.gris,
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 240,
                  child: OutlinedButton.icon(
                    onPressed: _ajouterStock,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Ajouter du stock'),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: OutlinedButton.icon(
                    onPressed: _ajuster,
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Retirer ou corriger'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final couts = widget.membre.peutVoirCouts;
    final categorieValide = _categories.any((c) => c.id == _categorieId) ? _categorieId : null;

    return PopScope(
      canPop: !_change,
      onPopInvokedWithResult: (dejaFait, _) {
        if (!dejaFait) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_modification ? 'Modifier le produit' : 'Nouveau produit'),
          actions: [
            if (_modification && widget.membre.estPatronne)
              IconButton(
                tooltip: 'Retirer du catalogue',
                icon: const Icon(Icons.archive_outlined),
                onPressed: _archiver,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('Le produit', [
                        _champCodeBarres(),
                        const SizedBox(height: 20),
                        _blocPhoto(),
                        const SizedBox(height: 20),
                        _champTexte(_nom, 'Nom du produit',
                            aide: 'Lait corporel au karité', obligatoire: true),
                        const SizedBox(height: 16),
                        _deuxColonnes(
                          _champTexte(_marque, 'Marque', aide: 'Nivea',
                              majuscules: TextCapitalization.words),
                          _champTexte(_variante, 'Teinte, contenance ou parfum', aide: '400 ml'),
                        ),
                        const SizedBox(height: 16),
                        _deuxColonnes(
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  key: ValueKey(categorieValide),
                                  initialValue: categorieValide,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Catégorie'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                        value: null, child: Text('Sans catégorie')),
                                    for (final c in _categories)
                                      DropdownMenuItem<String?>(value: c.id, child: Text(c.nom)),
                                  ],
                                  onChanged: (v) => setState(() => _categorieId = v),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Nouvelle catégorie',
                                onPressed: _nouvelleCategorie,
                                icon: const Icon(Icons.add_circle_outline,
                                    color: NacreaColors.prune),
                              ),
                            ],
                          ),
                          const SizedBox.shrink(),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _section('Prix et alerte', [
                        _deuxColonnes(
                          _champPrix(_prixVente, 'Prix de vente', obligatoire: true),
                          couts
                              ? _champPrix(_prixAchat, 'Prix d\'achat')
                              : _champPrix(_prixGros, 'Prix de gros (facultatif)'),
                        ),
                        if (couts) ...[
                          const SizedBox(height: 16),
                          _deuxColonnes(
                            _champPrix(_prixGros, 'Prix de gros (facultatif)'),
                            const SizedBox.shrink(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _stockMin,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Alerte de stock bas',
                            helperText: 'Nacréa vous prévient quand le stock descend à ce nombre',
                            prefixIcon: Icon(Icons.notifications_none),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      if (_modification)
                        _section('Stock', [_blocLots()])
                      else
                        _section('Stock de départ', [
                          Text('Combien en avez-vous déjà dans ${widget.boutique.nom} ?',
                              style: const TextStyle(color: NacreaColors.gris)),
                          const SizedBox(height: 16),
                          _deuxColonnes(
                            TextFormField(
                              controller: _stockInitial,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'Quantité en stock',
                                prefixIcon: Icon(Icons.inventory_2_outlined),
                              ),
                            ),
                            ChampDatePeremption(
                              date: _peremptionInitiale,
                              quandChoisie: (d) => setState(() => _peremptionInitiale = d),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 24),
                      if (_erreur != null) MessageErreur(_erreur!),
                      FilledButton(
                        onPressed: _chargement ? null : _enregistrer,
                        child: _chargement
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(_modification ? 'Enregistrer les modifications' : 'Ajouter le produit'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

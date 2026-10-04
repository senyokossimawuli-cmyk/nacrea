import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/depenses_repo.dart';
import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../utils/periode.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/carte_chiffre.dart';
import '../clientes/cliente_dialogs.dart' show ouvrirWhatsApp;

/// Dépenses de la boutique et fournisseurs (deux onglets).
class DepensesPage extends StatelessWidget {
  const DepensesPage({super.key, required this.membre, required this.boutique, required this.boutiques});
  final Membre membre;
  final Boutique boutique;
  final List<Boutique> boutiques;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: NacreaColors.prune,
              indicatorColor: NacreaColors.prune,
              unselectedLabelColor: NacreaColors.gris,
              tabs: [
                Tab(icon: Icon(Icons.receipt_outlined), text: 'Dépenses'),
                Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Fournisseurs'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OngletDepenses(membre: membre, boutique: boutique, boutiques: boutiques),
                _OngletFournisseurs(membre: membre),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Dépenses
// =====================================================================

class _OngletDepenses extends StatefulWidget {
  const _OngletDepenses({required this.membre, required this.boutique, required this.boutiques});
  final Membre membre;
  final Boutique boutique;
  final List<Boutique> boutiques;

  @override
  State<_OngletDepenses> createState() => _OngletDepensesState();
}

class _OngletDepensesState extends State<_OngletDepenses> {
  late final _repo = DepensesRepo(compteId: widget.membre.compteId);
  late Periode _periode = widget.membre.estPatronne ? Periode.mois : Periode.aujourdhui;
  bool _toutes = false; // toutes les boutiques (patronne)
  late Stream<List<Depense>> _depenses = _flux();

  Stream<List<Depense>> _flux() {
    final (debut, fin) = _periode.bornes;
    return _repo.surveiller(boutiqueId: _toutes ? null : widget.boutique.id, debut: debut, fin: fin);
  }

  void _changer({Periode? periode, bool? toutes}) => setState(() {
        _periode = periode ?? _periode;
        _toutes = toutes ?? _toutes;
        _depenses = _flux();
      });

  Future<void> _nouvelle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DepenseDialog(repo: _repo, membre: widget.membre, boutique: widget.boutique),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dépense enregistrée.')));
    }
  }

  Future<void> _supprimer(Depense d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Supprimer cette dépense ?'),
        content: Text('${d.titre} · ${fcfa(d.montant)} · ${dateCourte(d.date)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: NacreaColors.erreur)),
          ),
        ],
      ),
    );
    if (ok == true) await _repo.supprimer(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membre;
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return StreamBuilder<List<Depense>>(
      stream: _depenses,
      builder: (context, snap) {
        final liste = snap.data ?? const <Depense>[];
        final total = liste.fold(0, (s, d) => s + d.montant);
        final parCategorie = <String, int>{};
        for (final d in liste) {
          parCategorie[d.categorie] = (parCategorie[d.categorie] ?? 0) + d.montant;
        }
        final categoriesTriees = parCategorie.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: EdgeInsets.all(etroit ? 16 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Text('Dépenses', style: NacreaTheme.titre(size: etroit ? 30 : 36)),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: _nouvelle,
                          icon: const Icon(Icons.add),
                          label: const Text('Nouvelle dépense'),
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
                        if (m.estPatronne && widget.boutiques.length > 1)
                          FilterChip(
                            avatar: const Icon(Icons.storefront_outlined, size: 18),
                            label: const Text('Toutes les boutiques'),
                            selected: _toutes,
                            onSelected: (v) => _changer(toutes: v),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        CarteChiffre(
                          titre: 'Total des dépenses',
                          valeur: fcfa(total),
                          sousTitre: _toutes ? 'Toutes les boutiques' : widget.boutique.nom,
                        ),
                        for (final e in categoriesTriees.take(3))
                          CarteChiffre(titre: libelleCategorie(e.key), valeur: fcfa(e.value)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                      )
                    else if (liste.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Aucune dépense sur cette période.\n'
                          'Loyer, électricité, salaires, transport… notez-les ici pour connaître votre vrai bénéfice.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: NacreaColors.gris, height: 1.5),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final (i, d) in liste.indexed) ...[
                              if (i > 0) const Divider(height: 1, color: NacreaColors.bordure),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: NacreaColors.nude,
                                  child: Icon(_icone(d.categorie), color: NacreaColors.prune, size: 20),
                                ),
                                title: Text(d.titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text([
                                  dateCourte(d.date),
                                  if (d.titre != libelleCategorie(d.categorie)) libelleCategorie(d.categorie),
                                  d.payeAvec.libelle,
                                  if (d.fournisseurNom != null) d.fournisseurNom!,
                                  if (_toutes && d.boutiqueNom != null) d.boutiqueNom!,
                                ].join(' · ')),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(fcfa(d.montant), style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (m.estPatronne)
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        icon: const Icon(Icons.delete_outline, color: NacreaColors.gris),
                                        onPressed: () => _supprimer(d),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static IconData _icone(String c) => switch (c) {
        'loyer' => Icons.home_work_outlined,
        'electricite_eau' => Icons.bolt_outlined,
        'salaires' => Icons.badge_outlined,
        'transport' => Icons.directions_bus_outlined,
        'internet_telephone' => Icons.wifi,
        'entretien' => Icons.build_outlined,
        'publicite' => Icons.campaign_outlined,
        'taxes' => Icons.account_balance_outlined,
        _ => Icons.receipt_outlined,
      };
}

class _DepenseDialog extends StatefulWidget {
  const _DepenseDialog({required this.repo, required this.membre, required this.boutique});
  final DepensesRepo repo;
  final Membre membre;
  final Boutique boutique;

  @override
  State<_DepenseDialog> createState() => _DepenseDialogState();
}

class _DepenseDialogState extends State<_DepenseDialog> {
  final _form = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _libelle = TextEditingController();
  late final _fournisseursRepo = FournisseursRepo(compteId: widget.membre.compteId);
  List<Fournisseur> _fournisseurs = [];
  String _categorie = 'transport';
  PayeAvec _payeAvec = PayeAvec.caisse;
  String? _fournisseurId;
  DateTime _date = DateTime.now();
  bool _chargement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _fournisseursRepo.tous().then((l) {
      if (mounted) setState(() => _fournisseurs = l);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _montant.dispose();
    _libelle.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await widget.repo.ajouter(
        boutiqueId: widget.boutique.id,
        categorie: _categorie,
        libelle: _libelle.text,
        montant: int.parse(_montant.text),
        payeAvec: _payeAvec,
        date: _date,
        fournisseurId: _fournisseurId,
        userId: Supabase.instance.client.auth.currentUser?.id ?? '',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patronne = widget.membre.estPatronne;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Nouvelle dépense', style: NacreaTheme.titre(size: 28)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.boutique.nom, style: const TextStyle(color: NacreaColors.gris)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _categorie,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Catégorie', prefixIcon: Icon(Icons.category_outlined)),
                  items: [
                    for (final e in categoriesDepenses.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _categorie = v ?? 'autre'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _montant,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Indiquez le montant' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _libelle,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Détail (facultatif)',
                    hintText: 'Taxi pour la livraison, facture CEET…',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<PayeAvec>(
                  initialValue: _payeAvec,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Payée avec', prefixIcon: Icon(Icons.payments_outlined)),
                  items: [
                    for (final p in PayeAvec.values) DropdownMenuItem(value: p, child: Text(p.libelle)),
                  ],
                  onChanged: (v) => setState(() => _payeAvec = v ?? PayeAvec.caisse),
                ),
                if (_payeAvec == PayeAvec.caisse)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Elle sera déduite de l\'argent attendu à la clôture de la caisse.',
                      style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                    ),
                  ),
                if (_fournisseurs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: _fournisseurId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Fournisseur (facultatif)',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                      for (final f in _fournisseurs) DropdownMenuItem<String?>(value: f.id, child: Text(f.nom)),
                    ],
                    onChanged: (v) => setState(() => _fournisseurId = v),
                  ),
                ],
                if (patronne) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(DateTime.now().year - 2),
                        lastDate: DateTime.now(),
                        helpText: 'Date de la dépense',
                      );
                      if (d != null) setState(() => _date = d);
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Date : ${dateCourte(_date)}'),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: NacreaColors.nude, borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'Achat de marchandises ? Ce n\'est pas une dépense : utilisez « Ajouter du stock » '
                    'dans Produits. Son coût sera compté automatiquement à la vente.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 14),
                  MessageErreur(_erreur!),
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
                        child: const Text('Enregistrer'),
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

// =====================================================================
// Fournisseurs
// =====================================================================

class _OngletFournisseurs extends StatefulWidget {
  const _OngletFournisseurs({required this.membre});
  final Membre membre;

  @override
  State<_OngletFournisseurs> createState() => _OngletFournisseursState();
}

class _OngletFournisseursState extends State<_OngletFournisseurs> {
  late final _repo = FournisseursRepo(compteId: widget.membre.compteId);
  late final Stream<List<Fournisseur>> _fournisseurs = _repo.surveiller();

  Future<void> _modifier([Fournisseur? f]) async {
    await showDialog<bool>(context: context, builder: (_) => _FournisseurDialog(repo: _repo, fournisseur: f));
  }

  Future<void> _livraisons(Fournisseur f) async {
    final lignes = await _repo.livraisons(f.id);
    if (!mounted) return;
    final couts = widget.membre.peutVoirCouts;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, defilement) => ListView(
          controller: defilement,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Livraisons de ${f.nom}', style: NacreaTheme.titre(size: 24)),
            const SizedBox(height: 12),
            if (lignes.isEmpty)
              const Text(
                'Aucune livraison enregistrée. Choisissez ce fournisseur dans « Ajouter du stock ».',
                style: TextStyle(color: NacreaColors.gris),
              ),
            for (final l in lignes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${l['quantity']} × ${l['produit']}'),
                subtitle: Text([
                  dateCourte(DateTime.tryParse(l['received_at'] as String? ?? '')?.toLocal() ?? DateTime.now()),
                  if (l['boutique'] != null) l['boutique'] as String,
                ].join(' · ')),
                trailing: couts
                    ? Text(fcfa(((l['quantity'] as int?) ?? 0) * ((l['cost_price'] as int?) ?? 0)),
                        style: const TextStyle(fontWeight: FontWeight.w600))
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _appeler(String telephone) async {
    await launchUrl(Uri(scheme: 'tel', path: telephone.replaceAll(' ', '')));
  }

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    final couts = widget.membre.peutVoirCouts;
    return StreamBuilder<List<Fournisseur>>(
      stream: _fournisseurs,
      builder: (context, snap) {
        final liste = snap.data ?? const <Fournisseur>[];
        return ListView(
          padding: EdgeInsets.all(etroit ? 16 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Text('Fournisseurs', style: NacreaTheme.titre(size: etroit ? 30 : 36)),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () => _modifier(),
                          icon: const Icon(Icons.add),
                          label: const Text('Nouveau fournisseur'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                      )
                    else if (liste.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Aucun fournisseur pour l\'instant.\n'
                          'Ajoutez vos grossistes ici, puis choisissez-les en ajoutant du stock.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: NacreaColors.gris, height: 1.5),
                        ),
                      )
                    else
                      for (final f in liste)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _livraisons(f),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: NacreaColors.nude,
                                    child: Icon(Icons.local_shipping_outlined, color: NacreaColors.prune),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(f.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        Text(
                                          [
                                            if (f.telephone != null) f.telephone!,
                                            if (couts && f.achats > 0) 'Achats : ${fcfa(f.achats)}',
                                            if (f.dernierAchat != null) 'Dernière livraison : ${dateCourte(f.dernierAchat!)}',
                                          ].join(' · '),
                                          style: const TextStyle(color: NacreaColors.gris),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (f.telephone != null) ...[
                                    IconButton(
                                      tooltip: 'Commander par WhatsApp',
                                      icon: const Icon(Icons.chat_outlined, color: NacreaColors.prune),
                                      onPressed: () => ouvrirWhatsApp(context, f.telephone, 'Bonjour ${f.nom}, '),
                                    ),
                                    if (etroit)
                                      IconButton(
                                        tooltip: 'Appeler',
                                        icon: const Icon(Icons.call_outlined, color: NacreaColors.prune),
                                        onPressed: () => _appeler(f.telephone!),
                                      ),
                                  ],
                                  PopupMenuButton<String>(
                                    onSelected: (choix) async {
                                      if (choix == 'modifier') await _modifier(f);
                                      if (choix == 'archiver') await _repo.archiver(f.id);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'modifier', child: Text('Modifier')),
                                      if (widget.membre.estPatronne)
                                        const PopupMenuItem(value: 'archiver', child: Text('Retirer de la liste')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FournisseurDialog extends StatefulWidget {
  const _FournisseurDialog({required this.repo, this.fournisseur});
  final FournisseursRepo repo;
  final Fournisseur? fournisseur;

  @override
  State<_FournisseurDialog> createState() => _FournisseurDialogState();
}

class _FournisseurDialogState extends State<_FournisseurDialog> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.fournisseur?.nom);
  late final _telephone = TextEditingController(text: widget.fournisseur?.telephone);
  late final _note = TextEditingController(text: widget.fournisseur?.note);
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (!_form.currentState!.validate()) return;
    try {
      await widget.repo.enregistrer(
        id: widget.fournisseur?.id,
        nom: _nom.text,
        telephone: _telephone.text,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _erreur = messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(widget.fournisseur == null ? 'Nouveau fournisseur' : 'Modifier le fournisseur',
          style: NacreaTheme.titre(size: 26)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nom,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.store_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez le nom' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _telephone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone / WhatsApp (facultatif)',
                    hintText: '90 00 00 00',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (facultatif)',
                    hintText: 'Livre le mardi, marques Nivea et Dove…',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 14),
                  MessageErreur(_erreur!),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton(onPressed: _valider, child: const Text('Enregistrer'))),
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

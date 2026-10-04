import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/clientes_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

/// Numéro au format WhatsApp (chiffres avec indicatif), ou null s'il est incomplet.
/// Un numéro togolais à 8 chiffres reçoit l'indicatif 228.
String? numeroWhatsApp(String? saisi) {
  if (saisi == null) return null;
  var chiffres = saisi.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.startsWith('00')) chiffres = chiffres.substring(2);
  if (chiffres.length == 8) chiffres = '228$chiffres';
  return chiffres.length < 10 ? null : chiffres;
}

/// Ouvre WhatsApp vers [telephone] avec [texte] prêt à envoyer.
Future<void> ouvrirWhatsApp(BuildContext context, String? telephone, String texte) async {
  final numero = numeroWhatsApp(telephone);
  void dire(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  if (numero == null) {
    dire('Numéro de téléphone manquant ou incomplet.');
    return;
  }
  final lien = Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(texte)}');
  final ok = await launchUrl(lien, mode: LaunchMode.externalApplication);
  if (!ok) dire('Impossible d\'ouvrir WhatsApp.');
}

/// Texte de rappel poli pour une cliente qui doit de l'argent.
String texteRappel({required String cliente, required int dette, required String boutique}) =>
    'Bonjour $cliente, ici $boutique. Petit rappel : il vous reste ${fcfa(dette)} à régler. '
            'Merci beaucoup et à très bientôt !'
        .replaceAll('\u202F', ' ');

/// Fiche à remplir : nouvelle cliente ou modification. Renvoie la cliente enregistrée.
Future<Cliente?> ouvrirFormCliente(BuildContext context, ClientesRepo repo, {Cliente? cliente, String? nom}) {
  return showDialog<Cliente>(
    context: context,
    builder: (_) => _FormCliente(repo: repo, cliente: cliente, nomPropose: nom),
  );
}

class _FormCliente extends StatefulWidget {
  const _FormCliente({required this.repo, this.cliente, this.nomPropose});
  final ClientesRepo repo;
  final Cliente? cliente;
  final String? nomPropose;

  @override
  State<_FormCliente> createState() => _FormClienteState();
}

class _FormClienteState extends State<_FormCliente> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.cliente?.nom ?? widget.nomPropose);
  late final _tel = TextEditingController(text: widget.cliente?.telephone);
  late final _note = TextEditingController(text: widget.cliente?.note);
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _tel.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      // Même numéro qu'une cliente existante : on évite de créer un doublon.
      if (widget.cliente == null && _tel.text.trim().isNotEmpty) {
        final existante = await widget.repo.parTelephone(_tel.text);
        if (existante != null) {
          if (mounted) {
            setState(() => _erreur = 'Ce numéro appartient déjà à ${existante.nom}. '
                'Cherchez-la dans la liste au lieu de la recréer.');
          }
          return;
        }
      }
      final c = await widget.repo.enregistrer(
        id: widget.cliente?.id,
        nom: _nom.text,
        telephone: _tel.text,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(c);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(widget.cliente == null ? 'Nouvelle cliente' : 'Modifier la cliente',
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
                  decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez le nom' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _tel,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
                  decoration: const InputDecoration(
                    labelText: 'Téléphone / WhatsApp (conseillé)',
                    hintText: '90 00 00 00',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (facultatif)',
                    hintText: 'Type de peau, produits préférés…',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 12),
                  Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _chargement ? null : () => Navigator.of(context).pop(),
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

/// Choisir la cliente d'une vente (recherche par nom ou téléphone, ou création rapide).
Future<Cliente?> choisirCliente(BuildContext context, ClientesRepo repo) {
  return showDialog<Cliente>(context: context, builder: (_) => _ChoixCliente(repo: repo));
}

class _ChoixCliente extends StatefulWidget {
  const _ChoixCliente({required this.repo});
  final ClientesRepo repo;

  @override
  State<_ChoixCliente> createState() => _ChoixClienteState();
}

class _ChoixClienteState extends State<_ChoixCliente> {
  late final Stream<List<Cliente>> _clientes = widget.repo.surveiller();
  final _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _nouvelle() async {
    final saisi = _recherche.text.trim();
    final estNumero = RegExp(r'^[0-9 +]+$').hasMatch(saisi);
    final c = await ouvrirFormCliente(context, widget.repo, nom: estNumero ? null : saisi);
    if (c != null && mounted) Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final hauteur = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Cliente de la vente', style: NacreaTheme.titre(size: 26)),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      content: SizedBox(
        width: 440,
        height: hauteur * 0.6,
        child: Column(
          children: [
            TextField(
              controller: _recherche,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Nom ou téléphone…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<Cliente>>(
                stream: _clientes,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
                  }
                  final q = _recherche.text.trim().toLowerCase();
                  final qChiffres = q.replaceAll(RegExp(r'\D'), '');
                  final liste = snap.data!
                      .where((c) =>
                          q.isEmpty ||
                          c.nom.toLowerCase().contains(q) ||
                          (qChiffres.length >= 3 &&
                              (c.telephone ?? '').replaceAll(RegExp(r'\D'), '').contains(qChiffres)))
                      .toList();
                  if (liste.isEmpty) {
                    return Center(
                      child: Text(
                        snap.data!.isEmpty ? 'Aucune cliente enregistrée pour l\'instant.' : 'Aucune cliente trouvée.',
                        style: const TextStyle(color: NacreaColors.gris),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: liste.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = liste[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(
                          backgroundColor: NacreaColors.nude,
                          foregroundColor: NacreaColors.prune,
                          child: Text(c.nom.isEmpty ? '?' : c.nom[0].toUpperCase()),
                        ),
                        title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: c.telephone == null ? null : Text(c.telephone!),
                        trailing: c.doit
                            ? Text('Doit ${fcfa(c.dette)}',
                                style: const TextStyle(color: NacreaColors.erreur, fontWeight: FontWeight.w600))
                            : null,
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _nouvelle,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Nouvelle'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Enregistrer un remboursement de la cliente. Renvoie vrai si enregistré.
Future<bool> ouvrirRemboursement(
  BuildContext context, {
  required ClientesRepo repo,
  required Cliente cliente,
  required String boutiqueId,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _Remboursement(repo: repo, cliente: cliente, boutiqueId: boutiqueId),
  );
  return ok == true;
}

class _Remboursement extends StatefulWidget {
  const _Remboursement({required this.repo, required this.cliente, required this.boutiqueId});
  final ClientesRepo repo;
  final Cliente cliente;
  final String boutiqueId;

  @override
  State<_Remboursement> createState() => _RemboursementState();
}

class _RemboursementState extends State<_Remboursement> {
  final _montant = TextEditingController();
  String _moyen = 'cash';
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await widget.repo.rembourser(
        cliente: widget.cliente,
        boutiqueId: widget.boutiqueId,
        montant: int.tryParse(_montant.text) ?? 0,
        moyen: _moyen,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final saisi = int.tryParse(_montant.text) ?? 0;
    final reste = c.dette - saisi;
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Paiement de ${c.nom}', style: NacreaTheme.titre(size: 26)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Elle doit ${fcfa(c.dette)}', style: const TextStyle(color: NacreaColors.gris)),
              const SizedBox(height: 16),
              TextField(
                controller: _montant,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _valider(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(labelText: 'Montant reçu', suffixText: 'FCFA'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text('Tout · ${milliers(c.dette)}'),
                    backgroundColor: NacreaColors.nude,
                    side: BorderSide.none,
                    onPressed: () => setState(() => _montant.text = '${c.dette}'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Espèces')),
                  ButtonSegment(value: 'mobile_money', label: Text('Mobile Money')),
                ],
                selected: {_moyen},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _moyen = s.first),
              ),
              if (saisi > 0 && reste >= 0) ...[
                const SizedBox(height: 14),
                Text(
                  reste == 0 ? 'Elle sera à jour.' : 'Il restera ${fcfa(reste)} à payer.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: reste == 0 ? NacreaColors.succes : NacreaColors.chocolat,
                  ),
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _chargement ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _chargement || saisi <= 0 ? null : _valider,
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

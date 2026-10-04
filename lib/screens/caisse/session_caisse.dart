import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/caisse_repo.dart';
import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import 'caisse_page.dart';

String _heure(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

/// Couleur et texte d'un écart de caisse.
(String, Color) libelleEcart(int ecart) {
  if (ecart == 0) return ('Caisse juste', NacreaColors.succes);
  if (ecart < 0) return ('Manquant : ${fcfa(-ecart)}', NacreaColors.erreur);
  return ('Surplus : ${fcfa(ecart)}', NacreaColors.orTexte);
}

/// Porte d'entrée de la caisse : il faut l'ouvrir (fond de caisse) avant de vendre.
class CaissePorte extends StatefulWidget {
  const CaissePorte({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<CaissePorte> createState() => _CaissePorteState();
}

class _CaissePorteState extends State<CaissePorte> {
  late final _repo = CaisseRepo(boutiqueId: widget.boutique.id, compteId: widget.membre.compteId);
  late final _session = _repo.surveillerOuverte();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SessionCaisse?>(
      stream: _session,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
        }
        final session = snap.data;
        if (session == null) return _Ouverture(repo: _repo, boutique: widget.boutique);
        return Column(
          children: [
            _BarreSession(repo: _repo, session: session),
            Expanded(child: CaissePage(membre: widget.membre, boutique: widget.boutique)),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Ouverture

class _Ouverture extends StatefulWidget {
  const _Ouverture({required this.repo, required this.boutique});
  final CaisseRepo repo;
  final Boutique boutique;

  @override
  State<_Ouverture> createState() => _OuvertureState();
}

class _OuvertureState extends State<_Ouverture> {
  final _fond = TextEditingController();
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _fond.dispose();
    super.dispose();
  }

  Future<void> _ouvrir() async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await widget.repo.ouvrir(int.tryParse(_fond.text) ?? 0);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.point_of_sale_outlined, size: 48, color: NacreaColors.prune),
                  const SizedBox(height: 12),
                  Text('Ouvrir la caisse',
                      textAlign: TextAlign.center, style: NacreaTheme.titre(size: 32)),
                  const SizedBox(height: 8),
                  Text(
                    'Comptez la monnaie présente dans le tiroir de ${widget.boutique.nom} '
                    'avant la première vente de la journée.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NacreaColors.gris, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _fond,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _ouvrir(),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Fond de caisse',
                      suffixText: 'FCFA',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in [0, 5000, 10000, 20000])
                        ActionChip(
                          label: Text(milliers(v)),
                          backgroundColor: NacreaColors.nude,
                          side: BorderSide.none,
                          onPressed: () => setState(() => _fond.text = '$v'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_erreur != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
                    ),
                  FilledButton(
                    onPressed: _chargement ? null : _ouvrir,
                    child: const Text('Ouvrir la caisse'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Barre de session

class _BarreSession extends StatelessWidget {
  const _BarreSession({required this.repo, required this.session});
  final CaisseRepo repo;
  final SessionCaisse session;

  @override
  Widget build(BuildContext context) {
    final petitBouton = OutlinedButton.styleFrom(minimumSize: const Size(0, 40));
    return Container(
      width: double.infinity,
      color: NacreaColors.nude,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_open, size: 18, color: NacreaColors.succes),
              const SizedBox(width: 8),
              Text(
                'Caisse ouverte depuis ${_heure(session.ouverteLe)}'
                '${session.ouvertePar == null ? '' : ' par ${session.ouvertePar}'}'
                ' · Fond ${fcfa(session.fond)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: petitBouton,
                onPressed: () => _ouvrirMouvement(context),
                icon: const Icon(Icons.swap_vert, size: 18),
                label: const Text('Entrée / sortie'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => _ouvrirCloture(context),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Clôturer la caisse'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _ouvrirMouvement(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _MouvementDialog(repo: repo, session: session),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mouvement de caisse enregistré.')));
    }
  }

  Future<void> _ouvrirCloture(BuildContext context) async {
    final ecart = await showDialog<int>(
      context: context,
      builder: (_) => _ClotureDialog(repo: repo, session: session),
    );
    if (ecart != null && context.mounted) {
      final (texte, _) = libelleEcart(ecart);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Caisse clôturée. $texte'), duration: const Duration(seconds: 5)),
      );
    }
  }
}

// ---------------------------------------------------------------- Entrée / sortie

class _MouvementDialog extends StatefulWidget {
  const _MouvementDialog({required this.repo, required this.session});
  final CaisseRepo repo;
  final SessionCaisse session;

  @override
  State<_MouvementDialog> createState() => _MouvementDialogState();
}

class _MouvementDialogState extends State<_MouvementDialog> {
  bool _entree = false;
  final _montant = TextEditingController();
  final _motif = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _montant.dispose();
    _motif.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    try {
      await widget.repo.mouvement(
        widget.session,
        entree: _entree,
        montant: int.tryParse(_montant.text) ?? 0,
        motif: _motif.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _erreur = messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _entree
        ? ['Apport de monnaie', 'Remboursement']
        : ['Transport', 'Achat boutique', 'Dépôt en banque', 'Remise à la patronne'];
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Entrée ou sortie d\'argent'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Sortie'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: true, label: Text('Entrée'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_entree},
              onSelectionChanged: (s) => setState(() => _entree = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _montant,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Montant', suffixText: 'FCFA'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motif,
              decoration: const InputDecoration(labelText: 'Motif'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    backgroundColor: NacreaColors.nude,
                    side: BorderSide.none,
                    onPressed: () => setState(() => _motif.text = s),
                  ),
              ],
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        TextButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

// ---------------------------------------------------------------- Clôture

class _ClotureDialog extends StatefulWidget {
  const _ClotureDialog({required this.repo, required this.session});
  final CaisseRepo repo;
  final SessionCaisse session;

  @override
  State<_ClotureDialog> createState() => _ClotureDialogState();
}

class _ClotureDialogState extends State<_ClotureDialog> {
  late final Future<ResumeCaisse> _resume = widget.repo.resume(widget.session);
  final _compte = TextEditingController();
  final _note = TextEditingController();
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _compte.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _cloturer() async {
    if (_chargement) return;
    if (_compte.text.isEmpty) {
      setState(() => _erreur = 'Indiquez le montant compté dans le tiroir.');
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final ecart = await widget.repo.cloturer(
        widget.session,
        compte: int.parse(_compte.text),
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(ecart);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget ligne(String a, String b, {bool fort = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(a, style: TextStyle(fontWeight: fort ? FontWeight.w700 : FontWeight.w400))),
              Text(b, style: TextStyle(fontWeight: fort ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        );

    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Clôturer la caisse', style: NacreaTheme.titre(size: 28)),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<ResumeCaisse>(
          future: _resume,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
              );
            }
            final r = snap.data!;
            final compte = int.tryParse(_compte.text);
            final ecart = compte == null ? null : compte - r.attendu;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ligne('Fond de caisse', fcfa(r.fond)),
                  ligne('Ventes en espèces', '+ ${fcfa(r.ventesEspeces)}'),
                  if (r.remboursementsEspeces > 0)
                    ligne('Dettes payées en espèces', '+ ${fcfa(r.remboursementsEspeces)}'),
                  if (r.depenses > 0)
                    ligne('Dépenses payées avec la caisse', '- ${fcfa(r.depenses)}'),
                  if (r.entrees > 0) ligne('Entrées d\'argent', '+ ${fcfa(r.entrees)}'),
                  if (r.sorties > 0) ligne('Sorties d\'argent', '- ${fcfa(r.sorties)}'),
                  const Divider(color: NacreaColors.bordure),
                  ligne('Doit être dans le tiroir', fcfa(r.attendu), fort: true),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _compte,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Montant compté dans le tiroir',
                      suffixText: 'FCFA',
                    ),
                  ),
                  if (ecart != null) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (_) {
                      final (texte, couleur) = libelleEcart(ecart);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: couleur.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(texte,
                            style: TextStyle(color: couleur, fontSize: 16, fontWeight: FontWeight.w700)),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'Remarque (facultatif)'),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: _chargement ? null : _cloturer,
          child: const Text('Clôturer'),
        ),
      ],
    );
  }
}

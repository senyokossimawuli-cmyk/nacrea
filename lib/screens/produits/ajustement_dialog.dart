import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/produits_repo.dart';
import '../../data/stock_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/auth_layout.dart';

/// Fenêtre « Retirer ou corriger le stock » : casse, vol, cadeau, échantillon, périmé, correction.
Future<bool> ouvrirAjustement(
  BuildContext context, {
  required StockRepo repo,
  required Produit produit,
  required bool peutVoirCouts,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _AjustementDialog(repo: repo, produit: produit, peutVoirCouts: peutVoirCouts),
  );
  return ok ?? false;
}

class _AjustementDialog extends StatefulWidget {
  const _AjustementDialog({required this.repo, required this.produit, required this.peutVoirCouts});
  final StockRepo repo;
  final Produit produit;
  final bool peutVoirCouts;

  @override
  State<_AjustementDialog> createState() => _AjustementDialogState();
}

class _AjustementDialogState extends State<_AjustementDialog> {
  final _quantite = TextEditingController(text: '1');
  final _note = TextEditingController();
  MotifAjustement _motif = MotifAjustement.casse;
  bool _ajout = false; // pour « Correction » : ajouter au lieu de retirer
  bool _chargement = false;
  String? _erreur;

  static final _motifs = MotifAjustement.values.where((m) => m != MotifAjustement.inventaire).toList();

  @override
  void dispose() {
    _quantite.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _estAjout => _motif.retrait == null && _ajout;

  Future<void> _valider() async {
    final q = int.tryParse(_quantite.text) ?? 0;
    if (q <= 0) {
      setState(() => _erreur = 'Indiquez une quantité');
      return;
    }
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await widget.repo.ajuster(
        produitId: widget.produit.id!,
        quantite: _estAjout ? q : -q,
        motif: _motif,
        note: _note.text,
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
    final p = widget.produit;
    final q = int.tryParse(_quantite.text) ?? 0;
    final apres = p.stock + (_estAjout ? q : -q);
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Retirer ou corriger', style: NacreaTheme.titre(size: 28)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${p.nomComplet} · stock actuel : ${p.stock}', style: const TextStyle(color: NacreaColors.gris)),
              const SizedBox(height: 16),
              const Text('Motif', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _motifs)
                    ChoiceChip(
                      label: Text(m.libelle),
                      selected: _motif == m,
                      onSelected: (_) => setState(() => _motif = m),
                    ),
                ],
              ),
              if (_motif.retrait == null) ...[
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.remove), label: Text('Retirer')),
                    ButtonSegment(value: true, icon: Icon(Icons.add), label: Text('Ajouter')),
                  ],
                  selected: {_ajout},
                  onSelectionChanged: (v) => setState(() => _ajout = v.first),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _quantite,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: _estAjout ? 'Quantité à ajouter' : 'Quantité à retirer',
                  helperText: 'Stock après : $apres',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (facultatif)',
                  hintText: 'Tombé pendant le rangement, offert à Mme Afi…',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              if (widget.peutVoirCouts && !_estAjout && q > 0 && p.prixAchat > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Perte estimée : ${fcfa(q * p.prixAchat)} au prix d\'achat (déduite du bénéfice).',
                  style: const TextStyle(color: NacreaColors.orTexte, fontSize: 13),
                ),
              ],
              if (_motif.retrait == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Pour recompter tout le rayon, utilisez plutôt « Inventaire » dans Produits.',
                    style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                  ),
                ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
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
    );
  }
}

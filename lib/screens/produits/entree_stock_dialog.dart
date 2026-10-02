import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/auth_layout.dart';

/// Choix d'une date de péremption (bouton qui ouvre le calendrier).
class ChampDatePeremption extends StatelessWidget {
  const ChampDatePeremption({super.key, required this.date, required this.quandChoisie});
  final DateTime? date;
  final ValueChanged<DateTime?> quandChoisie;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final maintenant = DateTime.now();
        final choisie = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime(maintenant.year + 1, maintenant.month, maintenant.day),
          firstDate: DateTime(maintenant.year - 1),
          lastDate: DateTime(maintenant.year + 10),
          helpText: 'Date de péremption',
        );
        if (choisie != null) quandChoisie(choisie);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date de péremption (facultatif)',
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: date == null
              ? null
              : IconButton(
                  tooltip: 'Effacer la date',
                  icon: const Icon(Icons.close),
                  onPressed: () => quandChoisie(null),
                ),
        ),
        child: Text(
          date == null ? 'Aucune' : dateCourte(date!),
          style: TextStyle(color: date == null ? NacreaColors.gris : NacreaColors.chocolat),
        ),
      ),
    );
  }
}

/// Fenêtre « Ajouter du stock » : enregistre un nouveau lot pour la boutique.
Future<bool> ouvrirEntreeStock(
  BuildContext context, {
  required ProduitsRepo repo,
  required Boutique boutique,
  required Produit produit,
  required bool peutVoirCouts,
}) async {
  final resultat = await showDialog<bool>(
    context: context,
    builder: (_) => _EntreeStockDialog(
      repo: repo,
      boutique: boutique,
      produit: produit,
      peutVoirCouts: peutVoirCouts,
    ),
  );
  return resultat ?? false;
}

class _EntreeStockDialog extends StatefulWidget {
  const _EntreeStockDialog({
    required this.repo,
    required this.boutique,
    required this.produit,
    required this.peutVoirCouts,
  });
  final ProduitsRepo repo;
  final Boutique boutique;
  final Produit produit;
  final bool peutVoirCouts;

  @override
  State<_EntreeStockDialog> createState() => _EntreeStockDialogState();
}

class _EntreeStockDialogState extends State<_EntreeStockDialog> {
  final _form = GlobalKey<FormState>();
  final _quantite = TextEditingController();
  late final _prix = TextEditingController(text: '${widget.produit.prixAchat}');
  final _motif = TextEditingController();
  DateTime? _peremption;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _quantite.dispose();
    _prix.dispose();
    _motif.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await widget.repo.entreeStock(
        boutiqueId: widget.boutique.id,
        produitId: widget.produit.id!,
        quantite: int.parse(_quantite.text),
        prixAchat: int.tryParse(_prix.text) ?? widget.produit.prixAchat,
        peremption: _peremption,
        motif: _motif.text,
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
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Ajouter du stock', style: NacreaTheme.titre(size: 28)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.produit.nomComplet} · ${widget.boutique.nom}',
                  style: const TextStyle(color: NacreaColors.gris),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _quantite,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Quantité reçue',
                    prefixIcon: Icon(Icons.add_box_outlined),
                  ),
                  validator: (v) =>
                      (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Indiquez une quantité' : null,
                ),
                const SizedBox(height: 16),
                if (widget.peutVoirCouts) ...[
                  TextFormField(
                    controller: _prix,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Prix d\'achat unitaire',
                      suffixText: 'FCFA',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ChampDatePeremption(
                  date: _peremption,
                  quandChoisie: (d) => setState(() => _peremption = d),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motif,
                  decoration: const InputDecoration(
                    labelText: 'Note (facultatif)',
                    hintText: 'Arrivage du fournisseur…',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 16),
                  MessageErreur(_erreur!),
                ],
                const SizedBox(height: 24),
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
                        onPressed: _chargement ? null : _valider,
                        child: _chargement
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Enregistrer'),
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

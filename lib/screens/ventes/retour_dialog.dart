import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/retours_repo.dart';
import '../../data/ventes_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/auth_layout.dart';

/// Retour ou échange d'articles d'un reçu. Renvoie le montant remboursé (ou null).
Future<(int, Remboursement)?> ouvrirRetour(BuildContext context, {required RetoursRepo repo, required Vente vente}) {
  return showDialog<(int, Remboursement)>(
    context: context,
    builder: (_) => _RetourDialog(repo: repo, vente: vente),
  );
}

class _RetourDialog extends StatefulWidget {
  const _RetourDialog({required this.repo, required this.vente});
  final RetoursRepo repo;
  final Vente vente;

  @override
  State<_RetourDialog> createState() => _RetourDialogState();
}

class _RetourDialogState extends State<_RetourDialog> {
  late final Future<List<ArticleRetournable>> _articles = widget.repo.articles(widget.vente.id);
  final Map<String, int> _quantites = {};
  final Map<String, bool> _enStock = {};
  late Remboursement _remboursement =
      widget.vente.clienteId != null && widget.vente.credit > 0 ? Remboursement.dette : Remboursement.especes;
  final _note = TextEditingController();
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int _total(List<ArticleRetournable> articles) =>
      articles.fold(0, (s, a) => s + (_quantites[a.produitId] ?? 0) * a.remboursementUnitaire);

  Future<void> _valider(List<ArticleRetournable> articles) async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final montant = await widget.repo.enregistrer(
        venteId: widget.vente.id,
        clienteId: widget.vente.clienteId,
        ticket: widget.vente.ticket,
        articles: [
          for (final a in articles)
            ArticleRetour(a, _quantites[a.produitId] ?? 0, remisEnStock: _enStock[a.produitId] ?? true),
        ],
        remboursement: _remboursement,
        note: _note.text,
        userId: Supabase.instance.client.auth.currentUser?.id ?? '',
      );
      if (mounted) Navigator.pop(context, (montant, _remboursement));
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
      title: Text('Retour · reçu n° ${widget.vente.ticket}', style: NacreaTheme.titre(size: 24)),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<List<ArticleRetournable>>(
          future: _articles,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
              );
            }
            final articles = snap.data!;
            final total = _total(articles);
            final rien = articles.every((a) => a.retournable <= 0);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rien)
                    const Text('Tous les articles de ce reçu ont déjà été retournés.')
                  else
                    const Text('Choisissez les articles rapportés par la cliente :',
                        style: TextStyle(color: NacreaColors.gris)),
                  const SizedBox(height: 8),
                  for (final a in articles)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      '${fcfa(a.remboursementUnitaire)} l\'unité · acheté ${a.vendu}'
                                      '${a.dejaRetourne > 0 ? ' · déjà rendu ${a.dejaRetourne}' : ''}',
                                      style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: (_quantites[a.produitId] ?? 0) > 0
                                    ? () => setState(() => _quantites[a.produitId] = (_quantites[a.produitId] ?? 0) - 1)
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('${_quantites[a.produitId] ?? 0}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              IconButton(
                                onPressed: (_quantites[a.produitId] ?? 0) < a.retournable
                                    ? () => setState(() => _quantites[a.produitId] = (_quantites[a.produitId] ?? 0) + 1)
                                    : null,
                                icon: const Icon(Icons.add_circle_outline, color: NacreaColors.prune),
                              ),
                            ],
                          ),
                          if ((_quantites[a.produitId] ?? 0) > 0)
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: NacreaColors.prune,
                              value: _enStock[a.produitId] ?? true,
                              onChanged: (v) => setState(() => _enStock[a.produitId] = v),
                              title: Text((_enStock[a.produitId] ?? true)
                                  ? 'En bon état : remis en rayon'
                                  : 'Abîmé ou ouvert : pas remis en rayon (perte)'),
                            ),
                        ],
                      ),
                    ),
                  const Divider(color: NacreaColors.bordure),
                  DropdownButtonFormField<Remboursement>(
                    initialValue: _remboursement,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Rembourser par'),
                    items: [
                      for (final r in Remboursement.values)
                        if (r != Remboursement.dette || widget.vente.clienteId != null)
                          DropdownMenuItem(value: r, child: Text(r.libelle)),
                    ],
                    onChanged: (v) => setState(() => _remboursement = v ?? Remboursement.especes),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Motif (facultatif)',
                      hintText: 'Mauvaise teinte, allergie, produit abîmé…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: NacreaColors.nude, borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      'Échange : remboursez en « Espèces », puis vendez le nouveau produit à la caisse. '
                      'La cliente ne paie que la différence et la caisse reste juste.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'À rembourser : ${fcfa(total)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  if (_erreur != null) ...[
                    const SizedBox(height: 12),
                    MessageErreur(_erreur!),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _chargement ? null : () => Navigator.pop(context),
                          child: const Text('Annuler'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _chargement || _quantites.values.every((q) => q == 0)
                              ? null
                              : () => _valider(articles),
                          child: const Text('Valider le retour'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

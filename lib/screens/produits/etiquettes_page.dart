import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../data/base_locale.dart';
import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/etiquettes_pdf.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

/// Impression d'étiquettes code-barres (avec le prix) à coller sur les produits.
class EtiquettesPage extends StatefulWidget {
  const EtiquettesPage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<EtiquettesPage> createState() => _EtiquettesPageState();
}

class _EtiquettesPageState extends State<EtiquettesPage> {
  late final _repo = ProduitsRepo(compteId: widget.membre.compteId);
  late final Stream<List<Produit>> _produits = _repo.surveillerProduits(widget.boutique.id);
  final Map<String, int> _quantites = {};
  final _recherche = TextEditingController();
  FormatEtiquette _format = FormatEtiquette.a4;
  bool _travail = false;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _dire(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Donne un code-barres « maison » aux produits choisis qui n'en ont pas.
  Future<int> _creerCodes(List<Produit> tous) async {
    final sansCode = tous.where((p) => (_quantites[p.id] ?? 0) > 0 && (p.codeBarres ?? '').trim().isEmpty).toList();
    if (sansCode.isEmpty) return 0;
    final utilises = {for (final p in tous) p.codeBarres?.trim()};
    await db.writeTransaction((tx) async {
      for (final p in sansCode) {
        var code = nouveauCodeInterne();
        while (utilises.contains(code)) {
          code = nouveauCodeInterne();
        }
        utilises.add(code);
        await tx.execute('UPDATE products SET barcode = ? WHERE id = ?', [code, p.id]);
      }
    });
    return sansCode.length;
  }

  Future<void> _imprimer(List<Produit> tous) async {
    setState(() => _travail = true);
    try {
      final crees = await _creerCodes(tous);
      // Relire les produits pour avoir les nouveaux codes.
      final aJour = await _repo.produitsAvecStock(widget.boutique.id);
      final choix = [
        for (final p in aJour)
          if ((_quantites[p.id] ?? 0) > 0) (p, _quantites[p.id]!),
      ];
      final octets = await etiquettesPdf(quantites: choix, boutique: widget.boutique.nom, format: _format);
      if (crees > 0 && mounted) _dire('$crees code${crees > 1 ? 's' : ''}-barres créé${crees > 1 ? 's' : ''} pour vos produits.');
      await Printing.layoutPdf(name: 'Etiquettes-Nacrea', onLayout: (_) async => octets);
    } catch (e) {
      if (mounted) _dire(messageErreur(e));
    } finally {
      if (mounted) setState(() => _travail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Étiquettes code-barres')),
      body: StreamBuilder<List<Produit>>(
        stream: _produits,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
          final tous = snap.data!;
          final q = _recherche.text.trim().toLowerCase();
          final visibles = tous
              .where((p) => q.isEmpty || p.nomComplet.toLowerCase().contains(q) || (p.marque?.toLowerCase().contains(q) ?? false))
              .toList();
          final total = _quantites.values.fold(0, (s, n) => s + n);
          final sansCode = tous.where((p) => (_quantites[p.id] ?? 0) > 0 && (p.codeBarres ?? '').trim().isEmpty).length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<FormatEtiquette>(
                      initialValue: _format,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Format', prefixIcon: Icon(Icons.print_outlined)),
                      items: [
                        for (final f in FormatEtiquette.values) DropdownMenuItem(value: f, child: Text(f.libelle)),
                      ],
                      onChanged: (v) => setState(() => _format = v ?? FormatEtiquette.a4),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _recherche,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'Chercher un produit…', prefixIcon: Icon(Icons.search)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                          label: const Text('Autant que le stock'),
                          onPressed: () => setState(() {
                            for (final p in visibles) {
                              if (p.id != null && p.stock > 0) _quantites[p.id!] = p.stock;
                            }
                          }),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.looks_one_outlined, size: 18),
                          label: const Text('1 de chaque'),
                          onPressed: () => setState(() {
                            for (final p in visibles) {
                              if (p.id != null) _quantites[p.id!] = 1;
                            }
                          }),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 18),
                          label: const Text('Tout effacer'),
                          onPressed: () => setState(_quantites.clear),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: visibles.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: NacreaColors.bordure),
                  itemBuilder: (context, i) {
                    final p = visibles[i];
                    final n = _quantites[p.id] ?? 0;
                    final code = (p.codeBarres ?? '').trim();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.nomComplet, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${fcfa(p.prixVente)} · ${code.isEmpty ? 'sans code-barres (il sera créé)' : code} · stock ${p.stock}',
                        style: TextStyle(color: code.isEmpty ? NacreaColors.orTexte : NacreaColors.gris, fontSize: 13),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: n > 0 ? () => setState(() => _quantites[p.id!] = n - 1) : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text('$n', textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            onPressed: p.id == null ? null : () => setState(() => _quantites[p.id!] = n + 1),
                            icon: const Icon(Icons.add_circle_outline, color: NacreaColors.prune),
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
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$total étiquette${total > 1 ? 's' : ''}'
                            '${_format == FormatEtiquette.a4 && total > 0 ? ' · ${(total / 24).ceil()} page${total > 24 ? 's' : ''} A4' : ''}'
                            '${sansCode > 0 ? '\n$sansCode code${sansCode > 1 ? 's' : ''} à créer' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: total == 0 || _travail ? null : () => _imprimer(tous),
                          icon: _travail
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.print_outlined),
                          label: const Text('Imprimer'),
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

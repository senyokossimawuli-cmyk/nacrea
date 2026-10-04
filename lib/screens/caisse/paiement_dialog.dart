import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ventes_repo.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

class Reglement {
  Reglement({required this.paiements, this.recuEspeces, this.monnaie = 0});
  final List<Paiement> paiements;
  final int? recuEspeces;
  final int monnaie;
}

/// Fenêtre « Encaisser » : choix du paiement et calcul de la monnaie à rendre.
/// [cliente] : nom de la cliente du panier (nécessaire pour vendre à crédit).
Future<Reglement?> ouvrirPaiement(BuildContext context, int total, {String? cliente}) {
  return showDialog<Reglement>(
    context: context,
    builder: (_) => _PaiementDialog(total: total, cliente: cliente),
  );
}

class _PaiementDialog extends StatefulWidget {
  const _PaiementDialog({required this.total, this.cliente});
  final int total;
  final String? cliente;

  @override
  State<_PaiementDialog> createState() => _PaiementDialogState();
}

class _PaiementDialogState extends State<_PaiementDialog> {
  MoyenPaiement _moyen = MoyenPaiement.especes;
  bool _mixte = false;
  final _recu = TextEditingController();
  final _avance = TextEditingController();
  MoyenPaiement _moyenAvance = MoyenPaiement.especes;
  final _montants = {for (final m in MoyenPaiement.values) m: TextEditingController()};

  @override
  void dispose() {
    _recu.dispose();
    _avance.dispose();
    for (final c in _montants.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _recuValeur => int.tryParse(_recu.text) ?? 0;
  int get _avanceValeur => int.tryParse(_avance.text) ?? 0;

  /// Moyens proposés : le crédit seulement si une cliente est choisie (en paiement mixte).
  List<MoyenPaiement> get _moyensMixte => [
        for (final m in MoyenPaiement.values)
          if (m != MoyenPaiement.credit || widget.cliente != null) m,
      ];
  int get _sommeMixte => _montants.values.fold(0, (s, c) => s + (int.tryParse(c.text) ?? 0));

  /// Billets courants pour proposer des montants reçus en un clic.
  List<int> get _suggestions {
    final t = widget.total;
    final valeurs = <int>{t};
    for (final pas in [500, 1000, 2000, 5000, 10000]) {
      final arrondi = ((t + pas - 1) ~/ pas) * pas;
      if (arrondi > t) valeurs.add(arrondi);
    }
    return (valeurs.toList()..sort()).take(4).toList();
  }

  String? get _probleme {
    if (_mixte) {
      if ((int.tryParse(_montants[MoyenPaiement.credit]!.text) ?? 0) > 0 && widget.cliente == null) {
        return 'Choisissez la cliente pour vendre à crédit';
      }
      final ecart = widget.total - _sommeMixte;
      if (ecart > 0) return 'Il manque ${fcfa(ecart)}';
      if (ecart < 0) return 'Trop saisi de ${fcfa(-ecart)}';
      return null;
    }
    if (_moyen == MoyenPaiement.especes && _recu.text.isNotEmpty && _recuValeur < widget.total) {
      return 'Montant reçu insuffisant';
    }
    if (_moyen == MoyenPaiement.credit) {
      if (widget.cliente == null) return 'Choisissez d\'abord la cliente';
      if (_avanceValeur > widget.total) return 'L\'avance dépasse le total';
    }
    return null;
  }

  void _valider() {
    if (_probleme != null) return;
    if (_mixte) {
      Navigator.of(context).pop(Reglement(paiements: [
        for (final e in _montants.entries)
          if ((int.tryParse(e.value.text) ?? 0) > 0) Paiement(e.key, int.parse(e.value.text)),
      ]));
      return;
    }
    if (_moyen == MoyenPaiement.credit) {
      final avance = _avanceValeur;
      Navigator.of(context).pop(Reglement(paiements: [
        if (avance > 0) Paiement(_moyenAvance, avance),
        if (widget.total - avance > 0) Paiement(MoyenPaiement.credit, widget.total - avance),
      ]));
      return;
    }
    final especes = _moyen == MoyenPaiement.especes && _recu.text.isNotEmpty;
    Navigator.of(context).pop(Reglement(
      paiements: [Paiement(_moyen, widget.total)],
      recuEspeces: especes ? _recuValeur : null,
      monnaie: especes ? _recuValeur - widget.total : 0,
    ));
  }

  Widget _champMontant(TextEditingController c, String label, {bool focus = false}) => TextField(
        controller: c,
        autofocus: focus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _valider(),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        decoration: InputDecoration(labelText: label, suffixText: 'FCFA'),
      );

  /// Vente à crédit : avance éventuelle, le reste est noté sur le compte de la cliente.
  Widget _zoneCredit() {
    if (widget.cliente == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: NacreaColors.nude, borderRadius: BorderRadius.circular(12)),
        child: const Text(
          'Pour vendre à crédit, revenez au panier et touchez « Ajouter une cliente ».',
          style: TextStyle(height: 1.4),
        ),
      );
    }
    final reste = widget.total - _avanceValeur;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _champMontant(_avance, 'Avance payée maintenant (facultatif)', focus: true),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final m in [MoyenPaiement.especes, MoyenPaiement.mobileMoney])
              ChoiceChip(
                label: Text('Avance en ${m.libelle.toLowerCase()}'),
                selected: _moyenAvance == m,
                onSelected: (_) => setState(() => _moyenAvance = m),
              ),
          ],
        ),
        if (reste >= 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFCEBEB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reste à payer par ${widget.cliente}',
                      style: const TextStyle(fontSize: 15, color: NacreaColors.erreur)),
                ),
                Text(fcfa(reste),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700, color: NacreaColors.erreur)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final probleme = _probleme;
    final monnaie = _recuValeur - widget.total;

    return AlertDialog(
      backgroundColor: Colors.white,
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Total à payer', style: TextStyle(color: NacreaColors.gris)),
              Text(fcfa(widget.total),
                  style: NacreaTheme.titre(size: 44, color: NacreaColors.prune)),
              if (widget.cliente != null)
                Text('Cliente : ${widget.cliente}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              if (!_mixte) ...[
                Row(
                  children: [
                    for (final m in MoyenPaiement.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _BoutonMoyen(
                            moyen: m,
                            actif: _moyen == m,
                            quandTouche: () => setState(() => _moyen = m),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_moyen == MoyenPaiement.especes) ...[
                  _champMontant(_recu, 'Montant reçu (facultatif)', focus: true),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _suggestions)
                        ActionChip(
                          label: Text(milliers(s)),
                          backgroundColor: NacreaColors.nude,
                          side: BorderSide.none,
                          onPressed: () => setState(() => _recu.text = '$s'),
                        ),
                    ],
                  ),
                  if (_recu.text.isNotEmpty && monnaie >= 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F3EA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text('Monnaie à rendre',
                              style: TextStyle(fontSize: 16, color: NacreaColors.succes)),
                          const Spacer(),
                          Text(fcfa(monnaie),
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: NacreaColors.succes)),
                        ],
                      ),
                    ),
                  ],
                ],
                if (_moyen == MoyenPaiement.credit) _zoneCredit(),
              ] else ...[
                for (final m in _moyensMixte) ...[
                  _champMontant(_montants[m]!, m == MoyenPaiement.credit ? 'Crédit (reste à payer)' : m.libelle),
                  const SizedBox(height: 12),
                ],
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _mixte = !_mixte),
                  icon: Icon(_mixte ? Icons.looks_one_outlined : Icons.call_split),
                  label: Text(_mixte ? 'Un seul moyen de paiement' : 'Paiement mixte'),
                ),
              ),
              if (probleme != null) ...[
                const SizedBox(height: 8),
                Text(probleme,
                    style: const TextStyle(color: NacreaColors.erreur, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Retour'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: probleme == null ? _valider : null,
                      child: const Text('Valider la vente'),
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

class _BoutonMoyen extends StatelessWidget {
  const _BoutonMoyen({required this.moyen, required this.actif, required this.quandTouche});
  final MoyenPaiement moyen;
  final bool actif;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    final icone = switch (moyen) {
      MoyenPaiement.especes => Icons.payments_outlined,
      MoyenPaiement.mobileMoney => Icons.phone_android,
      MoyenPaiement.carte => Icons.credit_card,
      MoyenPaiement.credit => Icons.event_note_outlined,
    };
    return Material(
      color: actif ? NacreaColors.prune : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: actif ? NacreaColors.prune : NacreaColors.bordure),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: quandTouche,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icone, color: actif ? Colors.white : NacreaColors.prune),
              const SizedBox(height: 6),
              Text(
                moyen.libelle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: actif ? Colors.white : NacreaColors.chocolat,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

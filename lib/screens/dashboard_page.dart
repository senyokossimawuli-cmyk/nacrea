import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/base_locale.dart';
import '../data/produits_repo.dart';
import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../utils/format.dart';

/// Une boutique et son abonnement, tels qu'affichés sur l'accueil.
class _BoutiqueAbo {
  _BoutiqueAbo(this.boutique, this.statut, this.finPeriode, this.prixMensuel);
  final Boutique boutique;
  final String? statut;
  final DateTime? finPeriode;
  final int prixMensuel;
}

/// Page d'accueil : salutation, boutiques avec leur abonnement,
/// ajout d'un point de vente (patronne).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.membre, required this.boutiques});
  final Membre membre;
  final List<Boutique> boutiques;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// Lu sur l'appareil (fonctionne hors ligne) et mis à jour en direct.
  late final Stream<List<_BoutiqueAbo>> _boutiques = db
      .watch(
        'SELECT s.id, s.name, s.address, s.phone, a.status, a.current_period_end, a.monthly_price '
        'FROM shops s LEFT JOIN subscriptions a ON a.shop_id = s.id '
        'ORDER BY julianday(s.created_at)',
        triggerOnTables: const ['shops', 'subscriptions'],
      )
      .map((lignes) => [
            for (final l in lignes)
              _BoutiqueAbo(
                Boutique(
                  id: l['id'] as String,
                  nom: l['name'] as String? ?? '',
                  adresse: l['address'] as String?,
                  telephone: l['phone'] as String?,
                ),
                l['status'] as String?,
                DateTime.tryParse(l['current_period_end'] as String? ?? '')?.toLocal(),
                (l['monthly_price'] as int?) ?? 22000,
              ),
          ]);

  Future<void> _ajouter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _BoutiqueDialog(compteId: widget.membre.compteId),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau point de vente créé : 14 jours d\'essai gratuit.')),
      );
    }
  }

  Future<void> _modifier(Boutique b) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _BoutiqueDialog(compteId: widget.membre.compteId, boutique: b),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membre;
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.all(etroit ? 16 : 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bonjour, ${m.nom}', style: NacreaTheme.titre(size: etroit ? 32 : 40)),
                const SizedBox(height: 6),
                Text(
                  '${m.nomCompte} · ${m.estPatronne ? 'Patronne' : 'Employée'}',
                  style: const TextStyle(fontSize: 15, color: NacreaColors.gris),
                ),
                const SizedBox(height: 28),
                StreamBuilder<List<_BoutiqueAbo>>(
                  stream: _boutiques,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text(messageErreur(snap.error!),
                          style: const TextStyle(color: NacreaColors.erreur));
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                      );
                    }
                    final liste = snap.data!;
                    final total = liste.fold<int>(0, (s, b) => s + b.prixMensuel);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            Text(
                              m.estPatronne
                                  ? (liste.length > 1 ? 'Vos ${liste.length} boutiques' : 'Votre boutique')
                                  : 'Votre boutique',
                              style: NacreaTheme.titre(size: 26),
                            ),
                            if (m.estPatronne)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                onPressed: _ajouter,
                                icon: const Icon(Icons.add_business_outlined),
                                label: const Text('Ajouter un point de vente'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final b in liste)
                              _CarteBoutique(
                                b,
                                avecAbonnement: m.estPatronne,
                                largeur: etroit ? double.infinity : 300,
                                quandTouche: m.estPatronne ? () => _modifier(b.boutique) : null,
                              ),
                          ],
                        ),
                        if (m.estPatronne && liste.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Abonnement : ${liste.length} boutique${liste.length > 1 ? 's' : ''} · '
                            '${fcfa(total)} par mois',
                            style: const TextStyle(color: NacreaColors.gris, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: NacreaColors.nude,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, color: NacreaColors.orTexte),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Bientôt ici : les chiffres du jour et les alertes de toutes vos boutiques.',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CarteBoutique extends StatelessWidget {
  const _CarteBoutique(this.b, {required this.avecAbonnement, required this.largeur, this.quandTouche});
  final _BoutiqueAbo b;
  final bool avecAbonnement;
  final double largeur;
  final VoidCallback? quandTouche;

  @override
  Widget build(BuildContext context) {
    final (texte, couleur, fond) = _statut(b.statut, b.finPeriode);
    final boutique = b.boutique;
    return SizedBox(
      width: largeur,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: quandTouche,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: NacreaColors.prune, size: 28),
                    const Spacer(),
                    if (quandTouche != null)
                      const Icon(Icons.edit_outlined, color: NacreaColors.gris, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                Text(boutique.nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (boutique.adresse?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(boutique.adresse!, style: const TextStyle(color: NacreaColors.gris)),
                ],
                if (boutique.telephone?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(boutique.telephone!, style: const TextStyle(color: NacreaColors.gris)),
                ],
                if (avecAbonnement) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
                    child: Text(texte,
                        style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static (String, Color, Color) _statut(String? statut, DateTime? fin) {
    final date = fin == null ? '' : ' jusqu\'au ${dateCourte(fin)}';
    switch (statut) {
      case 'trial':
        return ('Essai gratuit$date', NacreaColors.orTexte, const Color(0xFFF7EEDB));
      case 'active':
        return ('Abonnement actif$date', NacreaColors.succes, const Color(0xFFE5F3EA));
      case 'late':
        return ('Paiement en retard', NacreaColors.erreur, const Color(0xFFFCEBEB));
      case 'suspended':
        return ('Suspendu (lecture seule)', NacreaColors.erreur, const Color(0xFFFCEBEB));
      default:
        return ('Abonnement en préparation…', NacreaColors.gris, NacreaColors.nude);
    }
  }
}

/// Créer un point de vente (en ligne) ou modifier une boutique (fonctionne hors ligne).
class _BoutiqueDialog extends StatefulWidget {
  const _BoutiqueDialog({required this.compteId, this.boutique});
  final String compteId;
  final Boutique? boutique;

  @override
  State<_BoutiqueDialog> createState() => _BoutiqueDialogState();
}

class _BoutiqueDialogState extends State<_BoutiqueDialog> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.boutique?.nom);
  late final _adresse = TextEditingController(text: widget.boutique?.adresse);
  late final _telephone = TextEditingController(text: widget.boutique?.telephone);
  bool _chargement = false;
  String? _erreur;

  bool get _creation => widget.boutique == null;

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    _telephone.dispose();
    super.dispose();
  }

  String? _texte(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _valider() async {
    if (_chargement || !_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      if (_creation) {
        // La création passe par le serveur : il prépare l'abonnement (14 jours d'essai).
        await Supabase.instance.client.from('shops').insert({
          'account_id': widget.compteId,
          'name': _nom.text.trim(),
          'address': _texte(_adresse),
          'phone': _texte(_telephone),
        });
      } else {
        await db.execute(
          'UPDATE shops SET name = ?, address = ?, phone = ? WHERE id = ?',
          [_nom.text.trim(), _texte(_adresse), _texte(_telephone), widget.boutique!.id],
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creation ? 'Nouveau point de vente' : 'Modifier la boutique',
          style: NacreaTheme.titre(size: 26)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_creation) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7EEDB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Chaque point de vente a son propre stock, sa caisse et ses ventes.\n'
                      'Abonnement : ${fcfa(22000)} par mois, après 14 jours d\'essai gratuit.',
                      style: const TextStyle(color: NacreaColors.chocolat),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nom,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la boutique',
                    hintText: 'Boutique de Bè',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez le nom' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _adresse,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (facultatif)',
                    hintText: 'Quartier, rue, repère',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _telephone,
                  keyboardType: TextInputType.phone,
                  onFieldSubmitted: (_) => _valider(),
                  decoration: const InputDecoration(
                    labelText: 'Téléphone (facultatif)',
                    hintText: '+228 90 00 00 00',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'L\'adresse et le téléphone sont imprimés sur les reçus.',
                  style: TextStyle(color: NacreaColors.gris, fontSize: 13),
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
                        onPressed: _chargement ? null : () => Navigator.pop(context, false),
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
                            : Text(_creation ? 'Créer' : 'Enregistrer'),
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

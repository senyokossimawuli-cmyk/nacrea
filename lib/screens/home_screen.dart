import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/nacrea_logo.dart';

/// Accueil après connexion : salutation et liste des boutiques avec leur abonnement.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.membre});
  final Membre membre;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Map<String, dynamic>>> _boutiques = _chargerBoutiques();

  Future<List<Map<String, dynamic>>> _chargerBoutiques() async {
    final lignes = await Supabase.instance.client
        .from('shops')
        .select('id, name, address, subscriptions(status, current_period_end)')
        .order('created_at');
    return List<Map<String, dynamic>>.from(lignes);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membre;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 24,
        title: const NacreaLogo(taille: 26, avecSlogan: false),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(m.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
          const SizedBox(width: 16),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: NacreaColors.bordure),
        ),
      ),
      body: RefreshIndicator(
        color: NacreaColors.prune,
        onRefresh: () async {
          setState(() => _boutiques = _chargerBoutiques());
          await _boutiques;
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bonjour, ${m.nom.split(' ').first}', style: NacreaTheme.titre(size: 40)),
                    const SizedBox(height: 6),
                    Text(
                      '${m.nomCompte} · ${m.estPatronne ? 'Patronne' : 'Employée'}',
                      style: const TextStyle(fontSize: 15, color: NacreaColors.gris),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      m.estPatronne ? 'Vos boutiques' : 'Votre boutique',
                      style: NacreaTheme.titre(size: 26),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _boutiques,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: CircularProgressIndicator(color: NacreaColors.prune),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Text(messageErreur(snap.error!),
                              style: const TextStyle(color: NacreaColors.erreur));
                        }
                        final boutiques = snap.data!;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [for (final b in boutiques) _CarteBoutique(boutique: b)],
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
                              'Bientôt ici : la caisse, les produits et le stock.',
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
        ),
      ),
    );
  }
}

class _CarteBoutique extends StatelessWidget {
  const _CarteBoutique({required this.boutique});
  final Map<String, dynamic> boutique;

  @override
  Widget build(BuildContext context) {
    // L'abonnement peut arriver sous forme d'objet ou de liste selon la base.
    final brut = boutique['subscriptions'];
    final Map? abo = brut is List ? (brut.isEmpty ? null : brut.first as Map) : brut as Map?;
    final (texte, couleur, fond) = _statut(abo);

    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_outlined, color: NacreaColors.prune, size: 28),
              const SizedBox(height: 14),
              Text(
                boutique['name'] as String? ?? '',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              if ((boutique['address'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Text(boutique['address'] as String,
                    style: const TextStyle(color: NacreaColors.gris)),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
                child: Text(texte,
                    style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static (String, Color, Color) _statut(Map? abo) {
    final fin = DateTime.tryParse(abo?['current_period_end'] as String? ?? '')?.toLocal();
    final date = fin == null
        ? ''
        : ' jusqu\'au ${fin.day.toString().padLeft(2, '0')}/${fin.month.toString().padLeft(2, '0')}/${fin.year}';
    switch (abo?['status']) {
      case 'trial':
        return ('Essai gratuit$date', NacreaColors.orTexte, const Color(0xFFF7EEDB));
      case 'active':
        return ('Abonnement actif$date', NacreaColors.succes, const Color(0xFFE5F3EA));
      case 'late':
        return ('Paiement en retard', NacreaColors.erreur, const Color(0xFFFCEBEB));
      case 'suspended':
        return ('Suspendu (lecture seule)', NacreaColors.erreur, const Color(0xFFFCEBEB));
      default:
        return ('Abonnement inconnu', NacreaColors.gris, NacreaColors.nude);
    }
  }
}

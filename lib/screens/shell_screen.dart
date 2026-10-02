import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/produits_repo.dart';
import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/nacrea_logo.dart';
import 'dashboard_page.dart';
import 'produits/produits_page.dart';

/// Cadre principal après connexion : menu (à gauche sur PC, en bas sur téléphone),
/// choix de la boutique et page affichée.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.membre});
  final Membre membre;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  late Future<List<Boutique>> _chargement = Boutique.chargerToutes();
  Boutique? _boutique;
  int _page = 0;

  static const _menu = [
    (icone: Icons.space_dashboard_outlined, iconeActive: Icons.space_dashboard, titre: 'Accueil'),
    (icone: Icons.inventory_2_outlined, iconeActive: Icons.inventory_2, titre: 'Produits'),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Boutique>>(
      future: _chargement,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
          );
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snap.hasError ? messageErreur(snap.error!) : 'Aucune boutique trouvée.'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _chargement = Boutique.chargerToutes()),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          );
        }
        final boutiques = snap.data!;
        final boutique = boutiques.firstWhere(
          (b) => b.id == _boutique?.id,
          orElse: () => boutiques.first,
        );
        return _construire(context, boutiques, boutique);
      },
    );
  }

  Widget _construire(BuildContext context, List<Boutique> boutiques, Boutique boutique) {
    final m = widget.membre;
    final page = switch (_page) {
      1 => ProduitsPage(key: ValueKey('produits-${boutique.id}'), membre: m, boutique: boutique),
      _ => DashboardPage(membre: m, boutiques: boutiques),
    };
    final large = MediaQuery.sizeOf(context).width >= 900;

    final barre = AppBar(
      toolbarHeight: 72,
      titleSpacing: 24,
      title: const NacreaLogo(taille: 26, avecSlogan: false),
      actions: [
        if (boutiques.length > 1)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DropdownButton<String>(
              value: boutique.id,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.expand_more, color: NacreaColors.prune),
              items: [
                for (final b in boutiques)
                  DropdownMenuItem(value: b.id, child: Text(b.nom)),
              ],
              onChanged: (id) => setState(() => _boutique = boutiques.firstWhere((b) => b.id == id)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 20, color: NacreaColors.prune),
                  const SizedBox(width: 8),
                  Text(boutique.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        if (large)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: Text(m.nom, style: const TextStyle(color: NacreaColors.gris))),
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
    );

    if (large) {
      return Scaffold(
        appBar: barre,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: Colors.white,
              selectedIndex: _page,
              onDestinationSelected: (i) => setState(() => _page = i),
              labelType: NavigationRailLabelType.all,
              indicatorColor: NacreaColors.nude,
              selectedIconTheme: const IconThemeData(color: NacreaColors.prune),
              selectedLabelTextStyle: const TextStyle(
                color: NacreaColors.prune,
                fontWeight: FontWeight.w600,
              ),
              destinations: [
                for (final d in _menu)
                  NavigationRailDestination(
                    icon: Icon(d.icone),
                    selectedIcon: Icon(d.iconeActive),
                    label: Text(d.titre),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: NacreaColors.bordure),
            Expanded(child: page),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: barre,
      body: page,
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: NacreaColors.nude,
        selectedIndex: _page,
        onDestinationSelected: (i) => setState(() => _page = i),
        destinations: [
          for (final d in _menu)
            NavigationDestination(
              icon: Icon(d.icone),
              selectedIcon: Icon(d.iconeActive, color: NacreaColors.prune),
              label: d.titre,
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/produits_repo.dart';
import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/deconnexion.dart';
import '../widgets/etat_synchro.dart';
import '../widgets/nacrea_logo.dart';
import 'caisse/session_caisse.dart';
import 'clientes/clientes_page.dart';
import 'dashboard_page.dart';
import 'equipe/equipe_page.dart';
import 'produits/produits_page.dart';
import 'ventes/ventes_page.dart';

/// Cadre principal après connexion : menu (à gauche sur PC, en bas sur téléphone),
/// choix de la boutique et page affichée.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.membre});
  final Membre membre;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final Stream<List<Boutique>> _boutiques = Boutique.surveiller();
  Boutique? _boutique;
  // Une employée n'a pas d'Accueil : elle arrive directement sur la caisse.
  int _page = 0;

  static const _accueil =
      (cle: 'accueil', icone: Icons.space_dashboard_outlined, iconeActive: Icons.space_dashboard, titre: 'Accueil');
  static const _caisse =
      (cle: 'caisse', icone: Icons.point_of_sale_outlined, iconeActive: Icons.point_of_sale, titre: 'Caisse');
  static const _produits =
      (cle: 'produits', icone: Icons.inventory_2_outlined, iconeActive: Icons.inventory_2, titre: 'Produits');
  static const _ventes =
      (cle: 'ventes', icone: Icons.receipt_long_outlined, iconeActive: Icons.receipt_long, titre: 'Ventes');
  static const _clientes =
      (cle: 'clientes', icone: Icons.favorite_border, iconeActive: Icons.favorite, titre: 'Clientes');
  static const _equipe =
      (cle: 'equipe', icone: Icons.groups_outlined, iconeActive: Icons.groups, titre: 'Équipe');

  late final _menu = widget.membre.estPatronne
      ? const [_accueil, _caisse, _produits, _ventes, _clientes, _equipe]
      : const [_caisse, _produits, _ventes, _clientes];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Boutique>>(
      stream: _boutiques,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
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
                    onPressed: () => deconnexion(context),
                    child: const Text('Se déconnecter'),
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
    if (_page >= _menu.length) _page = 0;
    final page = switch (_menu[_page].cle) {
      'caisse' => CaissePorte(key: ValueKey('caisse-${boutique.id}'), membre: m, boutique: boutique),
      'produits' => ProduitsPage(key: ValueKey('produits-${boutique.id}'), membre: m, boutique: boutique),
      'ventes' => VentesPage(key: ValueKey('ventes-${boutique.id}'), membre: m, boutique: boutique),
      'clientes' => ClientesPage(key: ValueKey('clientes-${boutique.id}'), membre: m, boutique: boutique),
      'equipe' => EquipePage(membre: m, boutiques: boutiques),
      _ => DashboardPage(membre: m, boutiques: boutiques),
    };
    final large = MediaQuery.sizeOf(context).width >= 900;

    final barre = AppBar(
      toolbarHeight: large ? 72 : 60,
      titleSpacing: large ? 24 : 14,
      title: NacreaLogo(taille: large ? 26 : 18, avecSlogan: false),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(child: EtatSynchro(compact: !large)),
        ),
        if (boutiques.length > 1)
          Padding(
            padding: EdgeInsets.only(right: large ? 16 : 4),
            child: DropdownButton<String>(
              value: boutique.id,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.expand_more, color: NacreaColors.prune),
              items: [
                for (final b in boutiques)
                  DropdownMenuItem(
                    value: b.id,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: large ? 260 : 110),
                      child: Text(b.nom, overflow: TextOverflow.ellipsis),
                    ),
                  ),
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
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: large ? 260 : 110),
                    child: Text(
                      boutique.nom,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
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
          onPressed: () => deconnexion(context),
        ),
        SizedBox(width: large ? 16 : 4),
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
        // 6 entrées sur un téléphone : on n'affiche que le nom de la page choisie.
        labelBehavior: _menu.length > 5
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
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

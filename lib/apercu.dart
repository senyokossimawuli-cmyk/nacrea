// Aperçu du tableau de bord avec des données d'exemple.
// Utilisé seulement pour les captures d'écran de vérification
// (fabrication avec --dart-define=APERCU=true) ; absent de l'application livrée.
import 'package:flutter/material.dart';

import 'data/accueil_repo.dart';
import 'data/rapports_repo.dart';
import 'screens/dashboard_page.dart';
import 'theme/nacrea_theme.dart';

Rapport _rapport({required int ca, required int n, int cout = 0, List<PointCourbe> courbe = const [],
    List<ProduitVendu> top = const [], int credits = 0}) =>
    Rapport(
      nbVentes: n,
      chiffreAffaires: ca,
      remises: 0,
      coutMarchandises: cout,
      depenses: const {},
      parMoyen: const {},
      remboursements: 0,
      topProduits: top,
      courbe: courbe,
      parMois: false,
      parBoutique: const {},
      valeurStock: 0,
      creditsEnCours: credits,
    );

Accueil exempleAccueil() {
  final n = DateTime.now();
  final j = DateTime(n.year, n.month, n.day);
  final montants = [42000, 0, 68500, 51000, 93500, 120000, 76500];
  String cle(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return Accueil(
    jour: _rapport(ca: 76500, n: 14, cout: 45200),
    hier: _rapport(ca: 120000, n: 19, cout: 70400),
    semaine: _rapport(ca: 451500, n: 80, courbe: [
      for (var i = 0; i < 7; i++) PointCourbe(cle(j.subtract(Duration(days: 6 - i))), montants[i]),
    ]),
    mois: _rapport(ca: 1385000, n: 241, cout: 812000, credits: 37500, top: [
      ProduitVendu(nom: 'Lait corporel karité · 400 ml', quantite: 46, chiffre: 184000, cout: 115000),
      ProduitVendu(nom: 'Rouge à lèvres mat · Cerise', quantite: 31, chiffre: 93000, cout: 55800),
      ProduitVendu(nom: 'Savon noir', quantite: 28, chiffre: 42000, cout: 22400),
      ProduitVendu(nom: 'Huile de coco · 250 ml', quantite: 19, chiffre: 47500, cout: 28500),
      ProduitVendu(nom: 'Fond de teint · Caramel', quantite: 12, chiffre: 102000, cout: 66000),
    ]),
    stockBas: [
      ProduitAlerte(nom: 'Crème éclaircissante', stock: 2, stockMin: 5),
      ProduitAlerte(nom: 'Mascara noir', stock: 0, stockMin: 3),
      ProduitAlerte(nom: 'Gel douche vanille', stock: 3, stockMin: 4),
      ProduitAlerte(nom: 'Shampoing argan', stock: 1, stockMin: 4),
    ],
    peremptions: [
      ProduitAlerte(nom: 'Lotion tonique', peremption: j.add(const Duration(days: 12)), stock: 6),
      ProduitAlerte(nom: 'Masque argile', peremption: j.subtract(const Duration(days: 2)), stock: 2),
    ],
    caisses: [CaisseBoutique(boutique: 'Beauté Awa', ouverteLe: j.add(const Duration(hours: 8, minutes: 12)))],
    dernieresVentes: [
      DerniereVente(ticket: 'A-0143', total: 12500, date: n.subtract(const Duration(minutes: 8)), cliente: 'Akossiwa'),
      DerniereVente(ticket: 'A-0142', total: 4000, date: n.subtract(const Duration(minutes: 31))),
      DerniereVente(ticket: 'A-0141', total: 27000, date: n.subtract(const Duration(hours: 1, minutes: 5)), cliente: 'Mme Kodjo'),
      DerniereVente(ticket: 'A-0140', total: 6500, date: n.subtract(const Duration(hours: 2))),
      DerniereVente(ticket: 'A-0139', total: 15000, date: n.subtract(const Duration(hours: 3))),
    ],
  );
}

class ApercuApp extends StatelessWidget {
  const ApercuApp({super.key});

  @override
  Widget build(BuildContext context) {
    NacreaColors.sombre = Uri.base.queryParameters['mode'] == 'sombre';
    final a = exempleAccueil();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NacreaTheme.actuel(),
      home: Scaffold(
        appBar: AppBar(title: const Text('YDS Beauty — aperçu')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EnTeteAccueil(nom: 'Awa', entreprise: 'Beauté Awa', quandAller: (_) {}),
                    const SizedBox(height: 24),
                    TableauAccueil(a: a, quandAller: (_) {}),
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

import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class ProduitVendu {
  ProduitVendu({required this.nom, required this.quantite, required this.chiffre, required this.cout});
  final String nom;
  final int quantite;
  final int chiffre; // prix de vente × quantité (avant remise globale)
  final int cout;
  int get marge => chiffre - cout;
}

class PointCourbe {
  PointCourbe(this.cle, this.montant);
  final String cle; // AAAA-MM-JJ, ou AAAA-MM pour l'année
  final int montant;
}

class Rapport {
  Rapport({
    required this.nbVentes,
    required this.chiffreAffaires,
    required this.remises,
    required this.coutMarchandises,
    required this.depenses,
    required this.parMoyen,
    required this.remboursements,
    required this.topProduits,
    required this.courbe,
    required this.parMois,
    required this.parBoutique,
    required this.valeurStock,
    required this.creditsEnCours,
    this.ecartsStock = 0,
    this.ecartsParMotif = const {},
    this.retours = 0,
    this.coutRetoursRemis = 0,
  });

  final int nbVentes;
  final int chiffreAffaires; // total encaissé + à crédit, après remises
  final int remises;
  final int coutMarchandises; // prix d'achat des produits vendus
  final Map<String, int> depenses; // par catégorie
  final Map<String, int> parMoyen; // cash, mobile_money, card, credit
  final int remboursements; // dettes réglées par les clientes sur la période
  final List<ProduitVendu> topProduits;
  final List<PointCourbe> courbe;
  final bool parMois;
  final Map<String, int> parBoutique; // nom → chiffre d'affaires (toutes les boutiques)
  final int valeurStock; // aujourd'hui, au prix d'achat
  final int creditsEnCours; // ce que doivent toutes les clientes aujourd'hui

  /// Casse, vol, cadeaux, inventaire… au prix d'achat (négatif = perte).
  final int ecartsStock;
  final Map<String, int> ecartsParMotif;

  /// Retours : montant remboursé, et prix d'achat des articles remis en rayon.
  final int retours;
  final int coutRetoursRemis;

  int get totalDepenses => depenses.values.fold(0, (s, v) => s + v);
  /// Chiffre d'affaires après retours.
  int get chiffreNet => chiffreAffaires - retours;
  int get coutNet => coutMarchandises - coutRetoursRemis;
  int get margeBrute => chiffreNet - coutNet;
  int get benefice => margeBrute - totalDepenses + ecartsStock;
  int get panierMoyen => nbVentes == 0 ? 0 : chiffreAffaires ~/ nbVentes;
  double get tauxMarge => chiffreNet == 0 ? 0 : margeBrute / chiffreNet;
}

String _jour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Calcule les chiffres d'une période sur l'appareil (fonctionne hors ligne).
class RapportsRepo {
  RapportsRepo({required this.compteId});
  final String compteId;

  /// [boutiqueId] nul : toutes les boutiques. [debut] et [fin] : jours inclus.
  Future<Rapport> calculer({String? boutiqueId, required DateTime debut, required DateTime fin}) async {
    final de = DateTime(debut.year, debut.month, debut.day).toUtc().toIso8601String();
    final a = DateTime(fin.year, fin.month, fin.day).add(const Duration(days: 1)).toUtc().toIso8601String();
    final parMois = fin.difference(debut).inDays > 62;

    // Filtre commun sur les ventes (alias s)
    const filtreVentes = "s.account_id = ? AND (? IS NULL OR s.shop_id = ?) AND s.status = 'completed' "
        'AND julianday(s.created_at) >= julianday(?) AND julianday(s.created_at) < julianday(?)';
    final p = [compteId, boutiqueId, boutiqueId, de, a];

    final ventes = await db.get(
      'SELECT COUNT(*) AS n, COALESCE(SUM(s.total), 0) AS total, COALESCE(SUM(s.discount), 0) AS remises '
      'FROM sales s WHERE $filtreVentes',
      p,
    );
    final cout = await db.get(
      'SELECT COALESCE(SUM(i.quantity * i.cost_price), 0) AS cout '
      'FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE $filtreVentes',
      p,
    );
    final moyens = await db.getAll(
      'SELECT pa.method, COALESCE(SUM(pa.amount), 0) AS total '
      'FROM payments pa JOIN sales s ON s.id = pa.sale_id WHERE $filtreVentes GROUP BY pa.method',
      p,
    );
    final remb = await db.get(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM customer_payments '
      "WHERE account_id = ? AND (? IS NULL OR shop_id = ?) AND method != 'return' "
      'AND julianday(created_at) >= julianday(?) AND julianday(created_at) < julianday(?)',
      p,
    );
    final depenses = await db.getAll(
      'SELECT category, COALESCE(SUM(amount), 0) AS total FROM expenses '
      'WHERE account_id = ? AND (? IS NULL OR shop_id = ?) AND spent_on >= ? AND spent_on <= ? '
      'GROUP BY category ORDER BY total DESC',
      [compteId, boutiqueId, boutiqueId, _jour(debut), _jour(fin)],
    );
    final retours = await db.get(
      'SELECT COALESCE(SUM(r.refund_amount), 0) AS rembourse, '
      '(SELECT COALESCE(SUM(i.quantity * i.cost_price), 0) FROM sale_return_items i JOIN sale_returns r2 ON r2.id = i.return_id '
      '  WHERE i.restocked = 1 AND r2.account_id = ? AND (? IS NULL OR r2.shop_id = ?) '
      '  AND julianday(r2.created_at) >= julianday(?) AND julianday(r2.created_at) < julianday(?)) AS cout_remis '
      'FROM sale_returns r WHERE r.account_id = ? AND (? IS NULL OR r.shop_id = ?) '
      'AND julianday(r.created_at) >= julianday(?) AND julianday(r.created_at) < julianday(?)',
      [...p, ...p],
    );
    final ecarts = await db.getAll(
      'SELECT reason, COALESCE(SUM(cost_value), 0) AS total FROM stock_adjustments '
      'WHERE account_id = ? AND (? IS NULL OR shop_id = ?) '
      'AND julianday(created_at) >= julianday(?) AND julianday(created_at) < julianday(?) '
      'GROUP BY reason',
      p,
    );
    final top = await db.getAll(
      'SELECT pr.name, pr.brand, pr.variant_label, SUM(i.quantity) AS qte, '
      'SUM(i.quantity * i.unit_price) AS ca, SUM(i.quantity * i.cost_price) AS cout '
      'FROM sale_items i JOIN sales s ON s.id = i.sale_id JOIN products pr ON pr.id = i.product_id '
      'WHERE $filtreVentes GROUP BY i.product_id ORDER BY ca DESC LIMIT 10',
      p,
    );
    final format = parMois ? '%Y-%m' : '%Y-%m-%d';
    final courbe = await db.getAll(
      "SELECT strftime('$format', s.created_at, 'localtime') AS cle, COALESCE(SUM(s.total), 0) AS total "
      'FROM sales s WHERE $filtreVentes GROUP BY cle ORDER BY cle',
      p,
    );
    final boutiques = await db.getAll(
      'SELECT sh.name, COALESCE(SUM(s.total), 0) AS total FROM sales s JOIN shops sh ON sh.id = s.shop_id '
      'WHERE $filtreVentes GROUP BY s.shop_id ORDER BY total DESC',
      p,
    );
    final stock = await db.get(
      'SELECT COALESCE(SUM(quantity * cost_price), 0) AS valeur FROM stock_lots '
      'WHERE account_id = ? AND (? IS NULL OR shop_id = ?) AND quantity > 0',
      [compteId, boutiqueId, boutiqueId],
    );
    final credits = await db.get(
      'SELECT '
      "(SELECT COALESCE(SUM(pa.amount), 0) FROM payments pa JOIN sales s ON s.id = pa.sale_id "
      "  WHERE s.account_id = ? AND pa.method = 'credit' AND s.status != 'cancelled') - "
      '(SELECT COALESCE(SUM(amount), 0) FROM customer_payments WHERE account_id = ?) AS du',
      [compteId, compteId],
    );

    // Courbe complète : un point par jour (ou par mois), même sans vente.
    final valeurs = {for (final l in courbe) l['cle'] as String: _entier(l['total'])};
    final points = <PointCourbe>[];
    if (parMois) {
      for (var m = DateTime(debut.year, debut.month); !m.isAfter(fin); m = DateTime(m.year, m.month + 1)) {
        final cle = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        points.add(PointCourbe(cle, valeurs[cle] ?? 0));
      }
    } else {
      for (var d = DateTime(debut.year, debut.month, debut.day); !d.isAfter(fin); d = DateTime(d.year, d.month, d.day + 1)) {
        final cle = _jour(d);
        points.add(PointCourbe(cle, valeurs[cle] ?? 0));
      }
    }

    String nomProduit(Map<String, Object?> l) => [l['name'], l['brand'], l['variant_label']]
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .join(' · ');

    final du = _entier(credits['du']);
    return Rapport(
      nbVentes: _entier(ventes['n']),
      chiffreAffaires: _entier(ventes['total']),
      remises: _entier(ventes['remises']),
      coutMarchandises: _entier(cout['cout']),
      depenses: {for (final l in depenses) l['category'] as String: _entier(l['total'])},
      parMoyen: {for (final l in moyens) l['method'] as String: _entier(l['total'])},
      remboursements: _entier(remb['total']),
      topProduits: [
        for (final l in top)
          ProduitVendu(
            nom: nomProduit(l),
            quantite: _entier(l['qte']),
            chiffre: _entier(l['ca']),
            cout: _entier(l['cout']),
          ),
      ],
      courbe: points,
      parMois: parMois,
      parBoutique: {for (final l in boutiques) l['name'] as String? ?? '': _entier(l['total'])},
      valeurStock: _entier(stock['valeur']),
      creditsEnCours: du < 0 ? 0 : du,
      ecartsParMotif: {for (final l in ecarts) l['reason'] as String: _entier(l['total'])},
      ecartsStock: ecarts.fold(0, (t, l) => t + _entier(l['total'])),
      retours: _entier(retours['rembourse']),
      coutRetoursRemis: _entier(retours['cout_remis']),
    );
  }
}

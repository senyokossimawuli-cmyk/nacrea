import 'base_locale.dart';
import 'rapports_repo.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Un produit à surveiller (stock bas ou péremption proche).
class ProduitAlerte {
  ProduitAlerte({required this.nom, this.boutique, this.stock, this.stockMin, this.peremption});
  final String nom;
  final String? boutique;
  final int? stock, stockMin;
  final DateTime? peremption;
}

class CaisseBoutique {
  CaisseBoutique({required this.boutique, this.ouverteLe});
  final String boutique;
  final DateTime? ouverteLe; // null : fermée
  bool get ouverte => ouverteLe != null;
}

class DerniereVente {
  DerniereVente({required this.ticket, required this.total, required this.date, this.boutique, this.cliente});
  final String ticket;
  final int total;
  final DateTime date;
  final String? boutique, cliente;
}

/// Tout ce que montre l'accueil de la patronne, toutes boutiques confondues.
class Accueil {
  Accueil({
    required this.jour,
    required this.hier,
    required this.semaine,
    required this.mois,
    required this.stockBas,
    required this.peremptions,
    required this.caisses,
    required this.dernieresVentes,
  });

  final Rapport jour, hier, semaine, mois;
  final List<ProduitAlerte> stockBas;
  final List<ProduitAlerte> peremptions;
  final List<CaisseBoutique> caisses;
  final List<DerniereVente> dernieresVentes;

  int get nbAlertes => stockBas.length + peremptions.length + (mois.creditsEnCours > 0 ? 1 : 0);
}

class AccueilRepo {
  AccueilRepo({required this.compteId});
  final String compteId;

  static const tables = [
    'sales', 'sale_items', 'payments', 'products', 'stock_lots', 'cash_sessions',
    'customer_payments', 'expenses', 'sale_returns', 'shops',
  ];

  /// Se recalcule à chaque vente, entrée de stock, ouverture de caisse…
  Stream<Accueil> surveiller() => db
      .watch('SELECT 1', triggerOnTables: tables)
      .asyncMap((_) => calculer());

  Future<Accueil> calculer() async {
    final rapports = RapportsRepo(compteId: compteId);
    final n = DateTime.now();
    final aujourdhui = DateTime(n.year, n.month, n.day);
    final veille = aujourdhui.subtract(const Duration(days: 1));

    final jour = await rapports.calculer(debut: aujourdhui, fin: aujourdhui);
    final hier = await rapports.calculer(debut: veille, fin: veille);
    final semaine = await rapports.calculer(debut: aujourdhui.subtract(const Duration(days: 6)), fin: aujourdhui);
    final mois = await rapports.calculer(debut: DateTime(n.year, n.month, 1), fin: aujourdhui);

    final plusieurs = (await db.get('SELECT COUNT(*) AS n FROM shops WHERE account_id = ?', [compteId]))['n'];
    final avecBoutique = _entier(plusieurs) > 1;

    // Stock bas : à ou sous le seuil d'alerte, dans chaque boutique.
    final bas = await db.getAll('''
      SELECT p.name, p.variant_label, p.min_stock, s.name AS boutique,
             COALESCE((SELECT SUM(l.quantity) FROM stock_lots l
                        WHERE l.product_id = p.id AND l.shop_id = s.id AND l.quantity > 0), 0) AS stock
        FROM products p JOIN shops s ON s.account_id = p.account_id
       WHERE p.account_id = ? AND COALESCE(p.active, 1) IN (1, 'true') AND COALESCE(p.min_stock, 0) > 0
         AND COALESCE((SELECT SUM(l.quantity) FROM stock_lots l
                        WHERE l.product_id = p.id AND l.shop_id = s.id AND l.quantity > 0), 0) <= p.min_stock
       ORDER BY stock, p.name COLLATE NOCASE
       LIMIT 50
    ''', [compteId]);

    // Péremption dans les 30 jours (ou déjà dépassée), produits encore en rayon.
    final limite = aujourdhui.add(const Duration(days: 30));
    final perimes = await db.getAll('''
      SELECT p.name, p.variant_label, s.name AS boutique, MIN(l.expiry_date) AS peremption, SUM(l.quantity) AS stock
        FROM stock_lots l
        JOIN products p ON p.id = l.product_id
        JOIN shops s ON s.id = l.shop_id
       WHERE l.account_id = ? AND l.quantity > 0 AND l.expiry_date IS NOT NULL
         AND julianday(l.expiry_date) <= julianday(?)
       GROUP BY p.id, s.id
       ORDER BY julianday(MIN(l.expiry_date))
       LIMIT 50
    ''', [compteId, limite.toIso8601String().substring(0, 10)]);

    final caisses = await db.getAll('''
      SELECT s.name,
             (SELECT c.opened_at FROM cash_sessions c
               WHERE c.shop_id = s.id AND c.status = 'open'
               ORDER BY julianday(c.opened_at) DESC LIMIT 1) AS ouverte_le
        FROM shops s WHERE s.account_id = ? ORDER BY julianday(s.created_at)
    ''', [compteId]);

    final ventes = await db.getAll('''
      SELECT v.ticket_number, v.total, v.created_at, s.name AS boutique, c.name AS cliente
        FROM sales v
        JOIN shops s ON s.id = v.shop_id
        LEFT JOIN customers c ON c.id = v.customer_id
       WHERE v.account_id = ? AND v.status != 'cancelled'
       ORDER BY julianday(v.created_at) DESC
       LIMIT 5
    ''', [compteId]);

    String nom(Map<String, Object?> l) => [l['name'], l['variant_label']]
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .join(' · ');

    return Accueil(
      jour: jour,
      hier: hier,
      semaine: semaine,
      mois: mois,
      stockBas: [
        for (final l in bas)
          ProduitAlerte(
            nom: nom(l),
            boutique: avecBoutique ? l['boutique'] as String? : null,
            stock: _entier(l['stock']),
            stockMin: _entier(l['min_stock']),
          ),
      ],
      peremptions: [
        for (final l in perimes)
          ProduitAlerte(
            nom: nom(l),
            boutique: avecBoutique ? l['boutique'] as String? : null,
            stock: _entier(l['stock']),
            peremption: _date(l['peremption']),
          ),
      ],
      caisses: [
        for (final l in caisses) CaisseBoutique(boutique: l['name'] as String? ?? '', ouverteLe: _date(l['ouverte_le'])),
      ],
      dernieresVentes: [
        for (final l in ventes)
          DerniereVente(
            ticket: l['ticket_number'] as String? ?? '',
            total: _entier(l['total']),
            date: _date(l['created_at']) ?? DateTime.now(),
            boutique: avecBoutique ? l['boutique'] as String? : null,
            cliente: l['cliente'] as String?,
          ),
      ],
    );
  }
}

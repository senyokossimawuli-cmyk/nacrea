import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;

import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Motifs d'ajustement de stock.
enum MotifAjustement {
  casse('casse', 'Casse', retrait: true),
  vol('vol', 'Vol ou perte', retrait: true),
  cadeau('cadeau', 'Cadeau offert', retrait: true),
  echantillon('echantillon', 'Échantillon ou testeur', retrait: true),
  perime('perime', 'Périmé, jeté', retrait: true),
  correction('correction', 'Correction', retrait: null),
  inventaire('inventaire', 'Inventaire', retrait: null);

  const MotifAjustement(this.code, this.libelle, {required this.retrait});
  final String code;
  final String libelle;

  /// true : retire toujours du stock ; null : ajout ou retrait.
  final bool? retrait;

  static MotifAjustement depuis(String? code) =>
      MotifAjustement.values.firstWhere((m) => m.code == code, orElse: () => MotifAjustement.correction);
}

class Ajustement {
  Ajustement({
    required this.id,
    required this.produit,
    required this.quantite,
    required this.motif,
    required this.valeur,
    this.note,
    required this.le,
  });
  final String id;
  final String produit;
  final int quantite;
  final MotifAjustement motif;
  final int valeur;
  final String? note;
  final DateTime le;
}

class Inventaire {
  Inventaire({required this.id, required this.nbProduits, required this.nbEcarts, required this.valeur, required this.le, this.note});
  final String id;
  final int nbProduits, nbEcarts, valeur;
  final DateTime le;
  final String? note;
}

/// Ligne d'inventaire : un produit, son stock dans le logiciel et ce qui a été compté.
class LigneInventaire {
  LigneInventaire({
    required this.produitId,
    required this.nom,
    this.codeBarres,
    required this.attendu,
    this.compte,
    required this.prixAchat,
  });
  final String produitId;
  final String nom;
  final String? codeBarres;
  final int attendu;
  final int? compte;
  final int prixAchat;

  bool get compteFait => compte != null;
  int get ecart => (compte ?? attendu) - attendu;
  int get valeurEcart => ecart * prixAchat;
}

/// Ajustements et inventaires d'une boutique (fonctionne hors ligne).
class StockRepo {
  StockRepo({required this.boutiqueId, required this.compteId});
  final String boutiqueId;
  final String compteId;

  /// Applique un ajustement aux lots sur l'appareil, comme le fera le serveur.
  /// Renvoie sa valeur au prix d'achat (négative pour un retrait).
  Future<int> _appliquer(SqliteWriteContext tx, String produitId, int quantite, String quand) async {
    final p = await tx.get('SELECT COALESCE(purchase_price, 0) AS cout FROM products WHERE id = ?', [produitId]);
    final cout = _entier(p['cout']);
    var restant = quantite.abs();
    var valeur = 0;
    if (quantite < 0) {
      final lots = await tx.getAll(
        'SELECT id, quantity, cost_price FROM stock_lots WHERE shop_id = ? AND product_id = ? AND quantity > 0 '
        'ORDER BY expiry_date IS NULL, expiry_date, julianday(received_at)',
        [boutiqueId, produitId],
      );
      for (final lot in lots) {
        if (restant == 0) break;
        final dispo = _entier(lot['quantity']);
        final prend = dispo < restant ? dispo : restant;
        await tx.execute('UPDATE stock_lots SET quantity = quantity - ? WHERE id = ?', [prend, lot['id']]);
        valeur -= prend * _entier(lot['cost_price']);
        restant -= prend;
      }
      if (restant > 0) {
        await tx.execute(
          'INSERT INTO stock_lots (id, shop_id, account_id, product_id, quantity, cost_price, received_at) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, ?)',
          [boutiqueId, compteId, produitId, -restant, cout, quand],
        );
        valeur -= restant * cout;
      }
    } else {
      final negatifs = await tx.getAll(
        'SELECT id, quantity FROM stock_lots WHERE shop_id = ? AND product_id = ? AND quantity < 0 '
        'ORDER BY julianday(received_at)',
        [boutiqueId, produitId],
      );
      for (final lot in negatifs) {
        if (restant == 0) break;
        final manque = -_entier(lot['quantity']);
        final prend = manque < restant ? manque : restant;
        await tx.execute('UPDATE stock_lots SET quantity = quantity + ? WHERE id = ?', [prend, lot['id']]);
        restant -= prend;
      }
      if (restant > 0) {
        await tx.execute(
          'INSERT INTO stock_lots (id, shop_id, account_id, product_id, quantity, cost_price, received_at) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, ?)',
          [boutiqueId, compteId, produitId, restant, cout, quand],
        );
      }
      valeur = quantite * cout;
    }
    return valeur;
  }

  /// Casse, vol, cadeau… [quantite] négative pour un retrait, positive pour un ajout.
  Future<void> ajuster({
    required String produitId,
    required int quantite,
    required MotifAjustement motif,
    String? note,
    required String userId,
  }) async {
    if (quantite == 0) throw Exception('Indiquez une quantité');
    final id = await nouvelId();
    final quand = maintenantIso();
    final texte = (note == null || note.trim().isEmpty) ? null : note.trim();
    await db.writeTransaction((tx) async {
      final valeur = await _appliquer(tx, produitId, quantite, quand);
      await tx.execute(
        'INSERT INTO stock_adjustments (id, account_id, shop_id, product_id, quantity, reason, cost_value, note, user_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, compteId, boutiqueId, produitId, quantite, motif.code, valeur, texte, userId, quand],
      );
      await ajouterOperation(tx, 'ajustement', {
        'p_adjustment_id': id,
        'p_shop_id': boutiqueId,
        'p_product_id': produitId,
        'p_quantity': quantite,
        'p_reason': motif.code,
        'p_note': texte,
        'p_created_at': quand,
      });
    });
  }

  /// Derniers ajustements de la boutique.
  Future<List<Ajustement>> historique({int limite = 100}) async {
    final lignes = await db.getAll(
      'SELECT a.id, a.quantity, a.reason, a.cost_value, a.note, a.created_at, p.name, p.variant_label '
      'FROM stock_adjustments a JOIN products p ON p.id = a.product_id '
      'WHERE a.shop_id = ? ORDER BY julianday(a.created_at) DESC LIMIT ?',
      [boutiqueId, limite],
    );
    return [
      for (final l in lignes)
        Ajustement(
          id: l['id'] as String,
          produit: [l['name'], l['variant_label']].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
          quantite: _entier(l['quantity']),
          motif: MotifAjustement.depuis(l['reason'] as String?),
          valeur: _entier(l['cost_value']),
          note: l['note'] as String?,
          le: DateTime.tryParse(l['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        ),
    ];
  }

  Future<List<Inventaire>> inventaires() async {
    final lignes = await db.getAll(
      'SELECT id, nb_products, nb_ecarts, ecart_valeur, note, created_at FROM inventories '
      'WHERE shop_id = ? ORDER BY julianday(created_at) DESC LIMIT 50',
      [boutiqueId],
    );
    return [
      for (final l in lignes)
        Inventaire(
          id: l['id'] as String,
          nbProduits: _entier(l['nb_products']),
          nbEcarts: _entier(l['nb_ecarts']),
          valeur: _entier(l['ecart_valeur']),
          note: l['note'] as String?,
          le: DateTime.tryParse(l['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        ),
    ];
  }

  // ---------------------------------------------------------------- Inventaire

  /// Produits actifs avec leur stock et ce qui a déjà été compté (brouillon).
  Stream<List<LigneInventaire>> surveillerInventaire() => db
      .watch(
        'SELECT p.id, p.name, p.brand, p.variant_label, p.barcode, COALESCE(p.purchase_price, 0) AS cout, '
        '(SELECT COALESCE(SUM(l.quantity), 0) FROM stock_lots l WHERE l.product_id = p.id AND l.shop_id = ?) AS stock, '
        'b.counted '
        'FROM products p LEFT JOIN inventaire_brouillon b ON b.product_id = p.id AND b.shop_id = ? '
        'WHERE p.account_id = ? AND (p.active IS NULL OR p.active = 1) '
        'ORDER BY p.name COLLATE NOCASE',
        parameters: [boutiqueId, boutiqueId, compteId],
        triggerOnTables: const ['products', 'stock_lots', 'inventaire_brouillon'],
      )
      .map((lignes) => [
            for (final l in lignes)
              LigneInventaire(
                produitId: l['id'] as String,
                nom: [l['name'], l['brand'], l['variant_label']]
                    .whereType<String>()
                    .where((t) => t.trim().isNotEmpty)
                    .join(' · '),
                codeBarres: l['barcode'] as String?,
                attendu: _entier(l['stock']),
                compte: l['counted'] == null ? null : _entier(l['counted']),
                prixAchat: _entier(l['cout']),
              ),
          ]);

  /// Enregistre (ou efface, si [compte] est nul) le comptage d'un produit.
  Future<void> compter(String produitId, int? compte) async {
    await db.writeTransaction((tx) async {
      await tx.execute('DELETE FROM inventaire_brouillon WHERE shop_id = ? AND product_id = ?', [boutiqueId, produitId]);
      if (compte != null) {
        await tx.execute(
          'INSERT INTO inventaire_brouillon (id, shop_id, product_id, counted, updated_at) VALUES (uuid(), ?, ?, ?, ?)',
          [boutiqueId, produitId, compte, maintenantIso()],
        );
      }
    });
  }

  Future<void> abandonnerInventaire() async {
    await db.execute('DELETE FROM inventaire_brouillon WHERE shop_id = ?', [boutiqueId]);
  }

  /// Valide l'inventaire : chaque écart entre le compté et le stock du logiciel
  /// devient un ajustement « inventaire ». Les produits non comptés ne changent pas.
  /// Renvoie la valeur totale des écarts (négative = manque).
  Future<int> validerInventaire({String? note, required String userId}) async {
    final inventaireId = await nouvelId();
    final quand = maintenantIso();
    final texte = (note == null || note.trim().isEmpty) ? null : note.trim();
    var total = 0;
    await db.writeTransaction((tx) async {
      final comptes = await tx.getAll(
        'SELECT b.product_id, b.counted, '
        '(SELECT COALESCE(SUM(l.quantity), 0) FROM stock_lots l WHERE l.product_id = b.product_id AND l.shop_id = ?) AS stock '
        'FROM inventaire_brouillon b WHERE b.shop_id = ?',
        [boutiqueId, boutiqueId],
      );
      if (comptes.isEmpty) throw Exception('Aucun produit compté');
      final lignes = <Map<String, Object>>[];
      var nbEcarts = 0;
      for (final c in comptes) {
        final delta = _entier(c['counted']) - _entier(c['stock']);
        if (delta == 0) continue;
        final produitId = c['product_id'] as String;
        final ajustementId = (await tx.get('SELECT uuid() AS id'))['id'] as String;
        final valeur = await _appliquer(tx, produitId, delta, quand);
        total += valeur;
        nbEcarts++;
        await tx.execute(
          'INSERT INTO stock_adjustments (id, account_id, shop_id, product_id, quantity, reason, cost_value, inventory_id, user_id, created_at) '
          "VALUES (?, ?, ?, ?, ?, 'inventaire', ?, ?, ?, ?)",
          [ajustementId, compteId, boutiqueId, produitId, delta, valeur, inventaireId, userId, quand],
        );
        lignes.add({'adjustment_id': ajustementId, 'product_id': produitId, 'delta': delta});
      }
      await tx.execute(
        'INSERT INTO inventories (id, account_id, shop_id, nb_products, nb_ecarts, ecart_valeur, note, user_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [inventaireId, compteId, boutiqueId, comptes.length, nbEcarts, total, texte, userId, quand],
      );
      await ajouterOperation(tx, 'inventaire', {
        'p_inventory_id': inventaireId,
        'p_shop_id': boutiqueId,
        'p_lines': lignes,
        'p_nb_products': comptes.length,
        'p_note': texte,
        'p_created_at': quand,
      });
      await tx.execute('DELETE FROM inventaire_brouillon WHERE shop_id = ?', [boutiqueId]);
    });
    return total;
  }
}

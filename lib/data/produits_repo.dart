import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/format.dart';
import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
int? _entierOuNull(Object? v) => v == null ? null : _entier(v);

/// Lit une date venant de la base (texte), ou null.
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class Boutique {
  Boutique({required this.id, required this.nom, this.adresse});
  final String id;
  final String nom;
  final String? adresse;

  static Boutique _depuis(Map<String, Object?> l) =>
      Boutique(id: l['id'] as String, nom: l['name'] as String? ?? '', adresse: l['address'] as String?);

  static Future<List<Boutique>> chargerToutes() async {
    final lignes = await db.getAll('SELECT id, name, address FROM shops ORDER BY julianday(created_at)');
    return [for (final l in lignes) _depuis(l)];
  }

  /// Liste des boutiques, mise à jour automatiquement (ex. nouvelle boutique créée ailleurs).
  static Stream<List<Boutique>> surveiller() => db
      .watch('SELECT id, name, address FROM shops ORDER BY julianday(created_at)')
      .map((lignes) => [for (final l in lignes) _depuis(l)]);
}

class Categorie {
  Categorie({required this.id, required this.nom});
  final String id;
  final String nom;
}

class Produit {
  Produit({
    this.id,
    required this.nom,
    this.marque,
    this.variante,
    this.codeBarres,
    this.photoUrl,
    this.prixAchat = 0,
    this.prixVente = 0,
    this.prixGros,
    this.stockMin = 0,
    this.categorieId,
    this.categorieNom,
    this.stock = 0,
    this.prochainePeremption,
  });

  final String? id;
  final String nom;
  final String? marque;
  final String? variante; // teinte, contenance, parfum…
  final String? codeBarres;
  final String? photoUrl;
  final int prixAchat;
  final int prixVente;
  final int? prixGros;
  final int stockMin;
  final String? categorieId;
  final String? categorieNom;

  /// Quantité en stock dans la boutique affichée.
  final int stock;
  final DateTime? prochainePeremption;

  bool get enRupture => stock <= 0;
  bool get stockBas => !enRupture && stockMin > 0 && stock <= stockMin;
  bool get perime =>
      prochainePeremption != null && prochainePeremption!.isBefore(DateTime.now());

  /// Expire dans les 90 prochains jours.
  bool get peremptionProche =>
      !perime &&
      prochainePeremption != null &&
      prochainePeremption!.difference(DateTime.now()).inDays <= 90;

  /// Nom complet affiché : "Crème karité · 250 ml"
  String get nomComplet =>
      (variante == null || variante!.isEmpty) ? nom : '$nom · $variante';

  static String? vide(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

class Lot {
  Lot({required this.id, required this.quantite, required this.prixAchat, this.peremption, required this.recuLe});
  final String id;
  final int quantite;
  final int prixAchat;
  final DateTime? peremption;
  final DateTime recuLe;
}

/// Produits avec leur stock dans une boutique (le stock est la somme des lots).
const _requeteProduits = '''
SELECT p.id, p.name, p.brand, p.variant_label, p.barcode, p.photo_url, p.purchase_price,
       p.sale_price, p.wholesale_price, p.min_stock, p.category_id, c.name AS categorie_nom,
       COALESCE(s.quantite, 0) AS stock, s.prochaine AS prochaine
  FROM products p
  LEFT JOIN categories c ON c.id = p.category_id
  LEFT JOIN (
        SELECT product_id,
               SUM(quantity) AS quantite,
               MIN(CASE WHEN quantity > 0 THEN expiry_date END) AS prochaine
          FROM stock_lots
         WHERE shop_id = ?
         GROUP BY product_id
       ) s ON s.product_id = p.id
 WHERE p.account_id = ? AND COALESCE(p.active, 1) IN (1, 'true')
 ORDER BY p.name COLLATE NOCASE
''';

Produit _produitDepuis(Map<String, Object?> p) => Produit(
      id: p['id'] as String,
      nom: p['name'] as String? ?? '',
      marque: p['brand'] as String?,
      variante: p['variant_label'] as String?,
      codeBarres: p['barcode'] as String?,
      photoUrl: p['photo_url'] as String?,
      prixAchat: _entier(p['purchase_price']),
      prixVente: _entier(p['sale_price']),
      prixGros: _entierOuNull(p['wholesale_price']),
      stockMin: _entier(p['min_stock']),
      categorieId: p['category_id'] as String?,
      categorieNom: p['categorie_nom'] as String?,
      stock: _entier(p['stock']),
      prochainePeremption: _date(p['prochaine']),
    );

/// Toutes les opérations sur les produits et le stock, sur la base locale.
class ProduitsRepo {
  ProduitsRepo({required this.compteId});
  final String compteId;

  Future<List<Categorie>> categories() async {
    final lignes = await db.getAll(
      'SELECT id, name FROM categories WHERE account_id = ? ORDER BY name COLLATE NOCASE',
      [compteId],
    );
    return [for (final l in lignes) Categorie(id: l['id'] as String, nom: l['name'] as String? ?? '')];
  }

  Future<Categorie> creerCategorie(String nom) async {
    final id = await nouvelId();
    await db.execute(
      'INSERT INTO categories (id, account_id, name, created_at) VALUES (?, ?, ?, ?)',
      [id, compteId, nom.trim(), maintenantIso()],
    );
    return Categorie(id: id, nom: nom.trim());
  }

  Future<List<Produit>> produitsAvecStock(String boutiqueId) async {
    final lignes = await db.getAll(_requeteProduits, [boutiqueId, compteId]);
    return [for (final l in lignes) _produitDepuis(l)];
  }

  /// Produits avec stock, mis à jour automatiquement à chaque vente ou réception.
  Stream<List<Produit>> surveillerProduits(String boutiqueId) => db
      .watch(_requeteProduits, parameters: [boutiqueId, compteId])
      .map((lignes) => [for (final l in lignes) _produitDepuis(l)]);

  /// Crée ou met à jour un produit. Renvoie son identifiant.
  Future<String> enregistrer(Produit produit) async {
    final valeurs = [
      Produit.vide(produit.nom) ?? produit.nom,
      Produit.vide(produit.marque),
      Produit.vide(produit.variante),
      Produit.vide(produit.codeBarres),
      produit.photoUrl,
      produit.prixAchat,
      produit.prixVente,
      produit.prixGros,
      produit.stockMin,
      produit.categorieId,
    ];
    if (produit.id == null) {
      final id = await nouvelId();
      await db.execute(
        'INSERT INTO products (id, account_id, name, brand, variant_label, barcode, photo_url, '
        'purchase_price, sale_price, wholesale_price, min_stock, category_id, active, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)',
        [id, compteId, ...valeurs, maintenantIso()],
      );
      return id;
    }
    await db.execute(
      'UPDATE products SET name = ?, brand = ?, variant_label = ?, barcode = ?, photo_url = ?, '
      'purchase_price = ?, sale_price = ?, wholesale_price = ?, min_stock = ?, category_id = ? '
      'WHERE id = ?',
      [...valeurs, produit.id],
    );
    return produit.id!;
  }

  /// Retire le produit du catalogue sans effacer son historique de ventes.
  Future<void> archiver(String produitId) async {
    await db.execute('UPDATE products SET active = 0 WHERE id = ?', [produitId]);
  }

  /// Envoie une photo (internet nécessaire) et renvoie son adresse publique.
  Future<String> envoyerPhoto(Uint8List octets, String extension) async {
    final stockage = Supabase.instance.client.storage.from('product-photos');
    final ext = extension.toLowerCase().replaceAll('.', '');
    final chemin = '$compteId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await stockage.uploadBinary(chemin, octets, fileOptions: FileOptions(contentType: type, upsert: true));
    return stockage.getPublicUrl(chemin);
  }

  /// Nouveau lot en stock : visible tout de suite, envoyé au serveur dès que possible.
  Future<void> entreeStock({
    required String boutiqueId,
    required String produitId,
    required int quantite,
    required int prixAchat,
    DateTime? peremption,
    String? motif,
  }) async {
    if (quantite <= 0) throw Exception('La quantité doit être supérieure à zéro');
    final lotId = await nouvelId();
    final quand = maintenantIso();
    final date = peremption == null ? null : dateBase(peremption);
    final note = (motif == null || motif.trim().isEmpty) ? null : motif.trim();

    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO stock_lots (id, shop_id, account_id, product_id, quantity, cost_price, expiry_date, received_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [lotId, boutiqueId, compteId, produitId, quantite, prixAchat, date, quand],
      );
      await ajouterOperation(tx, 'entree_stock', {
        'p_shop_id': boutiqueId,
        'p_product_id': produitId,
        'p_quantity': quantite,
        'p_cost_price': prixAchat,
        'p_expiry': date,
        'p_reason': note,
        'p_lot_id': lotId,
        'p_received_at': quand,
      });
    });
  }

  /// Lots encore en stock, du plus proche de la péremption au plus lointain.
  Future<List<Lot>> lots(String boutiqueId, String produitId) async {
    final lignes = await db.getAll(
      'SELECT id, quantity, cost_price, expiry_date, received_at FROM stock_lots '
      'WHERE shop_id = ? AND product_id = ? AND quantity > 0 '
      'ORDER BY expiry_date IS NULL, expiry_date, julianday(received_at)',
      [boutiqueId, produitId],
    );
    return [
      for (final l in lignes)
        Lot(
          id: l['id'] as String,
          quantite: _entier(l['quantity']),
          prixAchat: _entier(l['cost_price']),
          peremption: DateTime.tryParse(l['expiry_date'] as String? ?? ''),
          recuLe: _date(l['received_at']) ?? DateTime.now(),
        ),
    ];
  }
}

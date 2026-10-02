import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/format.dart';

SupabaseClient get _db => Supabase.instance.client;

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class Boutique {
  Boutique({required this.id, required this.nom, this.adresse});
  final String id;
  final String nom;
  final String? adresse;

  static Future<List<Boutique>> chargerToutes() async {
    final lignes = await _db.from('shops').select('id, name, address').order('created_at');
    return [
      for (final l in lignes)
        Boutique(id: l['id'] as String, nom: l['name'] as String, adresse: l['address'] as String?),
    ];
  }
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

  Map<String, dynamic> versBase(String compteId) => {
        'account_id': compteId,
        'name': nom,
        'brand': _vide(marque),
        'variant_label': _vide(variante),
        'barcode': _vide(codeBarres),
        'photo_url': photoUrl,
        'purchase_price': prixAchat,
        'sale_price': prixVente,
        'wholesale_price': prixGros,
        'min_stock': stockMin,
        'category_id': categorieId,
      };

  static String? _vide(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
}

class Lot {
  Lot({required this.id, required this.quantite, required this.prixAchat, this.peremption, required this.recuLe});
  final String id;
  final int quantite;
  final int prixAchat;
  final DateTime? peremption;
  final DateTime recuLe;
}

/// Toutes les opérations sur les produits et le stock.
class ProduitsRepo {
  ProduitsRepo({required this.compteId});
  final String compteId;

  Future<List<Categorie>> categories() async {
    final lignes = await _db.from('categories').select('id, name').eq('account_id', compteId).order('name');
    return [for (final l in lignes) Categorie(id: l['id'] as String, nom: l['name'] as String)];
  }

  Future<Categorie> creerCategorie(String nom) async {
    final l = await _db
        .from('categories')
        .insert({'account_id': compteId, 'name': nom.trim()})
        .select('id, name')
        .single();
    return Categorie(id: l['id'] as String, nom: l['name'] as String);
  }

  /// Produits actifs du compte, avec leur stock dans la boutique donnée.
  Future<List<Produit>> produitsAvecStock(String boutiqueId) async {
    final produits = await _db
        .from('products')
        .select('id, name, brand, variant_label, barcode, photo_url, purchase_price, '
            'sale_price, wholesale_price, min_stock, category_id, categories(name)')
        .eq('account_id', compteId)
        .eq('active', true)
        .order('name');
    final lignesStock = await _db
        .from('product_stock')
        .select('product_id, quantity, next_expiry')
        .eq('shop_id', boutiqueId);

    final stocks = <String, Map<String, dynamic>>{
      for (final s in lignesStock) s['product_id'] as String: s,
    };

    return [
      for (final p in produits)
        Produit(
          id: p['id'] as String,
          nom: p['name'] as String,
          marque: p['brand'] as String?,
          variante: p['variant_label'] as String?,
          codeBarres: p['barcode'] as String?,
          photoUrl: p['photo_url'] as String?,
          prixAchat: _entier(p['purchase_price']),
          prixVente: _entier(p['sale_price']),
          prixGros: p['wholesale_price'] == null ? null : _entier(p['wholesale_price']),
          stockMin: _entier(p['min_stock']),
          categorieId: p['category_id'] as String?,
          categorieNom: (p['categories'] is Map) ? (p['categories']['name'] as String?) : null,
          stock: _entier(stocks[p['id']]?['quantity']),
          prochainePeremption: DateTime.tryParse(stocks[p['id']]?['next_expiry'] as String? ?? ''),
        ),
    ];
  }

  /// Crée ou met à jour un produit. Renvoie son identifiant.
  Future<String> enregistrer(Produit produit) async {
    final donnees = produit.versBase(compteId);
    if (produit.id == null) {
      final l = await _db.from('products').insert(donnees).select('id').single();
      return l['id'] as String;
    }
    await _db.from('products').update(donnees).eq('id', produit.id!);
    return produit.id!;
  }

  /// Retire le produit du catalogue sans effacer son historique de ventes.
  Future<void> archiver(String produitId) async {
    await _db.from('products').update({'active': false}).eq('id', produitId);
  }

  /// Envoie une photo et renvoie son adresse publique.
  Future<String> envoyerPhoto(Uint8List octets, String extension) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final chemin = '$compteId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _db.storage
        .from('product-photos')
        .uploadBinary(chemin, octets, fileOptions: FileOptions(contentType: type, upsert: true));
    return _db.storage.from('product-photos').getPublicUrl(chemin);
  }

  Future<void> entreeStock({
    required String boutiqueId,
    required String produitId,
    required int quantite,
    required int prixAchat,
    DateTime? peremption,
    String? motif,
  }) async {
    await _db.rpc('receive_stock', params: {
      'p_shop_id': boutiqueId,
      'p_product_id': produitId,
      'p_quantity': quantite,
      'p_cost_price': prixAchat,
      'p_expiry': peremption == null ? null : dateBase(peremption),
      'p_reason': (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
    });
  }

  /// Lots encore en stock, du plus proche de la péremption au plus lointain.
  Future<List<Lot>> lots(String boutiqueId, String produitId) async {
    final lignes = await _db
        .from('stock_lots')
        .select('id, quantity, cost_price, expiry_date, received_at')
        .eq('shop_id', boutiqueId)
        .eq('product_id', produitId)
        .gt('quantity', 0)
        .order('expiry_date', ascending: true, nullsFirst: false);
    return [
      for (final l in lignes)
        Lot(
          id: l['id'] as String,
          quantite: _entier(l['quantity']),
          prixAchat: _entier(l['cost_price']),
          peremption: DateTime.tryParse(l['expiry_date'] as String? ?? ''),
          recuLe: DateTime.parse(l['received_at'] as String).toLocal(),
        ),
    ];
  }
}

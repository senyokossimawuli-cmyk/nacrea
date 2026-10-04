import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fiche trouvée pour un code-barres : sert à préremplir un nouveau produit.
class FicheTrouvee {
  FicheTrouvee({required this.nom, this.marque, this.variante, this.photoUrl, required this.source});
  final String nom;
  final String? marque;
  final String? variante;
  final String? photoUrl;

  /// « au catalogue Nacréa » ou « à Open Beauty Facts » (pour la phrase « grâce … »)
  final String source;
}

String? _texte(Object? v) {
  final t = v?.toString().trim() ?? '';
  return t.isEmpty ? null : t;
}

/// Cherche la fiche d'un code-barres (demande internet) :
/// 1. dans le catalogue Nacréa partagé entre toutes les boutiques ;
/// 2. sinon dans Open Beauty Facts, la base mondiale gratuite des cosmétiques.
/// Renvoie `null` si rien n'est trouvé ou sans connexion.
Future<FicheTrouvee?> chercherFiche(String code) async {
  final c = code.trim();
  if (c.length < 6) return null;

  try {
    final l = await Supabase.instance.client
        .from('catalogue')
        .select('name, brand, variant_label, photo_url')
        .eq('barcode', c)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    if (l != null && _texte(l['name']) != null) {
      return FicheTrouvee(
        nom: _texte(l['name'])!,
        marque: _texte(l['brand']),
        variante: _texte(l['variant_label']),
        photoUrl: _texte(l['photo_url']),
        source: 'au catalogue Nacréa',
      );
    }
  } catch (_) {
    // Pas de connexion ou catalogue indisponible : on essaie Open Beauty Facts.
  }

  try {
    final reponse = await http.get(
      Uri.parse('https://world.openbeautyfacts.org/api/v2/product/$c.json'
          '?fields=product_name,product_name_fr,brands,quantity,image_front_url,image_url'),
      headers: const {'User-Agent': 'Nacrea/1.0 (logiciel de gestion de boutiques)'},
    ).timeout(const Duration(seconds: 10));
    if (reponse.statusCode != 200) return null;
    final donnees = jsonDecode(utf8.decode(reponse.bodyBytes));
    if (donnees is! Map || donnees['product'] is! Map) return null;
    final p = donnees['product'] as Map;
    final nom = _texte(p['product_name_fr']) ?? _texte(p['product_name']);
    if (nom == null) return null;
    // « Nivea,Beiersdorf » : on garde la première marque.
    final marque = _texte(p['brands'])?.split(',').first.trim();
    return FicheTrouvee(
      nom: nom,
      marque: (marque?.isEmpty ?? true) ? null : marque,
      variante: _texte(p['quantity']),
      photoUrl: _texte(p['image_front_url']) ?? _texte(p['image_url']),
      source: 'à Open Beauty Facts',
    );
  } catch (_) {
    return null;
  }
}

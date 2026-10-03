import 'package:supabase_flutter/supabase_flutter.dart';

import 'produits_repo.dart';

SupabaseClient get _db => Supabase.instance.client;

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Moyens de paiement enregistrés (le logiciel n'encaisse rien lui-même).
enum MoyenPaiement {
  especes('cash', 'Espèces'),
  mobileMoney('mobile_money', 'Mobile Money'),
  carte('card', 'Carte');

  const MoyenPaiement(this.code, this.libelle);
  final String code;
  final String libelle;

  static String libelleDe(String code) => switch (code) {
        'cash' => 'Espèces',
        'mobile_money' => 'Mobile Money',
        'card' => 'Carte',
        'credit' => 'Crédit',
        _ => code,
      };
}

/// Une ligne du panier en cours.
class LignePanier {
  LignePanier({required this.produit, this.quantite = 1, int? prixUnitaire})
      : prixUnitaire = prixUnitaire ?? produit.prixVente;

  final Produit produit;
  int quantite;
  int prixUnitaire;

  int get total => quantite * prixUnitaire;
  bool get prixModifie => prixUnitaire != produit.prixVente;
}

class Paiement {
  Paiement(this.moyen, this.montant);
  final MoyenPaiement moyen;
  final int montant;
}

class ResultatVente {
  ResultatVente({required this.id, required this.ticket, required this.total});
  final String id;
  final String ticket;
  final int total;
}

class LigneVente {
  LigneVente({required this.nom, required this.quantite, required this.prixUnitaire, required this.remise});
  final String nom;
  final int quantite;
  final int prixUnitaire;
  final int remise;
  int get total => quantite * prixUnitaire - remise;
}

/// Une vente enregistrée, telle qu'affichée dans « Ventes ».
class Vente {
  Vente({
    required this.id,
    required this.ticket,
    required this.annulee,
    required this.sousTotal,
    required this.remise,
    required this.total,
    required this.date,
    required this.vendeuse,
    required this.paiements,
    required this.lignes,
  });

  final String id;
  final String ticket;
  final bool annulee;
  final int sousTotal;
  final int remise;
  final int total;
  final DateTime date;
  final String vendeuse;
  final Map<String, int> paiements; // code du moyen → montant
  final List<LigneVente> lignes;

  int get nbArticles => lignes.fold(0, (s, l) => s + l.quantite);
}

class VentesRepo {
  VentesRepo({required this.boutique});
  final Boutique boutique;

  Future<ResultatVente> enregistrer({
    required List<LignePanier> panier,
    required List<Paiement> paiements,
    required int remise,
  }) async {
    final r = await _db.rpc('record_sale', params: {
      'p_shop_id': boutique.id,
      'p_items': [
        for (final l in panier)
          {'product_id': l.produit.id, 'quantity': l.quantite, 'unit_price': l.prixUnitaire, 'discount': 0},
      ],
      'p_payments': [
        for (final p in paiements) {'method': p.moyen.code, 'amount': p.montant},
      ],
      'p_discount': remise,
    });
    final m = r as Map<String, dynamic>;
    return ResultatVente(
      id: m['sale_id'] as String,
      ticket: m['ticket_number'] as String,
      total: _entier(m['total']),
    );
  }

  /// Ventes depuis le début de la journée (heure locale), les plus récentes d'abord.
  Future<List<Vente>> ventesDuJour({DateTime? jour}) async {
    final j = jour ?? DateTime.now();
    final debut = DateTime(j.year, j.month, j.day);
    final fin = debut.add(const Duration(days: 1));

    final lignes = await _db
        .from('sales')
        .select('id, ticket_number, status, subtotal, discount, total, created_at, user_id, '
            'payments(method, amount), '
            'sale_items(quantity, unit_price, discount, products(name, variant_label))')
        .eq('shop_id', boutique.id)
        .gte('created_at', debut.toUtc().toIso8601String())
        .lt('created_at', fin.toUtc().toIso8601String())
        .order('created_at', ascending: false);

    final membres = await _db.from('members').select('user_id, display_name');
    final noms = <String, String>{
      for (final m in membres) m['user_id'] as String: m['display_name'] as String,
    };

    return [
      for (final v in lignes)
        Vente(
          id: v['id'] as String,
          ticket: v['ticket_number'] as String? ?? '',
          annulee: v['status'] == 'cancelled',
          sousTotal: _entier(v['subtotal']),
          remise: _entier(v['discount']),
          total: _entier(v['total']),
          date: DateTime.parse(v['created_at'] as String).toLocal(),
          vendeuse: noms[v['user_id']] ?? '—',
          paiements: {
            for (final p in (v['payments'] as List? ?? const []))
              p['method'] as String: _entier(p['amount']),
          },
          lignes: _regrouper(v['sale_items'] as List? ?? const []),
        ),
    ];
  }

  /// Une vente peut être répartie sur plusieurs lots : on regroupe par produit et prix.
  static List<LigneVente> _regrouper(List items) {
    final groupes = <String, LigneVente>{};
    for (final i in items) {
      final p = i['products'];
      final nom = p is Map
          ? [p['name'], p['variant_label']].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
          : 'Produit';
      final prix = _entier(i['unit_price']);
      final cle = '$nom|$prix';
      final avant = groupes[cle];
      groupes[cle] = LigneVente(
        nom: nom,
        quantite: (avant?.quantite ?? 0) + _entier(i['quantity']),
        prixUnitaire: prix,
        remise: (avant?.remise ?? 0) + _entier(i['discount']),
      );
    }
    return groupes.values.toList();
  }

  Future<void> annuler(String venteId, {String? motif}) async {
    await _db.rpc('cancel_sale', params: {
      'p_sale_id': venteId,
      'p_reason': (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
    });
  }
}

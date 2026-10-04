import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_locale.dart';
import 'produits_repo.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Moyens de paiement enregistrés (le logiciel n'encaisse rien lui-même).
enum MoyenPaiement {
  especes('cash', 'Espèces'),
  mobileMoney('mobile_money', 'Mobile Money'),
  carte('card', 'Carte'),
  credit('credit', 'Crédit');

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
    this.cliente,
  });

  final String id;
  final String ticket;
  final String? cliente;
  final bool annulee;
  final int sousTotal;
  final int remise;
  final int total;
  final DateTime date;
  final String vendeuse;
  final Map<String, int> paiements; // code du moyen → montant
  final List<LigneVente> lignes;

  int get nbArticles => lignes.fold(0, (s, l) => s + l.quantite);
  int get credit => paiements['credit'] ?? 0;
}

class VentesRepo {
  VentesRepo({required this.boutique, required this.compteId});
  final Boutique boutique;
  final String compteId;

  /// Enregistre la vente sur l'appareil (même sans internet) :
  /// le stock baisse tout de suite, le serveur est mis à jour dès que possible.
  Future<ResultatVente> enregistrer({
    required List<LignePanier> panier,
    required List<Paiement> paiements,
    required int remise,
    String? clienteId,
  }) async {
    if (panier.isEmpty) throw Exception('Le panier est vide');
    if (clienteId == null && paiements.any((p) => p.moyen == MoyenPaiement.credit && p.montant > 0)) {
      throw Exception('Choisissez la cliente pour vendre à crédit.');
    }
    final sousTotal = panier.fold(0, (s, l) => s + l.total);
    final total = sousTotal - remise;
    final paye = paiements.fold(0, (s, p) => s + p.montant);
    if (total < 0 || paye != total) throw Exception('Le paiement ne correspond pas au total');

    final venteId = await nouvelId();
    final maintenant = DateTime.now();
    final quand = maintenant.toUtc().toIso8601String();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    late String ticket;

    await db.writeTransaction((tx) async {
      // Numéro de ticket : AAAAMMJJ-0001, par boutique et par jour.
      final debut = DateTime(maintenant.year, maintenant.month, maintenant.day);
      final nb = await tx.get(
        'SELECT COUNT(*) AS n FROM sales WHERE shop_id = ? AND julianday(created_at) >= julianday(?)',
        [boutique.id, debut.toUtc().toIso8601String()],
      );
      final jour = '${maintenant.year}${maintenant.month.toString().padLeft(2, '0')}'
          '${maintenant.day.toString().padLeft(2, '0')}';
      ticket = '$jour-${(_entier(nb['n']) + 1).toString().padLeft(4, '0')}';

      await tx.execute(
        'INSERT INTO sales (id, shop_id, account_id, customer_id, user_id, ticket_number, status, subtotal, discount, total, created_at) '
        "VALUES (?, ?, ?, ?, ?, ?, 'completed', ?, ?, ?, ?)",
        [venteId, boutique.id, compteId, clienteId, userId, ticket, sousTotal, remise, total, quand],
      );

      // Sortie de stock : le lot qui périme le plus tôt part en premier.
      for (final l in panier) {
        var restant = l.quantite;
        final lots = await tx.getAll(
          'SELECT id, quantity, cost_price FROM stock_lots '
          'WHERE shop_id = ? AND product_id = ? AND quantity > 0 '
          'ORDER BY expiry_date IS NULL, expiry_date, julianday(received_at)',
          [boutique.id, l.produit.id],
        );
        for (final lot in lots) {
          if (restant == 0) break;
          final dispo = _entier(lot['quantity']);
          final prend = dispo < restant ? dispo : restant;
          await tx.execute('UPDATE stock_lots SET quantity = quantity - ? WHERE id = ?', [prend, lot['id']]);
          await tx.execute(
            'INSERT INTO sale_items (id, sale_id, shop_id, account_id, product_id, lot_id, quantity, unit_price, cost_price, discount) '
            'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?, 0)',
            [venteId, boutique.id, compteId, l.produit.id, lot['id'], prend, l.prixUnitaire, _entier(lot['cost_price'])],
          );
          restant -= prend;
        }
        if (restant > 0) {
          // Stock insuffisant : la vente passe quand même, le stock devient négatif.
          final lotId = await tx.get('SELECT uuid() AS id');
          await tx.execute(
            'INSERT INTO stock_lots (id, shop_id, account_id, product_id, quantity, cost_price, received_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [lotId['id'], boutique.id, compteId, l.produit.id, -restant, l.produit.prixAchat, quand],
          );
          await tx.execute(
            'INSERT INTO sale_items (id, sale_id, shop_id, account_id, product_id, lot_id, quantity, unit_price, cost_price, discount) '
            'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?, 0)',
            [venteId, boutique.id, compteId, l.produit.id, lotId['id'], restant, l.prixUnitaire, l.produit.prixAchat],
          );
        }
      }

      for (final p in paiements) {
        if (p.montant <= 0) continue;
        await tx.execute(
          'INSERT INTO payments (id, sale_id, shop_id, account_id, method, amount, created_at) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, ?)',
          [venteId, boutique.id, compteId, p.moyen.code, p.montant, quand],
        );
      }

      await ajouterOperation(tx, 'vente', {
        'p_shop_id': boutique.id,
        'p_items': [
          for (final l in panier)
            {'product_id': l.produit.id, 'quantity': l.quantite, 'unit_price': l.prixUnitaire, 'discount': 0},
        ],
        'p_payments': [
          for (final p in paiements)
            if (p.montant > 0) {'method': p.moyen.code, 'amount': p.montant},
        ],
        'p_discount': remise,
        'p_customer_id': clienteId,
        'p_sale_id': venteId,
        'p_ticket': ticket,
        'p_created_at': quand,
      });
    });

    return ResultatVente(id: venteId, ticket: ticket, total: total);
  }

  /// Ventes d'une journée (heure locale), les plus récentes d'abord, mises à jour en direct.
  Stream<List<Vente>> surveillerVentes(DateTime jour) {
    final debut = DateTime(jour.year, jour.month, jour.day);
    final fin = debut.add(const Duration(days: 1));
    return db.watch(
      'SELECT v.id, v.ticket_number, v.status, v.subtotal, v.discount, v.total, v.created_at, v.user_id, '
      'c.name AS cliente FROM sales v LEFT JOIN customers c ON c.id = v.customer_id '
      'WHERE v.shop_id = ? AND julianday(v.created_at) >= julianday(?) AND julianday(v.created_at) < julianday(?) '
      'ORDER BY julianday(v.created_at) DESC',
      parameters: [boutique.id, debut.toUtc().toIso8601String(), fin.toUtc().toIso8601String()],
      triggerOnTables: const ['sales', 'sale_items', 'payments', 'customers'],
    ).asyncMap(_completer);
  }

  Future<List<Vente>> _completer(Iterable<Map<String, Object?>> ventes) async {
    final liste = ventes.toList();
    if (liste.isEmpty) return const [];
    final ids = [for (final v in liste) v['id'] as String];
    final marques = List.filled(ids.length, '?').join(', ');

    final lignes = await db.getAll(
      'SELECT i.sale_id, i.quantity, i.unit_price, i.discount, p.name, p.variant_label '
      'FROM sale_items i LEFT JOIN products p ON p.id = i.product_id WHERE i.sale_id IN ($marques)',
      ids,
    );
    final paiements = await db.getAll(
      'SELECT sale_id, method, amount FROM payments WHERE sale_id IN ($marques)',
      ids,
    );
    final membres = await db.getAll('SELECT user_id, display_name FROM members');
    final noms = {for (final m in membres) m['user_id']: m['display_name'] as String? ?? '—'};

    final lignesParVente = <String, List<Map<String, Object?>>>{};
    for (final l in lignes) {
      lignesParVente.putIfAbsent(l['sale_id'] as String, () => []).add(l);
    }
    final paiementsParVente = <String, Map<String, int>>{};
    for (final p in paiements) {
      final m = paiementsParVente.putIfAbsent(p['sale_id'] as String, () => {});
      m[p['method'] as String] = (m[p['method']] ?? 0) + _entier(p['amount']);
    }

    return [
      for (final v in liste)
        Vente(
          id: v['id'] as String,
          ticket: v['ticket_number'] as String? ?? '',
          annulee: v['status'] == 'cancelled',
          sousTotal: _entier(v['subtotal']),
          remise: _entier(v['discount']),
          total: _entier(v['total']),
          date: DateTime.tryParse('${v['created_at']}')?.toLocal() ?? DateTime.now(),
          vendeuse: noms[v['user_id']] ?? '—',
          paiements: paiementsParVente[v['id']] ?? const {},
          lignes: _regrouper(lignesParVente[v['id']] ?? const []),
          cliente: v['cliente'] as String?,
        ),
    ];
  }

  /// Une vente peut être répartie sur plusieurs lots : on regroupe par produit et prix.
  static List<LigneVente> _regrouper(List<Map<String, Object?>> items) {
    final groupes = <String, LigneVente>{};
    for (final i in items) {
      final nom = [i['name'], i['variant_label']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' · ');
      final prix = _entier(i['unit_price']);
      final cle = '$nom|$prix';
      final avant = groupes[cle];
      groupes[cle] = LigneVente(
        nom: nom.isEmpty ? 'Produit' : nom,
        quantite: (avant?.quantite ?? 0) + _entier(i['quantity']),
        prixUnitaire: prix,
        remise: (avant?.remise ?? 0) + _entier(i['discount']),
      );
    }
    return groupes.values.toList();
  }

  /// Annulation par la patronne : nécessite internet (le stock est remis côté serveur).
  Future<void> annuler(String venteId, {String? motif}) async {
    await Supabase.instance.client.rpc('cancel_sale', params: {
      'p_sale_id': venteId,
      'p_reason': (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
    });
  }
}

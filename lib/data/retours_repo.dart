import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Comment la cliente est remboursée.
enum Remboursement {
  especes('cash', 'Espèces (pris dans la caisse)'),
  mobileMoney('mobile_money', 'Mobile Money'),
  carte('card', 'Carte'),
  dette('debt', 'Déduit de sa dette');

  const Remboursement(this.code, this.libelle);
  final String code;
  final String libelle;
}

/// Un produit d'un reçu, avec ce qui peut encore être retourné.
class ArticleRetournable {
  ArticleRetournable({
    required this.produitId,
    required this.nom,
    required this.vendu,
    required this.dejaRetourne,
    required this.remboursementUnitaire,
    required this.prixAchat,
  });
  final String produitId;
  final String nom;
  final int vendu;
  final int dejaRetourne;
  final int remboursementUnitaire; // remise du reçu comprise
  final int prixAchat;
  int get retournable => vendu - dejaRetourne;
}

/// Article choisi pour le retour.
class ArticleRetour {
  ArticleRetour(this.article, this.quantite, {this.remisEnStock = true});
  final ArticleRetournable article;
  final int quantite;
  final bool remisEnStock;
}

class RetoursRepo {
  RetoursRepo({required this.boutiqueId, required this.compteId});
  final String boutiqueId;
  final String compteId;

  /// Articles d'un reçu et quantités encore retournables.
  /// Même calcul que le serveur : la remise globale du reçu est répartie sur chaque article.
  Future<List<ArticleRetournable>> articles(String venteId) async {
    final vente = await db.get('SELECT subtotal, total FROM sales WHERE id = ?', [venteId]);
    final sousTotal = _entier(vente['subtotal']);
    final ratio = sousTotal > 0 ? _entier(vente['total']) / sousTotal : 1.0;
    final lignes = await db.getAll(
      'SELECT i.product_id, p.name, p.variant_label, SUM(i.quantity) AS qte, '
      'SUM(i.quantity * i.unit_price - i.discount) AS montant, SUM(i.quantity * i.cost_price) AS cout, '
      '(SELECT COALESCE(SUM(ri.quantity), 0) FROM sale_return_items ri JOIN sale_returns r ON r.id = ri.return_id '
      '  WHERE r.sale_id = i.sale_id AND ri.product_id = i.product_id) AS deja '
      'FROM sale_items i LEFT JOIN products p ON p.id = i.product_id '
      'WHERE i.sale_id = ? GROUP BY i.product_id ORDER BY p.name',
      [venteId],
    );
    return [
      for (final l in lignes)
        if (_entier(l['qte']) > 0)
          ArticleRetournable(
            produitId: l['product_id'] as String,
            nom: [l['name'], l['variant_label']].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
            vendu: _entier(l['qte']),
            dejaRetourne: _entier(l['deja']),
            remboursementUnitaire: (_entier(l['montant']) / _entier(l['qte']) * ratio).round(),
            prixAchat: (_entier(l['cout']) / _entier(l['qte'])).round(),
          ),
    ];
  }

  /// Enregistre le retour sur l'appareil (stock, remboursement) et l'envoie au serveur.
  /// Renvoie le montant remboursé.
  Future<int> enregistrer({
    required String venteId,
    required String? clienteId,
    required List<ArticleRetour> articles,
    required Remboursement remboursement,
    String? note,
    required String userId,
    required String ticket,
  }) async {
    final choisis = articles.where((a) => a.quantite > 0).toList();
    if (choisis.isEmpty) throw Exception('Choisissez au moins un article à retourner');
    if (remboursement == Remboursement.dette && clienteId == null) {
      throw Exception('Pas de cliente sur ce reçu : remboursez en espèces ou Mobile Money');
    }
    final retourId = await nouvelId();
    final reglementId = await nouvelId();
    final quand = maintenantIso();
    final texte = (note == null || note.trim().isEmpty) ? null : note.trim();
    final total = choisis.fold(0, (s, a) => s + a.quantite * a.article.remboursementUnitaire);

    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO sale_returns (id, account_id, shop_id, sale_id, customer_id, refund_amount, refund_method, note, user_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [retourId, compteId, boutiqueId, venteId, clienteId, total, remboursement.code, texte, userId, quand],
      );
      for (final a in choisis) {
        await tx.execute(
          'INSERT INTO sale_return_items (id, return_id, account_id, shop_id, product_id, quantity, unit_refund, cost_price, restocked) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?)',
          [retourId, compteId, boutiqueId, a.article.produitId, a.quantite, a.article.remboursementUnitaire,
            a.article.prixAchat, a.remisEnStock ? 1 : 0],
        );
        if (!a.remisEnStock) continue;
        // Remise en rayon : comble d'abord un stock négatif, puis nouveau lot.
        var restant = a.quantite;
        final negatifs = await tx.getAll(
          'SELECT id, quantity FROM stock_lots WHERE shop_id = ? AND product_id = ? AND quantity < 0 '
          'ORDER BY julianday(received_at)',
          [boutiqueId, a.article.produitId],
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
            [boutiqueId, compteId, a.article.produitId, restant, a.article.prixAchat, quand],
          );
        }
      }
      if (remboursement == Remboursement.dette && total > 0) {
        await tx.execute(
          'INSERT INTO customer_payments (id, account_id, shop_id, customer_id, amount, method, note, user_id, created_at) '
          "VALUES (?, ?, ?, ?, ?, 'return', ?, ?, ?)",
          [reglementId, compteId, boutiqueId, clienteId, total, 'Retour du reçu $ticket', userId, quand],
        );
      }
      await ajouterOperation(tx, 'retour', {
        'p_return_id': retourId,
        'p_shop_id': boutiqueId,
        'p_sale_id': venteId,
        'p_items': [
          for (final a in choisis)
            {'product_id': a.article.produitId, 'quantity': a.quantite, 'restock': a.remisEnStock},
        ],
        'p_refund_method': remboursement.code,
        'p_note': texte,
        'p_created_at': quand,
        'p_debt_payment_id': reglementId,
      });
    });
    return total;
  }
}

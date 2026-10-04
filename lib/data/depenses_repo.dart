import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Catégories de dépenses. Les achats de marchandises n'en font pas partie :
/// ils passent par « Ajouter du stock » et leur coût est compté à la vente.
const categoriesDepenses = <String, String>{
  'loyer': 'Loyer',
  'electricite_eau': 'Électricité et eau',
  'salaires': 'Salaires',
  'transport': 'Transport',
  'internet_telephone': 'Internet et téléphone',
  'entretien': 'Entretien et réparations',
  'publicite': 'Publicité',
  'taxes': 'Impôts et taxes',
  'autre': 'Autre',
};

String libelleCategorie(String c) => categoriesDepenses[c] ?? c;

/// Comment la dépense a été payée.
enum PayeAvec {
  caisse('Argent de la caisse'),
  especes('Espèces hors caisse'),
  mobileMoney('Mobile Money'),
  carte('Carte ou banque');

  const PayeAvec(this.libelle);
  final String libelle;

  String get methode => switch (this) {
        PayeAvec.mobileMoney => 'mobile_money',
        PayeAvec.carte => 'card',
        _ => 'cash',
      };

  static PayeAvec depuis(String? methode, bool caisse) => switch (methode) {
        'mobile_money' => PayeAvec.mobileMoney,
        'card' => PayeAvec.carte,
        _ => caisse ? PayeAvec.caisse : PayeAvec.especes,
      };
}

class Fournisseur {
  Fournisseur({required this.id, required this.nom, this.telephone, this.note, this.achats = 0, this.dernierAchat});
  final String id;
  final String nom;
  final String? telephone;
  final String? note;

  /// Total des marchandises reçues de ce fournisseur (prix d'achat × quantité).
  final int achats;
  final DateTime? dernierAchat;
}

class Depense {
  Depense({
    required this.id,
    required this.boutiqueId,
    required this.categorie,
    this.libelle,
    required this.montant,
    required this.payeAvec,
    required this.date,
    this.fournisseurId,
    this.fournisseurNom,
    this.boutiqueNom,
  });
  final String id;
  final String boutiqueId;
  final String categorie;
  final String? libelle;
  final int montant;
  final PayeAvec payeAvec;
  final DateTime date;
  final String? fournisseurId;
  final String? fournisseurNom;
  final String? boutiqueNom;

  String get titre => (libelle?.trim().isNotEmpty ?? false) ? libelle!.trim() : libelleCategorie(categorie);
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class FournisseursRepo {
  FournisseursRepo({required this.compteId});
  final String compteId;

  Stream<List<Fournisseur>> surveiller() => db
      .watch(
        'SELECT f.id, f.name, f.phone, f.note, '
        'COALESCE(SUM(l.quantity * l.cost_price), 0) AS achats, MAX(l.received_at) AS dernier '
        'FROM suppliers f LEFT JOIN stock_lots l ON l.supplier_id = f.id '
        'WHERE f.account_id = ? AND (f.active IS NULL OR f.active = 1) '
        'GROUP BY f.id ORDER BY f.name COLLATE NOCASE',
        parameters: [compteId],
        triggerOnTables: const ['suppliers', 'stock_lots'],
      )
      .map((lignes) => [
            for (final l in lignes)
              Fournisseur(
                id: l['id'] as String,
                nom: l['name'] as String? ?? '',
                telephone: l['phone'] as String?,
                note: l['note'] as String?,
                achats: _entier(l['achats']),
                dernierAchat: DateTime.tryParse(l['dernier'] as String? ?? '')?.toLocal(),
              ),
          ]);

  Future<List<Fournisseur>> tous() async {
    final lignes = await db.getAll(
      'SELECT id, name, phone FROM suppliers WHERE account_id = ? AND (active IS NULL OR active = 1) '
      'ORDER BY name COLLATE NOCASE',
      [compteId],
    );
    return [
      for (final l in lignes)
        Fournisseur(id: l['id'] as String, nom: l['name'] as String? ?? '', telephone: l['phone'] as String?),
    ];
  }

  /// Crée (id nul) ou modifie un fournisseur. Renvoie son id.
  Future<String> enregistrer({String? id, required String nom, String? telephone, String? note}) async {
    String? propre(String? t) => (t == null || t.trim().isEmpty) ? null : t.trim();
    if (nom.trim().isEmpty) throw Exception('Indiquez le nom du fournisseur');
    if (id == null) {
      final nouveau = await nouvelId();
      await db.execute(
        'INSERT INTO suppliers (id, account_id, name, phone, note, active, created_at) VALUES (?, ?, ?, ?, ?, 1, ?)',
        [nouveau, compteId, nom.trim(), propre(telephone), propre(note), maintenantIso()],
      );
      return nouveau;
    }
    await db.execute(
      'UPDATE suppliers SET name = ?, phone = ?, note = ? WHERE id = ?',
      [nom.trim(), propre(telephone), propre(note), id],
    );
    return id;
  }

  /// Retire le fournisseur des listes (son historique d'achats reste).
  Future<void> archiver(String id) async {
    await db.execute('UPDATE suppliers SET active = 0 WHERE id = ?', [id]);
  }

  /// Dernières livraisons reçues de ce fournisseur.
  Future<List<Map<String, Object?>>> livraisons(String fournisseurId) async {
    final lignes = await db.getAll(
      'SELECT l.received_at, l.quantity, l.cost_price, p.name AS produit, s.name AS boutique '
      'FROM stock_lots l JOIN products p ON p.id = l.product_id LEFT JOIN shops s ON s.id = l.shop_id '
      'WHERE l.supplier_id = ? ORDER BY julianday(l.received_at) DESC LIMIT 50',
      [fournisseurId],
    );
    return lignes.toList();
  }
}

class DepensesRepo {
  DepensesRepo({required this.compteId});
  final String compteId;

  /// Dépenses d'une boutique (ou de toutes si [boutiqueId] est nul) entre deux dates incluses.
  Stream<List<Depense>> surveiller({String? boutiqueId, required DateTime debut, required DateTime fin}) => db
      .watch(
        'SELECT e.id, e.shop_id, e.category, e.label, e.amount, e.method, e.from_till, e.spent_on, '
        'e.supplier_id, f.name AS fournisseur, s.name AS boutique '
        'FROM expenses e LEFT JOIN suppliers f ON f.id = e.supplier_id LEFT JOIN shops s ON s.id = e.shop_id '
        'WHERE e.account_id = ? AND (? IS NULL OR e.shop_id = ?) AND e.spent_on >= ? AND e.spent_on <= ? '
        'ORDER BY e.spent_on DESC, julianday(e.created_at) DESC',
        parameters: [compteId, boutiqueId, boutiqueId, _date(debut), _date(fin)],
        triggerOnTables: const ['expenses', 'suppliers'],
      )
      .map((lignes) => [
            for (final l in lignes)
              Depense(
                id: l['id'] as String,
                boutiqueId: l['shop_id'] as String,
                categorie: l['category'] as String? ?? 'autre',
                libelle: l['label'] as String?,
                montant: _entier(l['amount']),
                payeAvec: PayeAvec.depuis(l['method'] as String?, ouiNon(l['from_till'])),
                date: DateTime.tryParse(l['spent_on'] as String? ?? '') ?? DateTime.now(),
                fournisseurId: l['supplier_id'] as String?,
                fournisseurNom: l['fournisseur'] as String?,
                boutiqueNom: l['boutique'] as String?,
              ),
          ]);

  Future<void> ajouter({
    required String boutiqueId,
    required String categorie,
    String? libelle,
    required int montant,
    required PayeAvec payeAvec,
    required DateTime date,
    String? fournisseurId,
    required String userId,
  }) async {
    if (montant <= 0) throw Exception('Le montant doit être supérieur à zéro');
    await db.execute(
      'INSERT INTO expenses (id, account_id, shop_id, category, label, amount, method, from_till, '
      'supplier_id, spent_on, user_id, created_at) VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        compteId,
        boutiqueId,
        categorie,
        (libelle == null || libelle.trim().isEmpty) ? null : libelle.trim(),
        montant,
        payeAvec.methode,
        payeAvec == PayeAvec.caisse ? 1 : 0,
        fournisseurId,
        _date(date),
        userId,
        maintenantIso(),
      ],
    );
  }

  /// Réservé à la patronne (le serveur refuse pour une employée).
  Future<void> supprimer(String id) async {
    await db.execute('DELETE FROM expenses WHERE id = ?', [id]);
  }
}

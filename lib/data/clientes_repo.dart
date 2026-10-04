import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/format.dart';
import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
String? _texte(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Une cliente de l'entreprise (commune à toutes les boutiques).
class Cliente {
  Cliente({
    required this.id,
    required this.nom,
    this.telephone,
    this.note,
    this.dette = 0,
    this.derniereVisite,
  });

  final String id;
  final String nom;
  final String? telephone;
  final String? note;

  /// Ce qu'elle doit encore (0 si elle est à jour).
  final int dette;
  final DateTime? derniereVisite;

  bool get doit => dette > 0;

  static Cliente depuis(Map<String, Object?> l) => Cliente(
        id: l['id'] as String,
        nom: l['name'] as String? ?? '',
        telephone: l['phone'] as String?,
        note: l['notes'] as String?,
        dette: _entier(l['dette']),
        derniereVisite: _date(l['derniere_visite']),
      );
}

/// Un événement de l'historique d'une cliente : un achat ou un remboursement.
class MouvementCliente {
  MouvementCliente({
    required this.achat,
    required this.date,
    required this.montant,
    this.credit = 0,
    this.ticket,
    this.moyen,
    this.boutique,
    this.annule = false,
  });

  final bool achat; // sinon : remboursement
  final DateTime date;
  final int montant; // total de l'achat, ou montant remboursé
  final int credit; // partie de l'achat laissée à crédit
  final String? ticket;
  final String? moyen; // moyen du remboursement
  final String? boutique;
  final bool annule;
}

/// Ce que doit une cliente : crédits des ventes non annulées - remboursements.
const _sqlDette = '''
  COALESCE((SELECT SUM(p.amount) FROM payments p JOIN sales s ON s.id = p.sale_id
             WHERE s.customer_id = c.id AND p.method = 'credit' AND s.status != 'cancelled'), 0)
  - COALESCE((SELECT SUM(r.amount) FROM customer_payments r WHERE r.customer_id = c.id), 0)
''';

const _sqlCliente = '''
SELECT c.id, c.name, c.phone, c.notes,
       ($_sqlDette) AS dette,
       (SELECT MAX(s.created_at) FROM sales s WHERE s.customer_id = c.id) AS derniere_visite
  FROM customers c
''';

class ClientesRepo {
  ClientesRepo({required this.compteId});
  final String compteId;

  String? get _moi => Supabase.instance.client.auth.currentUser?.id;

  static const _tables = ['customers', 'customer_payments', 'sales', 'payments'];

  /// Toutes les clientes, par ordre alphabétique, mises à jour en direct.
  Stream<List<Cliente>> surveiller() => db
      .watch(
        '$_sqlCliente WHERE c.account_id = ? ORDER BY c.name COLLATE NOCASE',
        parameters: [compteId],
        triggerOnTables: _tables,
      )
      .map((lignes) => [for (final l in lignes) Cliente.depuis(l)]);

  /// Une cliente, mise à jour en direct (fiche cliente).
  Stream<Cliente?> surveillerUne(String id) => db
      .watch('$_sqlCliente WHERE c.id = ?', parameters: [id], triggerOnTables: _tables)
      .map((l) => l.isEmpty ? null : Cliente.depuis(l.first));

  /// Une cliente avec le même numéro existe déjà ? (évite les doublons)
  Future<Cliente?> parTelephone(String telephone) async {
    final chiffres = telephone.replaceAll(RegExp(r'\D'), '');
    if (chiffres.length < 8) return null;
    final fin = chiffres.substring(chiffres.length - 8);
    final lignes = await db.getAll(
      '$_sqlCliente WHERE c.account_id = ? AND c.phone IS NOT NULL',
      [compteId],
    );
    for (final l in lignes) {
      final t = (l['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
      if (t.endsWith(fin)) return Cliente.depuis(l);
    }
    return null;
  }

  /// Crée ou modifie une cliente (fonctionne sans internet). Renvoie la cliente.
  Future<Cliente> enregistrer({String? id, required String nom, String? telephone, String? note}) async {
    if (nom.trim().isEmpty) throw Exception('Indiquez le nom de la cliente.');
    if (id == null) {
      final nouvel = await nouvelId();
      await db.execute(
        'INSERT INTO customers (id, account_id, name, phone, notes, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        [nouvel, compteId, nom.trim(), _texte(telephone), _texte(note), maintenantIso()],
      );
      return Cliente(id: nouvel, nom: nom.trim(), telephone: _texte(telephone), note: _texte(note));
    }
    await db.execute(
      'UPDATE customers SET name = ?, phone = ?, notes = ? WHERE id = ?',
      [nom.trim(), _texte(telephone), _texte(note), id],
    );
    return Cliente(id: id, nom: nom.trim(), telephone: _texte(telephone), note: _texte(note));
  }

  /// La cliente rembourse tout ou partie de ce qu'elle doit (fonctionne sans internet).
  Future<void> rembourser({
    required Cliente cliente,
    required String boutiqueId,
    required int montant,
    required String moyen,
    String? note,
  }) async {
    if (montant <= 0) throw Exception('Indiquez le montant reçu.');
    final actuelle = await db.get('$_sqlCliente WHERE c.id = ?', [cliente.id]);
    final dette = _entier(actuelle['dette']);
    if (montant > dette) {
      throw Exception('La cliente ne doit que ${fcfa(dette < 0 ? 0 : dette)}.');
    }
    await db.execute(
      'INSERT INTO customer_payments (id, account_id, shop_id, customer_id, amount, method, note, user_id, created_at) '
      'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?)',
      [compteId, boutiqueId, cliente.id, montant, moyen, _texte(note), _moi, maintenantIso()],
    );
  }

  /// Achats et remboursements de la cliente, du plus récent au plus ancien.
  Stream<List<MouvementCliente>> surveillerHistorique(String clienteId) => db
      .watch(
        '''
SELECT 1 AS achat, s.created_at AS quand, s.total AS montant, s.ticket_number AS ticket,
       s.status AS statut, NULL AS moyen, sh.name AS boutique,
       COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.sale_id = s.id AND p.method = 'credit'), 0) AS credit
  FROM sales s LEFT JOIN shops sh ON sh.id = s.shop_id
 WHERE s.customer_id = ?
UNION ALL
SELECT 0, r.created_at, r.amount, NULL, NULL, r.method, sh.name, 0
  FROM customer_payments r LEFT JOIN shops sh ON sh.id = r.shop_id
 WHERE r.customer_id = ?
ORDER BY 2 DESC
''',
        parameters: [clienteId, clienteId],
        triggerOnTables: const ['sales', 'payments', 'customer_payments', 'shops'],
      )
      .map((lignes) => [
            for (final l in lignes)
              MouvementCliente(
                achat: _entier(l['achat']) == 1,
                date: _date(l['quand']) ?? DateTime.now(),
                montant: _entier(l['montant']),
                credit: _entier(l['credit']),
                ticket: l['ticket'] as String?,
                moyen: l['moyen'] as String?,
                boutique: l['boutique'] as String?,
                annule: l['statut'] == 'cancelled',
              ),
          ]);
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_locale.dart';

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Une journée de caisse : du fond de caisse du matin au comptage du soir.
class SessionCaisse {
  SessionCaisse({
    required this.id,
    required this.ouverte,
    required this.ouverteLe,
    required this.fond,
    this.ouvertePar,
    this.fermeeLe,
    this.fermeePar,
    this.attendu,
    this.compte,
    this.ecart,
    this.note,
  });

  final String id;
  final bool ouverte;
  final DateTime ouverteLe;
  final int fond;
  final String? ouvertePar;
  final DateTime? fermeeLe;
  final String? fermeePar;
  final int? attendu;
  final int? compte;
  final int? ecart; // compté - attendu : négatif = manquant
  final String? note;

  static SessionCaisse depuis(Map<String, Object?> l) => SessionCaisse(
        id: l['id'] as String,
        ouverte: l['status'] == 'open',
        ouverteLe: _date(l['opened_at']) ?? DateTime.now(),
        fond: _entier(l['opening_float']),
        ouvertePar: l['nom_ouverture'] as String?,
        fermeeLe: _date(l['closed_at']),
        fermeePar: l['nom_cloture'] as String?,
        attendu: l['expected_cash'] == null ? null : _entier(l['expected_cash']),
        compte: l['counted_cash'] == null ? null : _entier(l['counted_cash']),
        ecart: l['difference'] == null ? null : _entier(l['difference']),
        note: l['note'] as String?,
      );
}

/// Ce qui doit se trouver dans le tiroir à un instant donné.
class ResumeCaisse {
  ResumeCaisse({
    required this.fond,
    required this.ventesEspeces,
    this.remboursementsEspeces = 0,
    required this.entrees,
    required this.sorties,
  });
  final int fond;
  final int ventesEspeces;
  final int remboursementsEspeces; // dettes payées en espèces par les clientes
  final int entrees;
  final int sorties;
  int get attendu => fond + ventesEspeces + remboursementsEspeces + entrees - sorties;
}

class MouvementCaisse {
  MouvementCaisse({required this.entree, required this.montant, this.motif, required this.date});
  final bool entree;
  final int montant;
  final String? motif;
  final DateTime date;
}

const _selectSession = '''
SELECT c.*, mo.display_name AS nom_ouverture, mc.display_name AS nom_cloture
  FROM cash_sessions c
  LEFT JOIN members mo ON mo.user_id = c.opened_by
  LEFT JOIN members mc ON mc.user_id = c.closed_by
''';

class CaisseRepo {
  CaisseRepo({required this.boutiqueId, required this.compteId});
  final String boutiqueId;
  final String compteId;

  String? get _moi => Supabase.instance.client.auth.currentUser?.id;

  /// La caisse ouverte de la boutique (ou null), mise à jour en direct.
  Stream<SessionCaisse?> surveillerOuverte() => db
      .watch(
        "$_selectSession WHERE c.shop_id = ? AND c.status = 'open' ORDER BY julianday(c.opened_at) DESC LIMIT 1",
        parameters: [boutiqueId],
        triggerOnTables: const ['cash_sessions'],
      )
      .map((l) => l.isEmpty ? null : SessionCaisse.depuis(l.first));

  /// Sessions ouvertes un jour donné (heure locale), les plus récentes d'abord.
  Stream<List<SessionCaisse>> surveillerDuJour(DateTime jour) {
    final debut = DateTime(jour.year, jour.month, jour.day);
    final fin = debut.add(const Duration(days: 1));
    return db
        .watch(
          '$_selectSession WHERE c.shop_id = ? AND julianday(c.opened_at) >= julianday(?) '
          'AND julianday(c.opened_at) < julianday(?) ORDER BY julianday(c.opened_at) DESC',
          parameters: [boutiqueId, debut.toUtc().toIso8601String(), fin.toUtc().toIso8601String()],
          triggerOnTables: const ['cash_sessions'],
        )
        .map((lignes) => [for (final l in lignes) SessionCaisse.depuis(l)]);
  }

  Future<void> ouvrir(int fond) async {
    final deja = await db.getOptional(
      "SELECT id FROM cash_sessions WHERE shop_id = ? AND status = 'open'",
      [boutiqueId],
    );
    if (deja != null) throw Exception('La caisse est déjà ouverte.');
    await db.execute(
      'INSERT INTO cash_sessions (id, shop_id, account_id, status, opened_by, opened_at, opening_float) '
      "VALUES (uuid(), ?, ?, 'open', ?, ?, ?)",
      [boutiqueId, compteId, _moi, maintenantIso(), fond],
    );
  }

  /// Entrée (apport de monnaie…) ou sortie (transport, achat…) d'argent du tiroir.
  Future<void> mouvement(SessionCaisse s, {required bool entree, required int montant, String? motif}) async {
    if (montant <= 0) throw Exception('Indiquez un montant.');
    await db.execute(
      'INSERT INTO cash_movements (id, session_id, shop_id, account_id, type, amount, reason, user_id, created_at) '
      'VALUES (uuid(), ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        s.id,
        boutiqueId,
        compteId,
        entree ? 'in' : 'out',
        montant,
        (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
        _moi,
        maintenantIso(),
      ],
    );
  }

  Future<List<MouvementCaisse>> mouvements(SessionCaisse s) async {
    final lignes = await db.getAll(
      'SELECT type, amount, reason, created_at FROM cash_movements WHERE session_id = ? '
      'ORDER BY julianday(created_at)',
      [s.id],
    );
    return [
      for (final l in lignes)
        MouvementCaisse(
          entree: l['type'] == 'in',
          montant: _entier(l['amount']),
          motif: l['reason'] as String?,
          date: _date(l['created_at']) ?? DateTime.now(),
        ),
    ];
  }

  /// Ce qui doit être dans le tiroir : fond + ventes en espèces + dettes payées en espèces
  /// + entrées − sorties.
  Future<ResumeCaisse> resume(SessionCaisse s) async {
    final fin = (s.fermeeLe ?? DateTime.now().add(const Duration(minutes: 1))).toUtc().toIso8601String();
    final ventes = await db.get(
      'SELECT COALESCE(SUM(p.amount), 0) AS total FROM payments p JOIN sales v ON v.id = p.sale_id '
      "WHERE p.shop_id = ? AND p.method = 'cash' AND v.status = 'completed' "
      'AND julianday(v.created_at) >= julianday(?) AND julianday(v.created_at) <= julianday(?)',
      [boutiqueId, s.ouverteLe.toUtc().toIso8601String(), fin],
    );
    final remb = await db.get(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM customer_payments '
      "WHERE shop_id = ? AND method = 'cash' "
      'AND julianday(created_at) >= julianday(?) AND julianday(created_at) <= julianday(?)',
      [boutiqueId, s.ouverteLe.toUtc().toIso8601String(), fin],
    );
    final mvts = await db.get(
      "SELECT COALESCE(SUM(CASE WHEN type = 'in' THEN amount END), 0) AS entrees, "
      "COALESCE(SUM(CASE WHEN type = 'out' THEN amount END), 0) AS sorties "
      'FROM cash_movements WHERE session_id = ?',
      [s.id],
    );
    return ResumeCaisse(
      fond: s.fond,
      ventesEspeces: _entier(ventes['total']),
      remboursementsEspeces: _entier(remb['total']),
      entrees: _entier(mvts['entrees']),
      sorties: _entier(mvts['sorties']),
    );
  }

  /// Clôture : enregistre le montant compté et l'écart. Renvoie l'écart.
  Future<int> cloturer(SessionCaisse s, {required int compte, String? note}) async {
    final r = await resume(s);
    final ecart = compte - r.attendu;
    await db.execute(
      "UPDATE cash_sessions SET status = 'closed', closed_by = ?, closed_at = ?, "
      'expected_cash = ?, counted_cash = ?, difference = ?, note = ? WHERE id = ?',
      [
        _moi,
        maintenantIso(),
        r.attendu,
        compte,
        ecart,
        (note == null || note.trim().isEmpty) ? null : note.trim(),
        s.id,
      ],
    );
    return ecart;
  }
}

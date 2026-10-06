import 'package:supabase_flutter/supabase_flutter.dart';

import 'base_locale.dart';

SupabaseClient get _serveur => Supabase.instance.client;

class MembreEquipe {
  MembreEquipe({
    required this.id,
    required this.userId,
    required this.nom,
    required this.estPatronne,
    required this.actif,
    required this.peutVoirCouts,
    this.boutiqueId,
    this.boutiqueNom,
  });

  final String id;
  final String userId;
  final String nom;
  final bool estPatronne;
  final bool actif;
  final bool peutVoirCouts;
  final String? boutiqueId;
  final String? boutiqueNom;
}

class Invitation {
  Invitation({
    required this.id,
    required this.nom,
    required this.code,
    required this.boutiqueNom,
    required this.expireLe,
  });

  final String id;
  final String nom;
  final String code;
  final String boutiqueNom;
  final DateTime expireLe;
}

class EquipeRepo {
  EquipeRepo({required this.compteId});
  final String compteId;

  /// Patronne et employées, lues sur l'appareil, mises à jour en direct.
  Stream<List<MembreEquipe>> surveillerMembres() => db
      .watch(
        'SELECT m.id, m.user_id, m.display_name, m.role, m.active, m.can_see_costs, m.shop_id, '
        's.name AS boutique_nom FROM members m LEFT JOIN shops s ON s.id = m.shop_id '
        "WHERE m.account_id = ? ORDER BY m.role = 'owner' DESC, m.display_name COLLATE NOCASE",
        parameters: [compteId],
        triggerOnTables: const ['members', 'shops'],
      )
      .map((lignes) => [
            for (final l in lignes)
              MembreEquipe(
                id: l['id'] as String,
                userId: l['user_id'] as String? ?? '',
                nom: l['display_name'] as String? ?? '',
                estPatronne: l['role'] == 'owner',
                actif: l['active'] == null || ouiNon(l['active']),
                peutVoirCouts: ouiNon(l['can_see_costs']),
                boutiqueId: l['shop_id'] as String?,
                boutiqueNom: l['boutique_nom'] as String?,
              ),
          ]);

  /// Désactiver une employée lui retire l'accès immédiatement (dès la synchronisation).
  Future<void> activer(MembreEquipe m, bool actif) async {
    await db.execute('UPDATE members SET active = ? WHERE id = ?', [actif ? 1 : 0, m.id]);
  }

  Future<void> changerBoutique(MembreEquipe m, String boutiqueId) async {
    await db.execute('UPDATE members SET shop_id = ? WHERE id = ?', [boutiqueId, m.id]);
  }

  Future<void> autoriserCouts(MembreEquipe m, bool autorise) async {
    await db.execute('UPDATE members SET can_see_costs = ? WHERE id = ?', [autorise ? 1 : 0, m.id]);
  }

  // ---------- Invitations : demandent internet ----------

  Future<List<Invitation>> invitationsEnCours() async {
    final lignes = await _serveur
        .from('invitations')
        .select('id, display_name, code, expires_at, shops(name)')
        .eq('account_id', compteId)
        .isFilter('used_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return [
      for (final l in lignes)
        Invitation(
          id: l['id'] as String,
          nom: l['display_name'] as String,
          code: l['code'] as String,
          boutiqueNom: (l['shops'] is Map) ? (l['shops']['name'] as String? ?? '') : '',
          expireLe: DateTime.parse(l['expires_at'] as String).toLocal(),
        ),
    ];
  }

  /// Crée une invitation et renvoie son code (6 caractères).
  Future<String> inviter({required String boutiqueId, required String nom, bool voitCouts = false}) async {
    final code = await _serveur.rpc('create_invitation', params: {
      'p_shop_id': boutiqueId,
      'p_name': nom.trim(),
      'p_can_see_costs': voitCouts,
    });
    return code as String;
  }

  Future<void> supprimerInvitation(String id) async {
    await _serveur.from('invitations').delete().eq('id', id);
  }

  /// Pour une employée : rejoindre la boutique avec le code reçu de la patronne.
  static Future<void> rejoindre(String code) async {
    final compte = await _serveur.rpc('join_with_invitation', params: {'p_code': code.trim().toUpperCase()});
    if (compte == null) {
      throw Exception('Code invalide, déjà utilisé ou expiré. Vérifiez les lettres et les chiffres, '
          'ou demandez un nouveau code à la patronne.');
    }
  }
}

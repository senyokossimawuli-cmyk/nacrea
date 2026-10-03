import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/base_locale.dart';

/// La personne connectée, telle que Nacréa la connaît.
class Membre {
  Membre({
    required this.id,
    required this.role,
    required this.nom,
    required this.compteId,
    required this.nomCompte,
    this.boutiqueId,
    this.peutVoirCouts = false,
  });

  final String id;
  final String role; // 'owner' (patronne) ou 'employee' (employée)
  final String nom;
  final String compteId;
  final String nomCompte;
  final String? boutiqueId;

  /// Peut voir les prix d'achat et les marges (toujours vrai pour la patronne).
  final bool peutVoirCouts;

  bool get estPatronne => role == 'owner';

  /// Renvoie le membre de la personne connectée (lu sur l'appareil, même sans internet),
  /// ou null si elle n'a pas encore créé son entreprise.
  static Future<Membre?> charger() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final ligne = await db.getOptional(
      'SELECT m.id, m.role, m.display_name, m.account_id, m.shop_id, m.can_see_costs, a.name AS nom_compte '
      'FROM members m LEFT JOIN accounts a ON a.id = m.account_id '
      "WHERE m.user_id = ? AND COALESCE(m.active, 1) IN (1, 'true') LIMIT 1",
      [userId],
    );
    if (ligne == null) return null;

    return Membre(
      id: ligne['id'] as String,
      role: ligne['role'] as String? ?? 'employee',
      nom: ligne['display_name'] as String? ?? '',
      compteId: ligne['account_id'] as String,
      nomCompte: ligne['nom_compte'] as String? ?? '',
      boutiqueId: ligne['shop_id'] as String?,
      peutVoirCouts: ligne['role'] == 'owner' || ouiNon(ligne['can_see_costs']),
    );
  }

  /// Après la création de l'entreprise sur le serveur, attend qu'elle arrive sur l'appareil.
  static Future<Membre?> attendre({Duration delai = const Duration(seconds: 30)}) async {
    final fin = DateTime.now().add(delai);
    while (DateTime.now().isBefore(fin)) {
      final m = await charger();
      if (m != null) return m;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return null;
  }
}

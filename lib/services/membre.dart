import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Renvoie le membre de la personne connectée, ou null si elle
  /// n'a pas encore créé son entreprise.
  static Future<Membre?> charger() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;

    final ligne = await client
        .from('members')
        .select('id, role, display_name, account_id, shop_id, can_see_costs, accounts(name)')
        .eq('user_id', userId)
        .eq('active', true)
        .limit(1)
        .maybeSingle();
    if (ligne == null) return null;

    final compte = ligne['accounts'];
    return Membre(
      id: ligne['id'] as String,
      role: ligne['role'] as String,
      nom: ligne['display_name'] as String,
      compteId: ligne['account_id'] as String,
      nomCompte: compte is Map ? (compte['name'] as String? ?? '') : '',
      boutiqueId: ligne['shop_id'] as String?,
      peutVoirCouts: ligne['role'] == 'owner' || ligne['can_see_costs'] == true,
    );
  }
}

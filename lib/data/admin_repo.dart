import 'package:supabase_flutter/supabase_flutter.dart';

/// Espace administrateur de Nacréa (pour l'éditeur du logiciel).
/// Tout passe par le serveur : il faut internet.
SupabaseClient get _serveur => Supabase.instance.client;

int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

const libellesStatut = {
  'trial': 'Essai',
  'active': 'Payé',
  'late': 'En retard',
  'suspended': 'Suspendue',
};

const libellesMoyen = {
  'mobile_money': 'Mobile Money',
  'cash': 'Espèces',
  'bank': 'Virement',
  'other': 'Autre',
};

class ApercuAdmin {
  ApercuAdmin(Map<String, dynamic> j)
      : comptes = _entier(j['comptes']),
        boutiques = _entier(j['boutiques']),
        essai = _entier(j['essai']),
        actives = _entier(j['actives']),
        enRetard = _entier(j['en_retard']),
        suspendues = _entier(j['suspendues']),
        revenuMensuel = _entier(j['revenu_mensuel']),
        encaisseMois = _entier(j['encaisse_mois']),
        essaisFinProche = _entier(j['essais_fin_proche']);

  final int comptes, boutiques, essai, actives, enRetard, suspendues;
  final int revenuMensuel, encaisseMois, essaisFinProche;
}

class ClienteNacrea {
  ClienteNacrea(Map<String, dynamic> j)
      : id = j['id'] as String,
        nom = j['nom'] as String? ?? '',
        patronne = j['patronne'] as String?,
        email = j['email'] as String?,
        telephone = j['telephone'] as String?,
        creeLe = _date(j['cree_le']),
        nbBoutiques = _entier(j['nb_boutiques']),
        statuts = [for (final s in (j['statuts'] as List? ?? const [])) '$s'],
        mensuel = _entier(j['mensuel']),
        prochaineFin = _date(j['prochaine_fin']),
        derniereVente = _date(j['derniere_vente']);

  final String id;
  final String nom;
  final String? patronne, email, telephone;
  final DateTime? creeLe, prochaineFin, derniereVente;
  final int nbBoutiques, mensuel;
  final List<String> statuts;

  /// Statut le plus urgent parmi ses boutiques.
  String get statutPrincipal {
    for (final s in const ['suspended', 'late', 'trial', 'active']) {
      if (statuts.contains(s)) return s;
    }
    return 'trial';
  }

  bool get aRelancer =>
      statuts.contains('late') ||
      statuts.contains('suspended') ||
      (prochaineFin != null && prochaineFin!.difference(DateTime.now()).inDays <= 3);
}

class BoutiqueAdmin {
  BoutiqueAdmin(Map<String, dynamic> j)
      : id = j['id'] as String,
        nom = j['nom'] as String? ?? '',
        adresse = j['adresse'] as String?,
        telephone = j['telephone'] as String?,
        statut = j['statut'] as String? ?? 'trial',
        fin = _date(j['fin']),
        prix = _entier(j['prix']),
        derniereVente = _date(j['derniere_vente']),
        ventes30j = _entier(j['ventes_30j']);

  final String id, nom, statut;
  final String? adresse, telephone;
  final DateTime? fin, derniereVente;
  final int prix, ventes30j;
}

class PaiementAbonnement {
  PaiementAbonnement(Map<String, dynamic> j)
      : id = j['id'] as String,
        boutique = j['boutique'] as String? ?? '',
        montant = _entier(j['montant']),
        mois = _entier(j['mois']),
        moyen = j['moyen'] as String? ?? 'other',
        note = j['note'] as String?,
        le = _date(j['le']) ?? DateTime.now(),
        jusquAu = _date(j['jusqu_au']);

  final String id, boutique, moyen;
  final String? note;
  final int montant, mois;
  final DateTime le;
  final DateTime? jusquAu;
}

class FicheClienteNacrea {
  FicheClienteNacrea(Map<String, dynamic> j)
      : id = j['id'] as String,
        nom = j['nom'] as String? ?? '',
        patronne = j['patronne'] as String?,
        email = j['email'] as String?,
        telephone = j['telephone'] as String?,
        creeLe = _date(j['cree_le']),
        nbEmployees = _entier(j['nb_employees']),
        boutiques = [for (final b in (j['boutiques'] as List? ?? const [])) BoutiqueAdmin(b as Map<String, dynamic>)],
        paiements = [
          for (final p in (j['paiements'] as List? ?? const [])) PaiementAbonnement(p as Map<String, dynamic>)
        ];

  final String id, nom;
  final String? patronne, email, telephone;
  final DateTime? creeLe;
  final int nbEmployees;
  final List<BoutiqueAdmin> boutiques;
  final List<PaiementAbonnement> paiements;

  /// Téléphone à utiliser pour WhatsApp : celui de l'entreprise, sinon d'une boutique.
  String? get telephoneContact =>
      telephone ?? boutiques.map((b) => b.telephone).whereType<String>().where((t) => t.isNotEmpty).firstOrNull;
}

class AdminRepo {
  /// Vrai si la personne connectée est administratrice de Nacréa.
  /// Sans internet (ou si le script 11 n'est pas installé) : faux.
  static Future<bool> estAdmin() async {
    try {
      final r = await _serveur.rpc('is_platform_admin').timeout(const Duration(seconds: 8));
      return r == true;
    } catch (_) {
      return false;
    }
  }

  Future<ApercuAdmin> apercu() async =>
      ApercuAdmin(Map<String, dynamic>.from(await _serveur.rpc('admin_overview') as Map));

  Future<List<ClienteNacrea>> clientes() async {
    final liste = await _serveur.rpc('admin_accounts') as List;
    return [for (final c in liste) ClienteNacrea(Map<String, dynamic>.from(c as Map))];
  }

  Future<FicheClienteNacrea> fiche(String compteId) async => FicheClienteNacrea(
      Map<String, dynamic>.from(await _serveur.rpc('admin_account_detail', params: {'p_account_id': compteId}) as Map));

  Future<DateTime?> enregistrerPaiement({
    required String boutiqueId,
    required int montant,
    required int mois,
    required String moyen,
    String? note,
  }) async {
    final fin = await _serveur.rpc('admin_record_payment', params: {
      'p_shop_id': boutiqueId,
      'p_amount': montant,
      'p_months': mois,
      'p_method': moyen,
      'p_note': note,
    });
    return _date(fin);
  }

  Future<DateTime?> offrirJours(String boutiqueId, int jours) async =>
      _date(await _serveur.rpc('admin_extend', params: {'p_shop_id': boutiqueId, 'p_days': jours}));

  Future<String> suspendre(String boutiqueId, bool suspendre) async =>
      '${await _serveur.rpc('admin_set_suspended', params: {'p_shop_id': boutiqueId, 'p_suspendre': suspendre})}';

  Future<void> changerPrix(String boutiqueId, int prix) =>
      _serveur.rpc('admin_set_price', params: {'p_shop_id': boutiqueId, 'p_price': prix});

  Future<void> supprimerBoutique(String boutiqueId) =>
      _serveur.rpc('admin_delete_shop', params: {'p_shop_id': boutiqueId});

  Future<void> supprimerPaiement(String paiementId) =>
      _serveur.rpc('admin_delete_payment', params: {'p_payment_id': paiementId});
}

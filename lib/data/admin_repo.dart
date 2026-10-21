import 'package:supabase_flutter/supabase_flutter.dart';

/// Espace administrateur de YDS Beauty (pour l'éditeur du logiciel).
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
  /// Vrai si la personne connectée est administratrice de YDS Beauty.
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

// ---------------------------------------------------------------- Licences

class AppareilAdmin {
  AppareilAdmin(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String? ?? 'pc',
        nom = j['nom'] as String?,
        email = j['email'] as String?,
        premier = _date(j['premier']),
        vuLe = _date(j['vu_le']);

  final String id, type;
  final String? nom, email;
  final DateTime? premier, vuLe;

  bool get estPc => type == 'pc';
  String get libelle => nom ?? (estPc ? 'Ordinateur' : 'Téléphone');
}

class LicenceAdmin {
  LicenceAdmin(Map<String, dynamic> j)
      : id = j['id'] as String,
        cle = j['cle'] as String,
        note = j['note'] as String?,
        active = j['active'] == true,
        maxPc = _entier(j['max_pc']),
        maxTelephones = _entier(j['max_mobile']),
        creeLe = _date(j['cree_le']),
        activeeLe = _date(j['activee_le']),
        compteId = j['compte_id'] as String?,
        compte = j['compte'] as String?,
        patronne = j['patronne'] as String?,
        telephone = j['telephone'] as String?,
        mensuel = _entier(j['mensuel']),
        expireLe = _date(j['expire_le']),
        attenteMois = j['attente_mois'] == null ? null : _entier(j['attente_mois']),
        attenteJours = j['attente_jours'] == null ? null : _entier(j['attente_jours']),
        graceJours = j['grace_jours'] == null ? 7 : _entier(j['grace_jours']),
        appareils = [
          for (final a in (j['appareils'] as List? ?? const [])) AppareilAdmin(Map<String, dynamic>.from(a as Map))
        ];

  final String id, cle;
  final String? note, compteId, compte, patronne, telephone;
  final int mensuel, graceJours;
  final int? attenteMois, attenteJours;

  /// Date de fin (null : illimitée, ou durée qui démarrera à l'activation).
  final DateTime? expireLe;
  final bool active;
  final int maxPc, maxTelephones;
  final DateTime? creeLe, activeeLe;
  final List<AppareilAdmin> appareils;

  bool get libre => compteId == null;

  /// Durée qui démarrera quand la cliente activera la clé.
  bool get enAttente => expireLe == null && ((attenteMois ?? 0) > 0 || (attenteJours ?? 0) > 0);
  bool get illimitee => !enAttente && (expireLe == null || expireLe!.year >= 2900);
  bool get expiree => !illimitee && expireLe != null && DateTime.now().isAfter(expireLe!);
  bool get bloquee => expiree && DateTime.now().isAfter(expireLe!.add(Duration(days: graceJours)));

  /// Jours restants avant la fin (négatif si dépassée).
  int? get joursRestants => illimitee || expireLe == null ? null : expireLe!.difference(DateTime.now()).inHours ~/ 24;

  String get dureeEnAttente => [
        if ((attenteMois ?? 0) > 0) '$attenteMois mois',
        if ((attenteJours ?? 0) > 0) '$attenteJours jour${attenteJours! > 1 ? 's' : ''}',
      ].join(' et ');
  int get nbPc => appareils.where((a) => a.estPc).length;
  int get nbTelephones => appareils.where((a) => !a.estPc).length;
}

extension LicencesAdmin on AdminRepo {
  Future<List<LicenceAdmin>> licences({String? compteId}) async {
    final liste = await _serveur.rpc('admin_licenses', params: {'p_account_id': compteId}) as List;
    return [for (final l in liste) LicenceAdmin(Map<String, dynamic>.from(l as Map))];
  }

  /// Renvoie la clé créée.
  Future<String> creerLicence({
    String? note,
    int maxPc = 1,
    int maxTelephones = 1,
    String? compteId,
    int? mois,
    int? jours,
    DateTime? expireLe,
  }) async {
    final r = await _serveur.rpc('admin_create_license', params: {
      'p_note': note,
      'p_max_pc': maxPc,
      'p_max_mobile': maxTelephones,
      'p_account_id': compteId,
      'p_months': mois,
      'p_days': jours,
      'p_expires_at': expireLe?.toUtc().toIso8601String(),
    });
    return '${(r as Map)['cle']}';
  }

  /// Prolonge de N mois / N jours.
  Future<void> prolongerLicence(String id, {int mois = 0, int jours = 0}) =>
      _serveur.rpc('admin_extend_license', params: {'p_id': id, 'p_months': mois, 'p_days': jours});

  /// Date de fin précise (null : illimitée).
  Future<void> changerExpiration(String id, DateTime? fin) =>
      _serveur.rpc('admin_set_license_expiry', params: {'p_id': id, 'p_expires_at': fin?.toUtc().toIso8601String()});

  /// Paiement reçu : la licence est prolongée. Renvoie la nouvelle date de fin (null : illimitée).
  Future<DateTime?> enregistrerPaiementLicence(String id,
      {required int montant, required int mois, required String moyen, String? note}) async {
    final r = await _serveur.rpc('admin_record_license_payment', params: {
      'p_id': id,
      'p_amount': montant,
      'p_months': mois,
      'p_method': moyen,
      'p_note': note,
    });
    return _date(r);
  }

  Future<void> modifierLicence(String id, {String? note, required int maxPc, required int maxTelephones}) =>
      _serveur.rpc('admin_update_license',
          params: {'p_id': id, 'p_note': note, 'p_max_pc': maxPc, 'p_max_mobile': maxTelephones});

  Future<void> activerLicence(String id, bool active) =>
      _serveur.rpc('admin_set_license_active', params: {'p_id': id, 'p_active': active});

  Future<void> libererAppareil(String appareilId) =>
      _serveur.rpc('admin_remove_license_device', params: {'p_device': appareilId});

  Future<void> supprimerLicence(String id) => _serveur.rpc('admin_delete_license', params: {'p_id': id});
}

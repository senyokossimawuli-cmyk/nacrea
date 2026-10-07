import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

SupabaseClient get _serveur => Supabase.instance.client;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _entier(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// Un appareil enregistré sur la licence.
class AppareilLicence {
  AppareilLicence(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String? ?? 'pc',
        nom = j['nom'] as String?,
        email = j['email'] as String?,
        premier = _date(j['premier']),
        vuLe = _date(j['vu_le']),
        ceAppareil = j['ce_appareil'] == true;

  final String id, type;
  final String? nom, email;
  final DateTime? premier, vuLe;
  final bool ceAppareil;

  bool get estPc => type == 'pc';
  String get libelle => nom ?? (estPc ? 'Ordinateur' : 'Téléphone');
}

/// Réponse du serveur sur la licence de cet appareil.
class EtatLicence {
  EtatLicence(Map<String, dynamic> j, {this.horsLigne = false})
      : etat = j['etat'] as String? ?? 'aucune',
        patronne = j['patronne'] == true,
        admin = j['admin'] == true,
        cle = j['cle'] as String?,
        type = j['type'] as String?,
        maxPc = _entier(j['max_pc']),
        maxTelephones = _entier(j['max_mobile']),
        peutRemplacer = j['peut_remplacer'] == true,
        remplacementLe = _date(j['remplacement_le']),
        appareils = [
          for (final a in (j['appareils'] as List? ?? const [])) AppareilLicence(Map<String, dynamic>.from(a as Map))
        ];

  /// ok, aucune, desactivee, limite, cle_incorrecte, cle_deja_utilisee, sans_entreprise
  final String etat;
  final bool patronne, admin, peutRemplacer, horsLigne;
  final String? cle, type;
  final int maxPc, maxTelephones;
  final DateTime? remplacementLe;
  final List<AppareilLicence> appareils;

  /// Nacréa peut s'ouvrir. (« sans_entreprise » : l'écran de création de boutique s'en occupe.)
  bool get valide => etat == 'ok' || etat == 'sans_entreprise';

  String get resume => [
        if (maxPc > 0) '$maxPc ordinateur${maxPc > 1 ? 's' : ''}',
        if (maxTelephones > 0) '$maxTelephones téléphone${maxTelephones > 1 ? 's' : ''}',
      ].join(' et ');
}

/// Licence Nacréa : clé liée à l'entreprise, nombre d'appareils limité.
class Licence {
  static String? _idAppareil;

  static bool get _telephone => Platform.isAndroid || Platform.isIOS;

  /// 'pc' ou 'mobile'
  static String get typeAppareil => _telephone ? 'mobile' : 'pc';

  static String get nomAppareil {
    if (Platform.isAndroid) return 'Téléphone Android';
    if (Platform.isIOS) return 'iPhone';
    final nom = Platform.localHostname.trim();
    final type = Platform.isMacOS ? 'Mac' : 'PC';
    return nom.isEmpty ? type : '$type $nom';
  }

  static Future<File> _fichier(String nom) async {
    final dossier = await getApplicationSupportDirectory();
    await dossier.create(recursive: true);
    return File(p.join(dossier.path, nom));
  }

  /// Identifiant de cet appareil, créé une fois puis conservé.
  static Future<String> idAppareil() async {
    if (_idAppareil != null) return _idAppareil!;
    final f = await _fichier('nacrea-appareil.txt');
    if (await f.exists()) {
      final id = (await f.readAsString()).trim();
      if (id.length >= 16) return _idAppareil = id;
    }
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await f.writeAsString(id, flush: true);
    return _idAppareil = id;
  }

  static Future<Map<String, dynamic>> _params() async => {
        'p_device_id': await idAppareil(),
        'p_kind': typeAppareil,
        'p_name': nomAppareil,
      };

  // ----- Dernière vérification réussie, pour travailler sans internet -----

  static Future<void> _memoriser(EtatLicence e) async {
    try {
      final f = await _fichier('nacrea-licence.json');
      if (e.etat == 'ok') {
        await f.writeAsString(jsonEncode({
          'user': _serveur.auth.currentUser?.id,
          'le': DateTime.now().toUtc().toIso8601String(),
          'cle': e.cle,
          'admin': e.admin,
        }));
      } else if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Pas grave : on revérifiera à la prochaine ouverture.
    }
  }

  static Future<EtatLicence?> _derniereValide() async {
    try {
      final f = await _fichier('nacrea-licence.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final le = DateTime.tryParse('${j['le']}');
      if (j['user'] != _serveur.auth.currentUser?.id || le == null) return null;
      final age = DateTime.now().toUtc().difference(le);
      if (age.isNegative || age.inDays >= NacreaConfig.joursLicenceHorsLigne) return null;
      return EtatLicence({'etat': 'ok', 'cle': j['cle'], 'admin': j['admin']}, horsLigne: true);
    } catch (_) {
      return null;
    }
  }

  static EtatLicence _lire(Object? r) => EtatLicence(Map<String, dynamic>.from(r as Map));

  /// Vérifie la licence de cet appareil (à chaque ouverture).
  /// Sans internet : la dernière vérification réussie reste valable 30 jours.
  static Future<EtatLicence> verifier() async {
    try {
      final r = await _serveur.rpc('license_check', params: await _params()).timeout(const Duration(seconds: 12));
      final e = _lire(r);
      await _memoriser(e);
      return e;
    } on PostgrestException catch (e) {
      // Script 15 pas encore installé sur le serveur : on laisse passer.
      if (e.message.contains('Could not find the function')) return EtatLicence({'etat': 'ok'});
      rethrow;
    } catch (e) {
      final memo = await _derniereValide();
      if (memo != null) return memo;
      rethrow;
    }
  }

  /// La patronne tape sa clé.
  static Future<EtatLicence> activer(String cle) async {
    final r = await _serveur.rpc('license_activate', params: {'p_key': cle, ...await _params()});
    final e = _lire(r);
    await _memoriser(e);
    return e;
  }

  /// Remplace un ancien appareil par celui-ci.
  static Future<EtatLicence> remplacer(String ancienAppareilId) async {
    final r = await _serveur.rpc('license_replace_device', params: {'p_old_device': ancienAppareilId, ...await _params()});
    final e = _lire(r);
    await _memoriser(e);
    return e;
  }
}

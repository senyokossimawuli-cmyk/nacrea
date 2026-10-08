import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Vrai sur téléphone ou tablette (Android, iPhone).
bool get estTelephone => Platform.isAndroid || Platform.isIOS;

/// La caméra peut servir de scanner de codes-barres.
bool get cameraScanner => Platform.isAndroid || Platform.isIOS;

/// Nom affiché dans la liste des appareils de la licence.
String get nomAppareil {
  if (Platform.isAndroid) return 'Téléphone Android';
  if (Platform.isIOS) return 'iPhone';
  final nom = Platform.localHostname.trim();
  final type = Platform.isMacOS ? 'Mac' : 'PC';
  return nom.isEmpty ? type : '$type $nom';
}

Future<File> _fichier(String nom) async {
  final dossier = await getApplicationSupportDirectory();
  await dossier.create(recursive: true);
  return File(p.join(dossier.path, nom));
}

/// Petites données gardées sur l'appareil (identifiant, licence).
Future<String?> lireDonnee(String nom) async {
  final f = await _fichier(nom);
  return await f.exists() ? f.readAsString() : null;
}

Future<void> ecrireDonnee(String nom, String valeur) async =>
    (await _fichier(nom)).writeAsString(valeur, flush: true);

Future<void> effacerDonnee(String nom) async {
  final f = await _fichier(nom);
  if (await f.exists()) await f.delete();
}

/// Emplacement de la base de données locale.
Future<String> cheminBaseLocale(String nom) async {
  final dossier = await getApplicationSupportDirectory();
  return p.join(dossier.path, nom);
}

/// Faut-il expliquer comment mettre l'appli sur l'écran d'accueil ? (iPhone, navigateur seulement)
bool get proposerInstallationIphone => false;

import 'package:web/web.dart' as web;

String get _ua => web.window.navigator.userAgent;

bool get _iPad => _ua.contains('iPad') || (_ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);

/// Vrai sur téléphone ou tablette (iPhone, iPad, Android) ouvert dans le navigateur.
bool get estTelephone => _iPad || RegExp('iPhone|iPod|Android|Mobile').hasMatch(_ua);

/// La caméra peut servir de scanner de codes-barres (téléphone uniquement).
bool get cameraScanner => estTelephone;

/// Nom affiché dans la liste des appareils de la licence.
String get nomAppareil {
  if (_ua.contains('iPhone') || _ua.contains('iPod')) return 'iPhone';
  if (_iPad) return 'iPad';
  if (_ua.contains('Android')) return 'Téléphone Android (navigateur)';
  return 'Ordinateur (navigateur)';
}

/// Petites données gardées dans le navigateur (identifiant, licence).
Future<String?> lireDonnee(String nom) async {
  try {
    return web.window.localStorage.getItem('yds.$nom');
  } catch (_) {
    return null;
  }
}

Future<void> ecrireDonnee(String nom, String valeur) async {
  try {
    web.window.localStorage.setItem('yds.$nom', valeur);
  } catch (_) {}
}

Future<void> effacerDonnee(String nom) async {
  try {
    web.window.localStorage.removeItem('yds.$nom');
  } catch (_) {}
}

/// Dans le navigateur, la base locale a juste un nom.
Future<String> cheminBaseLocale(String nom) async => nom;

bool get _installee {
  try {
    return web.window.matchMedia('(display-mode: standalone)').matches;
  } catch (_) {
    return false;
  }
}

/// iPhone / iPad dans Safari, appli pas encore sur l'écran d'accueil.
bool get proposerInstallationIphone =>
    (_ua.contains('iPhone') || _ua.contains('iPod') || _iPad) && !_installee;

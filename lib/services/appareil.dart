// Ce qui dépend de l'appareil (PC, téléphone, navigateur web).
// Le bon fichier est choisi automatiquement selon la plateforme.
export 'appareil_io.dart' if (dart.library.js_interop) 'appareil_web.dart';

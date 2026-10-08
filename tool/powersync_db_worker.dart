// Base de données hors ligne dans le navigateur : ce fichier est transformé en
// web/powersync_db.worker.js au moment de fabriquer le site (voir .github/workflows).
// Il est compilé avec exactement les mêmes versions de paquets que l'application.
import 'package:powersync/web_worker.dart' as powersync;

void main() => powersync.main();

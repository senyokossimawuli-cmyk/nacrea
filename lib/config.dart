/// Connexion au projet Supabase de Nacréa.
/// La clé publique (publishable) peut figurer dans le logiciel :
/// la sécurité des données est assurée par les règles de la base.
/// Ne jamais mettre ici la clé "secret" ou "service_role".
class NacreaConfig {
  static const supabaseUrl = 'https://hzbczjfsqqwwpaazfysz.supabase.co';
  static const supabasePublishableKey =
      'sb_publishable_U7Qbem4nKosVVNn3-4r-ig_ZT7D_4BQ';

  /// Adresse de l'instance PowerSync (synchronisation hors ligne).
  static const powersyncUrl = 'https://6ac1026b2f27853eb0abf174.powersync.journeyapps.com';

  /// Numéro WhatsApp du service client Nacréa (indicatif compris, ex. 22890000000).
  /// Affiché aux patronnes dont l'abonnement est en retard ou suspendu.
  static const supportWhatsApp = '22879867879';

  /// Jours de retard tolérés avant que la caisse soit bloquée (comme sur le serveur).
  static const joursDeGrace = 7;
}

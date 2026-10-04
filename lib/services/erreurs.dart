import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit les erreurs techniques en messages clairs, en français.
String messageErreur(Object erreur) {
  if (erreur is AuthException) {
    final m = erreur.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'E-mail ou mot de passe incorrect.';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Un compte existe déjà avec cet e-mail. Connectez-vous.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirmez d\'abord votre e-mail grâce au lien reçu.';
    }
    if (m.contains('password')) {
      return 'Mot de passe trop faible : 8 caractères minimum.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Trop de tentatives. Patientez quelques minutes.';
    }
    return 'Connexion impossible : ${erreur.message}';
  }
  if (erreur is PostgrestException) {
    if (erreur.message.contains('déjà une entreprise')) {
      return 'Ce compte possède déjà une entreprise.';
    }
    if (erreur.message.contains('Could not find the function')) {
      return 'La base de données n\'est pas à jour : un script SUPABASE n\'a pas été exécuté.';
    }
    // Messages écrits par Nacréa dans ses scripts SQL (raise exception) : affichés tels quels.
    if (erreur.code == 'P0001') return erreur.message;
    return 'Erreur de la base de données : ${erreur.message}';
  }
  final texte = erreur.toString().toLowerCase();
  if (texte.contains('socket') || texte.contains('failed host lookup') ||
      texte.contains('network') || texte.contains('clientexception')) {
    return 'Pas de connexion internet. Vérifiez votre réseau puis réessayez.';
  }
  // Messages écrits par Nacréa lui-même (Exception('…')) : affichés tels quels.
  final brut = erreur.toString();
  if (erreur is Exception && brut.startsWith('Exception: ')) {
    return brut.substring('Exception: '.length);
  }
  return 'Une erreur est survenue. Réessayez.';
}

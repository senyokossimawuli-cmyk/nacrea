import 'package:flutter_test/flutter_test.dart';
import 'package:nacrea/services/erreurs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('les erreurs de connexion sont traduites en français', () {
    expect(
      messageErreur(AuthException('Invalid login credentials')),
      'E-mail ou mot de passe incorrect.',
    );
    expect(
      messageErreur(AuthException('User already registered')),
      'Un compte existe déjà avec cet e-mail. Connectez-vous.',
    );
  });

  test('une coupure réseau donne un message clair', () {
    expect(
      messageErreur(Exception('SocketException: Failed host lookup')),
      'Pas de connexion internet. Vérifiez votre réseau puis réessayez.',
    );
  });
}

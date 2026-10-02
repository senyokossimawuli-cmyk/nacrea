import 'package:flutter_test/flutter_test.dart';
import 'package:nacrea/services/erreurs.dart';
import 'package:nacrea/utils/format.dart';
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

  test('les montants sont affichés en FCFA avec des espaces', () {
    expect(fcfa(3500), '3\u202F500 FCFA');
    expect(fcfa(1250000), '1\u202F250\u202F000 FCFA');
    expect(fcfa(500), '500 FCFA');
  });
}

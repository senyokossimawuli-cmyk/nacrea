import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/nacrea_logo.dart';
import 'shell_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Choisit l'écran à afficher :
/// pas connectée → connexion ; connectée sans entreprise → création ; sinon → accueil.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) return const LoginScreen();
        // La clé force un rechargement quand une autre personne se connecte.
        return _ChargementMembre(key: ValueKey(session.user.id));
      },
    );
  }
}

class _ChargementMembre extends StatefulWidget {
  const _ChargementMembre({super.key});

  @override
  State<_ChargementMembre> createState() => _ChargementMembreState();
}

class _ChargementMembreState extends State<_ChargementMembre> {
  late Future<Membre?> _membre = Membre.charger();

  void _recharger() => setState(() => _membre = Membre.charger());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Membre?>(
      future: _membre,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NacreaLogo(taille: 40, avecSlogan: false),
                  SizedBox(height: 32),
                  CircularProgressIndicator(color: NacreaColors.prune),
                ],
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(messageErreur(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 240,
                      child: FilledButton(onPressed: _recharger, child: const Text('Réessayer')),
                    ),
                    TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final membre = snap.data;
        if (membre == null) return OnboardingScreen(quandCree: _recharger);
        return ShellScreen(membre: membre);
      },
    );
  }
}

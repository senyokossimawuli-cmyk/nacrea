import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_repo.dart';
import '../data/base_locale.dart';
import '../services/erreurs.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/deconnexion.dart';
import '../widgets/nacrea_logo.dart';
import 'admin/admin_page.dart';
import 'licence_screen.dart';
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
  late Future<(Membre?, bool)> _membre = _charger();

  /// Attend que les données de l'appareil soient prêtes, puis lit la personne connectée.
  /// Vérifie aussi (en parallèle) si c'est l'administrateur de YDS Beauty.
  static Future<(Membre?, bool)> _charger({bool attendreServeur = false}) async {
    final admin = AdminRepo.estAdmin();
    await attendrePremiereSynchro();
    final membre = await (attendreServeur ? Membre.attendre() : Membre.charger());
    return (membre, await admin);
  }

  void _recharger() => setState(() => _membre = _charger());

  /// Après la création de l'entreprise : elle arrive du serveur en quelques secondes.
  void _apresCreation() => setState(() => _membre = _charger(attendreServeur: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Membre?, bool)>(
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
                      onPressed: () => deconnexion(context),
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final (membre, admin) = snap.data!;
        if (membre != null) {
          // L'administrateur de YDS Beauty n'a pas besoin de licence.
          if (admin) return ShellScreen(membre: membre, estAdmin: true);
          return LicenceGate(membre: membre, enfant: () => ShellScreen(membre: membre, estAdmin: false));
        }
        if (admin) return const _AdminSeul();
        return OnboardingScreen(quandCree: _apresCreation);
      },
    );
  }
}

/// L'administrateur sans boutique à lui : il arrive directement sur l'espace admin.
class _AdminSeul extends StatelessWidget {
  const _AdminSeul();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const NacreaLogo(taille: 22, avecSlogan: false),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => deconnexion(context),
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: NacreaColors.bordure),
        ),
      ),
      body: const AdminPage(),
    );
  }
}

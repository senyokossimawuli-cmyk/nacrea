import 'package:flutter/material.dart';

import '../theme/nacrea_theme.dart';
import 'nacrea_logo.dart';

/// Mise en page des écrans d'accueil (connexion, inscription, création de boutique).
/// Grand écran (PC) : panneau prune avec le logo à gauche, formulaire à droite.
/// Petit écran (téléphone) : logo en haut, formulaire en dessous.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.titre, required this.sousTitre, required this.child});

  final String titre;
  final String sousTitre;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final formulaire = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titre, style: NacreaTheme.titre(size: 36)),
          const SizedBox(height: 8),
          Text(sousTitre, style: const TextStyle(fontSize: 15, color: NacreaColors.gris)),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(
                  child: Container(
                    color: NacreaColors.prune,
                    padding: const EdgeInsets.all(48),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NacreaLogo(taille: 64, surFondFonce: true),
                        SizedBox(height: 48),
                        Text(
                          'Vos ventes, votre stock et toutes vos boutiques,\nau même endroit.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, height: 1.5, color: NacreaColors.nude),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(48),
                      child: formulaire,
                    ),
                  ),
                ),
              ],
            );
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              child: Column(
                children: [
                  const NacreaLogo(taille: 44),
                  const SizedBox(height: 40),
                  formulaire,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bandeau d'erreur rouge, affiché au-dessus des boutons.
class MessageErreur extends StatelessWidget {
  const MessageErreur(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEBEB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: NacreaColors.erreur),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: NacreaColors.erreur))),
        ],
      ),
    );
  }
}

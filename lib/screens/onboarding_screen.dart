import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../widgets/auth_layout.dart';

/// Première connexion d'une patronne : elle crée son entreprise et sa première boutique.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.quandCree});

  /// Appelé une fois l'entreprise créée, pour afficher l'accueil.
  final VoidCallback quandCree;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _nomPatronne = TextEditingController();
  final _nomEntreprise = TextEditingController();
  final _nomBoutique = TextEditingController();
  final _telephone = TextEditingController();
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _nomPatronne.dispose();
    _nomEntreprise.dispose();
    _nomBoutique.dispose();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_chargement) return; // évite un double clic
    if (!_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final telephone = _telephone.text.trim();
      await Supabase.instance.client.rpc('create_account_with_shop', params: {
        'p_owner_name': _nomPatronne.text.trim(),
        'p_account_name': _nomEntreprise.text.trim(),
        'p_shop_name': _nomBoutique.text.trim(),
        'p_phone': telephone.isEmpty ? null : telephone,
      });
      widget.quandCree();
    } catch (e) {
      // L'entreprise existe déjà (par exemple après un double clic) : on affiche l'accueil.
      if (e is PostgrestException && e.message.contains('déjà une entreprise')) {
        widget.quandCree();
        return;
      }
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  String? _obligatoire(String? v, String quoi) =>
      (v == null || v.trim().isEmpty) ? 'Indiquez $quoi' : null;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titre: 'Bienvenue sur Nacréa',
      sousTitre: 'Présentez-nous votre entreprise et votre première boutique.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nomPatronne,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Votre nom',
                hintText: 'Awa Mensah',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => _obligatoire(v, 'votre nom'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomEntreprise,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nom de votre entreprise',
                hintText: 'Beauté d\'Awa',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (v) => _obligatoire(v, 'le nom de l\'entreprise'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomBoutique,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nom de la première boutique',
                hintText: 'Boutique du centre-ville',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              validator: (v) => _obligatoire(v, 'le nom de la boutique'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              onFieldSubmitted: (_) => _creer(),
              decoration: const InputDecoration(
                labelText: 'Téléphone (facultatif)',
                hintText: '+228 90 00 00 00',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 24),
            if (_erreur != null) MessageErreur(_erreur!),
            FilledButton(
              onPressed: _chargement ? null : _creer,
              child: _chargement
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Créer ma boutique'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }
}

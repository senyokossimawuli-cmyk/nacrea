import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/equipe_repo.dart';
import '../services/erreurs.dart';
import '../widgets/auth_layout.dart';
import '../widgets/deconnexion.dart';

/// Première connexion : la patronne crée son entreprise et sa première boutique,
/// ou une employée rejoint sa boutique avec le code reçu de la patronne.
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
  final _code = TextEditingController();
  bool _employee = false;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _nomPatronne.dispose();
    _nomEntreprise.dispose();
    _nomBoutique.dispose();
    _telephone.dispose();
    _code.dispose();
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

  Future<void> _rejoindre() async {
    if (_chargement) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await EquipeRepo.rejoindre(_code.text);
      widget.quandCree();
    } catch (e) {
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
      sousTitre: _employee
          ? 'Entrez le code que votre patronne vous a donné.'
          : 'Présentez-nous votre entreprise et votre première boutique.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.diamond_outlined), label: Text('Je suis la patronne')),
                ButtonSegment(value: true, icon: Icon(Icons.badge_outlined), label: Text('Je suis employée')),
              ],
              selected: {_employee},
              showSelectedIcon: false,
              onSelectionChanged: _chargement
                  ? null
                  : (choix) => setState(() {
                        _employee = choix.first;
                        _erreur = null;
                      }),
            ),
            const SizedBox(height: 24),
            if (_employee) ..._champsEmployee() else ..._champsPatronne(),
            const SizedBox(height: 24),
            if (_erreur != null) MessageErreur(_erreur!),
            FilledButton(
              onPressed: _chargement ? null : (_employee ? _rejoindre : _creer),
              child: _chargement
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_employee ? 'Rejoindre ma boutique' : 'Créer ma boutique'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => deconnexion(context),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _champsEmployee() => [
        TextFormField(
          key: const ValueKey('code'),
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w700),
          onFieldSubmitted: (_) => _rejoindre(),
          decoration: const InputDecoration(
            labelText: 'Code d\'invitation',
            hintText: 'AB3K7P',
            counterText: '',
          ),
          validator: (v) => (v == null || v.trim().length != 6) ? 'Le code contient 6 caractères' : null,
        ),
        const SizedBox(height: 8),
        const Text(
          'Pas de code ? Demandez à la patronne de vous inviter depuis le menu « Équipe ».',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ];

  List<Widget> _champsPatronne() => [
        TextFormField(
          key: const ValueKey('nomPatronne'),
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
      ];
}

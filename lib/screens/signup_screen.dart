import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/auth_layout.dart';
import 'code_email_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  bool _masque = true;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _creerCompte() async {
    if (_chargement) return; // évite un double clic
    if (!_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final reponse = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _motDePasse.text,
      );
      if (!mounted) return;
      if (reponse.session != null) {
        // Connectée directement : on revient à l'écran principal,
        // qui affichera la création de la boutique.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        // Confirmation par e-mail activée : on demande le code reçu.
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => CodeEmailScreen(email: _email.text.trim(), mode: ModeCode.inscription),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titre: 'Créer mon compte',
      sousTitre: 'Quelques secondes pour démarrer avec Nacréa.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Entrez une adresse e-mail valide' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motDePasse,
              obscureText: _masque,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                helperText: '8 caractères minimum',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _masque ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                  icon: Icon(_masque ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _masque = !_masque),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Choisissez au moins 8 caractères' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmation,
              obscureText: _masque,
              onFieldSubmitted: (_) => _creerCompte(),
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (v) =>
                  v != _motDePasse.text ? 'Les deux mots de passe sont différents' : null,
            ),
            const SizedBox(height: 24),
            if (_erreur != null) MessageErreur(_erreur!),
            FilledButton(
              onPressed: _chargement ? null : _creerCompte,
              child: _chargement
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Créer mon compte'),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Déjà un compte ?', style: TextStyle(color: NacreaColors.gris)),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Se connecter'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

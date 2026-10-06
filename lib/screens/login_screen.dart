import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../theme/nacrea_theme.dart';
import '../widgets/auth_layout.dart';
import 'code_email_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  bool _masque = true;
  bool _chargement = false;
  String? _erreur;
  bool _nonConfirme = false;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _seConnecter() async {
    if (_chargement) return; // évite un double clic
    if (!_form.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
      _nonConfirme = false;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _motDePasse.text,
      );
      // La redirection vers l'accueil se fait automatiquement.
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = messageErreur(e);
          _nonConfirme = e is AuthException && e.message.toLowerCase().contains('not confirmed');
        });
      }
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// E-mail pas encore confirmé : on renvoie un code et on ouvre l'écran de saisie.
  Future<void> _confirmer() async {
    final email = _email.text.trim();
    try {
      await Supabase.instance.client.auth.resend(type: OtpType.signup, email: email);
    } catch (_) {
      // Code peut-être déjà envoyé : on ouvre quand même l'écran.
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CodeEmailScreen(email: email, mode: ModeCode.inscription),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titre: 'Bon retour',
      sousTitre: 'Connectez-vous pour ouvrir votre boutique.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
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
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _seConnecter(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _masque ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                  icon: Icon(_masque ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _masque = !_masque),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Entrez votre mot de passe' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => MotDePasseOublieScreen(email: _email.text.trim()),
                )),
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            const SizedBox(height: 12),
            if (_erreur != null) MessageErreur(_erreur!),
            if (_nonConfirme)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton(
                  onPressed: _confirmer,
                  child: const Text('Confirmer mon e-mail avec un code'),
                ),
              ),
            FilledButton(
              onPressed: _chargement ? null : _seConnecter,
              child: _chargement
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Se connecter'),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Pas encore de compte ?', style: TextStyle(color: NacreaColors.gris)),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  ),
                  child: const Text('Créer mon compte'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

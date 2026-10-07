import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/erreurs.dart';
import '../widgets/auth_layout.dart';

GoTrueClient get _auth => Supabase.instance.client.auth;

enum ModeCode { inscription, motDePasse }

/// Saisie du code reçu par e-mail (6 à 8 chiffres selon le réglage Supabase) :
/// confirmation de l'inscription, ou mot de passe oublié.
/// Un code marche pareil sur PC et sur téléphone, sans lien à ouvrir.
class CodeEmailScreen extends StatefulWidget {
  const CodeEmailScreen({super.key, required this.email, required this.mode});
  final String email;
  final ModeCode mode;

  @override
  State<CodeEmailScreen> createState() => _CodeEmailScreenState();
}

class _CodeEmailScreenState extends State<CodeEmailScreen> {
  final _code = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  bool _codeValide = false; // mot de passe oublié : étape 2
  bool _masque = true;
  bool _chargement = false;
  String? _erreur;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<void> Function() action) async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _erreur = _message(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  String _message(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains('expired') || m.contains('invalid') || m.contains('otp')) {
      return 'Code incorrect ou expiré. Vérifiez les chiffres, ou demandez un nouveau code.';
    }
    return messageErreur(e);
  }

  Future<void> _verifier() => _faire(() async {
        final code = _code.text.trim();
        if (code.length < 6) throw Exception('Entrez le code reçu par e-mail.');
        await _auth.verifyOTP(
          email: widget.email,
          token: code,
          type: widget.mode == ModeCode.inscription ? OtpType.signup : OtpType.recovery,
        );
        if (!mounted) return;
        if (widget.mode == ModeCode.inscription) {
          // Connectée : l'écran principal prend le relais (création de la boutique).
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          setState(() => _codeValide = true);
        }
      });

  Future<void> _renvoyer() => _faire(() async {
        if (widget.mode == ModeCode.inscription) {
          await _auth.resend(type: OtpType.signup, email: widget.email);
        } else {
          await _auth.resetPasswordForEmail(widget.email);
        }
        if (mounted) setState(() => _info = 'Nouveau code envoyé à ${widget.email}.');
      });

  Future<void> _changerMotDePasse() => _faire(() async {
        if (_motDePasse.text.length < 8) throw Exception('Choisissez au moins 8 caractères.');
        if (_motDePasse.text != _confirmation.text) throw Exception('Les deux mots de passe sont différents.');
        await _auth.updateUser(UserAttributes(password: _motDePasse.text));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Mot de passe changé. Vous êtes connectée.')));
        Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Widget _bouton(String texte, VoidCallback action) => FilledButton(
        onPressed: _chargement ? null : action,
        child: _chargement
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(texte),
      );

  @override
  Widget build(BuildContext context) {
    if (_codeValide) {
      return AuthLayout(
        titre: 'Nouveau mot de passe',
        sousTitre: 'Choisissez votre nouveau mot de passe.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _motDePasse,
              obscureText: _masque,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: '8 caractères minimum',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_masque ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _masque = !_masque),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmation,
              obscureText: _masque,
              onSubmitted: (_) => _changerMotDePasse(),
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 24),
            if (_erreur != null) MessageErreur(_erreur!),
            _bouton('Enregistrer', _changerMotDePasse),
          ],
        ),
      );
    }

    return AuthLayout(
      titre: widget.mode == ModeCode.inscription ? 'Confirmez votre e-mail' : 'Mot de passe oublié',
      sousTitre: 'Nous avons envoyé un code à ${widget.email}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 10,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.w700),
            onSubmitted: (_) => _verifier(),
            decoration: const InputDecoration(labelText: 'Tapez ici le code reçu par e-mail', counterText: ''),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pensez à regarder dans les « Spam » ou « Courrier indésirable ».',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          if (_erreur != null) MessageErreur(_erreur!),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_info!, textAlign: TextAlign.center),
            ),
          _bouton('Valider', _verifier),
          const SizedBox(height: 12),
          TextButton(onPressed: _chargement ? null : _renvoyer, child: const Text('Renvoyer un code')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        ],
      ),
    );
  }
}

/// Mot de passe oublié : on demande l'e-mail, puis on envoie un code.
class MotDePasseOublieScreen extends StatefulWidget {
  const MotDePasseOublieScreen({super.key, this.email});
  final String? email;

  @override
  State<MotDePasseOublieScreen> createState() => _MotDePasseOublieScreenState();
}

class _MotDePasseOublieScreenState extends State<MotDePasseOublieScreen> {
  late final _email = TextEditingController(text: widget.email);
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _erreur = 'Entrez une adresse e-mail valide');
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await _auth.resetPasswordForEmail(email);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => CodeEmailScreen(email: email, mode: ModeCode.motDePasse),
      ));
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titre: 'Mot de passe oublié',
      sousTitre: 'Entrez votre e-mail : vous recevrez un code pour choisir un nouveau mot de passe.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _envoyer(),
            decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 24),
          if (_erreur != null) MessageErreur(_erreur!),
          FilledButton(
            onPressed: _chargement ? null : _envoyer,
            child: _chargement
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Recevoir un code'),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour')),
        ],
      ),
    );
  }
}

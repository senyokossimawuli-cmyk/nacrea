import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/abonnement.dart' show contacterNacrea;
import '../services/erreurs.dart';
import '../services/licence.dart';
import '../services/membre.dart';
import '../theme/nacrea_theme.dart';
import '../utils/format.dart';
import '../widgets/auth_layout.dart';
import '../widgets/deconnexion.dart';
import '../widgets/nacrea_logo.dart';

/// Vérifie la licence avant d'ouvrir YDS Beauty.
/// Licence valide → [enfant]. Sinon → saisie de la clé, ou explication.
class LicenceGate extends StatefulWidget {
  const LicenceGate({super.key, required this.membre, required this.enfant});
  final Membre membre;
  final Widget Function() enfant;

  @override
  State<LicenceGate> createState() => _LicenceGateState();
}

class _LicenceGateState extends State<LicenceGate> {
  late Future<EtatLicence> _etat = Licence.verifier();

  void _reverifier() => setState(() => _etat = Licence.verifier());
  void _nouvelEtat(EtatLicence e) => setState(() => _etat = Future.value(e));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EtatLicence>(
      future: _etat,
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
          return AuthLayout(
            titre: 'Vérification de la licence',
            sousTitre: 'YDS Beauty doit vérifier votre licence sur internet '
                '(au moins une fois tous les ${NacreaConfig.joursLicenceHorsLigne} jours).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MessageErreur(messageErreur(snap.error!)),
                FilledButton(onPressed: _reverifier, child: const Text('Réessayer')),
                const SizedBox(height: 12),
                TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
              ],
            ),
          );
        }
        final e = snap.data!;
        if (e.valide) return widget.enfant();
        return EcranLicence(
          etat: e,
          membre: widget.membre,
          quandReverifier: _reverifier,
          quandNouvelEtat: _nouvelEtat,
        );
      },
    );
  }
}

/// Écran affiché quand la licence n'est pas (ou plus) valable sur cet appareil.
class EcranLicence extends StatefulWidget {
  const EcranLicence({
    super.key,
    required this.etat,
    required this.membre,
    required this.quandReverifier,
    required this.quandNouvelEtat,
  });

  final EtatLicence etat;
  final Membre membre;
  final VoidCallback quandReverifier;
  final void Function(EtatLicence) quandNouvelEtat;

  @override
  State<EcranLicence> createState() => _EcranLicenceState();
}

class _EcranLicenceState extends State<EcranLicence> {
  final _cle = TextEditingController();
  bool _chargement = false;
  String? _erreur;

  EtatLicence get e => widget.etat;
  bool get _patronne => widget.membre.estPatronne;

  @override
  void dispose() {
    _cle.dispose();
    super.dispose();
  }

  Future<void> _faire(Future<EtatLicence> Function() action) async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final r = await action();
      if (!mounted) return;
      switch (r.etat) {
        case 'cle_incorrecte':
          setState(() => _erreur = 'Clé incorrecte. Vérifiez chaque caractère (elle commence par YDS-).');
        case 'cle_deja_utilisee':
          setState(() => _erreur = 'Cette clé est déjà utilisée par une autre entreprise. Contactez YDS Beauty.');
        default:
          widget.quandNouvelEtat(r);
      }
    } catch (err) {
      if (mounted) setState(() => _erreur = messageErreur(err));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _activer() {
    if (_cle.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 15) {
      setState(() => _erreur = 'Tapez la clé complète : YDS-XXXX-XXXX-XXXX');
      return;
    }
    _faire(() => Licence.activer(_cle.text));
  }

  Future<void> _remplacer(AppareilLicence a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Remplacer « ${a.libelle} » ?'),
        content: const Text(
          'Cet ancien appareil ne pourra plus ouvrir YDS Beauty, et celui-ci prendra sa place.\n\n'
          'Vous pourrez refaire un remplacement dans 30 jours. Vos données ne sont pas touchées.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remplacer')),
        ],
      ),
    );
    if (ok == true) await _faire(() => Licence.remplacer(a.id));
  }

  void _contacter(String sujet) => contacterNacrea(
        context,
        'Bonjour YDS Beauty, $sujet (entreprise « ${widget.membre.nomCompte} »'
        '${e.cle == null ? '' : ', licence ${e.cle}'}).',
      );

  Widget _bouton(String texte, VoidCallback action) => FilledButton(
        onPressed: _chargement ? null : action,
        child: _chargement
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(texte),
      );

  List<Widget> _basDePage() => [
        const SizedBox(height: 12),
        TextButton(onPressed: _chargement ? null : widget.quandReverifier, child: const Text('Vérifier à nouveau')),
        TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
      ];

  @override
  Widget build(BuildContext context) {
    return switch (e.etat) {
      'desactivee' => _desactivee(),
      'limite' => _limite(),
      _ => _aucune(),
    };
  }

  // ---------- Pas encore de licence ----------
  Widget _aucune() {
    if (!_patronne) {
      return AuthLayout(
        titre: 'YDS Beauty n\'est pas encore activé',
        sousTitre: 'La patronne doit d\'abord entrer la clé de licence sur son appareil. '
            'Ensuite, appuyez sur « Vérifier à nouveau ».',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_erreur != null) MessageErreur(_erreur!),
          _bouton('Vérifier à nouveau', widget.quandReverifier),
          TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
        ]),
      );
    }
    return AuthLayout(
      titre: 'Activez YDS Beauty',
      sousTitre: 'Entrez la clé de licence que YDS Beauty vous a envoyée. Vous ne la taperez qu\'une seule fois.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _cle,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(24),
              TextInputFormatter.withFunction((ancien, nouveau) => nouveau.copyWith(text: nouveau.text.toUpperCase())),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700),
            onSubmitted: (_) => _activer(),
            decoration: const InputDecoration(
              labelText: 'Clé de licence',
              hintText: 'YDS-XXXX-XXXX-XXXX',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (_erreur != null) MessageErreur(_erreur!),
          _bouton('Activer', _activer),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _contacter('je souhaite obtenir une clé de licence'),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Je n\'ai pas de clé : contacter YDS Beauty'),
          ),
          TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
        ],
      ),
    );
  }

  // ---------- Licence désactivée ----------
  Widget _desactivee() {
    return AuthLayout(
      titre: 'Licence suspendue',
      sousTitre: 'La licence${e.cle == null ? '' : ' ${e.cle}'} de votre entreprise est désactivée. '
          'Vos données sont en sécurité. '
          '${_patronne ? 'Contactez YDS Beauty pour la réactiver.' : 'Prévenez la patronne.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_erreur != null) MessageErreur(_erreur!),
          if (_patronne)
            FilledButton.icon(
              onPressed: () => _contacter('ma licence est désactivée, je souhaite la réactiver'),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Contacter YDS Beauty'),
            ),
          ..._basDePage(),
        ],
      ),
    );
  }

  // ---------- Trop d'appareils ----------
  Widget _limite() {
    final pc = e.type == 'pc';
    final occupes = e.appareils.where((a) => a.type == e.type).toList();
    final nature = pc ? 'ordinateur' : 'téléphone';
    return AuthLayout(
      titre: 'Appareil non autorisé',
      sousTitre: 'Votre licence permet ${e.resume}. '
          'La place ${pc ? 'd\'ordinateur' : 'de téléphone'} est déjà prise par :',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in occupes)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(a.estPc ? Icons.computer : Icons.smartphone, color: NacreaColors.prune),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.libelle, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            [
                              if (a.email != null) a.email!,
                              if (a.vuLe != null) 'utilisé le ${dateCourte(a.vuLe!)}',
                            ].join(' · '),
                            style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (_patronne && e.peutRemplacer)
                      TextButton(onPressed: _chargement ? null : () => _remplacer(a), child: const Text('Remplacer')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_erreur != null) MessageErreur(_erreur!),
          if (!_patronne)
            Text(
              'Demandez à la patronne de remplacer un appareil, ou d\'ajouter un $nature à la licence.',
              style: const TextStyle(color: NacreaColors.gris),
            )
          else ...[
            Text(
              e.peutRemplacer
                  ? 'Nouveau $nature ? Appuyez sur « Remplacer » : l\'ancien ne pourra plus ouvrir YDS Beauty. '
                      'Pour utiliser plus d\'appareils, contactez YDS Beauty.'
                  : 'Vous avez déjà remplacé un appareil récemment'
                      '${e.remplacementLe == null ? '' : ' : prochain remplacement possible le ${dateCourte(e.remplacementLe!)}'}. '
                      'Contactez YDS Beauty pour libérer une place ou ajouter un $nature.',
              style: const TextStyle(color: NacreaColors.gris, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _contacter('je souhaite utiliser YDS Beauty sur un $nature de plus'),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Contacter YDS Beauty'),
            ),
          ],
          ..._basDePage(),
        ],
      ),
    );
  }
}

/// Carte « Ma licence » (page Équipe, pour la patronne).
class CarteMaLicence extends StatefulWidget {
  const CarteMaLicence({super.key});

  @override
  State<CarteMaLicence> createState() => _CarteMaLicenceState();
}

class _CarteMaLicenceState extends State<CarteMaLicence> {
  final Future<EtatLicence> _etat = Licence.verifier();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EtatLicence>(
      future: _etat,
      builder: (context, snap) {
        final e = snap.data;
        if (e == null || e.cle == null || e.admin) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: NacreaColors.prune),
                    const SizedBox(width: 10),
                    const Text('Licence YDS Beauty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SelectableText(e.cle!,
                          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  e.horsLigne
                      ? 'Vérifiée sans internet. Les appareils s\'afficheront une fois connecté.'
                      : 'Valable sur ${e.resume}.',
                  style: const TextStyle(color: NacreaColors.gris),
                ),
                for (final a in e.appareils)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.estPc ? Icons.computer : Icons.smartphone),
                    title: Text('${a.libelle}${a.ceAppareil ? ' (cet appareil)' : ''}'),
                    subtitle: Text([
                      if (a.email != null) a.email!,
                      if (a.vuLe != null) 'utilisé le ${dateCourte(a.vuLe!)}',
                    ].join(' · ')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

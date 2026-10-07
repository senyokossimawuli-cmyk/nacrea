import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/equipe_repo.dart';
import '../../data/produits_repo.dart';
import '../../services/erreurs.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../licence_screen.dart' show CarteMaLicence;

/// Page Équipe (patronne) : employées, boutique de chacune, invitations.
class EquipePage extends StatefulWidget {
  const EquipePage({super.key, required this.membre, required this.boutiques});
  final Membre membre;
  final List<Boutique> boutiques;

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage> {
  late final _repo = EquipeRepo(compteId: widget.membre.compteId);
  late final _membres = _repo.surveillerMembres();
  late Future<List<Invitation>> _invitations = _repo.invitationsEnCours();

  void _rechargerInvitations() => setState(() => _invitations = _repo.invitationsEnCours());

  void _message(String texte) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

  String _texteInvitation(String nom, String code) =>
      'Bonjour $nom, voici ton code pour rejoindre ${widget.membre.nomCompte} sur Nacréa : $code\n\n'
      'Ouvre Nacréa, crée ton compte, choisis « Je suis employée » et tape ce code. '
      'Il est valable 7 jours.';

  Future<void> _partager(String nom, String code) async {
    final lien = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_texteInvitation(nom, code))}');
    final ok = await launchUrl(lien, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _message('Impossible d\'ouvrir WhatsApp.');
  }

  Future<void> _inviter() async {
    final resultat = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _InvitationDialog(repo: _repo, boutiques: widget.boutiques),
    );
    if (resultat == null || !mounted) return;
    final (nom, code) = resultat;
    _rechargerInvitations();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Code pour $nom'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                style: NacreaTheme.titre(size: 56, color: NacreaColors.prune).copyWith(letterSpacing: 8),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sur le PC de la boutique, l\'employée crée son compte, choisit « Je suis employée » '
                'et tape ce code. Il est valable 7 jours et ne sert qu\'une fois.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NacreaColors.gris, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _partager(nom, code),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Envoyer par WhatsApp'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _action(MembreEquipe m, String action) async {
    try {
      switch (action) {
        case 'desactiver':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              title: Text('Désactiver ${m.nom} ?'),
              content: const Text(
                'Elle ne pourra plus se connecter à Nacréa. Ses ventes passées restent dans l\'historique. '
                'Vous pourrez la réactiver à tout moment.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: NacreaColors.erreur),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Désactiver'),
                ),
              ],
            ),
          );
          if (ok == true) await _repo.activer(m, false);
        case 'activer':
          await _repo.activer(m, true);
        case 'couts':
          await _repo.autoriserCouts(m, !m.peutVoirCouts);
        case 'boutique':
          if (!mounted) return;
          final id = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              backgroundColor: Colors.white,
              title: Text('Boutique de ${m.nom}'),
              children: [
                for (final b in widget.boutiques)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(b.id),
                    child: Row(
                      children: [
                        Icon(b.id == m.boutiqueId ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: NacreaColors.prune),
                        const SizedBox(width: 12),
                        Text(b.nom),
                      ],
                    ),
                  ),
              ],
            ),
          );
          if (id != null && id != m.boutiqueId) await _repo.changerBoutique(m, id);
      }
    } catch (e) {
      if (mounted) _message(messageErreur(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Équipe', style: NacreaTheme.titre(size: 36)),
                const Text('Vos employées et la boutique de chacune.',
                    style: TextStyle(color: NacreaColors.gris)),
              ],
            ),
            SizedBox(
              width: 260,
              child: FilledButton.icon(
                onPressed: _inviter,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Inviter une employée'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const CarteMaLicence(),
        const SizedBox(height: 12),
        StreamBuilder<List<MembreEquipe>>(
          stream: _membres,
          builder: (context, snap) {
            final membres = snap.data ?? const <MembreEquipe>[];
            return Column(
              children: [
                for (final m in membres)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CarteMembre(
                      membre: m,
                      plusieursBoutiques: widget.boutiques.length > 1,
                      quandAction: (a) => _action(m, a),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text('Invitations en attente', style: NacreaTheme.titre(size: 26)),
        const SizedBox(height: 12),
        FutureBuilder<List<Invitation>>(
          future: _invitations,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
              );
            }
            if (snap.hasError) {
              return Row(
                children: [
                  const Expanded(
                    child: Text('Connexion internet nécessaire pour voir les invitations.',
                        style: TextStyle(color: NacreaColors.gris)),
                  ),
                  TextButton(onPressed: _rechargerInvitations, child: const Text('Réessayer')),
                ],
              );
            }
            final invitations = snap.data!;
            if (invitations.isEmpty) {
              return const Text('Aucune invitation en attente.', style: TextStyle(color: NacreaColors.gris));
            }
            return Column(
              children: [
                for (final i in invitations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Text(i.code,
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 3,
                                    color: NacreaColors.prune)),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(i.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('${i.boutiqueNom} · valable jusqu\'au ${dateCourte(i.expireLe)}',
                                      style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Envoyer par WhatsApp',
                              onPressed: () => _partager(i.nom, i.code),
                              icon: const Icon(Icons.chat_outlined, color: NacreaColors.prune),
                            ),
                            IconButton(
                              tooltip: 'Supprimer l\'invitation',
                              onPressed: () async {
                                try {
                                  await _repo.supprimerInvitation(i.id);
                                  _rechargerInvitations();
                                } catch (e) {
                                  if (mounted) _message(messageErreur(e));
                                }
                              },
                              icon: const Icon(Icons.delete_outline, color: NacreaColors.gris),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CarteMembre extends StatelessWidget {
  const _CarteMembre({required this.membre, required this.plusieursBoutiques, required this.quandAction});
  final MembreEquipe membre;
  final bool plusieursBoutiques;
  final ValueChanged<String> quandAction;

  @override
  Widget build(BuildContext context) {
    final m = membre;
    final initiales = m.nom
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();
    return Opacity(
      opacity: m.actif ? 1 : 0.55,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: m.estPatronne ? NacreaColors.prune : NacreaColors.nude,
                foregroundColor: m.estPatronne ? Colors.white : NacreaColors.prune,
                child: Text(initiales.isEmpty ? '?' : initiales),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        m.estPatronne ? 'Patronne · toutes les boutiques' : 'Employée · ${m.boutiqueNom ?? '—'}',
                        if (!m.estPatronne && m.peutVoirCouts) 'voit les prix d\'achat',
                        if (!m.actif) 'désactivée',
                      ].join(' · '),
                      style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (!m.estPatronne)
                PopupMenuButton<String>(
                  tooltip: 'Gérer',
                  onSelected: quandAction,
                  itemBuilder: (_) => [
                    if (plusieursBoutiques)
                      const PopupMenuItem(value: 'boutique', child: Text('Changer de boutique')),
                    PopupMenuItem(
                      value: 'couts',
                      child: Text(m.peutVoirCouts
                          ? 'Cacher les prix d\'achat'
                          : 'Montrer les prix d\'achat'),
                    ),
                    m.actif
                        ? const PopupMenuItem(value: 'desactiver', child: Text('Désactiver'))
                        : const PopupMenuItem(value: 'activer', child: Text('Réactiver')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({required this.repo, required this.boutiques});
  final EquipeRepo repo;
  final List<Boutique> boutiques;

  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  final _nom = TextEditingController();
  late String _boutiqueId = widget.boutiques.first.id;
  bool _couts = false;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (_chargement) return;
    if (_nom.text.trim().isEmpty) {
      setState(() => _erreur = 'Indiquez le nom de l\'employée.');
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final code = await widget.repo.inviter(boutiqueId: _boutiqueId, nom: _nom.text, voitCouts: _couts);
      if (mounted) Navigator.of(context).pop((_nom.text.trim(), code));
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Inviter une employée'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nom,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom de l\'employée', hintText: 'Kafui'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _boutiqueId,
              decoration: const InputDecoration(labelText: 'Boutique'),
              items: [
                for (final b in widget.boutiques) DropdownMenuItem(value: b.id, child: Text(b.nom)),
              ],
              onChanged: (v) => setState(() => _boutiqueId = v ?? _boutiqueId),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _couts,
              activeThumbColor: NacreaColors.prune,
              onChanged: (v) => setState(() => _couts = v),
              title: const Text('Peut voir les prix d\'achat et les marges'),
            ),
            if (_erreur != null)
              Text(_erreur!, style: const TextStyle(color: NacreaColors.erreur)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: _chargement ? null : _creer,
          child: const Text('Créer le code'),
        ),
      ],
    );
  }
}

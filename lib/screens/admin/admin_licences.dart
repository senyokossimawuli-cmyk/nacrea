import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/admin_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../clientes/cliente_dialogs.dart' show ouvrirWhatsApp;

final _repo = AdminRepo();

String _appareils(int pc, int tel) => [
      if (pc > 0) '$pc ordinateur${pc > 1 ? 's' : ''}',
      if (tel > 0) '$tel téléphone${tel > 1 ? 's' : ''}',
    ].join(' et ');

String _texteLicence(String cle, {String? patronne, required int pc, required int tel, bool dejaLiee = false}) =>
    'Bonjour${patronne == null || patronne.isEmpty ? '' : ' $patronne'}, voici votre clé de licence YDS Beauty : $cle\n'
    '${dejaLiee ? 'Elle est déjà activée sur votre entreprise, vous n\'avez rien à taper.' : 'Ouvrez YDS Beauty, connectez-vous, puis tapez cette clé quand elle vous est demandée.'} '
    'Elle fonctionne sur ${_appareils(pc, tel)}. Gardez ce message.';

Future<void> _envoyerWhatsApp(BuildContext context, String? telephone, String texte) async {
  if (telephone != null && telephone.trim().isNotEmpty) {
    await ouvrirWhatsApp(context, telephone, texte);
    return;
  }
  final ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texte)}'),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')));
  }
}

/// Montre une clé avec « Copier » et « Envoyer par WhatsApp ».
Future<void> montrerCle(BuildContext context, String cle,
    {String? telephone, String? patronne, int pc = 1, int tel = 1, bool dejaLiee = false, String titre = 'Clé de licence'}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text(titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(color: NacreaColors.nude, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(cle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 12),
          Text(
            dejaLiee
                ? 'Déjà liée à cette cliente : elle n\'a rien à taper. Valable sur ${_appareils(pc, tel)}.'
                : 'À envoyer à la cliente. Elle la tapera une seule fois. Valable sur ${_appareils(pc, tel)}.',
            style: const TextStyle(color: NacreaColors.gris),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: cle));
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Clé copiée.')));
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copier'),
        ),
        TextButton.icon(
          onPressed: () => _envoyerWhatsApp(
              ctx, telephone, _texteLicence(cle, patronne: patronne, pc: pc, tel: tel, dejaLiee: dejaLiee)),
          icon: const Icon(Icons.chat_outlined, size: 18),
          label: const Text('WhatsApp'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
      ],
    ),
  );
}

/// Formulaire : note + nombre d'appareils. Renvoie (note, pc, téléphones).
Future<(String?, int, int)?> _formulaireLicence(BuildContext context,
    {required String titre, String? note, int pc = 1, int tel = 1, bool avecNote = true}) {
  final champNote = TextEditingController(text: note);
  var nbPc = pc, nbTel = tel;
  Widget compteur(String libelle, IconData icone, int valeur, void Function(int) changer) => Row(
        children: [
          Icon(icone, color: NacreaColors.prune),
          const SizedBox(width: 10),
          Expanded(child: Text(libelle)),
          IconButton(
            onPressed: valeur > 0 ? () => changer(valeur - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(width: 28, child: Text('$valeur', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          IconButton(
            onPressed: valeur < 50 ? () => changer(valeur + 1) : null,
            icon: const Icon(Icons.add_circle_outline, color: NacreaColors.prune),
          ),
        ],
      );
  return showDialog<(String?, int, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(titre),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (avecNote) ...[
                TextField(
                  controller: champNote,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Pour qui ? (nom, téléphone…)',
                    helperText: 'Visible par vous seul',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              compteur('Ordinateurs', Icons.computer, nbPc, (v) => setD(() => nbPc = v)),
              compteur('Téléphones', Icons.smartphone, nbTel, (v) => setD(() => nbTel = v)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: nbPc + nbTel == 0 ? null : () => Navigator.pop(ctx, (champNote.text.trim(), nbPc, nbTel)),
            child: const Text('Valider'),
          ),
        ],
      ),
    ),
  );
}

/// Crée une licence (libre, ou directement liée à une cliente) et montre la clé.
Future<bool> nouvelleLicence(BuildContext context, {String? compteId, String? note, String? telephone, String? patronne}) async {
  final choix = await _formulaireLicence(
    context,
    titre: compteId == null ? 'Nouvelle licence' : 'Licence pour cette cliente',
    note: note,
  );
  if (choix == null || !context.mounted) return false;
  final (texte, pc, tel) = choix;
  try {
    final cle = await _repo.creerLicence(note: texte, maxPc: pc, maxTelephones: tel, compteId: compteId);
    if (context.mounted) {
      await montrerCle(context, cle,
          telephone: telephone, patronne: patronne, pc: pc, tel: tel, dejaLiee: compteId != null, titre: 'Licence créée');
    }
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
    return false;
  }
}

// =====================================================================
// Carte d'une licence
// =====================================================================

class CarteLicenceAdmin extends StatelessWidget {
  const CarteLicenceAdmin({super.key, required this.licence, required this.quandChange, this.telephone, this.patronne});
  final LicenceAdmin licence;
  final VoidCallback quandChange;
  final String? telephone, patronne;

  Future<void> _action(BuildContext context, Future<void> Function() faire, String message) async {
    try {
      await faire();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      quandChange();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageErreur(e))));
    }
  }

  Future<bool> _confirmer(BuildContext context, String titre, String texte, String bouton) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(titre),
          content: Text(texte),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(bouton)),
          ],
        ),
      ) ==
      true;

  Future<void> _menu(BuildContext context, String choix) async {
    final l = licence;
    switch (choix) {
      case 'montrer':
        await montrerCle(context, l.cle,
            telephone: telephone, patronne: patronne, pc: l.maxPc, tel: l.maxTelephones, dejaLiee: !l.libre);
      case 'modifier':
        final r = await _formulaireLicence(context,
            titre: 'Modifier la licence', note: l.note, pc: l.maxPc, tel: l.maxTelephones);
        if (r == null || !context.mounted) return;
        final (note, pc, tel) = r;
        await _action(context, () => _repo.modifierLicence(l.id, note: note, maxPc: pc, maxTelephones: tel),
            'Licence modifiée.');
      case 'activer':
        if (l.active &&
            !await _confirmer(
                context,
                'Désactiver ${l.cle} ?',
                'YDS Beauty ne s\'ouvrira plus${l.compte == null ? '' : ' chez « ${l.compte} »'} '
                    'dès sa prochaine connexion à internet (au plus tard dans 30 jours sans internet). '
                    'Ses données sont gardées. Vous pourrez la réactiver.',
                'Désactiver')) {
          return;
        }
        if (!context.mounted) return;
        await _action(context, () => _repo.activerLicence(l.id, !l.active),
            l.active ? 'Licence désactivée.' : 'Licence réactivée.');
      case 'supprimer':
        if (!await _confirmer(
            context,
            'Supprimer ${l.cle} ?',
            l.libre
                ? 'Cette clé ne pourra plus être utilisée.'
                : '« ${l.compte} » devra entrer une nouvelle clé pour ouvrir YDS Beauty. Ses données sont gardées.',
            'Supprimer')) {
          return;
        }
        if (!context.mounted) return;
        await _action(context, () => _repo.supprimerLicence(l.id), 'Licence supprimée.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = licence;
    final (texteStatut, couleur, fond) = !l.active
        ? ('Désactivée', NacreaColors.erreur, const Color(0xFFFCEBEB))
        : l.libre
            ? ('Pas encore utilisée', NacreaColors.orTexte, const Color(0xFFF7EEDB))
            : ('Active', NacreaColors.succes, const Color(0xFFE5F3EA));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined, color: NacreaColors.prune),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(l.cle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
                  child: Text(texteStatut, style: TextStyle(color: couleur, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                PopupMenuButton<String>(
                  onSelected: (c) => _menu(context, c),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'montrer', child: Text('Copier / envoyer la clé')),
                    const PopupMenuItem(value: 'modifier', child: Text('Nombre d\'appareils, note')),
                    PopupMenuItem(value: 'activer', child: Text(l.active ? 'Désactiver' : 'Réactiver')),
                    const PopupMenuItem(
                      value: 'supprimer',
                      child: Text('Supprimer', style: TextStyle(color: NacreaColors.erreur)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (l.compte != null) l.compte!,
                if (l.note != null) l.note!,
                'Ordinateurs ${l.nbPc}/${l.maxPc} · Téléphones ${l.nbTelephones}/${l.maxTelephones}',
                if (l.creeLe != null) 'créée le ${dateCourte(l.creeLe!)}',
              ].join(' · '),
              style: const TextStyle(color: NacreaColors.gris),
            ),
            for (final a in l.appareils)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(a.estPc ? Icons.computer : Icons.smartphone),
                title: Text(a.libelle),
                subtitle: Text([
                  if (a.email != null) a.email!,
                  if (a.vuLe != null) 'dernière utilisation le ${dateCourte(a.vuLe!)}',
                ].join(' · ')),
                trailing: TextButton(
                  onPressed: () async {
                    if (!await _confirmer(
                        context,
                        'Libérer « ${a.libelle} » ?',
                        'Cet appareil ne pourra plus ouvrir YDS Beauty, et sa place pourra être prise par un nouvel appareil.',
                        'Libérer')) {
                      return;
                    }
                    if (!context.mounted) return;
                    await _action(context, () => _repo.libererAppareil(a.id), 'Place libérée.');
                  },
                  child: const Text('Libérer'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Onglet « Licences » de l'espace admin
// =====================================================================

class OngletLicences extends StatefulWidget {
  const OngletLicences({super.key, required this.etroit});
  final bool etroit;

  @override
  State<OngletLicences> createState() => _OngletLicencesState();
}

class _OngletLicencesState extends State<OngletLicences> {
  late Future<List<LicenceAdmin>> _licences = _repo.licences();
  final _recherche = TextEditingController();

  void _recharger() => setState(() => _licences = _repo.licences());

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LicenceAdmin>>(
      future: _licences,
      builder: (context, snap) {
        final q = _recherche.text.trim().toLowerCase();
        final toutes = snap.data ?? const <LicenceAdmin>[];
        final visibles = toutes
            .where((l) =>
                q.isEmpty ||
                l.cle.toLowerCase().contains(q) ||
                (l.compte?.toLowerCase().contains(q) ?? false) ||
                (l.note?.toLowerCase().contains(q) ?? false))
            .toList();
        return RefreshIndicator(
          color: NacreaColors.prune,
          onRefresh: () async => _recharger(),
          child: ListView(
            padding: EdgeInsets.all(widget.etroit ? 16 : 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            '${toutes.length} licence${toutes.length > 1 ? 's' : ''} · '
                            '${toutes.where((l) => l.libre && l.active).length} pas encore utilisée'
                            '${toutes.where((l) => l.libre && l.active).length > 1 ? 's' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                            onPressed: () async {
                              if (await nouvelleLicence(context)) _recharger();
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Générer une licence'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Astuce : pour une cliente déjà inscrite, ouvrez sa fiche (onglet Clientes) '
                        'et créez sa licence là : elle sera activée directement, sans clé à taper.',
                        style: TextStyle(color: NacreaColors.gris, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _recherche,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            hintText: 'Chercher une clé, une cliente…', prefixIcon: Icon(Icons.search)),
                      ),
                      const SizedBox(height: 12),
                      if (snap.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                        )
                      else if (snap.hasError)
                        Column(children: [
                          Text(messageErreur(snap.error!), textAlign: TextAlign.center),
                          TextButton(onPressed: _recharger, child: const Text('Réessayer')),
                        ])
                      else if (visibles.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Aucune licence pour l\'instant.', textAlign: TextAlign.center),
                        )
                      else
                        for (final l in visibles)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: CarteLicenceAdmin(licence: l, quandChange: _recharger),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================================
// Licence dans la fiche d'une cliente
// =====================================================================

class LicenceDeLaCliente extends StatefulWidget {
  const LicenceDeLaCliente({super.key, required this.compteId, this.nomCompte, this.telephone, this.patronne});
  final String compteId;
  final String? nomCompte, telephone, patronne;

  @override
  State<LicenceDeLaCliente> createState() => _LicenceDeLaClienteState();
}

class _LicenceDeLaClienteState extends State<LicenceDeLaCliente> {
  late Future<List<LicenceAdmin>> _licence = _repo.licences(compteId: widget.compteId);

  void _recharger() => setState(() => _licence = _repo.licences(compteId: widget.compteId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LicenceAdmin>>(
      future: _licence,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        if (snap.hasError) {
          return Text(messageErreur(snap.error!), style: const TextStyle(color: NacreaColors.erreur));
        }
        final liste = snap.data!;
        if (liste.isNotEmpty) {
          return CarteLicenceAdmin(
            licence: liste.first,
            quandChange: _recharger,
            telephone: widget.telephone,
            patronne: widget.patronne,
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key_off_outlined, color: NacreaColors.orTexte),
                    SizedBox(width: 10),
                    Text('Pas encore de licence', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () async {
                    if (await nouvelleLicence(context,
                        compteId: widget.compteId,
                        note: widget.nomCompte,
                        telephone: widget.telephone,
                        patronne: widget.patronne)) {
                      _recharger();
                    }
                  },
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Créer sa licence'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

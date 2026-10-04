import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../data/admin_repo.dart';
import '../../services/erreurs.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import '../../widgets/auth_layout.dart';
import '../../widgets/carte_chiffre.dart';
import '../clientes/cliente_dialogs.dart' show ouvrirWhatsApp;

final _repo = AdminRepo();

const _jours = Duration(days: NacreaConfig.joursDeGrace);

(Color, Color) _couleursStatut(String s) => switch (s) {
      'active' => (NacreaColors.succes, const Color(0xFFE5F3EA)),
      'trial' => (NacreaColors.orTexte, const Color(0xFFF7EEDB)),
      _ => (NacreaColors.erreur, const Color(0xFFFCEBEB)),
    };

class _PastilleStatut extends StatelessWidget {
  const _PastilleStatut(this.statut);
  final String statut;

  @override
  Widget build(BuildContext context) {
    final (texte, fond) = _couleursStatut(statut);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(8)),
      child: Text(libellesStatut[statut] ?? statut,
          style: TextStyle(color: texte, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

String _ilYa(DateTime? d) {
  if (d == null) return 'aucune vente';
  final j = DateTime.now().difference(d).inDays;
  if (j <= 0) return 'aujourd\'hui';
  if (j == 1) return 'hier';
  return 'il y a $j jours';
}

/// Texte de relance WhatsApp adapté à la situation de la boutique.
String _texteRelance({required String? patronne, required String boutique, required String statut, DateTime? fin, required int prix}) {
  final bonjour = 'Bonjour${patronne == null || patronne.isEmpty ? '' : ' $patronne'}';
  final date = fin == null ? '' : dateCourte(fin);
  final texte = switch (statut) {
    'trial' => '$bonjour, votre essai gratuit de Nacréa pour « $boutique » se termine le $date. '
        'Pour continuer à vendre avec Nacréa : ${fcfa(prix)} par mois, payable par Mobile Money. Merci pour votre confiance !',
    'late' => '$bonjour, l\'abonnement Nacréa de « $boutique » est arrivé à échéance le $date. '
        'Merci de régler ${fcfa(prix)} pour éviter la mise en pause de la caisse'
        '${fin == null ? '' : ' le ${dateCourte(fin.add(_jours))}'}.',
    'suspended' => '$bonjour, la caisse Nacréa de « $boutique » est en pause car l\'abonnement n\'est pas réglé. '
        'Vos données sont en sécurité. Dès réception de ${fcfa(prix)}, nous la réactivons immédiatement.',
    _ => '$bonjour, votre abonnement Nacréa pour « $boutique » se termine le $date. '
        'Pensez à le renouveler (${fcfa(prix)} par mois) pour continuer sans interruption. Merci !',
  };
  return texte.replaceAll(' ', ' ');
}

// =====================================================================
// Écran principal
// =====================================================================

/// Espace administrateur : réservé à l'éditeur de Nacréa. Demande internet.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<(ApercuAdmin, List<ClienteNacrea>)> _donnees = _charger();
  final _recherche = TextEditingController();

  static Future<(ApercuAdmin, List<ClienteNacrea>)> _charger() async =>
      (await _repo.apercu(), await _repo.clientes());

  void _recharger() => setState(() => _donnees = _charger());

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _ouvrir(ClienteNacrea c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FicheAdmin(compteId: c.id)));
    _recharger();
  }

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return DefaultTabController(
      length: 3,
      child: FutureBuilder<(ApercuAdmin, List<ClienteNacrea>)>(
        future: _donnees,
        builder: (context, snap) {
          final aRelancer = snap.data?.$2.where((c) => c.aRelancer).toList() ?? const <ClienteNacrea>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                child: TabBar(
                  labelColor: NacreaColors.prune,
                  indicatorColor: NacreaColors.prune,
                  unselectedLabelColor: NacreaColors.gris,
                  tabs: [
                    const Tab(icon: Icon(Icons.insights_outlined), text: 'Vue d\'ensemble'),
                    const Tab(icon: Icon(Icons.storefront_outlined), text: 'Clientes'),
                    Tab(
                      icon: Badge(
                        isLabelVisible: aRelancer.isNotEmpty,
                        label: Text('${aRelancer.length}'),
                        child: const Icon(Icons.notifications_active_outlined),
                      ),
                      text: 'À relancer',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Builder(builder: (context) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${messageErreur(snap.error!)}\nL\'espace administrateur demande une connexion internet.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton(onPressed: _recharger, child: const Text('Réessayer')),
                          ],
                        ),
                      ),
                    );
                  }
                  final (apercu, clientes) = snap.data!;
                  return TabBarView(
                    children: [
                      _OngletApercu(apercu: apercu, etroit: etroit, quandActualiser: _recharger),
                      _OngletClientes(
                        clientes: clientes,
                        recherche: _recherche,
                        etroit: etroit,
                        quandOuvrir: _ouvrir,
                        quandChange: () => setState(() {}),
                      ),
                      _OngletRelances(clientes: aRelancer, etroit: etroit, quandOuvrir: _ouvrir),
                    ],
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _cadre(bool etroit, List<Widget> enfants, {Future<void> Function()? quandTirer}) {
  final liste = ListView(
    padding: EdgeInsets.all(etroit ? 16 : 24),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: enfants),
        ),
      ),
    ],
  );
  return quandTirer == null
      ? liste
      : RefreshIndicator(color: NacreaColors.prune, onRefresh: quandTirer, child: liste);
}

class _OngletApercu extends StatelessWidget {
  const _OngletApercu({required this.apercu, required this.etroit, required this.quandActualiser});
  final ApercuAdmin apercu;
  final bool etroit;
  final VoidCallback quandActualiser;

  @override
  Widget build(BuildContext context) {
    final a = apercu;
    return _cadre(etroit, quandTirer: () async => quandActualiser(), [
      Row(
        children: [
          Expanded(child: Text('Nacréa · Admin', style: NacreaTheme.titre(size: etroit ? 30 : 36))),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: quandActualiser,
            icon: const Icon(Icons.refresh, color: NacreaColors.prune),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          CarteChiffre(
            titre: 'Revenu mensuel',
            valeur: fcfa(a.revenuMensuel),
            sousTitre: 'boutiques payantes',
            couleur: NacreaColors.succes,
          ),
          CarteChiffre(titre: 'Encaissé ce mois', valeur: fcfa(a.encaisseMois)),
          CarteChiffre(titre: 'Clientes', valeur: '${a.comptes}', sousTitre: '${a.boutiques} boutiques'),
        ],
      ),
      const SizedBox(height: 20),
      Text('Boutiques par statut', style: NacreaTheme.titre(size: 22)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          CarteChiffre(titre: 'En essai', valeur: '${a.essai}',
              sousTitre: a.essaisFinProche > 0 ? '${a.essaisFinProche} finissent sous 3 jours' : null),
          CarteChiffre(titre: 'Payées', valeur: '${a.actives}', couleur: NacreaColors.succes),
          CarteChiffre(
            titre: 'En retard',
            valeur: '${a.enRetard}',
            couleur: a.enRetard > 0 ? NacreaColors.erreur : null,
          ),
          CarteChiffre(
            titre: 'Suspendues',
            valeur: '${a.suspendues}',
            couleur: a.suspendues > 0 ? NacreaColors.erreur : null,
          ),
        ],
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: NacreaColors.nude, borderRadius: BorderRadius.circular(14)),
        child: const Text(
          'Fonctionnement : une boutique en essai ou payée dont la date est passée devient « en retard ». '
          'Après ${NacreaConfig.joursDeGrace} jours de retard, elle est suspendue : sa caisse se met en pause, '
          'ses données restent consultables. Enregistrer un paiement la réactive aussitôt.',
          style: TextStyle(height: 1.5),
        ),
      ),
    ]);
  }
}

class _CarteCliente extends StatelessWidget {
  const _CarteCliente({required this.c, required this.quandTouche, this.avecRelance = false});
  final ClienteNacrea c;
  final VoidCallback quandTouche;
  final bool avecRelance;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: quandTouche,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(c.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        _PastilleStatut(c.statutPrincipal),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (c.patronne != null) c.patronne!,
                        '${c.nbBoutiques} boutique${c.nbBoutiques > 1 ? 's' : ''} · ${fcfa(c.mensuel)}/mois',
                      ].join(' · '),
                      style: const TextStyle(color: NacreaColors.gris),
                    ),
                    Text(
                      [
                        if (c.prochaineFin != null) 'Échéance : ${dateCourte(c.prochaineFin!)}',
                        'Dernière vente : ${_ilYa(c.derniereVente)}',
                      ].join(' · '),
                      style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (avecRelance)
                IconButton(
                  tooltip: 'Relancer par WhatsApp',
                  icon: const Icon(Icons.chat_outlined, color: NacreaColors.prune),
                  onPressed: () => ouvrirWhatsApp(
                    context,
                    c.telephone,
                    _texteRelance(
                      patronne: c.patronne,
                      boutique: c.nom,
                      statut: c.statutPrincipal,
                      fin: c.prochaineFin,
                      prix: c.mensuel,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, color: NacreaColors.gris),
            ],
          ),
        ),
      ),
    );
  }
}

class _OngletClientes extends StatelessWidget {
  const _OngletClientes({
    required this.clientes,
    required this.recherche,
    required this.etroit,
    required this.quandOuvrir,
    required this.quandChange,
  });
  final List<ClienteNacrea> clientes;
  final TextEditingController recherche;
  final bool etroit;
  final void Function(ClienteNacrea) quandOuvrir;
  final VoidCallback quandChange;

  @override
  Widget build(BuildContext context) {
    final q = recherche.text.trim().toLowerCase();
    final visibles = clientes
        .where((c) =>
            q.isEmpty ||
            c.nom.toLowerCase().contains(q) ||
            (c.patronne?.toLowerCase().contains(q) ?? false) ||
            (c.email?.toLowerCase().contains(q) ?? false) ||
            (c.telephone?.contains(q) ?? false))
        .toList()
      ..sort((a, b) => (b.creeLe ?? DateTime(2000)).compareTo(a.creeLe ?? DateTime(2000)));
    return _cadre(etroit, [
      TextField(
        controller: recherche,
        onChanged: (_) => quandChange(),
        decoration: const InputDecoration(
          hintText: 'Chercher une entreprise, une patronne, un e-mail…',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 8),
      Text('${visibles.length} cliente${visibles.length > 1 ? 's' : ''}, les plus récentes en premier',
          style: const TextStyle(color: NacreaColors.gris)),
      const SizedBox(height: 8),
      for (final c in visibles) _CarteCliente(c: c, quandTouche: () => quandOuvrir(c)),
    ]);
  }
}

class _OngletRelances extends StatelessWidget {
  const _OngletRelances({required this.clientes, required this.etroit, required this.quandOuvrir});
  final List<ClienteNacrea> clientes;
  final bool etroit;
  final void Function(ClienteNacrea) quandOuvrir;

  @override
  Widget build(BuildContext context) {
    final triees = [...clientes]
      ..sort((a, b) => (a.prochaineFin ?? DateTime(2100)).compareTo(b.prochaineFin ?? DateTime(2100)));
    return _cadre(etroit, [
      const Text(
        'Essais et abonnements qui se terminent sous 3 jours, en retard ou suspendus. '
        'Le bouton WhatsApp prépare un message adapté.',
        style: TextStyle(color: NacreaColors.gris, height: 1.4),
      ),
      const SizedBox(height: 12),
      if (triees.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text('Personne à relancer. Tout est à jour !', textAlign: TextAlign.center),
        ),
      for (final c in triees) _CarteCliente(c: c, avecRelance: true, quandTouche: () => quandOuvrir(c)),
    ]);
  }
}

// =====================================================================
// Fiche d'une cliente
// =====================================================================

class _FicheAdmin extends StatefulWidget {
  const _FicheAdmin({required this.compteId});
  final String compteId;

  @override
  State<_FicheAdmin> createState() => _FicheAdminState();
}

class _FicheAdminState extends State<_FicheAdmin> {
  late Future<FicheClienteNacrea> _fiche = _repo.fiche(widget.compteId);

  void _recharger() => setState(() => _fiche = _repo.fiche(widget.compteId));

  void _dire(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _action(Future<String?> Function() faire) async {
    try {
      final message = await faire();
      if (message != null && mounted) _dire(message);
      _recharger();
    } catch (e) {
      if (mounted) _dire(messageErreur(e));
    }
  }

  Future<void> _paiement(FicheClienteNacrea f, BoutiqueAdmin b) async {
    final resultat = await showDialog<(int, int, DateTime?)>(
      context: context,
      builder: (_) => _PaiementDialog(boutique: b),
    );
    if (resultat == null || !mounted) return;
    final (montant, mois, fin) = resultat;
    _recharger();
    final envoyer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Paiement enregistré'),
        content: Text('« ${b.nom} » est active${fin == null ? '' : ' jusqu\'au ${dateCourte(fin)}'}.\n'
            'Envoyer la confirmation à la patronne sur WhatsApp ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
        ],
      ),
    );
    if (envoyer == true && mounted) {
      await ouvrirWhatsApp(
        context,
        f.telephoneContact,
        'Bonjour${f.patronne == null ? '' : ' ${f.patronne}'}, nous avons bien reçu votre paiement de '
                '${fcfa(montant)} pour « ${b.nom} » ($mois mois). Votre abonnement Nacréa est actif'
                '${fin == null ? '' : ' jusqu\'au ${dateCourte(fin)}'}. Merci pour votre confiance !'
            .replaceAll(' ', ' '),
      );
    }
  }

  Future<void> _offrir(BoutiqueAdmin b) async {
    final jours = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: Colors.white,
        title: Text('Offrir des jours à « ${b.nom} »'),
        children: [
          for (final j in const [3, 7, 14, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, j),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('$j jours')),
            ),
        ],
      ),
    );
    if (jours == null) return;
    await _action(() async {
      final fin = await _repo.offrirJours(b.id, jours);
      return '$jours jours offerts${fin == null ? '' : ' : jusqu\'au ${dateCourte(fin)}'}.';
    });
  }

  Future<void> _prix(BoutiqueAdmin b) async {
    final champ = TextEditingController(text: '${b.prix}');
    final prix = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Prix mensuel de « ${b.nom} »'),
        content: TextField(
          controller: champ,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'FCFA', helperText: 'Prix normal : 22 000 FCFA'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(champ.text)), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (prix == null) return;
    await _action(() async {
      await _repo.changerPrix(b.id, prix);
      return 'Nouveau prix : ${fcfa(prix)} par mois.';
    });
  }

  Future<void> _suspendre(BoutiqueAdmin b) async {
    final suspendre = b.statut != 'suspended';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(suspendre ? 'Suspendre « ${b.nom} » ?' : 'Réactiver « ${b.nom} » ?'),
        content: Text(suspendre
            ? 'Sa caisse se mettra en pause dès la prochaine synchronisation. Ses données restent consultables.'
            : 'La caisse redevient utilisable si la date d\'abonnement n\'est pas dépassée. '
                'Sinon, enregistrez un paiement ou offrez des jours.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(suspendre ? 'Suspendre' : 'Réactiver')),
        ],
      ),
    );
    if (ok != true) return;
    await _action(() async {
      final statut = await _repo.suspendre(b.id, suspendre);
      return 'Statut : ${libellesStatut[statut] ?? statut}.';
    });
  }

  Future<void> _supprimer(BoutiqueAdmin b) async {
    final champ = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Supprimer « ${b.nom} » ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Toutes ses ventes, son stock et sa caisse seront effacés définitivement. '
                'Pour confirmer, tapez le nom de la boutique :',
              ),
              const SizedBox(height: 12),
              TextField(controller: champ, autofocus: true, onChanged: (_) => setD(() {})),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(
              onPressed: champ.text.trim() == b.nom.trim() ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Supprimer définitivement', style: TextStyle(color: NacreaColors.erreur)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _action(() async {
      await _repo.supprimerBoutique(b.id);
      return '« ${b.nom} » a été supprimée.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche cliente')),
      body: FutureBuilder<FicheClienteNacrea>(
        future: _fiche,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
          }
          if (snap.hasError) {
            return Center(child: Text(messageErreur(snap.error!)));
          }
          final f = snap.data!;
          return _cadre(etroit, quandTirer: () async => _recharger(), [
            Text(f.nom, style: NacreaTheme.titre(size: etroit ? 30 : 36)),
            const SizedBox(height: 6),
            Text(
              [
                if (f.patronne != null) 'Patronne : ${f.patronne}',
                if (f.email != null) f.email!,
                if (f.telephoneContact != null) f.telephoneContact!,
              ].join(' · '),
              style: const TextStyle(color: NacreaColors.gris),
            ),
            Text(
              [
                if (f.creeLe != null) 'Cliente depuis le ${dateCourte(f.creeLe!)}',
                '${f.nbEmployees} employée${f.nbEmployees > 1 ? 's' : ''}',
              ].join(' · '),
              style: const TextStyle(color: NacreaColors.gris),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => ouvrirWhatsApp(context, f.telephoneContact,
                    'Bonjour${f.patronne == null ? '' : ' ${f.patronne}'}, ici le service client Nacréa. '),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Écrire sur WhatsApp'),
              ),
            ),
            const SizedBox(height: 20),
            for (final b in f.boutiques)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined, color: NacreaColors.prune),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(b.nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                          _PastilleStatut(b.statut),
                          PopupMenuButton<String>(
                            onSelected: (choix) => switch (choix) {
                              'offrir' => _offrir(b),
                              'prix' => _prix(b),
                              'suspendre' => _suspendre(b),
                              'supprimer' => _supprimer(b),
                              'relancer' => ouvrirWhatsApp(
                                  context,
                                  b.telephone ?? f.telephoneContact,
                                  _texteRelance(
                                      patronne: f.patronne, boutique: b.nom, statut: b.statut, fin: b.fin, prix: b.prix),
                                ),
                              _ => null,
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'relancer', child: Text('Relancer par WhatsApp')),
                              const PopupMenuItem(value: 'offrir', child: Text('Offrir des jours')),
                              const PopupMenuItem(value: 'prix', child: Text('Changer le prix mensuel')),
                              PopupMenuItem(
                                value: 'suspendre',
                                child: Text(b.statut == 'suspended' ? 'Réactiver' : 'Suspendre'),
                              ),
                              if (f.boutiques.length > 1)
                                const PopupMenuItem(
                                  value: 'supprimer',
                                  child: Text('Supprimer la boutique', style: TextStyle(color: NacreaColors.erreur)),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (b.fin != null) '${b.statut == 'trial' ? 'Fin de l\'essai' : 'Payé jusqu\'au'} : ${dateCourte(b.fin!)}',
                          '${fcfa(b.prix)}/mois',
                        ].join(' · '),
                      ),
                      Text(
                        '${b.ventes30j} ventes sur 30 jours · dernière vente : ${_ilYa(b.derniereVente)}',
                        style: const TextStyle(color: NacreaColors.gris),
                      ),
                      if (b.adresse != null)
                        Text(b.adresse!, style: const TextStyle(color: NacreaColors.gris)),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: () => _paiement(f, b),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Enregistrer un paiement'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Paiements reçus', style: NacreaTheme.titre(size: 22)),
            const SizedBox(height: 8),
            if (f.paiements.isEmpty)
              const Text('Aucun paiement pour l\'instant.', style: TextStyle(color: NacreaColors.gris))
            else
              Card(
                child: Column(
                  children: [
                    for (final p in f.paiements)
                      ListTile(
                        title: Text('${fcfa(p.montant)} · ${p.mois} mois · ${p.boutique}'),
                        subtitle: Text([
                          dateCourte(p.le),
                          libellesMoyen[p.moyen] ?? p.moyen,
                          if (p.jusquAu != null) 'jusqu\'au ${dateCourte(p.jusquAu!)}',
                          if (p.note != null) p.note!,
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: 'Effacer (erreur de saisie)',
                          icon: const Icon(Icons.delete_outline, color: NacreaColors.gris),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Colors.white,
                                title: const Text('Effacer ce paiement ?'),
                                content: const Text(
                                  'À utiliser seulement pour une erreur de saisie. '
                                  'La date de fin d\'abonnement ne change pas.',
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Effacer')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _action(() async {
                                await _repo.supprimerPaiement(p.id);
                                return 'Paiement effacé.';
                              });
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _PaiementDialog extends StatefulWidget {
  const _PaiementDialog({required this.boutique});
  final BoutiqueAdmin boutique;

  @override
  State<_PaiementDialog> createState() => _PaiementDialogState();
}

class _PaiementDialogState extends State<_PaiementDialog> {
  int _mois = 1;
  late final _montant = TextEditingController(text: '${widget.boutique.prix}');
  final _note = TextEditingController();
  String _moyen = 'mobile_money';
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _montant.dispose();
    _note.dispose();
    super.dispose();
  }

  void _choisirMois(int m) => setState(() {
        _mois = m;
        _montant.text = '${widget.boutique.prix * m}';
      });

  Future<void> _valider() async {
    final montant = int.tryParse(_montant.text) ?? 0;
    if (montant <= 0 || _chargement) {
      setState(() => _erreur = 'Indiquez le montant reçu');
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final fin = await _repo.enregistrerPaiement(
        boutiqueId: widget.boutique.id,
        montant: montant,
        mois: _mois,
        moyen: _moyen,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, (montant, _mois, fin));
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
      title: Text('Paiement · ${widget.boutique.nom}', style: NacreaTheme.titre(size: 24)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Durée payée', style: TextStyle(color: NacreaColors.gris)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [1, 3, 6, 12])
                    ChoiceChip(
                      label: Text('$m mois'),
                      selected: _mois == m,
                      onSelected: (_) => _choisirMois(m),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _montant,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Montant reçu',
                  suffixText: 'FCFA',
                  helperText: 'Modifiable en cas de remise (paiement annuel…)',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _moyen,
                decoration: const InputDecoration(labelText: 'Reçu par'),
                items: [
                  for (final e in libellesMoyen.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _moyen = v ?? 'mobile_money'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (facultatif)',
                  hintText: 'Référence de la transaction Flooz / T-Money…',
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                MessageErreur(_erreur!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _chargement ? null : () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _chargement ? null : _valider,
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

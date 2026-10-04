import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/clientes_repo.dart';
import '../../data/produits_repo.dart';
import '../../data/ventes_repo.dart';
import '../../services/membre.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';
import 'cliente_dialogs.dart';

/// Liste des clientes, avec celles qui doivent de l'argent mises en avant.
class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key, required this.membre, required this.boutique});
  final Membre membre;
  final Boutique boutique;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  late final _repo = ClientesRepo(compteId: widget.membre.compteId);
  late final Stream<List<Cliente>> _clientes = _repo.surveiller();
  final _recherche = TextEditingController();
  bool _seulementDettes = false;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _ouvrir(Cliente c) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FicheCliente(repo: _repo, clienteId: c.id, boutique: widget.boutique),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final etroit = MediaQuery.sizeOf(context).width < 600;
    return StreamBuilder<List<Cliente>>(
      stream: _clientes,
      builder: (context, snap) {
        final toutes = snap.data ?? const <Cliente>[];
        final debitrices = toutes.where((c) => c.doit).toList();
        final totalDu = debitrices.fold(0, (s, c) => s + c.dette);
        final q = _recherche.text.trim().toLowerCase();
        final qChiffres = q.replaceAll(RegExp(r'\D'), '');
        final visibles = toutes
            .where((c) => !_seulementDettes || c.doit)
            .where((c) =>
                q.isEmpty ||
                c.nom.toLowerCase().contains(q) ||
                (qChiffres.length >= 3 &&
                    (c.telephone ?? '').replaceAll(RegExp(r'\D'), '').contains(qChiffres)))
            .toList();
        if (_seulementDettes) visibles.sort((a, b) => b.dette.compareTo(a.dette));

        return ListView(
          padding: EdgeInsets.all(etroit ? 16 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Text('Clientes', style: NacreaTheme.titre(size: etroit ? 30 : 36)),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          onPressed: () async {
                            final c = await ouvrirFormCliente(context, _repo);
                            if (c != null && mounted) _ouvrir(c);
                          },
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Nouvelle cliente'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Chiffre(titre: 'Clientes', valeur: '${toutes.length}'),
                        _Chiffre(
                          titre: 'Doivent de l\'argent',
                          valeur: '${debitrices.length}',
                          alerte: debitrices.isNotEmpty,
                        ),
                        _Chiffre(titre: 'Total à récupérer', valeur: fcfa(totalDu), alerte: totalDu > 0),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _recherche,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Chercher par nom ou téléphone…',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Seulement celles qui doivent'),
                        selected: _seulementDettes,
                        onSelected: (v) => setState(() => _seulementDettes = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!snap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                      )
                    else if (visibles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            toutes.isEmpty
                                ? 'Aucune cliente pour l\'instant.\nAjoutez-en une ici ou depuis la caisse.'
                                : 'Aucune cliente trouvée.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: NacreaColors.gris, height: 1.5),
                          ),
                        ),
                      )
                    else
                      for (final c in visibles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CarteCliente(cliente: c, quandTouche: () => _ouvrir(c)),
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.titre, required this.valeur, this.alerte = false});
  final String titre;
  final String valeur;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: alerte ? const Color(0xFFFCEBEB) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alerte ? const Color(0xFFF2C9C9) : NacreaColors.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titre, style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
          const SizedBox(height: 4),
          Text(valeur,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: alerte ? NacreaColors.erreur : NacreaColors.chocolat,
              )),
        ],
      ),
    );
  }
}

class _CarteCliente extends StatelessWidget {
  const _CarteCliente({required this.cliente, required this.quandTouche});
  final Cliente cliente;
  final VoidCallback quandTouche;

  @override
  Widget build(BuildContext context) {
    final c = cliente;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: quandTouche,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: NacreaColors.nude,
                foregroundColor: NacreaColors.prune,
                child: Text(c.nom.isEmpty ? '?' : c.nom[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nom, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        if (c.telephone != null) c.telephone!,
                        if (c.derniereVisite != null) 'Dernier achat ${dateCourte(c.derniereVisite!)}',
                      ].join(' · '),
                      style: const TextStyle(color: NacreaColors.gris, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (c.doit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBEB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Doit ${fcfa(c.dette)}',
                      style: const TextStyle(color: NacreaColors.erreur, fontWeight: FontWeight.w700)),
                )
              else
                const Icon(Icons.chevron_right, color: NacreaColors.gris),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fiche d'une cliente : ce qu'elle doit, paiements, rappel WhatsApp et historique.
class FicheCliente extends StatefulWidget {
  const FicheCliente({super.key, required this.repo, required this.clienteId, required this.boutique});
  final ClientesRepo repo;
  final String clienteId;
  final Boutique boutique;

  @override
  State<FicheCliente> createState() => _FicheClienteState();
}

class _FicheClienteState extends State<FicheCliente> {
  late final Stream<Cliente?> _cliente = widget.repo.surveillerUne(widget.clienteId);
  late final Stream<List<MouvementCliente>> _historique = widget.repo.surveillerHistorique(widget.clienteId);

  Future<void> _rembourser(Cliente c) async {
    final ok = await ouvrirRemboursement(context, repo: widget.repo, cliente: c, boutiqueId: widget.boutique.id);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paiement enregistré.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche cliente')),
      body: StreamBuilder<Cliente?>(
        stream: _cliente,
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) {
            return const Center(child: CircularProgressIndicator(color: NacreaColors.prune));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: NacreaColors.nude,
                            foregroundColor: NacreaColors.prune,
                            child: Text(c.nom.isEmpty ? '?' : c.nom[0].toUpperCase(),
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.nom, style: NacreaTheme.titre(size: 30)),
                                if (c.telephone != null)
                                  Text(c.telephone!, style: const TextStyle(color: NacreaColors.gris)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Modifier',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => ouvrirFormCliente(context, widget.repo, cliente: c),
                          ),
                        ],
                      ),
                      if (c.note != null) ...[
                        const SizedBox(height: 12),
                        Text(c.note!, style: const TextStyle(fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: c.doit ? const Color(0xFFFCEBEB) : const Color(0xFFE5F3EA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.doit ? 'Elle doit' : 'À jour',
                                style: TextStyle(color: c.doit ? NacreaColors.erreur : NacreaColors.succes)),
                            Text(
                              c.doit ? fcfa(c.dette) : 'Aucune dette',
                              style: NacreaTheme.titre(
                                size: 36,
                                color: c.doit ? NacreaColors.erreur : NacreaColors.succes,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (c.doit)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                              onPressed: () => _rembourser(c),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Elle paie'),
                            ),
                          if (c.doit && c.telephone != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                              onPressed: () => ouvrirWhatsApp(
                                context,
                                c.telephone,
                                texteRappel(cliente: c.nom, dette: c.dette, boutique: widget.boutique.nom),
                              ),
                              icon: const Icon(Icons.chat_outlined),
                              label: const Text('Rappel WhatsApp'),
                            ),
                          if (c.telephone != null)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                              onPressed: () => launchUrl(Uri.parse('tel:${c.telephone!.replaceAll(' ', '')}')),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Appeler'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text('Historique', style: NacreaTheme.titre(size: 24)),
                      const SizedBox(height: 8),
                      StreamBuilder<List<MouvementCliente>>(
                        stream: _historique,
                        builder: (context, h) {
                          final liste = h.data;
                          if (liste == null) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator(color: NacreaColors.prune)),
                            );
                          }
                          if (liste.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Aucun achat pour l\'instant.', style: TextStyle(color: NacreaColors.gris)),
                            );
                          }
                          return Column(children: [for (final m in liste) _LigneHistorique(m)]);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LigneHistorique extends StatelessWidget {
  const _LigneHistorique(this.m);
  final MouvementCliente m;

  @override
  Widget build(BuildContext context) {
    final date = '${dateCourte(m.date)} · ${m.date.hour.toString().padLeft(2, '0')}h'
        '${m.date.minute.toString().padLeft(2, '0')}';
    final barre = m.annule ? TextDecoration.lineThrough : TextDecoration.none;
    final String titre;
    final String detail;
    final Color couleur;
    if (m.achat) {
      titre = 'Achat${m.ticket != null ? ' · reçu n° ${m.ticket}' : ''}${m.annule ? ' (annulé)' : ''}';
      detail = [
        date,
        if (m.boutique != null) m.boutique!,
        if (m.credit > 0) 'dont ${fcfa(m.credit)} à crédit',
      ].join(' · ');
      couleur = m.credit > 0 && !m.annule ? NacreaColors.erreur : NacreaColors.chocolat;
    } else {
      titre = 'Paiement reçu';
      detail = [date, MoyenPaiement.libelleDe(m.moyen ?? ''), if (m.boutique != null) m.boutique!].join(' · ');
      couleur = NacreaColors.succes;
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: NacreaColors.bordure))),
      child: Row(
        children: [
          Icon(m.achat ? Icons.shopping_bag_outlined : Icons.check_circle_outline, color: couleur),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TextStyle(fontWeight: FontWeight.w600, decoration: barre)),
                Text(detail, style: const TextStyle(color: NacreaColors.gris, fontSize: 13)),
              ],
            ),
          ),
          Text(
            '${m.achat ? '' : '- '}${fcfa(m.montant)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: couleur, decoration: barre),
          ),
        ],
      ),
    );
  }
}

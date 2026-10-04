
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/ventes_repo.dart';
import '../../theme/nacrea_theme.dart';
import '../../utils/format.dart';

/// Données d'un reçu de vente.
class Recu {
  Recu({
    required this.boutique,
    this.adresse,
    this.telephoneBoutique,
    required this.numero,
    required this.date,
    required this.lignes,
    required this.sousTotal,
    required this.remise,
    required this.total,
    required this.paiements,
    this.recuEspeces,
    this.monnaie = 0,
    this.vendeuse,
    this.annule = false,
    this.cliente,
    this.telephoneCliente,
  });

  final String boutique;
  final String? adresse;
  final String? telephoneBoutique;
  final String numero;
  final DateTime date;
  final List<LigneVente> lignes;
  final int sousTotal;
  final int remise;
  final int total;
  final Map<String, int> paiements;
  final int? recuEspeces;
  final int monnaie;
  final String? vendeuse;
  final bool annule;
  final String? cliente;
  final String? telephoneCliente;

  /// Partie laissée à crédit (« reste à payer »).
  int get credit => paiements['credit'] ?? 0;

  String get heure =>
      '${date.hour.toString().padLeft(2, '0')}h${date.minute.toString().padLeft(2, '0')}';
}

// ------------------------------------------------------------------ Fenêtre

/// Affiche le reçu avec les boutons Imprimer, WhatsApp et [bouton].
Future<void> afficherRecu(BuildContext context, Recu r, {String bouton = 'Nouvelle vente'}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      contentPadding: const EdgeInsets.all(24),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecuVue(recu: r),
              const SizedBox(height: 24),
              if (!r.annule) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => imprimerRecu(ctx, r),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => envoyerRecuWhatsApp(ctx, r),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(bouton),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RecuVue extends StatelessWidget {
  const RecuVue({super.key, required this.recu});
  final Recu recu;

  @override
  Widget build(BuildContext context) {
    final t = recu;
    const petit = TextStyle(fontSize: 13, color: NacreaColors.gris);
    Widget ligne(String a, String b, {bool fort = false, Color? couleur}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(a,
                    style: TextStyle(
                        fontWeight: fort ? FontWeight.w700 : FontWeight.w400,
                        fontSize: fort ? 18 : 14,
                        color: couleur)),
              ),
              Text(b,
                  style: TextStyle(
                      fontWeight: fort ? FontWeight.w700 : FontWeight.w500,
                      fontSize: fort ? 18 : 14,
                      color: couleur)),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t.annule)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFFCEBEB),
            child: const Text('VENTE ANNULÉE',
                textAlign: TextAlign.center,
                style: TextStyle(color: NacreaColors.erreur, fontWeight: FontWeight.w700)),
          ),
        Text(t.boutique, textAlign: TextAlign.center, style: NacreaTheme.titre(size: 26)),
        if ((t.adresse ?? '').isNotEmpty) Text(t.adresse!, textAlign: TextAlign.center, style: petit),
        if ((t.telephoneBoutique ?? '').isNotEmpty)
          Text('Tél. ${t.telephoneBoutique}', textAlign: TextAlign.center, style: petit),
        const SizedBox(height: 4),
        Text('Reçu n° ${t.numero} · ${dateCourte(t.date)} à ${t.heure}',
            textAlign: TextAlign.center, style: petit),
        if (t.vendeuse != null)
          Text('Servi par ${t.vendeuse}', textAlign: TextAlign.center, style: petit),
        const Divider(height: 28, color: NacreaColors.bordure),
        for (final l in t.lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Expanded(child: Text('${l.quantite} × ${fcfa(l.prixUnitaire)}', style: petit)),
                    Text(fcfa(l.total)),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 24, color: NacreaColors.bordure),
        if (t.remise > 0) ...[
          ligne('Sous-total', fcfa(t.sousTotal)),
          ligne('Remise', '- ${fcfa(t.remise)}', couleur: NacreaColors.orTexte),
        ],
        ligne('TOTAL', fcfa(t.total), fort: true, couleur: NacreaColors.prune),
        const SizedBox(height: 8),
        for (final p in t.paiements.entries)
          if (p.key != 'credit') ligne(MoyenPaiement.libelleDe(p.key), fcfa(p.value)),
        if (t.recuEspeces != null) ...[
          ligne('Reçu en espèces', fcfa(t.recuEspeces!)),
          ligne('Monnaie rendue', fcfa(t.monnaie)),
        ],
        if (t.cliente != null) ligne('Cliente', t.cliente!),
        if (t.credit > 0) ligne('Reste à payer', fcfa(t.credit), fort: true, couleur: NacreaColors.erreur),
        const SizedBox(height: 16),
        const Text('Merci de votre visite !',
            textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
      ],
    );
  }
}

// ------------------------------------------------------------------ Impression

/// Les polices de base du PDF n'ont pas l'espace fine : on la remplace.
String _pdf(String s) => s.replaceAll(' ', ' ').replaceAll('—', '-');

/// Reçu au format rouleau 80 mm (s'imprime aussi sur une imprimante classique).
Future<Uint8List> recuPdf(Recu r) async {
  final doc = pw.Document(title: 'Reçu ${r.numero}', author: r.boutique);
  final petit = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
  final normal = const pw.TextStyle(fontSize: 9);
  final gras = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);

  pw.Widget ligne(String a, String b, {pw.TextStyle? style}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(_pdf(a), style: style ?? normal), pw.Text(_pdf(b), style: style ?? normal)],
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(6 * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(_pdf(r.boutique),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if ((r.adresse ?? '').isNotEmpty)
            pw.Text(_pdf(r.adresse!), textAlign: pw.TextAlign.center, style: petit),
          if ((r.telephoneBoutique ?? '').isNotEmpty)
            pw.Text(_pdf('Tél. ${r.telephoneBoutique}'), textAlign: pw.TextAlign.center, style: petit),
          pw.SizedBox(height: 4),
          pw.Text(_pdf('Reçu n° ${r.numero}'), textAlign: pw.TextAlign.center, style: gras),
          pw.Text(_pdf('${dateCourte(r.date)} à ${r.heure}'), textAlign: pw.TextAlign.center, style: petit),
          if (r.vendeuse != null)
            pw.Text(_pdf('Servi par ${r.vendeuse}'), textAlign: pw.TextAlign.center, style: petit),
          pw.Divider(thickness: 0.5),
          for (final l in r.lignes) ...[
            pw.Text(_pdf(l.nom), style: gras),
            ligne('${l.quantite} x ${fcfa(l.prixUnitaire)}', fcfa(l.total)),
            pw.SizedBox(height: 3),
          ],
          pw.Divider(thickness: 0.5),
          if (r.remise > 0) ...[
            ligne('Sous-total', fcfa(r.sousTotal)),
            ligne('Remise', '- ${fcfa(r.remise)}'),
          ],
          ligne('TOTAL', fcfa(r.total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final p in r.paiements.entries)
            if (p.key != 'credit') ligne(MoyenPaiement.libelleDe(p.key), fcfa(p.value)),
          if (r.recuEspeces != null) ...[
            ligne('Reçu en espèces', fcfa(r.recuEspeces!)),
            ligne('Monnaie rendue', fcfa(r.monnaie)),
          ],
          if (r.cliente != null) ligne('Cliente', r.cliente!),
          if (r.credit > 0)
            ligne('RESTE A PAYER', fcfa(r.credit), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Text('Merci de votre visite !',
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Ouvre la fenêtre d'impression de Windows (choix de l'imprimante, ou « Microsoft Print to PDF »).
Future<void> imprimerRecu(BuildContext context, Recu r) async {
  try {
    await Printing.layoutPdf(
      name: 'Recu-${r.numero}',
      format: PdfPageFormat.roll80,
      onLayout: (_) => recuPdf(r),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impression impossible. Vérifiez que l\'imprimante est allumée et installée.')),
      );
    }
  }
}

// ------------------------------------------------------------------ WhatsApp

/// Texte du reçu, mis en forme pour WhatsApp (*gras*).
String recuTexte(Recu r) {
  final b = StringBuffer()
    ..writeln('*${r.boutique}*')
    ..writeln('Reçu n° ${r.numero}')
    ..writeln('${dateCourte(r.date)} à ${r.heure}')
    ..writeln();
  for (final l in r.lignes) {
    b.writeln('${l.quantite} × ${l.nom} : ${fcfa(l.total)}');
  }
  b.writeln();
  if (r.remise > 0) b.writeln('Remise : -${fcfa(r.remise)}');
  b.writeln('*TOTAL : ${fcfa(r.total)}*');
  final moyens = r.paiements.entries
      .where((p) => p.key != 'credit')
      .map((p) => '${MoyenPaiement.libelleDe(p.key)} ${fcfa(p.value)}')
      .join(' + ');
  if (moyens.isNotEmpty) b.writeln('Payé : $moyens');
  if (r.credit > 0) b.writeln('*Reste à payer : ${fcfa(r.credit)}*');
  b
    ..writeln()
    ..write('Merci de votre visite et à bientôt !');
  return b.toString().replaceAll(' ', ' ');
}

/// Demande le numéro de la cliente puis ouvre WhatsApp avec le reçu prêt à envoyer.
Future<void> envoyerRecuWhatsApp(BuildContext context, Recu r) async {
  final champ = TextEditingController(text: r.telephoneCliente ?? '228 ');
  final numero = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Envoyer le reçu par WhatsApp'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: champ,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
          decoration: const InputDecoration(
            labelText: 'Numéro WhatsApp de la cliente',
            helperText: 'Avec l\'indicatif du pays, ex. 228 90 00 00 00',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(champ.text), child: const Text('Ouvrir WhatsApp')),
      ],
    ),
  );
  if (numero == null) return;

  var chiffres = numero.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.length == 8) chiffres = '228$chiffres'; // numéro local togolais sans indicatif
  if (chiffres.length < 10) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro incomplet : ajoutez l\'indicatif du pays (ex. 228).')),
      );
    }
    return;
  }

  final lien = Uri.parse('https://wa.me/$chiffres?text=${Uri.encodeComponent(recuTexte(r))}');
  final ouvert = await launchUrl(lien, mode: LaunchMode.externalApplication);
  if (!ouvert && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp. Vérifiez la connexion internet.')),
    );
  }
}

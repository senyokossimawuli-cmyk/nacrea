import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/produits_repo.dart';
import '../utils/format.dart';

enum FormatEtiquette {
  a4('Planche A4 · 24 étiquettes (70 × 37 mm)'),
  rouleau('Rouleau d\'étiquettes 40 × 30 mm');

  const FormatEtiquette(this.libelle);
  final String libelle;
}

/// Choisit le type de code-barres adapté au code du produit.
pw.Barcode typeCode(String code) {
  final ean13 = pw.Barcode.ean13();
  if (RegExp(r'^\d{13}$').hasMatch(code) && ean13.isValid(code)) return ean13;
  final ean8 = pw.Barcode.ean8();
  if (RegExp(r'^\d{8}$').hasMatch(code) && ean8.isValid(code)) return ean8;
  return pw.Barcode.code128();
}

/// Code-barres « maison » (EAN-13 commençant par 20 : réservé aux magasins).
String nouveauCodeInterne([Random? r]) {
  final hasard = r ?? Random.secure();
  final chiffres = '20${List.generate(10, (_) => hasard.nextInt(10)).join()}';
  var somme = 0;
  for (var i = 0; i < 12; i++) {
    somme += int.parse(chiffres[i]) * (i.isEven ? 1 : 3);
  }
  return '$chiffres${(10 - somme % 10) % 10}';
}

String _propre(String s) => s.replaceAll(' ', ' ');

pw.Widget _etiquette(Produit p, String boutique, {required bool petite}) {
  final code = p.codeBarres!.trim();
  return pw.Container(
    padding: pw.EdgeInsets.all(petite ? 4 : 6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (!petite)
          pw.Text(_propre(boutique), style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700), maxLines: 1),
        pw.Text(
          _propre(p.nomComplet),
          style: pw.TextStyle(fontSize: petite ? 7 : 8, fontWeight: pw.FontWeight.bold),
          maxLines: 2,
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(
          _propre(fcfa(p.prixVente)),
          style: pw.TextStyle(fontSize: petite ? 10 : 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Expanded(
          child: pw.BarcodeWidget(
            barcode: typeCode(code),
            data: code,
            drawText: true,
            textStyle: pw.TextStyle(fontSize: petite ? 6 : 7),
          ),
        ),
      ],
    ),
  );
}

/// PDF d'étiquettes : chaque produit répété [quantites] fois.
Future<Uint8List> etiquettesPdf({
  required List<(Produit, int)> quantites,
  required String boutique,
  required FormatEtiquette format,
}) async {
  final doc = pw.Document(title: 'Étiquettes Nacréa');
  final liste = [
    for (final (p, n) in quantites)
      if ((p.codeBarres ?? '').trim().isNotEmpty)
        for (var i = 0; i < n; i++) p,
  ];

  if (format == FormatEtiquette.rouleau) {
    const mm = PdfPageFormat.mm;
    for (final p in liste) {
      doc.addPage(pw.Page(
        pageFormat: const PdfPageFormat(40 * mm, 30 * mm),
        build: (_) => _etiquette(p, boutique, petite: true),
      ));
    }
  } else {
    // A4 : 3 colonnes × 8 lignes de 70 × 37,1 mm, sans marge (planches standard).
    const mm = PdfPageFormat.mm;
    const colonnes = 3, rangees = 8;
    for (var debut = 0; debut < liste.length; debut += colonnes * rangees) {
      final page = liste.sublist(debut, min(debut + colonnes * rangees, liste.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Column(
          children: [
            for (var r = 0; r < rangees; r++)
              pw.SizedBox(
                height: 297 * mm / rangees,
                child: pw.Row(
                  children: [
                    for (var c = 0; c < colonnes; c++)
                      pw.SizedBox(
                        width: 210 * mm / colonnes,
                        child: r * colonnes + c < page.length
                            ? _etiquette(page[r * colonnes + c], boutique, petite: false)
                            : pw.SizedBox(),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ));
    }
  }
  return doc.save();
}

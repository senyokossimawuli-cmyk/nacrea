import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Colonnes du modèle Excel, dans l'ordre.
const colonnesModele = [
  'Nom du produit',
  'Marque',
  'Variante (teinte, contenance)',
  'Catégorie',
  'Code-barres',
  'Prix d\'achat',
  'Prix de vente',
  'Prix de gros',
  'Quantité en stock',
  'Alerte stock bas',
  'Date de péremption',
];

/// Une ligne du fichier, prête à être importée (ou avec ses erreurs).
class LigneImport {
  LigneImport({
    required this.numero,
    required this.nom,
    this.marque,
    this.variante,
    this.categorie,
    this.codeBarres,
    this.prixAchat,
    this.prixVente,
    this.prixGros,
    this.stock,
    this.stockMin,
    this.peremption,
    this.erreurs = const [],
  });

  final int numero; // numéro de ligne dans Excel
  final String nom;
  final String? marque, variante, categorie, codeBarres;
  final int? prixAchat, prixVente, prixGros, stock, stockMin;
  final DateTime? peremption;
  final List<String> erreurs;

  bool get valide => erreurs.isEmpty;
}

/// Fabrique le modèle Excel à remplir (avec deux lignes d'exemple).
Uint8List modeleExcel() {
  final x = Excel.createExcel();
  final defaut = x.getDefaultSheet() ?? 'Sheet1';
  x.rename(defaut, 'Produits');
  final feuille = x['Produits'];
  feuille.appendRow([for (final c in colonnesModele) TextCellValue(c)]);
  feuille.appendRow([
    TextCellValue('Lait corporel karité'),
    TextCellValue('Nivea'),
    TextCellValue('400 ml'),
    TextCellValue('Soins du corps'),
    TextCellValue('4005900123456'),
    const IntCellValue(2500),
    const IntCellValue(4000),
    const IntCellValue(3500),
    const IntCellValue(12),
    const IntCellValue(3),
    const DateCellValue(year: 2027, month: 6, day: 30),
  ]);
  feuille.appendRow([
    TextCellValue('Rouge à lèvres mat'),
    TextCellValue('Maybelline'),
    TextCellValue('Rouge cerise'),
    TextCellValue('Maquillage'),
    null,
    const IntCellValue(1800),
    const IntCellValue(3000),
    null,
    const IntCellValue(6),
    null,
    null,
  ]);
  for (var i = 0; i < colonnesModele.length; i++) {
    feuille.setColumnWidth(i, i == 0 ? 32 : 18);
  }
  return Uint8List.fromList(x.encode()!);
}

// ---------------------------------------------------------------- Lecture

String _normaliser(String s) {
  const accents = {'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', '’': "'"};
  final b = StringBuffer();
  for (final c in s.toLowerCase().trim().split('')) {
    b.write(accents[c] ?? c);
  }
  return b.toString();
}

/// Reconnaît une colonne d'après son titre, même écrit un peu différemment.
String? _cle(String titre) {
  final t = _normaliser(titre);
  if (t.isEmpty) return null;
  if (t.contains('gros')) return 'gros';
  if (t.contains('achat') || t.contains('revient')) return 'achat';
  if (t.contains('vente') || t == 'prix' || t.contains('prix unitaire')) return 'vente';
  if (t.contains('alerte') || t.contains('minimum') || t.contains('stock min')) return 'min';
  if (t.contains('stock') || t.contains('quantite') || t == 'qte' || t == 'qté') return 'stock';
  if (t.contains('peremption') || t.contains('expiration') || t.startsWith('dlc') || t.startsWith('date')) {
    return 'peremption';
  }
  if (t.contains('code') || t.contains('ean')) return 'code';
  if (t.contains('categorie') || t.contains('rayon') || t.contains('famille')) return 'categorie';
  if (t.contains('marque')) return 'marque';
  if (t.contains('variante') || t.contains('teinte') || t.contains('contenance') || t.contains('parfum')) {
    return 'variante';
  }
  if (t.contains('nom') || t.contains('produit') || t.contains('designation') || t.contains('article')) return 'nom';
  return null;
}

String _texte(CellValue? v) => switch (v) {
      null => '',
      DateCellValue d => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      DateTimeCellValue d => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      DoubleCellValue d when d.value == d.value.roundToDouble() => d.value.toInt().toString(),
      _ => v.toString().trim(),
    };

/// « 2 500 », « 2500 FCFA », « 2.500 », 2500.0 → 2500
int? _nombre(String s) {
  final propre = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (propre.isEmpty) return null;
  // 2.500 ou 2,500 (séparateur de milliers) → 2500 ; 2500,50 → 2501
  final milliers = RegExp(r'^\d{1,3}([.,]\d{3})+$');
  if (milliers.hasMatch(propre)) return int.tryParse(propre.replaceAll(RegExp('[.,]'), ''));
  return double.tryParse(propre.replaceAll(',', '.'))?.round();
}

DateTime? _date(String s) {
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$').firstMatch(s);
  if (m != null) {
    var annee = int.parse(m.group(3)!);
    if (annee < 100) annee += 2000;
    return DateTime(annee, int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  // Nombre de jours Excel (ex. 46568)
  final n = int.tryParse(s);
  if (n != null && n > 30000 && n < 80000) return DateTime(1899, 12, 30).add(Duration(days: n));
  return null;
}

/// Code-barres : Excel transforme souvent 4005900123456 en 4.0059E+12 ; on récupère les chiffres.
String? _code(String s) {
  if (s.isEmpty) return null;
  final sci = RegExp(r'^\d+(\.\d+)?[eE]\+\d+$');
  if (sci.hasMatch(s)) return double.parse(s).toStringAsFixed(0);
  return s.replaceAll(' ', '');
}

/// Lit un fichier Excel (.xlsx) ou CSV et renvoie ses lignes de produits.
List<LigneImport> lireFichier(Uint8List octets, String nomFichier) {
  final List<List<String>> lignes;
  if (nomFichier.toLowerCase().endsWith('.csv')) {
    var texte = utf8.decode(octets, allowMalformed: true);
    if (texte.startsWith('﻿')) texte = texte.substring(1);
    final sep = texte.split('\n').first.contains(';') ? ';' : ',';
    lignes = [
      for (final l in const LineSplitter().convert(texte))
        [for (final c in l.split(sep)) c.replaceAll('"', '').trim()],
    ];
  } else {
    final x = Excel.decodeBytes(octets);
    final feuille = x.tables.values.firstWhere((t) => t.maxRows > 0, orElse: () => x.tables.values.first);
    lignes = [
      for (final r in feuille.rows) [for (final c in r) _texte(c?.value)],
    ];
  }

  // Ligne des titres : la première qui contient au moins le nom et un prix.
  var debut = -1;
  Map<String, int> colonnes = {};
  for (var i = 0; i < lignes.length && i < 10; i++) {
    final cles = <String, int>{};
    for (var j = 0; j < lignes[i].length; j++) {
      final k = _cle(lignes[i][j]);
      if (k != null && !cles.containsKey(k)) cles[k] = j;
    }
    if (cles.containsKey('nom') && (cles.containsKey('vente') || cles.containsKey('achat'))) {
      debut = i;
      colonnes = cles;
      break;
    }
  }
  if (debut < 0) {
    throw Exception('Colonnes introuvables. Le fichier doit avoir au moins les colonnes « Nom du produit » '
        'et « Prix de vente ». Utilisez le modèle YDS Beauty.');
  }

  String val(List<String> l, String cle) {
    final j = colonnes[cle];
    return (j == null || j >= l.length) ? '' : l[j].trim();
  }

  final resultat = <LigneImport>[];
  for (var i = debut + 1; i < lignes.length; i++) {
    final l = lignes[i];
    if (l.every((c) => c.trim().isEmpty)) continue;
    final erreurs = <String>[];
    final nom = val(l, 'nom');
    if (nom.isEmpty) erreurs.add('nom manquant');
    final vente = _nombre(val(l, 'vente'));
    if (vente == null || vente <= 0) erreurs.add('prix de vente manquant');
    final stockTexte = val(l, 'stock');
    final stock = _nombre(stockTexte);
    if (stockTexte.isNotEmpty && (stock == null || stock < 0)) erreurs.add('quantité invalide');
    final dateTexte = val(l, 'peremption');
    final peremption = _date(dateTexte);
    if (dateTexte.isNotEmpty && peremption == null) erreurs.add('date de péremption illisible');
    String? opt(String c) => val(l, c).isEmpty ? null : val(l, c);
    resultat.add(LigneImport(
      numero: i + 1,
      nom: nom,
      marque: opt('marque'),
      variante: opt('variante'),
      categorie: opt('categorie'),
      codeBarres: _code(val(l, 'code')),
      prixAchat: _nombre(val(l, 'achat')),
      prixVente: vente,
      prixGros: _nombre(val(l, 'gros')),
      stock: stock,
      stockMin: _nombre(val(l, 'min')),
      peremption: peremption,
      erreurs: erreurs,
    ));
  }
  return resultat;
}

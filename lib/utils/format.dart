/// Mise en forme des montants et des dates, à la française.
library;

/// 3500 → "3 500 FCFA"
String fcfa(int montant) => '${milliers(montant)} FCFA';

/// 1250000 → "1 250 000"
String milliers(int n) {
  final signe = n < 0 ? '-' : '';
  final chiffres = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' '); // espace fine insécable
    buffer.write(chiffres[i]);
  }
  return '$signe$buffer';
}

/// DateTime → "16/10/2026"
String dateCourte(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Date au format de la base (AAAA-MM-JJ) pour les dates sans heure.
String dateBase(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

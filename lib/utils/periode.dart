/// Période choisie pour les dépenses et les rapports (dates incluses, au jour près).
enum Periode {
  aujourdhui("Aujourd'hui"),
  semaine('7 derniers jours'),
  mois('Ce mois'),
  moisDernier('Mois dernier'),
  annee('Cette année');

  const Periode(this.libelle);
  final String libelle;

  /// Premier et dernier jour de la période (à minuit, heure locale).
  (DateTime, DateTime) get bornes {
    final n = DateTime.now();
    final jour = DateTime(n.year, n.month, n.day);
    return switch (this) {
      Periode.aujourdhui => (jour, jour),
      Periode.semaine => (jour.subtract(const Duration(days: 6)), jour),
      Periode.mois => (DateTime(n.year, n.month, 1), jour),
      Periode.moisDernier => (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 0)),
      Periode.annee => (DateTime(n.year, 1, 1), jour),
    };
  }
}

const _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

String nomMois(DateTime d) => '${_mois[d.month - 1]} ${d.year}';

const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// « mardi 21 octobre 2026 »
String dateLongue(DateTime d) => '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]} ${d.year}';

/// « L », « M », « M », « J »… (initiale du jour)
String initialeJour(DateTime d) => _jours[d.weekday - 1][0].toUpperCase();

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Base de données locale de Nacréa (sur le PC ou le téléphone).
///
/// Le logiciel lit et écrit toujours ici, même sans internet.
/// PowerSync envoie les changements à Supabase dès que la connexion revient,
/// et rapatrie les changements faits ailleurs (autre boutique, application patronne).
late final PowerSyncDatabase db;

const schemaLocal = Schema([
  Table('accounts', [
    Column.text('name'),
    Column.text('owner_user_id'),
    Column.text('phone'),
    Column.text('created_at'),
  ]),
  Table('shops', [
    Column.text('account_id'),
    Column.text('name'),
    Column.text('address'),
    Column.text('phone'),
    Column.text('activation_code'),
    Column.text('created_at'),
  ]),
  Table('members', [
    Column.text('user_id'),
    Column.text('account_id'),
    Column.text('shop_id'),
    Column.text('role'),
    Column.text('display_name'),
    Column.integer('can_see_costs'),
    Column.integer('active'),
    Column.text('created_at'),
  ]),
  Table('subscriptions', [
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('status'),
    Column.integer('monthly_price'),
    Column.text('current_period_end'),
    Column.text('created_at'),
  ]),
  Table('categories', [
    Column.text('account_id'),
    Column.text('name'),
    Column.text('created_at'),
  ]),
  Table('products', [
    Column.text('account_id'),
    Column.text('category_id'),
    Column.text('name'),
    Column.text('brand'),
    Column.text('variant_label'),
    Column.text('barcode'),
    Column.text('photo_url'),
    Column.integer('purchase_price'),
    Column.integer('sale_price'),
    Column.integer('wholesale_price'),
    Column.integer('min_stock'),
    Column.integer('active'),
    Column.text('created_at'),
  ], indexes: [
    Index('compte', [IndexedColumn('account_id')]),
    Index('code_barres', [IndexedColumn('barcode')]),
  ]),
  Table('stock_lots', [
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('product_id'),
    Column.integer('quantity'),
    Column.integer('cost_price'),
    Column.text('expiry_date'),
    Column.text('received_at'),
  ], indexes: [
    Index('boutique_produit', [IndexedColumn('shop_id'), IndexedColumn('product_id')]),
  ]),
  Table('sales', [
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('customer_id'),
    Column.text('user_id'),
    Column.text('ticket_number'),
    Column.text('status'),
    Column.integer('subtotal'),
    Column.integer('discount'),
    Column.integer('total'),
    Column.text('created_at'),
  ], indexes: [
    Index('boutique', [IndexedColumn('shop_id')]),
  ]),
  Table('sale_items', [
    Column.text('sale_id'),
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('product_id'),
    Column.text('lot_id'),
    Column.integer('quantity'),
    Column.integer('unit_price'),
    Column.integer('cost_price'),
    Column.integer('discount'),
  ], indexes: [
    Index('vente', [IndexedColumn('sale_id')]),
  ]),
  Table('payments', [
    Column.text('sale_id'),
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('method'),
    Column.integer('amount'),
    Column.text('created_at'),
  ], indexes: [
    Index('vente', [IndexedColumn('sale_id')]),
  ]),

  Table('cash_sessions', [
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('status'),
    Column.text('opened_by'),
    Column.text('opened_at'),
    Column.integer('opening_float'),
    Column.text('closed_by'),
    Column.text('closed_at'),
    Column.integer('expected_cash'),
    Column.integer('counted_cash'),
    Column.integer('difference'),
    Column.text('note'),
  ], indexes: [
    Index('boutique', [IndexedColumn('shop_id')]),
  ]),
  Table('cash_movements', [
    Column.text('session_id'),
    Column.text('shop_id'),
    Column.text('account_id'),
    Column.text('type'),
    Column.integer('amount'),
    Column.text('reason'),
    Column.text('user_id'),
    Column.text('created_at'),
  ], indexes: [
    Index('session', [IndexedColumn('session_id')]),
  ]),

  /// Opérations à rejouer sur le serveur (vente, entrée de stock) : envoyées puis effacées.
  Table.insertOnly('operations', [
    Column.text('type'),
    Column.text('payload'),
    Column.text('created_at'),
  ]),

  /// Envois refusés par le serveur, gardés pour ne rien perdre.
  Table.localOnly('envois_refuses', [
    Column.text('type'),
    Column.text('payload'),
    Column.text('erreur'),
    Column.text('created_at'),
  ]),
]);

/// Tables écrites localement en avance (affichage immédiat) mais enregistrées
/// sur le serveur par une opération : leurs changements ne sont pas envoyés tels quels.
const _tablesViaOperations = {'stock_lots', 'sales', 'sale_items', 'payments'};

/// Colonnes oui/non : SQLite les stocke en 0/1, Supabase attend true/false.
const _colonnesOuiNon = {'active', 'can_see_costs'};

/// Erreurs définitives : renvoyer la même donnée ne servira à rien.
final _erreursDefinitives = [
  RegExp(r'^22...$'), // donnée invalide
  RegExp(r'^23...$'), // contrainte non respectée
  RegExp(r'^42501$'), // accès refusé
  RegExp(r'^P0001$'), // refus métier (ex. paiement incorrect)
];

/// Date et heure au format de la base.
String maintenantIso() => DateTime.now().toUtc().toIso8601String();

/// Nouvel identifiant unique, créé sans internet.
Future<String> nouvelId() async => (await db.get('SELECT uuid() AS id'))['id'] as String;

/// Vrai pour les colonnes oui/non, qu'elles arrivent en 1/0 ou en true/false.
bool ouiNon(Object? v) => v == 1 || v == true || v == 'true' || v == '1';

/// Ajoute une opération à envoyer au serveur (dans une transaction en cours).
Future<void> ajouterOperation(SqliteWriteContext tx, String type, Map<String, dynamic> donnees) async {
  await tx.execute(
    'INSERT INTO operations (id, type, payload, created_at) VALUES (uuid(), ?, ?, ?)',
    [type, jsonEncode(donnees), maintenantIso()],
  );
}

class _ConnecteurSupabase extends PowerSyncBackendConnector {
  Future<void>? _rafraichissement;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await _rafraichissement;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: NacreaConfig.powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  @override
  void invalidateCredentials() {
    _rafraichissement = Supabase.instance.client.auth
        .refreshSession()
        .timeout(const Duration(seconds: 5))
        .then((_) => null, onError: (_) => null);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final rest = Supabase.instance.client;
    while (true) {
      final transaction = await database.getNextCrudTransaction();
      if (transaction == null) return;

      for (final op in transaction.crud) {
        try {
          await _envoyer(rest, op);
        } on PostgrestException catch (e) {
          final code = e.code;
          if (code != null && _erreursDefinitives.any((re) => re.hasMatch(code))) {
            // Refus définitif : on garde une trace locale au lieu de bloquer la file.
            await database.execute(
              'INSERT INTO envois_refuses (id, type, payload, erreur, created_at) '
              'VALUES (uuid(), ?, ?, ?, ?)',
              [
                op.table == 'operations' ? (op.opData?['type'] ?? op.table) : op.table,
                jsonEncode(op.opData),
                '${e.code} ${e.message}',
                maintenantIso(),
              ],
            );
            debugPrint('Nacréa : envoi refusé (${op.table}) : ${e.message}');
          } else {
            rethrow; // erreur passagère (réseau…) : PowerSync réessaiera plus tard
          }
        }
      }
      await transaction.complete();
    }
  }

  Future<void> _envoyer(SupabaseClient client, CrudEntry op) async {
    if (op.table == 'operations') {
      final type = op.opData?['type'] as String?;
      final donnees = jsonDecode(op.opData?['payload'] as String? ?? '{}') as Map<String, dynamic>;
      switch (type) {
        case 'vente':
          await client.rpc('record_sale', params: donnees);
        case 'entree_stock':
          await client.rpc('receive_stock', params: donnees);
        default:
          debugPrint('Nacréa : opération inconnue $type');
      }
      return;
    }
    if (_tablesViaOperations.contains(op.table)) return;

    final table = client.from(op.table);
    final donnees = <String, dynamic>{
      for (final e in (op.opData ?? const <String, dynamic>{}).entries)
        e.key: _colonnesOuiNon.contains(e.key) && e.value != null ? ouiNon(e.value) : e.value,
    };
    switch (op.op) {
      case UpdateType.put:
        await table.upsert({...donnees, 'id': op.id});
      case UpdateType.patch:
        await table.update(donnees).eq('id', op.id);
      case UpdateType.delete:
        await table.delete().eq('id', op.id);
    }
  }
}

_ConnecteurSupabase? _connecteur;

void _connecter() {
  _connecteur = _ConnecteurSupabase();
  db.connect(connector: _connecteur!);
}

/// Ouvre la base locale et la relie à la session Supabase.
Future<void> ouvrirBaseLocale() async {
  final dossier = await getApplicationSupportDirectory();
  db = PowerSyncDatabase(schema: schemaLocal, path: p.join(dossier.path, 'nacrea.db'));
  await db.initialize();

  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) _connecter();

  auth.onAuthStateChange.listen((data) async {
    switch (data.event) {
      case AuthChangeEvent.signedIn:
        _connecter();
      case AuthChangeEvent.signedOut:
        _connecteur = null;
        await db.disconnect();
      case AuthChangeEvent.tokenRefreshed:
        _connecteur?.prefetchCredentials();
      default:
        break;
    }
  });
}

/// Attend que les données soient arrivées au moins une fois sur cet appareil.
/// Sans internet lors de la toute première connexion, c'est impossible : on le signale.
Future<void> attendrePremiereSynchro() async {
  if (db.currentStatus.hasSynced == true) return;
  try {
    await db.waitForFirstSync().timeout(const Duration(seconds: 45));
  } on TimeoutException {
    throw Exception(
      'Première synchronisation impossible. Connectez-vous à internet une première fois '
      'pour télécharger les données de votre boutique.',
    );
  }
}

/// Nombre de changements faits ici et pas encore envoyés au serveur.
Future<int> changementsEnAttente() async => (await db.getUploadQueueStats()).count;

/// Déconnexion complète : refusée si des ventes n'ont pas encore été envoyées.
/// Renvoie un message d'explication si la déconnexion n'a pas eu lieu.
Future<String?> seDeconnecter() async {
  final enAttente = await changementsEnAttente();
  if (enAttente > 0) {
    return '$enAttente changement${enAttente > 1 ? 's' : ''} pas encore envoyé${enAttente > 1 ? 's' : ''} '
        'au serveur. Reconnectez internet et patientez quelques secondes avant de vous déconnecter.';
  }
  await Supabase.instance.client.auth.signOut();
  await db.disconnectAndClear();
  return null;
}

// dart format width=100
// test/features/admin/squadre/admin_squadra_detail_screen_test.dart
//
// The redesigned Squadra detail on the wave-0 summary shell: SummaryHero + Modifica, then
// Relazioni (membri) → Sintesi (descrizione, note). The prototype's Attività section is the
// squadra's active cantieri; no device or `/api/squadre` source carries that relation, so it is
// dropped rather than invented.
//
// Regressions kept from the previous screen:
//   1. GET /api/squadre/{id} wraps the squadra's own fields under a "squadra" key
//      (backend record SquadraDetailResponse(Squadra, Membri)).
//   2. capSquadraNome is the derived lead the server already sends.
//   3. A member's last-access timestamp comes from the same single bulk `allUsersProvider` fetch
//      the list screen uses — never a per-member `/api/users/{id}` call.
//   4. A header action links to this squadra's own schedule, pre-filtered.
//   5. Add/remove member still refreshes the detail instead of leaving a stale row.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/squadre/admin_squadra_detail_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient(this._detail, {List<Map<String, dynamic>>? users})
    : _users = users ?? const [],
      super(Dio());

  final Map<String, dynamic>? _detail;
  final List<Map<String, dynamic>> _users;

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => _detail;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async =>
      _users;
}

class _FailingAdminApiClient extends AdminApiClient {
  _FailingAdminApiClient() : super(Dio());

  int detailCalls = 0;

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async {
    detailCalls++;
    throw DioException(requestOptions: RequestOptions(path: '/api/squadre/$id'));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async =>
      const [];
}

class _PendingAdminApiClient extends AdminApiClient {
  _PendingAdminApiClient() : super(Dio());

  final completer = Completer<Map<String, dynamic>?>();

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) => completer.future;

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async =>
      const [];
}

/// Unlike [_FakeAdminApiClient], this fake's `fetchSquadraDetail` result actually changes after
/// `removeSquadraMember`/`addSquadraMember` succeed — the exact condition needed to prove
/// `adminSquadraDetailProvider` is genuinely re-fetched, not just left showing whatever the first
/// fetch returned.
class _StatefulAdminApiClient extends AdminApiClient {
  _StatefulAdminApiClient(this._membri) : super(Dio());

  List<Map<String, dynamic>> _membri;
  int removeCalls = 0;
  int addCalls = 0;

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => {
    'squadra': {'id': id, 'nome': 'Squadra Nord', 'isActive': true},
    'membri': _membri,
  };

  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async =>
      [
        {'id': 'u2', 'firstName': 'Luigi', 'lastName': 'Bianchi'},
      ];

  @override
  Future<void> removeSquadraMember(String squadraId, String userId) async {
    removeCalls++;
    _membri = _membri.where((m) => m['userId'] != userId).toList();
  }

  @override
  Future<void> addSquadraMember(
    String squadraId, {
    required String userId,
    int ruolo = SquadraRuolo.membro,
  }) async {
    addCalls++;
    _membri = [
      ..._membri,
      {'userId': userId, 'ruolo': ruolo},
    ];
  }
}

/// Add-member picker population + label regressions.
///
/// `fetchAllUsersWithSquadraInfo` (the squadra LIST screen's source — every active user, no role
/// filter) and `fetchTechnicians` (the old, role-filtered source) deliberately return DIFFERENT
/// sets, so a test that finds the Office user proves the picker stopped reading from
/// `fetchTechnicians`. Before the fix it did read from there, so the Office user never appeared —
/// the operator's "si possono inserire solo paolo e daniel".
class _PickerPopulationApiClient extends AdminApiClient {
  _PickerPopulationApiClient() : super(Dio());

  @override
  Future<Map<String, dynamic>?> fetchSquadraDetail(String id) async => {
    'squadra': {'id': id, 'nome': 'Squadra Nord', 'isActive': true},
    'membri': <Map<String, dynamic>>[],
  };

  /// Every active user, no role filter — the list screen's population. Note the payload carries
  /// no `displayName` (the `User` schema has `fullName`/`firstName`/`lastName`), just as the real
  /// `/api/users` response does not.
  @override
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({bool activeOnly = true}) async =>
      [
        {
          'id': 'u-tech',
          'firstName': 'Daniel',
          'lastName': 'Rossi',
          'roles': ['Technician'],
        },
        {
          'id': 'u-office',
          'firstName': 'Paolo',
          'lastName': 'Verdi',
          'roles': ['Office'],
        },
        // No name fields at all, only an email — must still be offered, but never under the email.
        {'id': 'u-noname', 'email': 'ghost@tasktap.io'},
      ];

  /// The old, role-filtered source — deliberately narrower (technicians only).
  @override
  Future<List<Map<String, dynamic>>> fetchTechnicians() async => [
    {'id': 'u-tech', 'firstName': 'Daniel', 'lastName': 'Rossi'},
  ];
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 1, 1),
);

Widget _buildView({
  required AdminApiClient api,
  Map<String, dynamic>? squadra,
  bool online = true,
  AppDatabase? db,
  Set<String> capabilities = const {'team.squadra.write', 'pianificazione.schedule.read'},
}) {
  return ProviderScope(
    overrides: [
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith((ref) => Future.value(_entitlementWith(capabilities))),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
    ],
    child: MaterialApp(
      home: AdminSquadraDetailScreen(squadra: squadra ?? {'id': 'sq-1', 'nome': 'Squadra Nord'}),
    ),
  );
}

Map<String, dynamic> _prototypeDetail() => {
  'squadra': {
    'id': 'sq-1',
    'nome': 'Squadra Nord',
    'descrizione': 'Zona nord della città.',
    'specializzazione': 'Elettrico',
    'note': 'Pronta disponibilità nei festivi.',
    'capSquadraNome': 'Daniel Shala',
    'isActive': true,
  },
  'membri': [
    {'userId': 'u2', 'ruolo': 0},
    {'userId': 'u1', 'ruolo': 1},
    {'userId': 'u3', 'ruolo': 0},
    {'userId': 'u4', 'ruolo': 0},
  ],
};

List<Map<String, dynamic>> _prototypeUsers() => [
  {'id': 'u1', 'displayName': 'Daniel Shala'},
  {'id': 'u2', 'displayName': 'Giulia Verdi', 'lastAccessAt': '2026-08-20T10:30:00Z'},
  {'id': 'u3', 'displayName': 'Anna Neri'},
  {'id': 'u4', 'displayName': 'Paolo Galli'},
];

Future<void> _pump(
  WidgetTester tester, {
  required AdminApiClient api,
  Map<String, dynamic>? squadra,
  bool online = true,
  AppDatabase? db,
  Set<String> capabilities = const {'team.squadra.write', 'pianificazione.schedule.read'},
}) async {
  await tester.pumpWidget(
    _buildView(api: api, squadra: squadra, online: online, db: db, capabilities: capabilities),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  testWidgets('renders the summary hero, Relazioni → Sintesi, and no FAB', (tester) async {
    await _pump(tester, api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()));

    // Hero: kind, entity, status stamp, facts and the primary action.
    expect(find.text('SUMMARY · SQUADRA'), findsNWidgets(2)); // kicker above + kind in the card
    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Lead Daniel Shala · 4 membri · Elettrico'), findsOneWidget);
    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('ATTIVA')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('Modifica')), findsOneWidget);
    expect(find.byType(AppFab), findsNothing);

    // Relazioni first, then Sintesi; the prototype's Attività (cantieri) has no source.
    expect(find.text('Relazioni'), findsOneWidget);
    expect(find.text('4 MEMBRI'), findsOneWidget);
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Attività'), findsNothing);

    final relazioniY = tester.getTopLeft(find.text('Relazioni')).dy;
    final sintesiY = tester.getTopLeft(find.text('Sintesi')).dy;
    expect(relazioniY, lessThan(sintesiY));

    // Lead is first among the members and carries the lead role.
    expect(find.text('Daniel Shala'), findsOneWidget);
    expect(find.textContaining('CAPO SQUADRA'), findsOneWidget);
    expect(find.text('Giulia Verdi'), findsOneWidget);
    expect(find.textContaining('ULTIMO ACCESSO'), findsWidgets);

    // Sintesi carries only the free text the prototype names.
    expect(find.text('DESCRIZIONE'), findsOneWidget);
    expect(find.text('Zona nord della città.'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('Pronta disponibilità nei festivi.'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('hero facts stay in the hero and Sintesi repeats none of them', (tester) async {
    await _pump(tester, api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()));

    // There is exactly one joined hero line, and the specializzazione appears only there.
    expect(find.text('Lead Daniel Shala · 4 membri · Elettrico'), findsOneWidget);
    expect(find.textContaining('Elettrico'), findsOneWidget);
    expect(find.textContaining('Lead Daniel Shala'), findsOneWidget);
    // Sintesi owns the description and note, with no overlap.
    expect(find.text('Zona nord della città.'), findsOneWidget);
    expect(find.text('Pronta disponibilità nei festivi.'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('hides Relazioni when the squadra has no members and Sintesi when blank', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeAdminApiClient({
        'squadra': {'id': 'sq-2', 'nome': 'Squadra Sud', 'isActive': true},
        'membri': <Map<String, dynamic>>[],
      }),
    );

    expect(find.text('0 membri'), findsOneWidget);
    expect(find.text('Relazioni'), findsNothing);
    expect(find.text('Sintesi'), findsNothing);
    expect(find.text('Attività'), findsNothing);
    // The add-member action still lives in the header, so an empty squadra is not a dead end.
    expect(find.bySemanticsLabel('Aggiungi membro'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('unwraps the "squadra" envelope and shows the lead from the server', (tester) async {
    await _pump(
      tester,
      api: _FakeAdminApiClient({
        'squadra': {
          'id': 'sq-1',
          'nome': 'Squadra Nord',
          'descrizione': 'Zona nord',
          'specializzazione': 'Elettrico',
          'capSquadraNome': 'Mario Rossi',
          'isActive': true,
        },
        'membri': <Map<String, dynamic>>[],
      }, users: const []),
    );

    // Nome/descrizione/specializzazione/lead all come from the unwrapped envelope.
    expect(find.text('Squadra Nord'), findsOneWidget);
    expect(find.text('Zona nord'), findsOneWidget);
    expect(find.text('Lead Mario Rossi · 0 membri · Elettrico'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('an inactive squadra shows INATTIVA', (tester) async {
    await _pump(
      tester,
      api: _FakeAdminApiClient({
        'squadra': {'id': 'sq-3', 'nome': 'Squadra Est', 'isActive': false},
        'membri': <Map<String, dynamic>>[],
      }),
    );

    final hero = find.byKey(const Key('detail-hero-card'));
    expect(find.descendant(of: hero, matching: find.text('INATTIVA')), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('falls back to the list row when the detail request returns nothing', (tester) async {
    await _pump(
      tester,
      api: _FakeAdminApiClient(null),
      squadra: {
        'id': 'sq-flat',
        'nome': 'Squadra Flat',
        'capSquadraNome': 'Luca Bianchi',
        'isActive': true,
      },
    );

    expect(find.text('Squadra Flat'), findsOneWidget);
    expect(find.text('Lead Luca Bianchi · 0 membri'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a missing route extra shows an unavailable state instead of crashing', (
    tester,
  ) async {
    await _pump(tester, api: _FakeAdminApiClient(null), squadra: const {});

    expect(find.text('Squadra non disponibile'), findsOneWidget);
    expect(find.textContaining('Apri la squadra dall'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('has a header action linking to this squadra\'s pianificazioni', (tester) async {
    await _pump(tester, api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()));

    expect(find.bySemanticsLabel('Pianificazioni squadra'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('shows the loading skeleton while the detail request is pending', (tester) async {
    final api = _PendingAdminApiClient();
    await tester.pumpWidget(_buildView(api: api));

    expect(find.byKey(const Key('detail-loading-skeleton')), findsOneWidget);

    api.completer.complete(null);
    await tester.pumpAndSettle();
    await _dispose(tester);
  });

  testWidgets('offline failure names the connection instead of claiming a lost squadra', (
    tester,
  ) async {
    final api = _FailingAdminApiClient();
    await _pump(tester, api: api, online: false);

    expect(find.text('Squadre non disponibili offline'), findsOneWidget);
    expect(find.textContaining('si leggono con la connessione'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('online failure shows the generic retry state', (tester) async {
    final api = _FailingAdminApiClient();
    await _pump(tester, api: api, online: true);

    expect(find.text('Squadra non disponibile'), findsOneWidget);
    expect(find.textContaining('Non è stato possibile caricare'), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the detail route is pushed from Modifica', (tester) async {
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (_, _) =>
              AdminSquadraDetailScreen(squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'}),
        ),
        GoRoute(
          path: '/altro/squadre/:id/modifica',
          builder: (_, state) => Scaffold(body: Text('modifica:${state.pathParameters['id']}')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(
            _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()),
          ),
          isOnlineProvider.overrideWithValue(true),
          cachedEntitlementProvider.overrideWith(
            (ref) => Future.value(_entitlementWith({'team.squadra.write'})),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('detail-hero-card')),
        matching: find.text('Modifica'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('modifica:sq-1'), findsOneWidget);

    await _dispose(tester);
  });

  group('member last-access display (Gap 6)', () {
    late AppDatabase db;
    setUp(() => db = _makeDb());
    tearDown(() async => db.close());

    testWidgets('shows the formatted last-access timestamp for a resolved member', (tester) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await _pump(
        tester,
        db: db,
        api: _FakeAdminApiClient(
          {
            'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord', 'isActive': true},
            'membri': [
              {'userId': 'u1', 'ruolo': 0},
            ],
          },
          users: [
            {'id': 'u1', 'squadraId': 'sq-1', 'lastAccessAt': '2026-08-20T10:30:00Z'},
          ],
        ),
      );

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.textContaining('ULTIMO ACCESSO'), findsWidgets);
      expect(find.textContaining('20/08/2026'), findsOneWidget);

      await _dispose(tester);
    });

    testWidgets('shows "Mai" for a resolved member who has never accessed the app', (tester) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await _pump(
        tester,
        db: db,
        api: _FakeAdminApiClient(
          {
            'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord', 'isActive': true},
            'membri': [
              {'userId': 'u1', 'ruolo': 0},
            ],
          },
          users: [
            {'id': 'u1', 'squadraId': 'sq-1', 'lastAccessAt': null},
          ],
        ),
      );

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.textContaining('ULTIMO ACCESSO: MAI'), findsOneWidget);

      await _dispose(tester);
    });

    testWidgets('omits the last-access line for a member absent from the bulk fetch', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await _pump(
        tester,
        db: db,
        api: _FakeAdminApiClient({
          'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord', 'isActive': true},
          'membri': [
            {'userId': 'u1', 'ruolo': 0},
          ],
        }, users: const []), // u1 not found — unknown, not "never accessed"
      );

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.textContaining('ULTIMO ACCESSO'), findsNothing);
      expect(find.text('MEMBRO'), findsOneWidget);

      await _dispose(tester);
    });
  });

  group('refresh after mutating actions', () {
    // Regression: adminSquadraDetailProvider was a plain FutureProvider.autoDispose.family with
    // no invalidation anywhere in this screen — removing/adding a member succeeded on the server
    // but the list kept showing the pre-mutation membri until the admin left and re-entered.

    testWidgets('removing a member refreshes the list instead of leaving the stale row', (
      tester,
    ) async {
      final api = _StatefulAdminApiClient([
        {'userId': 'u1', 'ruolo': 0},
      ]);

      await _pump(tester, api: api);

      expect(find.text('MEMBRO'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.userMinus));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi'));
      await tester.pumpAndSettle();

      expect(api.removeCalls, 1);
      // If the provider were never invalidated, this would still find the row — the fetch that
      // populated it was never re-run, so the widget tree would be unchanged.
      expect(find.text('Membro non sincronizzato'), findsNothing);
      expect(find.text('Relazioni'), findsNothing);
      expect(find.text('0 MEMBRI'), findsNothing);

      await _dispose(tester);
    });

    testWidgets('adding a member refreshes the list instead of leaving it invisible', (
      tester,
    ) async {
      final api = _StatefulAdminApiClient(const []);

      await _pump(tester, api: api);

      expect(find.text('Relazioni'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Aggiungi membro'));
      await tester.pumpAndSettle();
      // Open the technician dropdown, then pick the one entry the fake exposes.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luigi Bianchi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aggiungi'));
      await tester.pumpAndSettle();

      expect(api.addCalls, 1);
      // If the provider were never invalidated, this would still show the empty state — the new
      // member would exist server-side but never appear on this screen.
      expect(find.text('Relazioni'), findsOneWidget);
      expect(find.text('Luigi Bianchi'), findsOneWidget);

      await _dispose(tester);
    });
  });

  group('add-member picker population & labels', () {
    // Opens the "Aggiungi membro" sheet and expands the user dropdown.
    Future<void> openPicker(WidgetTester tester, AdminApiClient api) async {
      await _pump(tester, api: api);
      await tester.tap(find.bySemanticsLabel('Aggiungi membro'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('offers a non-Technician active user, same population as the list screen', (
      tester,
    ) async {
      await openPicker(tester, _PickerPopulationApiClient());

      // The Office user is only in `fetchAllUsersWithSquadraInfo` — finding it proves the picker
      // reads the list screen's population, not the old role-filtered `fetchTechnicians()`.
      expect(find.text('Paolo Verdi'), findsWidgets);
      expect(find.text('Daniel Rossi'), findsWidgets);

      await _dispose(tester);
    });

    testWidgets('never labels a nameless user with their email address', (tester) async {
      await openPicker(tester, _PickerPopulationApiClient());

      // Still offered (not dropped), but under a neutral label — never the raw email.
      expect(find.text('ghost@tasktap.io'), findsNothing);
      expect(find.text('Utente senza nome'), findsWidgets);

      await _dispose(tester);
    });
  });

  testWidgets('320px: the detail does not overflow with real Italian strings', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      api: _FakeAdminApiClient(
        {
          'squadra': {
            'id': 'sq-1',
            'nome': 'Squadra Manutenzione Nord Est',
            'descrizione': 'Manutenzione ordinaria e straordinaria degli impianti elettrici.',
            'specializzazione': 'Impianti elettrici industriali',
            'note': 'Pronta disponibilità nei festivi e reperibilità notturna.',
            'capSquadraNome': 'Alessandro Maria Della Valle',
            'isActive': true,
          },
          'membri': [
            {'userId': 'u1', 'ruolo': 1},
            {'userId': 'u2', 'ruolo': 0},
          ],
        },
        users: [
          {'id': 'u1', 'displayName': 'Alessandro Maria Della Valle'},
          {'id': 'u2', 'displayName': 'Giovanni Battista Stradivari'},
        ],
      ),
    );

    expect(tester.takeException(), isNull);

    await _dispose(tester);
  });

  // Regression for c6a3a5b8: the squadra detail lost its `team.squadra.write` guards.
  group('capability gates', () {
    testWidgets('without team.squadra.write every write action is withheld', (tester) async {
      await _pump(
        tester,
        api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()),
        capabilities: const {'pianificazione.schedule.read'},
      );

      expect(find.text('Non hai i permessi per questa azione.'), findsOneWidget);
      expect(find.bySemanticsLabel('Aggiungi membro'), findsNothing);
      expect(find.byIcon(LucideIcons.userMinus), findsNothing);
      // The read-only pianificazioni link is not a write and stays when its own read capability is
      // held.
      expect(find.bySemanticsLabel('Pianificazioni squadra'), findsOneWidget);

      await _dispose(tester);
    });

    testWidgets('without pianificazione.schedule.read the pianificazioni link is withheld', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()),
        capabilities: const {'team.squadra.write'},
      );

      // `/altro/pianificazioni` would redirect to /forbidden without the read capability, so the
      // header action is hidden rather than left to dead-end.
      expect(find.bySemanticsLabel('Pianificazioni squadra'), findsNothing);
      // The write action is independent of it.
      expect(find.bySemanticsLabel('Aggiungi membro'), findsOneWidget);

      await _dispose(tester);
    });

    testWidgets('with team.squadra.write Modifica is enabled and members are actionable', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeAdminApiClient(_prototypeDetail(), users: _prototypeUsers()),
        capabilities: const {'team.squadra.write'},
      );

      expect(find.text('Non hai i permessi per questa azione.'), findsNothing);
      expect(find.bySemanticsLabel('Aggiungi membro'), findsOneWidget);
      expect(find.byIcon(LucideIcons.userMinus), findsWidgets);

      await _dispose(tester);
    });
  });
}

// dart format width=100
// test/features/admin/squadre/admin_squadra_detail_screen_test.dart
//
// Three things regression-tested here:
//   1. GET /api/squadre/{id} wraps the squadra's own fields under a "squadra" key
//      (backend record SquadraDetailResponse(Squadra, Membri)) — reading fields off the
//      un-unwrapped envelope left nome/descrizione/specializzazione blank on every real fetch.
//   2. The backend derives capSquadraNome on every /api/squadre/{id} response
//      (PopulateCapiSquadraAsync) but mobile never displayed it — item 8b of the audit.
//   3. Gap 6 of the feature audit: `User.LastAccessAt` is a real column returned on every
//      `/api/users` response but was surfaced nowhere on mobile — the member row now shows it,
//      derived from the same bulk `allUsersWithSquadraProvider` fetch the list screen uses for
//      member counts (Gap 7), not a live per-member call.
//   4. Gap 9: a header action links to this squadra's own schedule, pre-filtered.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
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
  Future<List<Map<String, dynamic>>> fetchAllUsersWithSquadraInfo({
    bool activeOnly = true,
  }) async => _users;
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _buildView({
  required Map<String, dynamic>? detail,
  required Map<String, dynamic> squadra,
  List<Map<String, dynamic>>? users,
  AppDatabase? db,
}) {
  return ProviderScope(
    overrides: [
      adminApiClientProvider.overrideWithValue(_FakeAdminApiClient(detail, users: users)),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
    ],
    child: MaterialApp(home: AdminSquadraDetailScreen(squadra: squadra)),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  testWidgets('unwraps the "squadra" envelope and shows capo squadra name', (tester) async {
    await tester.pumpWidget(
      _buildView(
        detail: {
          'squadra': {
            'id': 'sq-1',
            'nome': 'Squadra Nord',
            'descrizione': 'Zona nord',
            'specializzazione': 'Elettrico',
            'capSquadraNome': 'Mario Rossi',
          },
          'membri': <Map<String, dynamic>>[],
        },
        squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
      ),
    );
    await tester.pumpAndSettle();

    // Nome/descrizione/specializzazione all come from the unwrapped envelope.
    expect(find.text('Zona nord'), findsOneWidget);
    expect(find.text('Elettrico'), findsWidgets);
    // The new capo-squadra row.
    expect(find.text('CAPO SQUADRA'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('falls back to em-dash when no capo squadra is assigned', (tester) async {
    await tester.pumpWidget(
      _buildView(
        detail: {
          'squadra': {'id': 'sq-2', 'nome': 'Squadra Sud', 'specializzazione': 'Idraulico'},
          'membri': <Map<String, dynamic>>[],
        },
        squadra: {'id': 'sq-2', 'nome': 'Squadra Sud'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CAPO SQUADRA'), findsOneWidget);
    expect(find.text('—'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('has a header action linking to this squadra\'s pianificazioni', (tester) async {
    await tester.pumpWidget(
      _buildView(
        detail: {
          'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord'},
          'membri': <Map<String, dynamic>>[],
        },
        squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Pianificazioni squadra'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  group('member last-access display (Gap 6)', () {
    late AppDatabase db;
    setUp(() => db = _makeDb());
    tearDown(() async => db.close());

    testWidgets('shows the formatted last-access timestamp for a resolved member', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await tester.pumpWidget(
        _buildView(
          db: db,
          detail: {
            'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord'},
            'membri': [
              {'userId': 'u1', 'ruolo': 0},
            ],
          },
          squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
          users: [
            {'id': 'u1', 'squadraId': 'sq-1', 'lastAccessAt': '2026-08-20T10:30:00Z'},
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ultimo accesso:'), findsOneWidget);
      expect(find.textContaining('20/08/2026'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows "Mai" for a resolved member who has never accessed the app', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await tester.pumpWidget(
        _buildView(
          db: db,
          detail: {
            'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord'},
            'membri': [
              {'userId': 'u1', 'ruolo': 0},
            ],
          },
          squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
          users: [
            {'id': 'u1', 'squadraId': 'sq-1', 'lastAccessAt': null},
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ultimo accesso: Mai'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('omits the last-access line for a member absent from the bulk fetch', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));

      await tester.pumpWidget(
        _buildView(
          db: db,
          detail: {
            'squadra': {'id': 'sq-1', 'nome': 'Squadra Nord'},
            'membri': [
              {'userId': 'u1', 'ruolo': 0},
            ],
          },
          squadra: {'id': 'sq-1', 'nome': 'Squadra Nord'},
          users: const [], // u1 not found — unknown, not "never accessed"
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ultimo accesso'), findsNothing);
      expect(find.text('Membro'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

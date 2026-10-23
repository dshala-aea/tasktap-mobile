// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/ferie/ferie_permessi_list_screen.dart';

class _FakeAbsenceRequestApiClient extends AbsenceRequestApiClient {
  _FakeAbsenceRequestApiClient(this._items) : super(Dio());

  List<AbsenceRequestDto> _items;
  final List<String> cancelledCalls = [];
  Object? throwOnCancel;
  Object? throwOnFetch;

  @override
  Future<List<AbsenceRequestDto>> fetchMine() async {
    if (throwOnFetch != null) throw throwOnFetch!;
    return _items;
  }

  @override
  Future<void> cancel(String id) async {
    cancelledCalls.add(id);
    if (throwOnCancel != null) throw throwOnCancel!;
    _items = [
      for (final it in _items)
        if (it.id == id)
          AbsenceRequestDto(
            id: it.id,
            requestedByUserId: it.requestedByUserId,
            createdByUserId: it.createdByUserId,
            type: it.type,
            startDate: it.startDate,
            endDate: it.endDate,
            status: 3, // Cancelled
          )
        else
          it,
    ];
  }
}

AbsenceRequestDto _request({
  required String id,
  int type = 0,
  int status = 0,
}) => AbsenceRequestDto(
  id: id,
  requestedByUserId: 'user-1',
  createdByUserId: 'user-1',
  type: type,
  startDate: DateTime(2026, 9, 10),
  endDate: DateTime(2026, 9, 12),
  status: status,
);

/// A fresh in-memory database per test, closed at teardown.
AppDatabase _newDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// Puts one request in the device's mirror — what the sync would have written.
Future<void> _seedMirror(
  AppDatabase db, {
  String id = 'mirror-1',
  int type = 0,
  int status = 0,
  String startDate = '2026-10-22',
  String endDate = '2026-10-24',
}) => db
    .into(db.absenceRequests)
    .insert(
      AbsenceRequestsCompanion.insert(
        id: id,
        requestedByUserId: 'user-1',
        createdByUserId: 'user-1',
        type: type,
        startDate: startDate,
        endDate: endDate,
        status: status,
        createdAt: DateTime.utc(2026, 10, 20, 9),
      ),
    );

Widget _buildScreen(
  _FakeAbsenceRequestApiClient fake, {
  required AppDatabase db,
  bool online = true,
}) {
  return ProviderScope(
    overrides: [
      absenceRequestApiClientProvider.overrideWithValue(fake),
      appDatabaseProvider.overrideWithValue(db),
      // Cancel goes through ensureOnlineOrWarn (the same guard the sibling create flow uses) —
      // without these, the unoverridden real providers resolve as offline/unknown in the test
      // harness and every cancel silently no-ops before it reaches the fake client.
      isOnlineProvider.overrideWithValue(online),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(home: FeriePermessiListScreen()),
  );
}

/// Drift's stream subscriptions schedule a zero-duration timer when they close, and the
/// `autoDispose` freshness provider is cancelled when the scope goes away. Unmounting inside the
/// test body lets that timer fire instead of tripping "A Timer is still pending" at teardown.
Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('renders requests the client returns', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1'), _request(id: 'ar-2', type: 1)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('Ferie'), findsOneWidget);
    expect(find.text('Permesso'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('a ROL request reads ROL, not the last label in the list', (tester) async {
    // The label list used to stop at Malattia and clamp: every type added after it — ROL, ex
    // festività, the permesso variants, Legge 104 — rendered as "Malattia".
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', type: 3)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('ROL'), findsOneWidget);
    expect(find.text('Malattia'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('empty list shows an empty state', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([]);
    final db = _newDb();

    await tester.pumpWidget(_buildScreen(fake, db: db));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna richiesta'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('offline answers from the synced mirror instead of an online-only card', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient([]);
    final db = _newDb();
    await _seedMirror(db, type: 5, status: 1);

    await tester.pumpWidget(_buildScreen(fake, db: db, online: false));
    await tester.pumpAndSettle();

    expect(find.text('Permesso retribuito'), findsOneWidget);
    expect(find.text('Ferie e permessi non disponibili offline'), findsNothing);
    expect(find.text('Impossibile caricare i dati'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('offline on a device that has never synced says the list was never downloaded', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient([]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb(), online: false));
    await tester.pumpAndSettle();

    expect(find.text('Richieste non ancora scaricate'), findsOneWidget);
    expect(
      find.text('Nessuna richiesta'),
      findsNothing,
      reason: 'an empty mirror is a missing download, not a fact about the technician',
    );
    await _disposeScreen(tester);
  });

  testWidgets('a real failure keeps the red error card', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([])..throwOnFetch = Exception('boom');

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile caricare i dati'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('a Rejected request has no cancel affordance', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', status: 2)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('swiping a Pending request then confirming cancels it', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Annullare la richiesta?'), findsOneWidget);
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['ar-1']);
    await _disposeScreen(tester);
  });

  testWidgets('a failed cancel surfaces a message rather than failing silently', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')])
      ..throwOnCancel = Exception('boom');

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['ar-1']);
    expect(find.text('Impossibile annullare la richiesta. Riprova.'), findsOneWidget);
    await _disposeScreen(tester);
  });
}

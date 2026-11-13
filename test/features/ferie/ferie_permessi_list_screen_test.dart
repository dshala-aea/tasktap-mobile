// dart format width=100
import 'dart:ui' show SemanticsAction;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/core/widgets/list/list_filter_row.dart';
import 'package:tasktap_mobile/features/ferie/ferie_permessi_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

class _FakeAbsenceRequestApiClient extends AbsenceRequestApiClient {
  _FakeAbsenceRequestApiClient(this._items) : super(Dio());

  List<AbsenceRequestDto> _items;
  final List<String> cancelledCalls = [];
  Object? throwOnCancel;
  Object? throwOnFetch;

  /// What the last read put on the wire: the screen is the technician's own history, so this must
  /// be their internal id — an unscoped read is the whole tenant for an approve-holder.
  String? lastUserId;

  @override
  Future<List<AbsenceRequestDto>> fetchMine({String? userId}) async {
    lastUserId = userId;
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
  String startDate = '2026-09-10',
  String endDate = '2026-09-12',
  String? startTime,
  String? endTime,
}) {
  final start = DateTime.parse(startDate);
  final end = DateTime.parse(endDate);
  return AbsenceRequestDto(
    id: id,
    requestedByUserId: 'user-1',
    createdByUserId: 'user-1',
    type: type,
    startDate: start,
    endDate: end,
    startTime: startTime,
    endTime: endTime,
    status: status,
  );
}

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

Future<void> _seedColleague(AppDatabase db, {String id = 'user-1', String name = 'Daniel Shala'}) =>
    db.into(db.colleagues).insert(ColleaguesCompanion.insert(id: id, displayName: name));

Widget _buildScreen(
  _FakeAbsenceRequestApiClient fake, {
  required AppDatabase db,
  bool online = true,
  List<Override> extraOverrides = const [],
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
      ...extraOverrides,
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

/// The quick chip row also contains a stamp with the same uppercase label, so scope chip finders
/// to the filter row instead of matching the whole tree.
Finder _chip(String label) =>
    find.descendant(of: find.byType(ListFilterRow), matching: find.text(label));

/// The screen opens on the prototype's `In attesa` preset, so tests that need the whole history
/// first switch to `Tutte`.
Future<void> _showAll(WidgetTester tester) async {
  await tester.tap(_chip('TUTTE'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  setUp(() {
    // The real provider reads the signed-in user's internal id from prefs on every read.
    SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
  });

  testWidgets('opens with In attesa active, like the prototype', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', status: 0),
      _request(id: 'ar-2', status: 1),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Approvate'), findsNothing);
    expect(_chip('IN ATTESA'), findsOneWidget);
    expect(find.text('1 RICHIESTA'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('renders requests the client returns, grouped by status', (tester) async {
    final db = _newDb();
    await _seedColleague(db);
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1'),
      _request(id: 'ar-2', type: 1),
      _request(id: 'ar-3', status: 1, startDate: '2026-09-20', endDate: '2026-09-22'),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: db));
    await tester.pumpAndSettle();
    await _showAll(tester);

    // The row title is the person; this screen only ever reads the caller's own requests.
    expect(find.text('Daniel Shala'), findsNWidgets(3));
    expect(find.textContaining('Ferie ·'), findsNWidgets(2));
    expect(find.textContaining('Permesso ·'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget); // group heading
    expect(find.text('Approvate'), findsOneWidget); // group heading
    expect(_chip('IN ATTESA'), findsOneWidget);
    expect(_chip('APPROVATE'), findsOneWidget);
    expect(find.text('3 RICHIESTE'), findsOneWidget);
    expect(find.text('2 IN ATTESA'), findsOneWidget);
    expect(
      fake.lastUserId,
      'user-1',
      reason:
          'the list is always scoped to the caller: an omitted userId is the whole tenant for '
          'an approve-holder, rendered with no requester per row',
    );
    await _disposeScreen(tester);
  });

  testWidgets('an unknown caller id never asks unscoped', (tester) async {
    // Before the device has ever reached /api/Auth/me (or after a consented sign-out wiped prefs)
    // there is no self to scope to. Issuing the request anyway would be answered with the tenant,
    // so the provider must answer from the device's own mirror instead.
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(
      fake.lastUserId,
      isNull,
      reason: 'no request may go out for an unknown caller — omitted userId means "everyone" here',
    );
    expect(find.text('Richieste non ancora scaricate'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('a ROL request reads ROL, not the last label in the list', (tester) async {
    // The label list used to stop at Malattia and clamp: every type added after it — ROL, ex
    // festività, the permesso variants, Legge 104 — rendered as "Malattia".
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', type: 3)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.textContaining('ROL'), findsOneWidget);
    expect(find.textContaining('Malattia'), findsNothing);
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
    await _showAll(tester);

    expect(find.textContaining('Permesso retribuito'), findsOneWidget);
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
    await _showAll(tester);

    expect(find.byType(Dismissible), findsNothing);
    expect(find.text('Annulla'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('a cancelled request is grouped as Annullate and cannot be cancelled again', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', status: 3)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await _showAll(tester);

    expect(find.text('Annullate'), findsOneWidget);
    expect(find.text('ANNULLATA'), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('the status chips filter the groups and the summary', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', status: 0),
      _request(id: 'ar-2', status: 1),
      _request(id: 'ar-3', status: 2),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await _showAll(tester);

    await tester.tap(_chip('IN ATTESA'));
    await tester.pumpAndSettle();

    expect(find.text('In attesa'), findsOneWidget); // group heading
    expect(find.text('Approvate'), findsNothing);
    expect(find.text('Respinte'), findsNothing);
    expect(find.text('1 RICHIESTA'), findsOneWidget);
    expect(find.text('1 IN ATTESA'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('the Filtri sheet filters by status and type, and Azzera clears it', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', status: 0, type: 0),
      _request(id: 'ar-2', status: 1, type: 1),
      _request(id: 'ar-3', status: 2, type: 0),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
    expect(find.text('Restringi per stato, tipo e periodo.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ferie-filter-status-approvate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    expect(find.text('Approvate'), findsOneWidget);
    expect(find.text('In attesa'), findsNothing);
    expect(find.text('Respinte'), findsNothing);

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ferie-filter-reset')));
    await tester.pumpAndSettle();

    // Azzera returns to the prototype default, not to an all-status view.
    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Approvate'), findsNothing);
    expect(find.text('Respinte'), findsNothing);

    await _showAll(tester);
    expect(find.text('In attesa'), findsOneWidget);
    expect(find.text('Approvate'), findsOneWidget);
    expect(find.text('Respinte'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('the Tipo facet keeps Ferie and the permesso family apart', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', type: 0),
      _request(id: 'ar-2', type: 5),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ferie-filter-type-permesso')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permesso retribuito'), findsOneWidget);
    expect(find.textContaining('Ferie ·'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('search matches the type and period', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', type: 0, startDate: '2026-09-10', endDate: '2026-09-12'),
      _request(id: 'ar-2', type: 3, startDate: '2026-10-01', endDate: '2026-10-01'),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ROL');
    await tester.pumpAndSettle();

    expect(find.textContaining('ROL ·'), findsOneWidget);
    expect(find.textContaining('Ferie ·'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('Nuovo is a header action and the FAB is gone', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('NUOVO'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('the inline Annulla action opens the same confirmation as a swipe', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(find.text('Annullare la richiesta?'), findsOneWidget);
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['ar-1']);
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

  testWidgets('the list does not overflow at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await _disposeScreen(tester);
  });

  testWidgets('the person line reads the persisted id fresh, not the cached provider', (
    tester,
  ) async {
    final db = _newDb();
    await _seedColleague(db);
    await _seedColleague(db, id: 'stale-user', name: 'Vecchio Utente');
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(
      _buildScreen(
        fake,
        db: db,
        // The cached FutureProvider is the documented stale-id trap after a forced sign-out; the
        // screen must use the persisted key instead.
        extraOverrides: [internalUserIdProvider.overrideWith((ref) async => 'stale-user')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daniel Shala'), findsOneWidget);
    expect(find.text('Vecchio Utente'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('falls back to a neutral title when the colleague mirror has no name', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.text('Le mie richieste'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('sheet controls expose a semantic tap action', (tester) async {
    final handle = tester.ensureSemantics();
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    final choice = tester.getSemantics(find.byKey(const Key('ferie-filter-status-inAttesa')));
    expect(choice.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    final date = tester.getSemantics(find.byKey(const Key('ferie-filter-from')));
    expect(date.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
    await _disposeScreen(tester);
  });

  testWidgets('the Periodo facet opens the date picker', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ferie-filter-from')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('a DST-spanning two-day request renders 2 giorni', (tester) async {
    // 29–30 March 2026 is the Europe/Rome spring-forward: a local-midnight difference is 23h and
    // truncates to "1 giorno". The UI must count civil days, not elapsed hours.
    final fake = _FakeAbsenceRequestApiClient([
      _request(id: 'ar-1', startDate: '2026-03-29', endDate: '2026-03-30'),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 giorni'), findsOneWidget);
    expect(find.textContaining('1 giorno'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('a multi-day request with times renders days, not hours', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([
      _request(
        id: 'ar-1',
        startDate: '2026-03-29',
        endDate: '2026-03-31',
        startTime: '09:00:00',
        endTime: '11:00:00',
      ),
    ]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 giorni'), findsOneWidget);
    expect(find.textContaining('2 ore'), findsNothing);
    await _disposeScreen(tester);
  });

  testWidgets('selecting Annullate from the sheet shows a visible preset', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', status: 3)]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await _showAll(tester);
    expect(find.text('Annullate'), findsOneWidget);

    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ferie-filter-status-annullate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();

    expect(_chip('ANNULLATE'), findsOneWidget);
    expect(find.text('Annullate'), findsOneWidget);
    await _disposeScreen(tester);
  });

  testWidgets('the filter sheet does not overflow at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake, db: _newDb()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FILTRI'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Applica'), findsOneWidget);
    await _disposeScreen(tester);
  });

  group('absenceRequestOverlapsPeriod', () {
    final item = _request(id: 'ar-1', startDate: '2026-11-10', endDate: '2026-11-12');

    test('keeps everything when no period is set', () {
      expect(absenceRequestOverlapsPeriod(item), isTrue);
    });

    test('keeps a request intersecting either boundary', () {
      expect(
        absenceRequestOverlapsPeriod(
          item,
          from: DateTime(2026, 11, 12),
          to: DateTime(2026, 11, 20),
        ),
        isTrue,
      );
      expect(
        absenceRequestOverlapsPeriod(item, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 10)),
        isTrue,
      );
    });

    test('drops a disjoint request', () {
      expect(
        absenceRequestOverlapsPeriod(
          item,
          from: DateTime(2026, 11, 13),
          to: DateTime(2026, 11, 20),
        ),
        isFalse,
      );
      expect(
        absenceRequestOverlapsPeriod(item, from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 9)),
        isFalse,
      );
    });

    test('honours an open-ended period', () {
      expect(absenceRequestOverlapsPeriod(item, from: DateTime(2026, 11, 12)), isTrue);
      expect(absenceRequestOverlapsPeriod(item, to: DateTime(2026, 11, 9)), isFalse);
    });
  });
}

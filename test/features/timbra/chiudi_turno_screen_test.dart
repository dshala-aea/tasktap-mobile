// test/features/timbra/chiudi_turno_screen_test.dart
//
// Widget tests for ChiudiTurnoScreen — the end-of-session flow relocated off
// `_ActiveSessionBody`'s old in-place "Note di chiusura" bottom sheet + immediate `onEnd` call.
// These exercise the exact GPS-purpose/offline-fallback/error-humanising behaviour
// cantiere_timbra_screen_test.dart used to cover on `_handleEndCantiere` before it moved here —
// see chiudi_turno_screen.dart's own header comment on why this is a relocation, not a rewrite.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/chiudi_turno_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeLocationService extends ILocationService {
  @override
  Future<GpsCoords?> getCurrentPosition() async => (lat: 45.4654, lng: 9.1859, accuracy: 10.0);
}

class _FakeApiClient extends CantiereWorklogApiClient {
  _FakeApiClient({this.endShouldThrow = false, this.endErrorStatusCode}) : super(Dio());

  final bool endShouldThrow;

  /// When set, the thrown DioException carries a response with this status code instead of being
  /// a bare connection error — exercises the "server answered, don't fall back to the queue" path.
  final int? endErrorStatusCode;

  final List<EndCantiereRequest?> endRequests = [];
  final List<List<CantiereMobileSessionDto>> upsertCalls = [];

  // Overridden so ChiudiTurnoScreen's own `activeCantiereLogProvider.notifier` read (to call
  // `clearActive()` on a successful end) doesn't fall through to the real base implementation's
  // network call — with no baseUrl configured that hangs for a very long default timeout instead
  // of failing fast, which is what made this fake necessary in the original
  // cantiere_timbra_screen_test.dart's own `_FakeApiClient` too.
  @override
  Future<List<CantiereWorkLogDto>> getActive() async => [];

  @override
  Future<void> endCantiere([EndCantiereRequest? request]) async {
    if (endShouldThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cantiereworklog/end'),
        type: endErrorStatusCode == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
        response: endErrorStatusCode == null
            ? null
            : Response(
                requestOptions: RequestOptions(path: '/api/cantiereworklog/end'),
                statusCode: endErrorStatusCode,
              ),
      );
    }
    endRequests.add(request);
  }

  @override
  Future<List<CantiereMobileSessionResult>> upsertSessions(
    List<CantiereMobileSessionDto> sessions,
  ) async {
    upsertCalls.add(List.of(sessions));
    return sessions
        .map(
          (s) => CantiereMobileSessionResult(
            clientId: s.clientId,
            cantiereWorkLogId: 'wl-${s.clientId}',
            startTime: s.startTime,
            endTime: s.endTime,
            isActive: s.endTime == null,
          ),
        )
        .toList();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Pumps a placeholder "Home" screen with a button that pushes ChiudiTurnoScreen, matching how
/// `_ActiveSessionBody` really reaches it (`Navigator.push`, not a named route — see that
/// button's own doc comment). Lets a successful end's `Navigator.pop()` land somewhere real,
/// instead of popping a test harness's only route.
Widget _buildHarness({
  required AppDatabase db,
  required _FakeApiClient apiClient,
  ILocationService? locationService,
  String cantiereId = 'cant-1',
  String? ticketId,
  DateTime? startTime,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cantiereWorklogApiClientProvider.overrideWithValue(apiClient),
      locationServiceProvider.overrideWithValue(locationService ?? _FakeLocationService()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChiudiTurnoScreen(
                    cantiereId: cantiereId,
                    ticketId: ticketId,
                    startTime: startTime ?? DateTime.now().toUtc().subtract(const Duration(hours: 1)),
                  ),
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openChiudiTurno(WidgetTester tester) async {
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  Future<void> seedCantiere(AppDatabase db) => db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: 'cant-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Cantiere Via Roma',
        ),
      );

  testWidgets('renders the session summary and both closing fields', (tester) async {
    await seedCantiere(db);
    final api = _FakeApiClient();
    await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
    await _openChiudiTurno(tester);

    expect(find.text('Timbra uscita'), findsOneWidget);
    expect(find.text('Cantiere Via Roma'), findsOneWidget);
    // AppFieldLabel uppercases its text (see app_text_field.dart) — the field labels render as
    // "LAVORO SVOLTO" / "NOTE DI SICUREZZA", not title case.
    expect(find.text('LAVORO SVOLTO'), findsOneWidget);
    expect(find.text('NOTE DI SICUREZZA'), findsOneWidget);
    expect(find.text('Conferma uscita'), findsOneWidget);
    expect(find.text('Esci senza aggiungere note'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('shows the passive departure GPS indicator', (tester) async {
    await seedCantiere(db);
    final api = _FakeApiClient();
    await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
    await _openChiudiTurno(tester);

    expect(find.text('Posizione rilevata automaticamente'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('Conferma uscita sends the typed notes and pops back on success', (tester) async {
    await seedCantiere(db);
    final api = _FakeApiClient();
    await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
    await _openChiudiTurno(tester);

    // Two AppTextField.multiline in order — Lavoro svolto, then Note di sicurezza (the label sits
    // above each field as its own Text, not inside the TextFormField's decoration — see
    // app_text_field.dart's own doc comment — so these are found by position, not by label text).
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Sostituito filtro');
    await tester.enterText(fields.at(1), 'Nessuna anomalia');

    await tester.tap(find.text('Conferma uscita'));
    await tester.pumpAndSettle();

    expect(api.endRequests, hasLength(1));
    expect(api.endRequests.single?.description, 'Sostituito filtro');
    expect(api.endRequests.single?.safetyNotes, 'Nessuna anomalia');
    expect(api.endRequests.single?.departureLatitude, 45.4654);

    // Popped back to the harness's own "apri" button.
    expect(find.text('apri'), findsOneWidget);
    expect(find.text('Uscita cantiere registrata con successo.'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
    '"Esci senza aggiungere note" discards whatever is typed and still ends the session',
    (tester) async {
      await seedCantiere(db);
      final api = _FakeApiClient();
      await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
      await _openChiudiTurno(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'testo che non deve essere inviato',
      );

      await tester.tap(find.text('Esci senza aggiungere note'));
      await tester.pumpAndSettle();

      expect(api.endRequests, hasLength(1));
      expect(api.endRequests.single?.description, isNull);
      expect(api.endRequests.single?.safetyNotes, isNull);
      expect(find.text('apri'), findsOneWidget);

      await _teardown(tester);
    },
  );

  testWidgets(
    'connection error queues the end event locally and still pops, with a warning toast',
    (tester) async {
      await seedCantiere(db);
      // A real "uscita" queued offline always closes a real open "ingresso" already in the local
      // queue (this screen is only ever reached from an active session) — without one,
      // assembleCantiereIntervals() has nothing to close and CantiereTimbraSyncService's own
      // syncNow() has no interval to upsert at all, which isn't the scenario this test means to
      // cover.
      await db
          .into(db.cantierePunches)
          .insert(
            CantierePunchesCompanion.insert(
              id: 'e-ingresso',
              eventTime: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
              eventType: 'ingresso',
              cantiereId: const Value('cant-1'),
              // assembleCantiereIntervals() drops an interval with no customerId carried from its
              // opening event (see that function's own closeOpen() null-guard) — without this the
              // sync push silently has nothing to send.
              customerId: const Value('cust-1'),
            ),
          );
      final api = _FakeApiClient(endShouldThrow: true);
      await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
      await _openChiudiTurno(tester);

      await tester.tap(find.text('Conferma uscita'));
      await tester.pumpAndSettle();
      // The queued event's own background sync is fire-and-forget (`unawaited(...syncNow())` —
      // see chiudi_turno_screen.dart) and goes through Drift's real async isolate round-trip, which
      // `pumpAndSettle()` alone doesn't reliably wait out — same race
      // cantiere_timbra_screen_test.dart's own offline check-in test documents. A couple of fixed
      // pumps drain it.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Uscita registrata offline: verrà inviata al ritorno della connessione.'),
        findsOneWidget,
      );
      expect(find.text('apri'), findsOneWidget);

      final events = await (db.select(db.cantierePunches)).get();
      expect(events.where((e) => e.eventType == 'uscita'), hasLength(1));
      expect(api.upsertCalls, isNotEmpty);

      await _teardown(tester);
    },
  );

  testWidgets(
    'a server-answered error (not a reachability failure) surfaces inline instead of queueing',
    (tester) async {
      await seedCantiere(db);
      final api = _FakeApiClient(endShouldThrow: true, endErrorStatusCode: 404);
      await tester.pumpWidget(_buildHarness(db: db, apiClient: api));
      await _openChiudiTurno(tester);

      await tester.tap(find.text('Conferma uscita'));
      await tester.pumpAndSettle();

      expect(find.text('Nessuna sessione cantiere attiva trovata.'), findsOneWidget);
      // Stayed on screen — a 404 is a real answer, not a reachability failure to queue past.
      expect(find.text('apri'), findsNothing);
      expect(find.text('Conferma uscita'), findsOneWidget);

      final events = await (db.select(db.cantierePunches)).get();
      expect(events, isEmpty);

      await _teardown(tester);
    },
  );
}

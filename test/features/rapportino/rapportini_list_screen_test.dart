// dart format width=100
// test/features/rapportino/rapportini_list_screen_test.dart
//
// Widget tests for RapportiniListScreen (D3b-2).
//
// Covers:
//   1. Renders ListRows from seeded drafts.
//   2. Filter chip "Bozza" narrows results.
//   3. EmptyState shown when no drafts.
//   4. AppFab is present.
//   5. Submitted draft tap navigates to view route (not editor).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/data/reports/server_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';
import 'package:tasktap_mobile/features/rapportino/rapportini_list_screen.dart';

import '../../data/reports/server_report_dto_test.dart' show backendFixture;

class _FakeServerApi extends ServerReportApiClient {
  _FakeServerApi({this.fail = false, this.stato = 0, this.delay = Duration.zero}) : super(Dio());
  final bool fail;
  final int stato;
  final Duration delay;
  int calls = 0;
  @override
  Future<ServerReportDto> fetchReport(String reportId) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw DioException(requestOptions: RequestOptions(path: '/x'));
    return ServerReportDto.fromJson({...backendFixture(), 'id': reportId, 'stato': stato});
  }
}

class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _buildRouted({required AppDatabase db, required ServerReportApiClient api}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const RapportiniListScreen()),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        builder: (_, s) => Scaffold(body: Text('editor:${s.pathParameters['reportId']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      syncProvider.overrideWith((ref) => _NoopSync(db)),
      serverReportApiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class MockDio extends Mock implements Dio {}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedDraft(
  AppDatabase db, {
  required String id,
  String title = 'Rapportino di test',
  String submissionState = 'draft',
  String stato = 'Bozza',
  bool isLocalOnly = true,
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: title,
          insertedUserId: 'user-1',
          locationId: 'loc-1',
          isLocalOnly: Value(isLocalOnly),
          stato: Value(stato),
          submissionState: Value(submissionState),
        ),
      );
}

Widget _buildList({required AppDatabase db}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: RapportiniListScreen()),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('RapportiniListScreen — row rendering', () {
    testWidgets('renders one row per seeded draft, titled', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Intervento idraulico');
      await _seedDraft(db, id: 'draft-2', title: 'Revisione caldaia');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      // Vetro (module #3) replaced ListRow with a bespoke priority-striped row, same as the
      // ticket list — the behaviour that matters is "one row per draft, showing its title."
      expect(find.text('Intervento idraulico'), findsOneWidget);
      expect(find.text('Revisione caldaia'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with Bozza for a draft-state report', (tester) async {
      await _seedDraft(db, id: 'draft-1', submissionState: 'draft');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(StatusPill), findsWidgets);
      // Uppercased by StatusStamp now (Il Documento's stamp device) — see
      // status_pill_test.dart's own note on this rendering change.
      expect(find.text('BOZZA'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with Inviata for a submitted report', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Rapportino inviato',
        submissionState: 'submitted',
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      // Uppercased by StatusStamp now (Il Documento's stamp device) — see
      // status_pill_test.dart's own note on this rendering change.
      expect(find.text('INVIATA'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — opening a server-created Bozza', () {
    testWidgets('imports the full report before opening the editor', (tester) async {
      await _seedDraft(db, id: 'srv-1', title: 'Da server', isLocalOnly: false);

      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Da server'));
      await tester.pumpAndSettle();

      expect(find.text('editor:srv-1'), findsOneWidget);
      expect(await db.select(db.reportStaffTable).get(), hasLength(1));
      final row = await (db.select(db.draftReports)..where((r) => r.id.equals('srv-1'))).getSingle();
      expect(row.diagnosi, 'Pompa bloccata');
      expect(row.isLocalOnly, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a failed import shows an error and does not open a blank editor', (tester) async {
      await _seedDraft(db, id: 'srv-1', title: 'Da server', isLocalOnly: false);

      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi(fail: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Da server'));
      await tester.pumpAndSettle();

      expect(find.textContaining('serve la connessione'), findsOneWidget);
      expect(find.text('editor:srv-1'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a server report no longer Bozza says so, not "serve la connessione"', (
      tester,
    ) async {
      await _seedDraft(db, id: 'srv-1', title: 'Da server', isLocalOnly: false);

      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi(stato: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Da server'));
      await tester.pumpAndSettle();

      expect(find.text('Questo rapportino non è più modificabile.'), findsOneWidget);
      expect(find.textContaining('serve la connessione'), findsNothing);
      expect(find.text('editor:srv-1'), findsNothing);
      expect(await db.select(db.reportStaffTable).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('two fast taps run ONE import', (tester) async {
      await _seedDraft(db, id: 'srv-1', title: 'Da server', isLocalOnly: false);
      final api = _FakeServerApi(delay: const Duration(milliseconds: 200));

      await tester.pumpWidget(_buildRouted(db: db, api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Da server'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Da server'));
      await tester.pumpAndSettle();

      expect(api.calls, 1);
      expect(find.text('editor:srv-1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a local draft opens straight away, no import', (tester) async {
      await _seedDraft(db, id: 'loc-1', title: 'Locale');

      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi(fail: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locale'));
      await tester.pumpAndSettle();

      expect(find.text('editor:loc-1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — filter chip', () {
    testWidgets('filter Bozza shows only bozza drafts', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza A', submissionState: 'draft');
      await _seedDraft(db, id: 'draft-2', title: 'Inviata B', submissionState: 'submitted');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      // Both visible initially under "Tutti"
      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Inviata B'), findsOneWidget);

      // Tap "Bozza" chip
      final bozzaChip = find.widgetWithText(AppChip, 'Bozza').first;
      await tester.ensureVisible(bozzaChip);
      await tester.tap(bozzaChip);
      await tester.pumpAndSettle();

      // Only Bozza A should remain
      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Inviata B'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter Inviata shows only submitted drafts', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza locale', submissionState: 'draft');
      await _seedDraft(db, id: 'draft-2', title: 'Già inviato', submissionState: 'submitted');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      final inviataCip = find.widgetWithText(AppChip, 'Inviata').first;
      await tester.ensureVisible(inviataCip);
      await tester.tap(inviataCip);
      await tester.pumpAndSettle();

      expect(find.text('Già inviato'), findsOneWidget);
      expect(find.text('Bozza locale'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter Pagata shows empty state (no local data yet)', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza A');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      final pagataChip = find.widgetWithText(AppChip, 'Pagata').first;
      await tester.ensureVisible(pagataChip);
      await tester.tap(pagataChip);
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — empty state', () {
    testWidgets('shows EmptyState when no drafts exist', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — FAB', () {
    testWidgets('AppFab is present', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(AppFab), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Item 13: edit/delete now follow the backend's own "before office review" boundary
  // (ReportStateMachine.CanEditOrDelete — Bozza/Inviato/Respinto), not draft-only.
  group('RapportiniListScreen — delete a draft (swipe, before office review)', () {
    late MockDio mockDio;

    setUp(() {
      mockDio = MockDio();
      when(() => mockDio.delete<void>(any())).thenAnswer(
        (_) async => Response<void>(requestOptions: RequestOptions(path: ''), statusCode: 204),
      );
    });

    Widget buildWithDio({required AppDatabase db}) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
      ],
      child: const MaterialApp(home: RapportiniListScreen()),
    );

    testWidgets('swiping a Bozza row and confirming removes it locally', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Da eliminare', submissionState: 'draft');
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Da eliminare'), findsOneWidget);

      await tester.drag(find.text('Da eliminare'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Eliminare il rapportino?'), findsOneWidget);
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(find.text('Da eliminare'), findsNothing);
      expect(await db.select(db.draftReports).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('cancelling the confirmation keeps the row', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Non eliminare', submissionState: 'draft');
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Non eliminare'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(find.text('Non eliminare'), findsOneWidget);
      expect(await db.select(db.draftReports).get(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a report sent but not yet reviewed by the office (Inviato) can still be swiped', (
      tester,
    ) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'In attesa di revisione',
        stato: 'Inviato',
        submissionState: 'submitted',
      );
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a rejected report (Respinto) can still be swiped', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Respinto dall\'ufficio',
        stato: 'Respinto',
        submissionState: 'submitted',
      );
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a report already reviewed by the office (Controllato) has no swipe-to-delete '
        'affordance', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Già controllato',
        stato: 'Controllato',
        submissionState: 'submitted',
      );
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — header', () {
    testWidgets('ScreenHeader shows title Rapportini', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('header subtitle shows totali count', (tester) async {
      await _seedDraft(db, id: 'draft-1');
      await _seedDraft(db, id: 'draft-2');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('2 totali'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

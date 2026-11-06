// dart format width=100
// test/features/admin/reports/admin_report_detail_screen_test.dart
//
// Regression: a "controlla"/"fattura" state transition popped back to the list screen with the
// comment "// Pop to refresh list" — but popping refreshes nothing on its own. adminReportsProvider
// (a .family keyed by the list's stato filter) was never invalidated, so the list kept showing the
// report's pre-transition stato until a manual pull-to-refresh.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_detail_screen.dart';
import 'package:tasktap_mobile/features/admin/reports/admin_report_list_screen.dart';

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient() : super(Dio());

  int controllaCalls = 0;
  int fatturaCalls = 0;

  @override
  Future<void> controllaReport(String reportId) async => controllaCalls++;

  @override
  Future<void> fatturaReport(String reportId) async => fatturaCalls++;
}

void main() {
  setUpAll(() async => initializeDateFormatting('it'));

  testWidgets('renders the shell: Documenti → Sintesi → Attività, Apri PDF, no FAB', (
    tester,
  ) async {
    final api = _FakeAdminApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith(
            (ref, filter) async => const ReportListRows([], fromMirror: false),
          ),
        ],
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => AdminReportDetailScreen(
                report: const {
                  'id': 'r1',
                  'title': 'Rapportino 2026-0412',
                  'stato': 'Inviato',
                  'createdAt': '2026-10-01T08:00:00Z',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apri PDF'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Documenti'), findsOneWidget);
    expect(find.text('Sintesi'), findsOneWidget);
    expect(find.text('Attività'), findsOneWidget);
    expect(find.text('PDF rapporto'), findsOneWidget);
    expect(find.text('Firma cliente'), findsOneWidget);
    expect(find.text('Firma tecnico'), findsOneWidget);
    // The state transition is kept, now inside Attività.
    expect(find.text('Segna come controllato'), findsOneWidget);

    final documenti = tester.getTopLeft(find.text('Documenti')).dy;
    final sintesi = tester.getTopLeft(find.text('Sintesi')).dy;
    final attivita = tester.getTopLeft(find.text('Attività')).dy;
    expect(documenti, lessThan(sintesi));
    expect(sintesi, lessThan(attivita));
  });

  testWidgets('a state transition invalidates adminReportsProvider, not just the pop', (
    tester,
  ) async {
    final api = _FakeAdminApiClient();
    var fetchCalls = 0;

    // `adminReportsProvider` is `.autoDispose` — invalidating it with nothing watching just marks
    // it dirty for whenever it's next read, it does not force an eager re-fetch. The real list
    // screen watches it and stays mounted underneath the detail push (Flutter's Navigator keeps
    // previous routes alive), so a small stand-in watcher, mounted alongside the detail screen
    // the same way, is what actually proves invalidate() forces a re-run — not the pop by itself.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith((ref, filter) async {
            fetchCalls++;
            return const ReportListRows([], fromMirror: false);
          }),
        ],
        child: MaterialApp(
          home: Column(
            children: [
              // Stands in for the real list screen, which stays mounted underneath the detail
              // push (Flutter's Navigator keeps previous routes alive) and is what actually
              // observes the invalidation.
              Consumer(
                builder: (context, ref, _) {
                  ref.watch(adminReportsProvider(const StatoFilter(null)));
                  return const SizedBox.shrink();
                },
              ),
              Expanded(
                child: Navigator(
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    builder: (_) => AdminReportDetailScreen(
                      report: const {'id': 'r1', 'title': 'Rapportino 1', 'stato': 'Inviato'},
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fetchesBeforeTransition = fetchCalls;
    expect(fetchesBeforeTransition, 1);

    final controlla = find.text('Segna come controllato');
    await tester.ensureVisible(controlla);
    await tester.tap(controlla);
    await tester.pumpAndSettle();

    expect(api.controllaCalls, 1);
    expect(fetchCalls, greaterThan(fetchesBeforeTransition));
  });

  testWidgets('the Fattura action stays on this screen showing Fatturato + an XML download action, '
      'instead of popping back to the list', (tester) async {
    await initializeDateFormatting('it', null);
    final api = _FakeAdminApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiClientProvider.overrideWithValue(api),
          adminReportsProvider.overrideWith(
            (ref, filter) async => const ReportListRows([], fromMirror: false),
          ),
        ],
        child: MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => AdminReportDetailScreen(
                report: const {'id': 'r1', 'title': 'Rapportino 1', 'stato': 'Controllato'},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Segna come fatturato'), findsOneWidget);

    final fattura = find.text('Segna come fatturato');
    await tester.ensureVisible(fattura);
    await tester.tap(fattura);
    await tester.pumpAndSettle();

    // Transition fired, but the screen is still here — this used to pop back to the list on
    // its own, which is the reported bug (the office user's next step is usually downloading
    // the XML, not going back to find the row again).
    expect(api.fatturaCalls, 1);
    expect(find.byType(AdminReportDetailScreen), findsOneWidget);
    expect(find.text('Scarica XML fattura'), findsOneWidget);
    expect(find.text('Segna come fatturato'), findsNothing);
  });

  testWidgets('offline detail facts come from the mirror row, including photos', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Rossi Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 11, 1),
            title: 'Perdita acqua sotto il lavello',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );
    await db
        .into(db.colleagues)
        .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Daniel Shala'));
    await db
        .into(db.draftReports)
        .insert(
          DraftReportsCompanion.insert(
            id: 'r1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 11, 3, 8),
            title: 'Rapportino 2026-0412',
            insertedUserId: 'u1',
            locationId: 'loc-1',
            customerId: const Value('cust-1'),
            ticketId: const Value('t1'),
            stato: const Value('Inviato'),
            startedAt: Value(DateTime.utc(2026, 11, 3, 8)),
            endedAt: Value(DateTime.utc(2026, 11, 4, 14)),
            diagnosi: const Value('Guarnizione usurata'),
            soluzione: const Value('Sostituita la guarnizione'),
            technicianNotes: const Value('Accesso dal cortile interno.'),
          ),
        );
    await db
        .into(db.reportAllegati)
        .insert(
          ReportAllegatiCompanion.insert(
            id: 'photo-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 11, 3, 9),
            fileName: 'foto_lavello.jpg',
            contentType: 'image/jpeg',
            sizeBytes: 2048,
            storagePath: '',
            url: '/api/reports/r1/attachments/photo-1/content',
            entityType: 1,
            entityId: 'r1',
            uploadedByUserId: 'u1',
          ),
        );
    await db.setLastSync(DateTime.utc(2026, 11, 5));

    final overrides = [
      appDatabaseProvider.overrideWithValue(db),
      isOnlineProvider.overrideWithValue(false),
    ];
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    final rows = await container.read(adminReportsProvider(const StatoFilter('Inviato')).future);
    final row = rows.rows.single;
    expect(rows.fromMirror, isTrue);
    expect(row['insertedUserId'], 'u1');
    expect(row['diagnosi'], 'Guarnizione usurata');
    expect(row['soluzione'], 'Sostituita la guarnizione');

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: AdminReportDetailScreen(report: row)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rossi Srl · Novembre · 30 ore'), findsOneWidget);
    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
    expect(find.text('Daniel Shala'), findsOneWidget);
    expect(find.text('Guarnizione usurata'), findsOneWidget);
    expect(find.text('Sostituita la guarnizione'), findsOneWidget);
    expect(find.text('Accesso dal cortile interno.'), findsOneWidget);
    expect(find.text('foto_lavello.jpg'), findsOneWidget);

    // The list passes the raw `/api/Reports` row as `extra`; a representative server-shaped map
    // must render the same hero facts as the mirror row above.
    final serverRow = <String, dynamic>{
      'id': 'r1',
      'title': 'Rapportino 2026-0412',
      'numero': '2026-0412',
      'stato': 'Inviato',
      'customerId': 'cust-1',
      'locationId': 'loc-1',
      'ticketId': 't1',
      'insertedUserId': 'u1',
      'createdAt': '2026-11-03T08:00:00Z',
      'startedAt': '2026-11-03T08:00:00Z',
      'endedAt': '2026-11-04T14:00:00Z',
      'inviatoAt': '2026-11-04T15:00:00Z',
      'customerSignatureAllegatoId': 'a1',
      'technicianSignatureAllegatoId': 'a2',
      'diagnosi': 'Guarnizione usurata',
      'soluzione': 'Sostituita la guarnizione',
      'technicianNotes': 'Accesso dal cortile interno.',
    };

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: AdminReportDetailScreen(report: serverRow)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rapportino 2026-0412'), findsOneWidget);
    expect(find.text('Rossi Srl · Novembre · 30 ore'), findsOneWidget);
    expect(find.text('Sede Milano'), findsOneWidget);
    expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
    expect(find.text('Daniel Shala'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

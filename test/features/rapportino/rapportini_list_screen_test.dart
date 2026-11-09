// dart format width=100
// test/features/rapportino/rapportini_list_screen_test.dart
//
// Widget tests for RapportiniListScreen (redesigned "Il Documento" list).
//
// Covers:
//   - header / search / quick chips / summary
//   - prototype group order and data-derived counts
//   - row anatomy: title+number, cliente/sede/data, firme/ore, status stamp
//   - the real filter sheet (statuses, Cliente, Sede, Tecnico, Periodo, Solo da inviare)
//   - search by report, cliente, sede and date
//   - empty filter vs empty catalogue vs never-synced
//   - delete (swipe and button), and the Bozza-only editor rule
//   - 320px layout

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/reports/server_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart'
    show ConnectivityNotifier, connectivityProvider;
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/rapportini_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

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

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}

Widget _buildRouted({
  required AppDatabase db,
  required ServerReportApiClient api,
  bool online = true,
  String? internalUserId = 'user-1',
  Entitlement? entitlement,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const RapportiniListScreen()),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        builder: (_, s) => Scaffold(body: Text('editor:${s.pathParameters['reportId']}')),
      ),
      GoRoute(
        path: '/altro/rapportini/view/:reportId',
        builder: (_, s) => Scaffold(body: Text('view:${s.pathParameters['reportId']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cachedEntitlementProvider.overrideWith((ref) async => entitlement ?? _writeReportEntitlement),
      syncProvider.overrideWith((ref) => _NoopSync(db)),
      serverReportApiClientProvider.overrideWithValue(api),
      connectivityProvider.overrideWith(() => _FakeConnectivity(online)),
      pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      lastSyncProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 6, 1))),
      internalUserIdProvider.overrideWith((ref) async => internalUserId),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class MockDio extends Mock implements Dio {}

/// The default seat for this file: a technician who may create and delete rapportini. Tests that
/// exercise the read-only path pass an entitlement without `rapportini.report.write`.
final _writeReportEntitlement = Entitlement(
  features: const {'rapportini'},
  capabilities: const {'rapportini.report.write'},
  seatType: 'field',
  fetchedAt: DateTime.utc(2026, 11, 9),
);

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<AppDatabase> _makeDb({bool synced = true}) async {
  final db = AppDatabase(NativeDatabase.memory());
  if (synced) await db.setLastSync(DateTime.utc(2026, 6, 1));
  return db;
}

Future<void> _seedDraft(
  AppDatabase db, {
  required String id,
  String title = 'Rapportino di test',
  String submissionState = 'draft',
  String stato = 'Bozza',
  bool isLocalOnly = true,
  String? numero,
  String? customerId,
  String locationId = 'loc-1',
  String insertedUserId = 'user-1',
  String? technicianSignatureId,
  String? customerSignatureId,
  int? customerSignatureAbsenceReason,
  DateTime? updatedAt,
  DateTime? createdAt,
}) async {
  await db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: createdAt ?? DateTime.utc(2026, 6, 1),
          updatedAt: Value(updatedAt),
          title: title,
          numero: Value(numero),
          insertedUserId: insertedUserId,
          customerId: Value(customerId),
          locationId: locationId,
          isLocalOnly: Value(isLocalOnly),
          stato: Value(stato),
          submissionState: Value(submissionState),
          technicianSignatureAllegatoId: Value(technicianSignatureId),
          customerSignatureAllegatoId: Value(customerSignatureId),
          customerSignatureAbsenceReason: Value(customerSignatureAbsenceReason),
        ),
      );
}

Future<void> _seedCustomer(
  AppDatabase db, {
  required String id,
  required String name,
  bool isActive = true,
}) async {
  await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: name,
          isActive: Value(isActive),
        ),
      );
}

Future<void> _seedLocation(
  AppDatabase db, {
  required String id,
  required String customerId,
  required String name,
  bool isActive = true,
}) async {
  await db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: customerId,
          name: name,
          isActive: Value(isActive),
        ),
      );
}

Future<void> _seedColleague(AppDatabase db, {required String id, required String name}) async {
  await db.into(db.colleagues).insert(ColleaguesCompanion.insert(id: id, displayName: name));
}

Future<void> _seedHours(AppDatabase db, {required String reportId, required double hours}) async {
  await db
      .into(db.reportStaffTable)
      .insert(
        ReportStaffTableCompanion.insert(
          id: 'staff-$reportId',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: reportId,
          userId: 'user-1',
          hoursWorked: Value(hours),
        ),
      );
}

Widget _buildList({required AppDatabase db, Entitlement? entitlement}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cachedEntitlementProvider.overrideWith(
        (ref) async => entitlement ?? _writeReportEntitlement,
      ),
      connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
      pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      lastSyncProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 6, 1))),
    ],
    child: const MaterialApp(home: RapportiniListScreen()),
  );
}

/// The quick chips live in [ListFilterRow]; group headings share the same texts, so always
/// scope a chip lookup to the filter row.
Finder _quickChip(String label) =>
    find.descendant(of: find.byType(ListFilterRow), matching: find.text(label.toUpperCase()));

/// A tall surface so a whole bottom sheet, and every group heading in a long list, is built.
Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  setUp(() async => db = await _makeDb());
  tearDown(() async => db.close());

  group('RapportiniListScreen — header and shell', () {
    testWidgets('shows the prototype title, subtitle, search hint and Nuovo action', (
      tester,
    ) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini'), findsOneWidget);
      expect(
        find.text('Il documento che deve uscire dal cantiere: bozza, firma, invio.'),
        findsOneWidget,
      );
      expect(find.text('Cerca rapportino, cliente, sede o data…'), findsOneWidget);
      expect(find.text('NUOVO'), findsOneWidget);
      expect(find.byType(AppFab), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('quick chips map to the prototype, with Tutti selected by default', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(_quickChip('Tutti'), findsOneWidget);
      expect(_quickChip('Da inviare'), findsOneWidget);
      expect(_quickChip('In revisione'), findsOneWidget);
      expect(_quickChip('Fatturati'), findsOneWidget);
      expect(_quickChip('Firmati'), findsNothing);
      expect(find.text('FILTRI'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Nuovo creates a local draft and opens its editor', (tester) async {
      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NUOVO'));
      await tester.pumpAndSettle();

      expect(find.textContaining('editor:'), findsOneWidget);
      expect(await db.select(db.draftReports).get(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Nuovo without a signed-in author warns and does not navigate', (tester) async {
      await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi(), internalUserId: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('NUOVO'));
      await tester.pumpAndSettle();

      expect(find.text('Accedi per creare un rapporto di intervento.'), findsOneWidget);
      expect(find.textContaining('editor:'), findsNothing);
      expect(await db.select(db.draftReports).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Nuovo is hidden without rapportini.report.write', (tester) async {
      await tester.pumpWidget(
        _buildList(
          db: db,
          entitlement: Entitlement(
            features: const {'rapportini'},
            capabilities: const {},
            seatType: 'field',
            fetchedAt: DateTime.utc(2026, 11, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NUOVO'), findsNothing);
      expect(find.byType(ListHeaderAction), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — row rendering', () {
    testWidgets('renders one row per seeded draft, titled', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Intervento idraulico');
      await _seedDraft(db, id: 'draft-2', title: 'Revisione caldaia');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Intervento idraulico'), findsOneWidget);
      expect(find.text('Revisione caldaia'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows the status stamp label for a draft', (tester) async {
      await _seedDraft(db, id: 'draft-1', submissionState: 'draft');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(StatusStamp), findsWidgets);
      expect(find.text('BOZZA'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows Inviata for a submitted report', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Rapportino inviato',
        submissionState: 'submitted',
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('INVIATA'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a draft whose last send failed does not read as an untouched Bozza', (
      tester,
    ) async {
      await _seedDraft(db, id: 'draft-1', submissionState: 'failed');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('INVIO FALLITO'), findsWidgets);
      expect(find.text('BOZZA'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a numbered report shows its number next to the title', (tester) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Revisione caldaia',
        numero: 'RAP-2026-0042',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining('#RAP-2026-0042'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a draft the server has not numbered shows no invented reference', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza appena creata');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining('#'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the meta line is cliente · sede · data and the secondary is firme · ore', (
      tester,
    ) async {
      await _seedCustomer(db, id: 'cus-1', name: 'Rossi Srl');
      await _seedLocation(db, id: 'loc-1', customerId: 'cus-1', name: 'Milano');
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Rapportino 2026-0412',
        customerId: 'cus-1',
        technicianSignatureId: 'tech-sig',
        customerSignatureId: 'cust-sig',
        createdAt: DateTime.now().toUtc(),
      );
      await _seedHours(db, reportId: 'draft-1', hours: 4.5);

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Rossi Srl · Milano · oggi'), findsOneWidget);
      expect(find.text('2 firme · 4h 30min'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a report with only the technician signature says the customer is missing', (
      tester,
    ) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        technicianSignatureId: 'tech-sig',
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining('Firma cliente mancante'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a recorded absence reason is shown instead of a generic missing signature', (
      tester,
    ) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        technicianSignatureId: 'tech-sig',
        customerSignatureAbsenceReason: 0,
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cliente assente'), findsOneWidget);
      expect(find.textContaining('Firma cliente non richiesta'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a deactivated customer and site still show in the row and stay searchable', (
      tester,
    ) async {
      await _seedCustomer(db, id: 'cus-old', name: 'Cliente Dismesso', isActive: false);
      await _seedLocation(
        db,
        id: 'loc-old',
        customerId: 'cus-old',
        name: 'Sede Dismessa',
        isActive: false,
      );
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Rapportino storico',
        customerId: 'cus-old',
        locationId: 'loc-old',
        createdAt: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.text('Cliente Dismesso · Sede Dismessa · oggi'), findsOneWidget);

      for (final query in ['dismesso', 'sede dismessa']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.text('Rapportino storico'), findsOneWidget, reason: query);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — groups and summary', () {
    testWidgets('groups server states in the prototype order with derived counts', (tester) async {
      await _useTallSurface(tester);
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza 1');
      await _seedDraft(
        db,
        id: 'inviata-1',
        title: 'Inviata 1',
        stato: 'Inviato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );
      await _seedDraft(
        db,
        id: 'controllata-1',
        title: 'Controllata 1',
        stato: 'Controllato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );
      await _seedDraft(
        db,
        id: 'fatturata-1',
        title: 'Fatturata 1',
        stato: 'Fatturato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );
      await _seedDraft(
        db,
        id: 'respinta-1',
        title: 'Respinta 1',
        stato: 'Respinto',
        submissionState: 'submitted',
        isLocalOnly: false,
      );
      await _seedDraft(
        db,
        id: 'annullata-1',
        title: 'Annullata 1',
        stato: 'Annullato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      final headings = tester
          .widgetList<ListGroupHeader>(find.byType(ListGroupHeader))
          .map((h) => h.title)
          .toList();
      expect(headings, [
        'Da inviare',
        'In revisione',
        'Controllati',
        'Fatturati',
        'Respinti',
        'Annullati',
      ]);
      expect(find.text('6 RAPPORTINI'), findsOneWidget);
      expect(find.text('1 DA INVIARE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the summary follows the filtered set', (tester) async {
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza 1');
      await _seedDraft(
        db,
        id: 'inviata-1',
        title: 'Inviata 1',
        stato: 'Inviato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();
      await tester.tap(_quickChip('In revisione'));
      await tester.pumpAndSettle();

      expect(find.text('1 RAPPORTINO'), findsOneWidget);
      expect(find.text('0 DA INVIARE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — quick status filters', () {
    testWidgets('Da inviare keeps every unsent draft and hides submitted reports', (tester) async {
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza A', submissionState: 'draft');
      await _seedDraft(db, id: 'pronta-1', title: 'Pronta B', submissionState: 'readyToSubmit');
      await _seedDraft(db, id: 'fallita-1', title: 'Fallita C', submissionState: 'failed');
      await _seedDraft(
        db,
        id: 'inviata-1',
        title: 'Inviata D',
        stato: 'Inviato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();
      await tester.tap(_quickChip('Da inviare'));
      await tester.pumpAndSettle();

      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Pronta B'), findsOneWidget);
      expect(find.text('Fallita C'), findsOneWidget);
      expect(find.text('Inviata D'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('In revisione shows only submitted reports', (tester) async {
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza locale', submissionState: 'draft');
      await _seedDraft(
        db,
        id: 'inviata-1',
        title: 'Già inviato',
        stato: 'Inviato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();
      await tester.tap(_quickChip('In revisione'));
      await tester.pumpAndSettle();

      expect(find.text('Già inviato'), findsOneWidget);
      expect(find.text('Bozza locale'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Fatturati with no local data shows the empty-filter state', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Bozza A');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();
      await tester.tap(_quickChip('Fatturati'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nessun risultato'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Fatturati maps to the invoiced (Pagata) server state', (tester) async {
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza A');
      await _seedDraft(
        db,
        id: 'fatturata-1',
        title: 'Fatturata B',
        stato: 'Fatturato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();
      await tester.tap(_quickChip('Fatturati'));
      await tester.pumpAndSettle();

      expect(find.text('Fatturata B'), findsOneWidget);
      expect(find.text('Bozza A'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the old status filters all remain reachable in the Filtri sheet', (tester) async {
      await _useTallSurface(tester);
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();

      for (final label in ['Tutti', 'Bozza', 'Inviata', 'Respinta', 'Pagata', 'Annullato']) {
        expect(find.widgetWithText(AppChip, label), findsOneWidget, reason: label);
      }
      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('TECNICO'), findsOneWidget);
      expect(find.text('PERIODO'), findsOneWidget);
      expect(find.text('Solo da inviare'), findsOneWidget);
      expect(find.text('Applica'), findsOneWidget);
      expect(find.text('Azzera'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('applying the retained Respinta facet filters the list', (tester) async {
      await _useTallSurface(tester);
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza A');
      await _seedDraft(
        db,
        id: 'respinta-1',
        title: 'Respinta B',
        stato: 'Respinto',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppChip, 'Respinta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Respinta B'), findsOneWidget);
      expect(find.text('Bozza A'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Azzera clears an applied filter', (tester) async {
      await _useTallSurface(tester);
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza A');
      await _seedDraft(
        db,
        id: 'respinta-1',
        title: 'Respinta B',
        stato: 'Respinto',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppChip, 'Respinta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();
      expect(find.text('Bozza A'), findsNothing);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Azzera'));
      await tester.pumpAndSettle();

      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Respinta B'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the Cliente facet filters by customer', (tester) async {
      await _useTallSurface(tester);
      await _seedCustomer(db, id: 'cus-1', name: 'Rossi Srl');
      await _seedCustomer(db, id: 'cus-2', name: 'Bianchi Srl');
      await _seedDraft(db, id: 'rossi', title: 'Cliente Rossi', customerId: 'cus-1');
      await _seedDraft(db, id: 'bianchi', title: 'Cliente Bianchi', customerId: 'cus-2');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String?>).first);
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rossi Srl').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Cliente Rossi'), findsOneWidget);
      expect(find.text('Cliente Bianchi'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the Sede facet filters by location', (tester) async {
      await _useTallSurface(tester);
      await _seedLocation(db, id: 'loc-1', customerId: 'cus-1', name: 'Milano');
      await _seedLocation(db, id: 'loc-2', customerId: 'cus-1', name: 'Sesto');
      await _seedDraft(db, id: 'milano', title: 'Sede Milano', locationId: 'loc-1');
      await _seedDraft(db, id: 'sesto', title: 'Sede Sesto', locationId: 'loc-2');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String?>).at(1));
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sesto').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Sede Sesto'), findsOneWidget);
      expect(find.text('Sede Milano'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the Tecnico facet filters by the inserted user', (tester) async {
      await _useTallSurface(tester);
      await _seedColleague(db, id: 'user-1', name: 'Daniel Shala');
      await _seedColleague(db, id: 'user-2', name: 'Marco Rossi');
      await _seedDraft(db, id: 'daniel', title: 'Rapportino Daniel', insertedUserId: 'user-1');
      await _seedDraft(db, id: 'marco', title: 'Rapportino Marco', insertedUserId: 'user-2');

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String?>).at(2));
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marco Rossi').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Rapportino Marco'), findsOneWidget);
      expect(find.text('Rapportino Daniel'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the Periodo Da facet excludes reports before the chosen date', (tester) async {
      await _useTallSurface(tester);
      final now = DateTime.now();
      // Far enough from "today" that a device-zone/business-zone day skew cannot flip the verdict.
      await _seedDraft(
        db,
        id: 'recent',
        title: 'Futuro vicino',
        updatedAt: now.add(const Duration(days: 5)).toUtc(),
      );
      await _seedDraft(
        db,
        id: 'old',
        title: 'Passato lontano',
        updatedAt: now.subtract(const Duration(days: 30)).toUtc(),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Qualsiasi').first);
      await tester.tap(find.text('Qualsiasi').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Futuro vicino'), findsOneWidget);
      expect(find.text('Passato lontano'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the Periodo A facet excludes reports after the chosen date', (tester) async {
      await _useTallSurface(tester);
      final now = DateTime.now();
      await _seedDraft(
        db,
        id: 'recent',
        title: 'Passato vicino',
        updatedAt: now.subtract(const Duration(days: 5)).toUtc(),
      );
      await _seedDraft(
        db,
        id: 'future',
        title: 'Futuro lontano',
        updatedAt: now.add(const Duration(days: 30)).toUtc(),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Qualsiasi').last);
      await tester.tap(find.text('Qualsiasi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Passato vicino'), findsOneWidget);
      expect(find.text('Futuro lontano'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Solo da inviare keeps only unsent reports', (tester) async {
      await _useTallSurface(tester);
      await _seedDraft(db, id: 'bozza-1', title: 'Bozza A');
      await _seedDraft(
        db,
        id: 'inviata-1',
        title: 'Inviata B',
        stato: 'Inviato',
        submissionState: 'submitted',
        isLocalOnly: false,
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Bozza A'), findsOneWidget);
      expect(find.text('Inviata B'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — search', () {
    testWidgets('matches report title, customer, site and date', (tester) async {
      await _seedCustomer(db, id: 'cus-1', name: 'Rossi Srl');
      await _seedLocation(db, id: 'loc-1', customerId: 'cus-1', name: 'Milano');
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Manutenzione caldaia',
        customerId: 'cus-1',
        createdAt: DateTime.utc(2026, 11, 12),
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      for (final query in ['manutenzione', 'rossi', 'milano', '12/11/26']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(find.text('Manutenzione caldaia'), findsOneWidget, reason: query);
      }

      await tester.enterText(find.byType(TextField), 'inesistente');
      await tester.pumpAndSettle();
      expect(find.text('Nessun risultato'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — empty states', () {
    testWidgets('an empty catalogue shows "Nessun rapportino" once synced', (tester) async {
      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a never-synced device says the data is not downloaded yet', (tester) async {
      final fresh = await _makeDb(synced: false);
      addTearDown(fresh.close);

      await tester.pumpWidget(_buildList(db: fresh));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini non ancora scaricati'), findsOneWidget);

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
      final row = await (db.select(
        db.draftReports,
      )..where((r) => r.id.equals('srv-1'))).getSingle();
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

      expect(find.text('Questo rapporto di intervento non è più modificabile.'), findsOneWidget);
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
        cachedEntitlementProvider.overrideWith((ref) async => _writeReportEntitlement),
        dioProvider.overrideWithValue(mockDio),
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        lastSyncProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 6, 1))),
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

      expect(find.text('Eliminare il rapporto di intervento?'), findsOneWidget);
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(find.text('Da eliminare'), findsNothing);
      expect(await db.select(db.draftReports).get(), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the inline Elimina button offers the same delete path', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Da eliminare', submissionState: 'draft');
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(find.text('Da eliminare'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('delete is hidden without rapportini.report.write', (tester) async {
      await _seedDraft(db, id: 'draft-1', title: 'Da eliminare', submissionState: 'draft');
      await tester.pumpWidget(
        _buildList(
          db: db,
          entitlement: Entitlement(
            features: const {'rapportini'},
            capabilities: const {},
            seatType: 'field',
            fetchedAt: DateTime.utc(2026, 11, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No inline trash button and no swipe affordance: both reach the same delete path.
      expect(find.byTooltip('Elimina'), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.text('Da eliminare'), findsOneWidget);

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

    testWidgets(
      'a report sent to the office (Inviato) has no swipe-to-delete affordance — it leaves '
      'through the office Annulla workflow',
      (tester) async {
        await _seedDraft(
          db,
          id: 'draft-1',
          title: 'In attesa di revisione',
          stato: 'Inviato',
          submissionState: 'submitted',
        );
        await tester.pumpWidget(buildWithDio(db: db));
        await tester.pumpAndSettle();

        expect(find.byType(Dismissible), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a rejected report (Respinto) has no swipe-to-delete affordance either', (
      tester,
    ) async {
      await _seedDraft(
        db,
        id: 'draft-1',
        title: 'Respinto dall\'ufficio',
        stato: 'Respinto',
        submissionState: 'submitted',
      );
      await tester.pumpWidget(buildWithDio(db: db));
      await tester.pumpAndSettle();

      expect(find.byType(Dismissible), findsNothing);

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

  // ── O-3 / P0-8 (owner decision D8 + audit F15) ──────────────────────────────
  //
  // Non-Bozza reports are read-only on mobile: the list must never route them into the editor,
  // whose first autosave rewrites `stato:'Bozza'` + `isLocalOnly:true` over the server's copy.
  group('RapportiniListScreen — only a Bozza opens the editor', () {
    for (final caso in const [
      ('Inviato', 'submitted'),
      ('Respinto', 'submitted'),
      ('Controllato', 'submitted'),
      ('Fatturato', 'submitted'),
    ]) {
      testWidgets('${caso.$1} opens the read-only view, never the editor', (tester) async {
        await _seedDraft(
          db,
          id: 'srv-1',
          title: 'Rapportino ${caso.$1.toLowerCase()}',
          stato: caso.$1,
          submissionState: caso.$2,
          isLocalOnly: false,
        );

        await tester.pumpWidget(_buildRouted(db: db, api: _FakeServerApi()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rapportino ${caso.$1.toLowerCase()}'));
        await tester.pumpAndSettle();

        expect(find.text('view:srv-1'), findsOneWidget);
        expect(find.text('editor:srv-1'), findsNothing);
        expect(
          (await (db.select(
            db.draftReports,
          )..where((r) => r.id.equals('srv-1'))).getSingle()).stato,
          caso.$1,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  });

  // The editor is gated on `rapportini.report.write`; a read-only seat tapping its Bozza row must
  // get feedback on the list rather than a push that only dead-ends at /forbidden.
  testWidgets('a read-only seat tapping a Bozza stays on the list and is told why', (tester) async {
    await _seedDraft(db, id: 'loc-1', title: 'Bozza locale');

    await tester.pumpWidget(
      _buildRouted(
        db: db,
        api: _FakeServerApi(),
        entitlement: Entitlement(
          features: const {'rapportini'},
          capabilities: const {},
          seatType: 'field',
          fetchedAt: DateTime.utc(2026, 11, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bozza locale'));
    await tester.pumpAndSettle();

    expect(find.text('editor:loc-1'), findsNothing);
    expect(find.text('view:loc-1'), findsNothing);
    expect(
      find.text('Non hai i permessi per modificare questo rapportino.'),
      findsOneWidget,
    );
    // Still on the list: the tap produced feedback, not a navigation.
    expect(find.text('Rapportini'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  group('RapportiniListScreen — delete of a server-known report is online-only', () {
    testWidgets('offline, the row is kept and the technician is told why', (tester) async {
      final mockDio = MockDio();
      when(() => mockDio.delete<void>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/reports/srv-1'),
          type: DioExceptionType.connectionError,
        ),
      );
      await _seedDraft(db, id: 'srv-1', title: 'Da eliminare', isLocalOnly: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            cachedEntitlementProvider.overrideWith((ref) async => _writeReportEntitlement),
            dioProvider.overrideWithValue(mockDio),
            connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
            pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
            lastSyncProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 6, 1))),
          ],
          child: const MaterialApp(home: RapportiniListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(find.textContaining('serve la connessione'), findsOneWidget);
      expect(find.text('Da eliminare'), findsOneWidget);
      expect(await db.select(db.draftReports).get(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('online, the server delete succeeds and then the local row goes', (tester) async {
      final mockDio = MockDio();
      when(() => mockDio.delete<void>(any())).thenAnswer(
        (_) async => Response<void>(requestOptions: RequestOptions(path: ''), statusCode: 204),
      );
      await _seedDraft(db, id: 'srv-1', title: 'Da eliminare', isLocalOnly: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            cachedEntitlementProvider.overrideWith((ref) async => _writeReportEntitlement),
            dioProvider.overrideWithValue(mockDio),
            connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
            pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
            lastSyncProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 6, 1))),
          ],
          child: const MaterialApp(home: RapportiniListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Elimina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(find.text('Da eliminare'), findsNothing);
      expect(await db.select(db.draftReports).get(), isEmpty);
      verify(() => mockDio.delete<void>('/api/reports/srv-1')).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('RapportiniListScreen — narrow layout', () {
    testWidgets('320px wide with long Italian strings does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await _seedCustomer(db, id: 'cus-1', name: 'Azienda Costruzioni Rossi & Figli Srl');
      await _seedLocation(
        db,
        id: 'loc-1',
        customerId: 'cus-1',
        name: 'Cantiere di ristrutturazione Via Roma angolo Via Verdi',
      );
      await _seedDraft(
        db,
        id: 'draft-1',
        title:
            'Manutenzione straordinaria dell\'impianto di riscaldamento e verifica delle valvole '
            'di sicurezza',
        customerId: 'cus-1',
      );

      await tester.pumpWidget(_buildList(db: db));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

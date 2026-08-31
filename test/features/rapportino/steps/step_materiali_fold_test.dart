// dart format width=100
// test/features/rapportino/steps/step_materiali_fold_test.dart
//
// Widget tests for the Controlli checklist inside StepMaterialiFold.
//
// The checklist replaced a free-text "type a control ID" dialog with the
// ticket's real checklist (GET /api/tickets/{ticketId}/controls, resolved
// server-side from the maintenance-template version — ADR-0012). These
// tests cover the same three outcomes ticket_detail_screen_test.dart covers
// for the read-only Controllo tab — data / empty / offline — plus that the
// rendered inputs actually write back to the editor state.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/app_text_field.dart';
import 'package:tasktap_mobile/core/widgets/app_toggle.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/reports/ticket_controls_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_materiali_fold.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

const _reportId = 'draft-1';
const _ticketId = 'ticket-1';

ProviderContainer _buildContainer({
  required AppDatabase db,
  Dio? dio,
  bool isOnline = true,
  String? ticketId = _ticketId,
}) {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio ?? MockDio()),
      isOnlineProvider.overrideWithValue(isOnline),
      reportEditorProvider(_reportId).overrideWith(
        (ref) => ReportEditorNotifier(
          initialState: ReportEditorState(
            reportId: _reportId,
            tenantId: 'tenant-1',
            insertedUserId: 'user-1',
            ticketId: ticketId,
          ),
          repo: DraftReportRepository(db),
        ),
      ),
    ],
  );
  return container;
}

Widget _buildStep(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      // StepMaterialiFold no longer bounds its own height — it now sits inside the compartment
      // sheet's ambient SingleChildScrollView (see openCompartmentSheet), so tests host it the
      // same way rather than a bare, height-bounded Scaffold body.
      home: Scaffold(body: SingleChildScrollView(child: StepMaterialiFold(reportId: _reportId))),
    ),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('Controlli checklist — data', () {
    testWidgets('renders the real checklist items with type-driven inputs', (tester) async {
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/tickets/$_ticketId/controls')).thenAnswer(
        (_) async => _okResponse([
          {
            'id': 'grp-1',
            'name': 'Sezione A',
            'description': null,
            'sortOrder': 0,
            'subgroups': <dynamic>[],
            'controls': [
              {
                'id': 'tc-1',
                'templateControlId': 'tpl-1',
                'controlLineageId': 'lin-1',
                'label': 'Pressione OK',
                'description': null,
                'type': 0, // Checkbox
                'isRequired': true,
                'options': null,
                'valoreLimite': null,
                'sortOrder': 0,
                'status': 'Pending',
                'stringValue': null,
                'boolValue': null,
                'dateValue': null,
                'completedByReportId': null,
                'completedAt': null,
              },
              {
                'id': 'tc-2',
                'templateControlId': 'tpl-2',
                'controlLineageId': 'lin-2',
                'label': 'Note aggiuntive',
                'description': null,
                'type': 1, // FreeText
                'isRequired': false,
                'options': null,
                'valoreLimite': null,
                'sortOrder': 1,
                'status': 'Pending',
                'stringValue': null,
                'boolValue': null,
                'dateValue': null,
                'completedByReportId': null,
                'completedAt': null,
              },
            ],
          },
        ], '/api/tickets/$_ticketId/controls'),
      );

      final container = _buildContainer(db: db, dio: dio);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      // Real labels from the template, not a free-text "ID" box.
      expect(find.text('Pressione OK'), findsOneWidget);
      expect(find.text('Note aggiuntive'), findsOneWidget);
      // The old dialog is gone.
      expect(find.text('Aggiungi controllo'), findsNothing);
      expect(find.text('Nome controllo / ID'), findsNothing);
      // A checkbox-type item renders a toggle, not a text box. (Two
      // AppToggles total: the pre-existing "Nessun materiale utilizzato"
      // toggle plus this checklist item's.)
      expect(find.byType(AppToggle), findsNWidgets(2));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('ticking a checkbox control writes the answer to editor state', (tester) async {
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/tickets/$_ticketId/controls')).thenAnswer(
        (_) async => _okResponse([
          {
            'id': 'grp-1',
            'name': 'Sezione A',
            'description': null,
            'sortOrder': 0,
            'subgroups': <dynamic>[],
            'controls': [
              {
                'id': 'tc-1',
                'templateControlId': 'tpl-1',
                'controlLineageId': 'lin-1',
                'label': 'Pressione OK',
                'description': null,
                'type': 0,
                'isRequired': true,
                'options': null,
                'valoreLimite': null,
                'sortOrder': 0,
                'status': 'Pending',
                'stringValue': null,
                'boolValue': null,
                'dateValue': null,
                'completedByReportId': null,
                'completedAt': null,
              },
            ],
          },
        ], '/api/tickets/$_ticketId/controls'),
      );

      final container = _buildContainer(db: db, dio: dio);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      // .last: the checklist item's toggle, not the pre-existing "Nessun
      // materiale utilizzato" one above it.
      await tester.tap(find.byType(AppToggle).last);
      await tester.pumpAndSettle();

      final rows = container.read(reportEditorProvider(_reportId)).controlloRows;
      expect(rows, hasLength(1));
      // The answer references the TicketControl id — the identity a
      // rapportino's finding is submitted against — not a typed-in string.
      expect(rows.single.controlId, 'tc-1');
      expect(rows.single.boolValue, isTrue);
    });

    testWidgets('typing into a free-text control writes the answer', (tester) async {
      final dio = MockDio();
      when(() => dio.get<List<dynamic>>('/api/tickets/$_ticketId/controls')).thenAnswer(
        (_) async => _okResponse([
          {
            'id': 'grp-1',
            'name': 'Sezione A',
            'description': null,
            'sortOrder': 0,
            'subgroups': <dynamic>[],
            'controls': [
              {
                'id': 'tc-2',
                'templateControlId': 'tpl-2',
                'controlLineageId': 'lin-2',
                'label': 'Note aggiuntive',
                'description': null,
                'type': 1,
                'isRequired': false,
                'options': null,
                'valoreLimite': null,
                'sortOrder': 0,
                'status': 'Pending',
                'stringValue': null,
                'boolValue': null,
                'dateValue': null,
                'completedByReportId': null,
                'completedAt': null,
              },
            ],
          },
        ], '/api/tickets/$_ticketId/controls'),
      );

      final container = _buildContainer(db: db, dio: dio);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Tutto regolare');
      await tester.pumpAndSettle();

      final rows = container.read(reportEditorProvider(_reportId)).controlloRows;
      expect(rows, hasLength(1));
      expect(rows.single.controlId, 'tc-2');
      expect(rows.single.stringValue, 'Tutto regolare');
    });
  });

  group('Controlli checklist — empty / not applicable', () {
    testWidgets('says honestly that no controls are planned for this ticket', (tester) async {
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/$_ticketId/controls'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/tickets/$_ticketId/controls'));

      final container = _buildContainer(db: db, dio: dio);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.text('Nessun controllo previsto per questo intervento.'), findsOneWidget);
      // Never falls back to the old free-text box.
      expect(find.text('Aggiungi controllo'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('explains that controls require a linked ticket when there is none', (
      tester,
    ) async {
      final container = _buildContainer(db: db, ticketId: null);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('non è collegato a nessun ticket'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Controlli checklist — offline', () {
    testWidgets('says plainly it is offline when nothing was ever cached', (tester) async {
      final container = _buildContainer(db: db, isOnline: false);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      expect(find.textContaining('Controlli non disponibili offline'), findsOneWidget);
      expect(find.text('Nessun controllo previsto per questo intervento.'), findsNothing);
      // Offline must never degrade into the old typed-ID box either.
      expect(find.text('Aggiungi controllo'), findsNothing);
    });
  });

  // ── Offline cache (mobile audit item #3) ────────────────────────────────────
  //
  // Every other section of this offline-first form works with zero network at capture time; the
  // checklist used to be the one exception (no local cache — see the group above for the
  // "nothing cached yet" case, unchanged by this feature). These verify the cache itself: a
  // successful online fetch persists it, a cached checklist is viewable/answerable offline, and
  // an answer given offline is an ordinary ControlloRow — already included in the submit payload
  // the same way as every other answer (SubmissionQueue._buildRequest reads it straight from
  // Drift, unaware of whether the checklist that produced it came from the network or the cache).

  group('Controlli checklist — offline cache', () {
    Map<String, dynamic> controlsPayload() => {
      'id': 'grp-1',
      'name': 'Sezione A',
      'description': null,
      'sortOrder': 0,
      'subgroups': <dynamic>[],
      'controls': [
        {
          'id': 'tc-1',
          'templateControlId': 'tpl-1',
          'controlLineageId': 'lin-1',
          'label': 'Pressione OK',
          'description': null,
          'type': 0, // Checkbox
          'isRequired': true,
          'options': null,
          'valoreLimite': null,
          'sortOrder': 0,
          'status': 'Pending',
          'stringValue': null,
          'boolValue': null,
          'dateValue': null,
          'completedByReportId': null,
          'completedAt': null,
        },
      ],
    };

    testWidgets('a successful online fetch caches the checklist locally', (tester) async {
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/$_ticketId/controls'),
      ).thenAnswer((_) async => _okResponse([controlsPayload()], '/api/tickets/$_ticketId/controls'));

      final container = _buildContainer(db: db, dio: dio);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      final cached = await (db.select(
        db.cachedTicketControls,
      )..where((t) => t.ticketId.equals(_ticketId))).getSingleOrNull();
      expect(cached, isNotNull);
      expect(cached!.controlsJson, contains('Pressione OK'));
    });

    testWidgets('a cached checklist is viewable and answerable while offline', (tester) async {
      // Seed the cache as if a previous online fetch already happened, before this device lost
      // connectivity mid-draft.
      await TicketControlsCacheRepository(db).cacheControls(_ticketId, [
        TicketControlGroupDto.fromJson(controlsPayload()),
      ]);

      final container = _buildContainer(db: db, isOnline: false);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      // No offline error — the cache stands in for the network fetch.
      expect(find.textContaining('Controlli non disponibili offline'), findsNothing);
      expect(find.text('Pressione OK'), findsOneWidget);

      // Still answerable: ticking it writes an ordinary ControlloRow, same as when online.
      await tester.tap(find.byType(AppToggle).last);
      await tester.pumpAndSettle();

      final rows = container.read(reportEditorProvider(_reportId)).controlloRows;
      expect(rows, hasLength(1));
      expect(rows.single.controlId, 'tc-1');
      expect(rows.single.boolValue, isTrue);
    });

    testWidgets('an answer recorded offline is persisted as a normal draft controllo row — '
        'the same table SubmissionQueue reads to build the submit payload', (tester) async {
      await TicketControlsCacheRepository(db).cacheControls(_ticketId, [
        TicketControlGroupDto.fromJson(controlsPayload()),
      ]);

      final container = _buildContainer(db: db, isOnline: false);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppToggle).last);
      await tester.pumpAndSettle();

      // What SubmissionQueue._buildRequest actually reads at submit time.
      final repo = DraftReportRepository(db);
      final persisted = await repo.getControlli(_reportId);
      expect(persisted, hasLength(1));
      expect(persisted.single.controlId, 'tc-1');
      expect(persisted.single.boolValue, isTrue);
    });
  });

  group('Aggiungi materiale — Fabbisogno suggestions + scan entry point', () {
    testWidgets('shows the scan button', (tester) async {
      final container = _buildContainer(db: db, ticketId: null);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aggiungi materiale'));
      await tester.pumpAndSettle();

      expect(find.text('Scansiona codice'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('no suggestions row when the rapportino has no linked ticket', (tester) async {
      final container = _buildContainer(db: db, ticketId: null);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aggiungi materiale'));
      await tester.pumpAndSettle();

      expect(find.text('Dal fabbisogno del ticket'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('planned materiali from the ticket render as tappable suggestions', (tester) async {
      // Local-Drift-backed now (see ticketMaterialiProvider's own doc comment) — seeded directly,
      // not stubbed on MockDio.
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              code: 'ART-001',
              name: 'Guarnizione EPDM',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              ticketId: _ticketId,
              materialeId: const Value('mat-1'),
              quantity: 3,
              isAvailable: const Value(true),
            ),
          );

      final container = _buildContainer(db: db);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aggiungi materiale'));
      await tester.pumpAndSettle();

      expect(find.text('Dal fabbisogno del ticket'), findsOneWidget);
      expect(find.text('Guarnizione EPDM'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tapping a suggestion fills quantity and unit from the planned line', (
      tester,
    ) async {
      // Local-Drift-backed now — seeded directly, not stubbed on MockDio.
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              ticketId: _ticketId,
              freeTextName: const Value('Nastro isolante'),
              quantity: 2,
              unitOfMeasure: const Value('rt'),
              isAvailable: const Value(true),
            ),
          );

      final container = _buildContainer(db: db);
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildStep(container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aggiungi materiale'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nastro isolante'));
      await tester.pumpAndSettle();

      final qtyField = tester.widget<TextField>(
        find.descendant(of: find.byType(AppFieldShell).first, matching: find.byType(TextField)),
      );
      expect(qtyField.controller?.text, '2.0');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

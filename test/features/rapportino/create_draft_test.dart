// dart format width=100
// test/features/rapportino/create_draft_test.dart
//
// Tests for createReworkDraft — the "Rilavora" affordance a rejected (Respinto) rapportino
// gets on RapportinoViewScreen (mobile audit item #1).
//
// The backend's ReportStateMachine only allows Bozza → Inviato (CanInvia requires
// Stato == Bozza), so a Respinto report cannot be resubmitted under its own id. Rework instead
// clones the rejected report's data into a brand-new local draft — this file verifies that clone:
// header fields, staff/materiali/controlli rows, and that signatures are deliberately NOT carried
// over (they attest to a version of the report the office already rejected).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/cantiere_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/rapportino/create_draft.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Returns [reportIdToReturn] from [createFromCantiereWorklogs] and [staffToReturn] from
/// [fetchReportStaff] — never touches the network.
class _FakeCantiereReportApiClient extends CantiereReportApiClient {
  _FakeCantiereReportApiClient({
    this.reportIdToReturn = 'report-1',
    this.staffToReturn = const [],
  }) : super(Dio());

  final String reportIdToReturn;
  final List<ReportStaffSeedDto> staffToReturn;

  String? calledWithCantiereId;

  /// When set, [fetchReportStaff] throws instead of returning [staffToReturn] — used to prove the
  /// zero-worklogs fallback also covers a network drop between the two calls.
  Object? throwsOnFetchStaff;

  @override
  Future<String> createFromCantiereWorklogs(String cantiereId) async {
    calledWithCantiereId = cantiereId;
    return reportIdToReturn;
  }

  @override
  Future<List<ReportStaffSeedDto>> fetchReportStaff(String reportId) async {
    if (throwsOnFetchStaff != null) throw throwsOnFetchStaff!;
    return staffToReturn;
  }
}

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

final _testUser = AuthUser(
  id: 'user-2',
  email: 'tecnico@example.com',
  accessToken: 'tok',
  refreshToken: 'ref',
  expiresAt: DateTime.utc(2030, 1, 1),
);

/// Pumps a tiny widget tree, exposing a real WidgetRef via a Consumer (createReworkDraft, like
/// createLocalDraft, takes a WidgetRef — it is meant to be called from a widget callback).
Future<String?> _callCreateReworkDraft(
  WidgetTester tester,
  ProviderContainer container,
  DraftReport source,
) async {
  String? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await createReworkDraft(ref, source);
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

/// A real GUID (v4), matching what `POST /api/reports/{id:guid}/attachments` and
/// `SubmitReportRequest.Id` (a `Guid` field, backend-side) actually accept — the format bug this
/// file guards against had every attachment upload 404 at the route level, since a
/// `draft-<timestamp>` string never matches `{id:guid}`.
final _guidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

Future<String?> _callCreateLocalDraft(
  WidgetTester tester,
  ProviderContainer container, {
  required String title,
  String? ticketId,
  String? cantiereId,
  String? customerId,
  String? tenantId,
  String? workAddress,
}) async {
  String? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await createLocalDraft(
                  ref,
                  title: title,
                  ticketId: ticketId,
                  cantiereId: cantiereId,
                  customerId: customerId,
                  tenantId: tenantId,
                  workAddress: workAddress,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

Future<String?> _callCreateCantiereReportDraft(
  WidgetTester tester,
  ProviderContainer container, {
  required String cantiereId,
  required String cantiereName,
  String? customerId,
  String? tenantId,
  String? workAddress,
}) async {
  String? result;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            return ElevatedButton(
              onPressed: () async {
                result = await createCantiereReportDraft(
                  ref,
                  cantiereId: cantiereId,
                  cantiereName: cantiereName,
                  customerId: customerId,
                  tenantId: tenantId,
                  workAddress: workAddress,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

DraftReportsCompanion _rejectedReportCompanion({String id = 'report-1'}) =>
    DraftReportsCompanion.insert(
      id: id,
      tenantId: 'tenant-1',
      createdAt: DateTime.utc(2026, 6, 1),
      title: 'Manutenzione impianto',
      scheduleId: const Value('sched-1'),
      ticketId: const Value('ticket-1'),
      customerId: const Value('cust-1'),
      details: const Value('Sostituita guarnizione'),
      technicianNotes: const Value('Da ricontrollare tra 6 mesi'),
      insertedUserId: 'tecnico-1',
      locationId: 'loc-1',
      materialiNotRequired: const Value(false),
      isLocalOnly: const Value(false),
      stato: const Value('Respinto'),
      submissionState: const Value('submitted'),
      customerSignatureAllegatoId: const Value('sig-c-1'),
      technicianSignatureAllegatoId: const Value('sig-t-1'),
      customerSignoffText: const Value('Confermo accettazione'),
    );

void main() {
  late AppDatabase db;
  late DraftReportRepository repo;

  setUp(() {
    db = _makeDb();
    repo = DraftReportRepository(db);
  });

  tearDown(() async => db.close());

  ProviderContainer buildContainer({AuthUser? user, CantiereReportApiClient? cantiereReportApi}) =>
      ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWithValue(user),
          if (cantiereReportApi != null)
            cantiereReportApiClientProvider.overrideWithValue(cantiereReportApi),
        ],
      );

  group('createLocalDraft', () {
    testWidgets('generates a real GUID id, not a draft-<timestamp> string', (tester) async {
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final id = await _callCreateLocalDraft(tester, container, title: 'Nuovo rapportino');

      expect(id, isNotNull);
      expect(
        _guidPattern.hasMatch(id!),
        isTrue,
        reason: 'must satisfy POST /api/reports/{id:guid}/attachments — a draft-<timestamp> '
            'string never matches that route',
      );
    });

    testWidgets('persists cantiereId — a cantiere-created rapportino keeps its link', (
      tester,
    ) async {
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final id = await _callCreateLocalDraft(
        tester,
        container,
        title: 'Rapportino — Cantiere Via Roma',
        cantiereId: 'cant-1',
        customerId: 'cust-1',
        tenantId: 'tenant-1',
      );

      final draft = await repo.getDraft(id!);
      expect(draft!.cantiereId, 'cant-1');
      expect(draft.ticketId, isNull, reason: 'a cantiere-originated draft has no ticket link');
    });

    testWidgets('persists workAddress into metadataJson, readable back through the editor state', (
      tester,
    ) async {
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final id = await _callCreateLocalDraft(
        tester,
        container,
        title: 'Rapportino — Cantiere Via Roma',
        workAddress: 'Via Roma 10, Milano, 20100',
      );

      final draft = await repo.getDraft(id!);
      expect(draft!.metadataJson, contains('Via Roma 10, Milano, 20100'));
    });

    testWidgets('leaves metadataJson null when no workAddress is given', (tester) async {
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final id = await _callCreateLocalDraft(tester, container, title: 'Nuovo rapportino');

      final draft = await repo.getDraft(id!);
      expect(draft!.metadataJson, isNull);
    });

    testWidgets('seeds the creating technician as the first staff row', (tester) async {
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final id = await _callCreateLocalDraft(tester, container, title: 'Nuovo rapportino');

      final staff = await repo.getStaff(id!);
      expect(staff, hasLength(1));
      expect(staff.single.userId, _testUser.id);
      expect(
        staff.single.hoursWorked,
        isNull,
        reason: 'names who is on the job, but does not guess their hours',
      );
    });
  });

  group('createReworkDraft', () {
    testWidgets('generates a real GUID id, not a draft-<timestamp> string', (tester) async {
      await repo.createDraft(_rejectedReportCompanion());
      final source = (await repo.getDraft('report-1'))!;

      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);

      expect(newId, isNotNull);
      expect(_guidPattern.hasMatch(newId!), isTrue);
    });

    testWidgets('carries cantiereId over — a cantiere-linked rework keeps its link', (
      tester,
    ) async {
      await repo.createDraft(
        _rejectedReportCompanion(id: 'report-cant').copyWith(
          ticketId: const Value(null),
          cantiereId: const Value('cant-1'),
        ),
      );
      final source = (await repo.getDraft('report-cant'))!;

      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);
      final newDraft = await repo.getDraft(newId!);

      expect(newDraft!.cantiereId, 'cant-1');
    });

    testWidgets('clones header fields into a new draft id, starting fresh as Bozza', (
      tester,
    ) async {
      await repo.createDraft(_rejectedReportCompanion());
      final source = (await repo.getDraft('report-1'))!;

      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);

      expect(newId, isNotNull);
      expect(newId, isNot('report-1'), reason: 'a new report id, not the rejected one');

      final newDraft = await repo.getDraft(newId!);
      expect(newDraft, isNotNull);
      expect(newDraft!.title, 'Manutenzione impianto');
      expect(newDraft.details, 'Sostituita guarnizione');
      expect(newDraft.technicianNotes, 'Da ricontrollare tra 6 mesi');
      expect(newDraft.ticketId, 'ticket-1');
      expect(newDraft.scheduleId, 'sched-1');
      expect(newDraft.customerId, 'cust-1');
      expect(newDraft.stato, 'Bozza');
      expect(newDraft.isLocalOnly, isTrue);
      expect(newDraft.submissionState, 'draft');

      // The rejected report itself is left exactly as it was.
      final original = await repo.getDraft('report-1');
      expect(original!.stato, 'Respinto');
    });

    testWidgets('does not carry over signatures or customer sign-off', (tester) async {
      await repo.createDraft(_rejectedReportCompanion());
      final source = (await repo.getDraft('report-1'))!;

      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);
      final newDraft = await repo.getDraft(newId!);

      expect(newDraft!.customerSignatureAllegatoId, isNull);
      expect(newDraft.technicianSignatureAllegatoId, isNull);
      expect(newDraft.customerSignoffText, isNull);
    });

    testWidgets('clones staff, materiali and controlli rows under the new report id', (
      tester,
    ) async {
      await repo.createDraft(_rejectedReportCompanion());
      await repo.upsertStaff(
        ReportStaffTableCompanion.insert(
          id: 's-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: 'report-1',
          userId: 'user-1',
          hoursWorked: const Value(4.0),
          kmTraveled: const Value(20.0),
        ),
      );
      await repo.upsertMateriale(
        ReportMaterialiCompanion.insert(
          id: 'm-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: 'report-1',
          freeTextName: const Value('Guarnizione'),
          quantity: 2.0,
        ),
      );
      await repo.upsertControllo(
        ReportControlliCompanion.insert(
          id: 'c-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          reportId: 'report-1',
          controlId: 'ctrl-1',
          stringValue: const Value('120 bar'),
        ),
      );

      final source = (await repo.getDraft('report-1'))!;
      final container = buildContainer(user: _testUser);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);

      final newStaff = await repo.getStaff(newId!);
      expect(newStaff, hasLength(1));
      expect(newStaff.single.userId, 'user-1');
      expect(newStaff.single.hoursWorked, 4.0);
      expect(newStaff.single.id, isNot('s-1'), reason: 'a new row id, not reusing the source one');

      final newMateriali = await repo.getMateriali(newId);
      expect(newMateriali, hasLength(1));
      expect(newMateriali.single.freeTextName, 'Guarnizione');
      expect(newMateriali.single.quantity, 2.0);

      final newControlli = await repo.getControlli(newId);
      expect(newControlli, hasLength(1));
      expect(newControlli.single.controlId, 'ctrl-1');
      expect(newControlli.single.stringValue, '120 bar');

      // The rejected report's own child rows are untouched.
      expect((await repo.getStaff('report-1')).single.id, 's-1');
    });

    testWidgets('refuses (returns null) with no signed-in author, same as createLocalDraft', (
      tester,
    ) async {
      await repo.createDraft(_rejectedReportCompanion());
      final source = (await repo.getDraft('report-1'))!;

      final container = buildContainer(user: null);
      addTearDown(container.dispose);

      final newId = await _callCreateReworkDraft(tester, container, source);
      expect(newId, isNull);

      // Nothing was created. A one-shot query, not `.watchAllReports()`: a live `.watch()`
      // stream subscription left open inside a testWidgets body races this Flutter test binding's
      // teardown against Drift's NativeDatabase closing ("Bad state: Cannot close sink while
      // adding stream") — unrelated to correctness, but a `test`-vs-`testWidgets` interaction
      // worth avoiding here rather than working around per-run.
      final rows = await db.select(db.draftReports).get();
      expect(rows, hasLength(1));
    });
  });

  group('createCantiereReportDraft', () {
    testWidgets('reuses the backend-issued report id for the local draft', (tester) async {
      final api = _FakeCantiereReportApiClient(reportIdToReturn: 'server-report-1');
      final container = buildContainer(user: _testUser, cantiereReportApi: api);
      addTearDown(container.dispose);

      final id = await _callCreateCantiereReportDraft(
        tester,
        container,
        cantiereId: 'cant-1',
        cantiereName: 'Cantiere Via Roma',
      );

      expect(api.calledWithCantiereId, 'cant-1');
      expect(id, 'server-report-1');

      final draft = await repo.getDraft('server-report-1');
      expect(draft, isNotNull, reason: 'the local draft must be keyed by the backend report id');
      expect(draft!.cantiereId, 'cant-1');
      expect(draft.title, 'Rapportino — Cantiere Via Roma');
      expect(draft.isLocalOnly, isTrue);
      expect(draft.stato, 'Bozza');
      expect(draft.ticketId, isNull, reason: 'a cantiere-originated draft has no ticket link');
    });

    testWidgets('hydrates staff rows with the hours the backend already seeded', (tester) async {
      final api = _FakeCantiereReportApiClient(
        reportIdToReturn: 'server-report-2',
        staffToReturn: [
          ReportStaffSeedDto(
            userId: 'user-1',
            hoursWorked: 4.5,
            kmTraveled: 12,
            startTime: DateTime.utc(2026, 8, 16, 7),
            endTime: DateTime.utc(2026, 8, 16, 11, 30),
          ),
          const ReportStaffSeedDto(userId: 'user-2', hoursWorked: 3),
        ],
      );
      final container = buildContainer(user: _testUser, cantiereReportApi: api);
      addTearDown(container.dispose);

      final id = await _callCreateCantiereReportDraft(
        tester,
        container,
        cantiereId: 'cant-1',
        cantiereName: 'Cantiere Via Roma',
      );

      final staff = await repo.getStaff(id!);
      expect(staff, hasLength(2));
      final byUser = {for (final s in staff) s.userId: s};
      expect(byUser['user-1']!.hoursWorked, 4.5);
      expect(byUser['user-1']!.kmTraveled, 12);
      // Drift's DateTime column round-trips through local wall-clock time, not UTC — compare in
      // UTC (same convention as SubmitReportStaffDto.toJson's own .toUtc() calls) rather than
      // asserting the value came back with its original timezone tag intact.
      expect(byUser['user-1']!.startTime!.toUtc(), DateTime.utc(2026, 8, 16, 7));
      expect(byUser['user-2']!.hoursWorked, 3);
    });

    testWidgets(
      'seeds the creating technician as a blank staff row when the backend returns zero — '
      'same default as manual entry',
      (tester) async {
        final api = _FakeCantiereReportApiClient(reportIdToReturn: 'server-report-3');
        final container = buildContainer(user: _testUser, cantiereReportApi: api);
        addTearDown(container.dispose);

        final id = await _callCreateCantiereReportDraft(
          tester,
          container,
          cantiereId: 'cant-1',
          cantiereName: 'Cantiere Via Roma',
        );

        final staff = await repo.getStaff(id!);
        expect(staff, hasLength(1));
        expect(staff.single.userId, _testUser.id);
        expect(staff.single.hoursWorked, isNull);
      },
    );

    testWidgets(
      'still creates the local draft with the zero-worklogs fallback when fetching staff fails',
      (tester) async {
        final api = _FakeCantiereReportApiClient(reportIdToReturn: 'server-report-4')
          ..throwsOnFetchStaff = DioException(
            requestOptions: RequestOptions(path: '/api/reports/server-report-4'),
          );
        final container = buildContainer(user: _testUser, cantiereReportApi: api);
        addTearDown(container.dispose);

        final id = await _callCreateCantiereReportDraft(
          tester,
          container,
          cantiereId: 'cant-1',
          cantiereName: 'Cantiere Via Roma',
        );

        expect(
          id,
          'server-report-4',
          reason:
              'the backend Report already exists at this point — a failed hydration read must '
              'not orphan it with no local draft at all',
        );
        final staff = await repo.getStaff(id!);
        expect(staff, hasLength(1));
        expect(staff.single.userId, _testUser.id);
      },
    );

    testWidgets('persists workAddress into metadataJson, same shape as createLocalDraft', (
      tester,
    ) async {
      final api = _FakeCantiereReportApiClient(reportIdToReturn: 'server-report-5');
      final container = buildContainer(user: _testUser, cantiereReportApi: api);
      addTearDown(container.dispose);

      final id = await _callCreateCantiereReportDraft(
        tester,
        container,
        cantiereId: 'cant-1',
        cantiereName: 'Cantiere Via Roma',
        workAddress: 'Via Roma 10, Milano, 20100',
      );

      final draft = await repo.getDraft(id!);
      expect(draft!.metadataJson, contains('Via Roma 10, Milano, 20100'));
    });

    testWidgets(
      'refuses (returns null) with no signed-in author, without calling the backend',
      (tester) async {
        final api = _FakeCantiereReportApiClient();
        final container = buildContainer(user: null, cantiereReportApi: api);
        addTearDown(container.dispose);

        final id = await _callCreateCantiereReportDraft(
          tester,
          container,
          cantiereId: 'cant-1',
          cantiereName: 'Cantiere Via Roma',
        );

        expect(id, isNull);
        expect(api.calledWithCantiereId, isNull);
        expect(await db.select(db.draftReports).get(), isEmpty);
      },
    );
  });
}

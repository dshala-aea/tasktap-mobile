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

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/draft_report_repository.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/rapportino/create_draft.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

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

  ProviderContainer buildContainer({AuthUser? user}) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      currentUserProvider.overrideWithValue(user),
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
}

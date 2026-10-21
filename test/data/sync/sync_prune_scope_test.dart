import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

/// O-7b: the device mirror prunes to the server's authoritative `scope`.
///
/// The payload used to be upsert-only, so a row that left scope (a schedule past the window, a
/// ticket reassigned away, a report aged out, a deactivated material, a deleted customer, a
/// removed instrument) stayed on the phone forever. The prune fixes that — but a careless prune
/// is a new data-loss path, so these tests pin the four safety rules as hard as the deletions:
/// no scope ⇒ no prune, a null member ⇒ no prune for that collection, unsent local work pins
/// what it references, and locally-owned drafts are never candidates.
class MockDio extends Mock implements Dio {}

/// Sentinel for "the scope key is not on the wire at all".
const _absent = Object();

Response<Map<String, dynamic>> _ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

/// A payload with every array present and empty — the delta a device sees when nothing changed
/// but the scope moved. [scope] omitted entirely means an older backend; passing it explicitly as
/// null is the same thing spelled the other way on the wire.
Map<String, dynamic> _payload({
  Object? scope = _absent,
  List<Map<String, dynamic>> customers = const [],
  List<Map<String, dynamic>> tickets = const [],
  bool carryStrumenti = false,
  List<Map<String, dynamic>> strumenti = const [],
  bool carryChecklist = false,
  List<String> omittedTicketIds = const [],
}) => {
  'syncedAt': '2026-10-21T08:00:00Z',
  'since': null,
  if (!identical(scope, _absent)) 'scope': scope,
  'schedules': <Object>[],
  'draftReports': <Object>[],
  'submittedReports': <Object>[],
  'customers': customers,
  'locations': <Object>[],
  'tickets': tickets,
  'ticketMateriali': <Object>[],
  'materiali': <Object>[],
  'materialiBarcodes': <Object>[],
  'cantieri': <Object>[],
  'ticketStatuses': <Object>[],
  'ticketTypes': <Object>[],
  'colleagues': <Object>[],
  if (carryStrumenti) 'strumenti': strumenti,
  if (carryChecklist) ...{
    'controlGroups': <Object>[],
    'ticketControls': <Object>[],
    'ticketAssets': <Object>[],
    'assets': <Object>[],
    'reportStrumenti': <Object>[],
    'checklistTruncated': false,
    'checklistOmittedTicketIds': omittedTicketIds,
  },
};

/// A scope object with only the collections named in [ids]; every other member is null (no
/// authoritative set). Passing a member explicitly as null keeps it in the map — which is what
/// `strumenti` looks like for a caller without instrument permission.
Map<String, dynamic> _scope(Map<String, Object?> ids) => {
  'schedules': null,
  'tickets': null,
  'locations': null,
  'customers': null,
  'cantieri': null,
  'agents': null,
  'draftReports': null,
  'submittedReports': null,
  'materiali': null,
  'materialiBarcodes': null,
  'strumenti': null,
  ...ids,
};

Map<String, dynamic> _customerJson(String id) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'companyName': 'ACME $id',
  'isActive': true,
};

void main() {
  late AppDatabase db;
  late MockDio dio;
  late SyncService svc;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
    svc = SyncService(db: db, dio: dio);
  });

  tearDown(() => db.close());

  void respond(Map<String, dynamic> body) {
    when(
      () => dio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _ok(body));
  }

  // ── Seed helpers ──────────────────────────────────────────────────────────

  Future<void> seedCustomer(String id, {String? agentId}) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          companyName: 'ACME $id',
          agentId: Value(agentId),
        ),
      );

  Future<void> seedLocation(String id, {String customerId = 'cust-1'}) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          customerId: customerId,
          name: 'Sede $id',
        ),
      );

  Future<void> seedAgent(String id) => db
      .into(db.agents)
      .insert(
        AgentsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          nome: 'Agente $id',
        ),
      );

  Future<void> seedCantiere(String id) => db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          name: 'Cantiere $id',
        ),
      );

  Future<void> seedTicket(
    String id, {
    String customerId = 'cust-1',
    String locationId = 'loc-1',
    String? agentId,
    String? cantiereId,
  }) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          title: 'Ticket $id',
          customerId: customerId,
          locationId: locationId,
          statusId: 1,
          typeId: 1,
          agentId: Value(agentId),
          cantiereId: Value(cantiereId),
        ),
      );

  Future<void> seedSchedule(String id, {String? ticketId}) => db
      .into(db.schedules)
      .insert(
        SchedulesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          ticketId: Value(ticketId),
          activityDate: DateTime.utc(2026, 10, 21),
          timeStartMinutes: 480,
          timeEndMinutes: 1020,
          userId: 'user-1',
          statusId: 1,
          locationId: 'loc-1',
          title: 'Schedule $id',
          description: '',
        ),
      );

  Future<void> seedMateriale(String id) => db
      .into(db.materiali)
      .insert(
        MaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          code: 'C-$id',
          name: 'Materiale $id',
        ),
      );

  Future<void> seedBarcode(String id, {String materialeId = 'mat-1'}) => db
      .into(db.materialeBarcodes)
      .insert(
        MaterialeBarcodesCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          materialeId: materialeId,
          barcode: 'BC-$id',
        ),
      );

  Future<void> seedStrumento(String id) => db
      .into(db.strumenti)
      .insert(StrumentiCompanion.insert(id: id, name: 'Strumento $id', matricola: 'M-$id'));

  Future<void> seedTicketMateriale(String id, {String ticketId = 'ticket-1'}) => db
      .into(db.ticketMateriali)
      .insert(
        TicketMaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          ticketId: ticketId,
          quantity: 1.0,
        ),
      );

  Future<void> seedTicketControl(String id, {String ticketId = 'ticket-1'}) => db
      .into(db.ticketControls)
      .insert(
        TicketControlsCompanion.insert(
          id: id,
          ticketId: ticketId,
          templateControlId: 'tc-$id',
          controlLineageId: 'lineage-$id',
          groupId: 'g1',
          label: 'Controllo $id',
          type: 'Text',
        ),
      );

  Future<void> seedTicketAsset({String ticketId = 'ticket-1'}) => db
      .into(db.ticketAssets)
      .insert(
        TicketAssetsCompanion.insert(ticketId: ticketId, prodottoAssistenzaId: 'pa-1'),
      );

  Future<void> seedDraft(
    String id, {
    bool isLocalOnly = false,
    String stato = 'Bozza',
    String submissionState = 'draft',
    String? ticketId,
    String? customerId,
    String? locationId,
    String? cantiereId,
  }) => db
      .into(db.draftReports)
      .insert(
        DraftReportsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          title: 'Rapportino $id',
          ticketId: Value(ticketId),
          customerId: Value(customerId),
          cantiereId: Value(cantiereId),
          insertedUserId: 'user-1',
          locationId: locationId ?? 'loc-1',
          stato: Value(stato),
          submissionState: Value(submissionState),
          isLocalOnly: Value(isLocalOnly),
        ),
      );

  Future<void> seedReportMateriale(String id, {required String reportId, String? materialeId}) => db
      .into(db.reportMateriali)
      .insert(
        ReportMaterialiCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          reportId: reportId,
          materialeId: Value(materialeId),
          quantity: 1.0,
        ),
      );

  Future<void> seedReportControllo(String id, {required String reportId}) => db
      .into(db.reportControlli)
      .insert(
        ReportControlliCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026),
          reportId: reportId,
          controlId: 'ctrl-1',
        ),
      );

  Future<void> seedReportStrumento(String id, {required String reportId, String? strumentoId}) => db
      .into(db.reportStrumenti)
      .insert(
        ReportStrumentiCompanion.insert(
          id: id,
          reportId: reportId,
          strumentoId: Value(strumentoId),
          name: 'Strumento $id',
          matricola: 'M-$id',
        ),
      );

  Future<void> seedPendingAttachment(String id, {required String ticketId}) => db
      .into(db.pendingTicketAttachments)
      .insert(
        PendingTicketAttachmentsCompanion.insert(
          id: id,
          createdAt: DateTime.utc(2026),
          ticketId: ticketId,
          localPath: '/tmp/$id.jpg',
          fileName: '$id.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 10,
        ),
      );

  Future<void> seedCantierePunch(String id, {String cantiereId = 'cantiere-1'}) => db
      .into(db.cantierePunches)
      .insert(
        CantierePunchesCompanion.insert(
          id: id,
          eventTime: DateTime.utc(2026, 10, 20, 8),
          eventType: 'ingresso',
          cantiereId: Value(cantiereId),
        ),
      );

  // ── One deletion per collection family ────────────────────────────────────

  group('a row that left scope is deleted', () {
    test('schedule — and its assignments go with it', () async {
      await seedSchedule('sched-1');
      await db
          .into(db.scheduleAssignees)
          .insert(
            ScheduleAssigneesCompanion.insert(scheduleId: 'sched-1', userId: 'user-1'),
          );

      respond(_payload(scope: _scope({'schedules': <String>[]})));
      await svc.sync();

      expect(await db.select(db.schedules).get(), isEmpty);
      expect(
        await db.select(db.scheduleAssignees).get(),
        isEmpty,
        reason: 'the one real foreign key in the schema must not be left dangling',
      );
    });

    test('ticket', () async {
      await seedTicket('ticket-1');

      respond(_payload(scope: _scope({'tickets': <String>[]})));
      await svc.sync();

      expect(await db.select(db.tickets).get(), isEmpty);
    });

    test('location', () async {
      await seedLocation('loc-1');

      respond(_payload(scope: _scope({'locations': <String>[]})));
      await svc.sync();

      expect(await db.select(db.locations).get(), isEmpty);
    });

    test('customer', () async {
      await seedCustomer('cust-1');

      respond(_payload(scope: _scope({'customers': <String>[]})));
      await svc.sync();

      expect(await db.select(db.customers).get(), isEmpty);
    });

    test('cantiere', () async {
      await seedCantiere('cantiere-1');

      respond(_payload(scope: _scope({'cantieri': <String>[]})));
      await svc.sync();

      expect(await db.select(db.cantieri).get(), isEmpty);
    });

    test('agent', () async {
      await seedAgent('agent-1');

      respond(_payload(scope: _scope({'agents': <String>[]})));
      await svc.sync();

      expect(await db.select(db.agents).get(), isEmpty);
    });

    test('material', () async {
      await seedMateriale('mat-1');

      respond(_payload(scope: _scope({'materiali': <String>[]})));
      await svc.sync();

      expect(await db.select(db.materiali).get(), isEmpty);
    });

    test('barcode', () async {
      await seedMateriale('mat-1');
      await seedBarcode('bc-1');

      respond(_payload(scope: _scope({'materialiBarcodes': <String>[]})));
      await svc.sync();

      expect(await db.select(db.materialeBarcodes).get(), isEmpty);
      expect(
        await db.select(db.materiali).get(),
        hasLength(1),
        reason: 'a barcode manifest says nothing about the material catalogue',
      );
    });

    test('instrument, when scope.strumenti is an empty list', () async {
      await seedStrumento('s1');

      respond(
        _payload(
          scope: _scope({'strumenti': <String>[]}),
          carryStrumenti: true,
          strumenti: const [],
        ),
      );
      await svc.sync();

      expect(await db.select(db.strumenti).get(), isEmpty);
    });
  });

  // ── Pins: unsent local work keeps what it references ──────────────────────

  test(
    'a ticket an unsent local draft points at survives, with its customer, location and agent',
    () async {
      await seedAgent('agent-1');
      await seedCustomer('cust-1', agentId: 'agent-1');
      await seedLocation('loc-1');
      await seedTicket('ticket-1', agentId: 'agent-1');
      await seedDraft(
        'draft-1',
        isLocalOnly: true,
        ticketId: 'ticket-1',
        customerId: 'cust-1',
        locationId: 'loc-1',
      );
      // Out of scope but unreferenced: proves the prune really ran.
      await seedTicket('ticket-gone');

      respond(
        _payload(
          scope: _scope({
            'schedules': <String>[],
            'tickets': <String>[],
            'locations': <String>[],
            'customers': <String>[],
            'agents': <String>[],
            'draftReports': <String>[],
            'submittedReports': <String>[],
          }),
        ),
      );
      await svc.sync();

      expect(
        (await db.select(db.tickets).get()).map((t) => t.id),
        ['ticket-1'],
        reason: 'the ticket a draft still needs must stay readable, not hidden',
      );
      expect((await db.select(db.customers).get()).map((c) => c.id), ['cust-1']);
      expect((await db.select(db.locations).get()).map((l) => l.id), ['loc-1']);
      expect((await db.select(db.agents).get()).map((a) => a.id), ['agent-1']);
      expect((await db.select(db.draftReports).get()).map((r) => r.id), ['draft-1']);
    },
  );

  test('a local draft pins the materials and instruments its rows reference', () async {
    await seedDraft('draft-1', isLocalOnly: true);
    await seedMateriale('mat-1');
    await seedStrumento('s1');
    await seedReportMateriale('rm-1', reportId: 'draft-1', materialeId: 'mat-1');
    await seedReportStrumento('rs-1', reportId: 'draft-1', strumentoId: 's1');
    await seedMateriale('mat-gone');
    await seedStrumento('s-gone');

    respond(
      _payload(
        scope: _scope({'materiali': <String>[], 'strumenti': <String>[]}),
        carryStrumenti: true,
        strumenti: const [],
      ),
    );
    await svc.sync();

    expect((await db.select(db.materiali).get()).map((m) => m.id), ['mat-1']);
    expect(
      (await db.select(db.strumenti).get()).map((s) => s.id),
      ['s1'],
      reason: 'the wholesale instrument replace must honour the pins too',
    );
  });

  test('a cantiere survives while a cantiere punch is pending', () async {
    await seedCantiere('cantiere-1');
    await seedCantiere('cantiere-gone');
    await seedCantierePunch('punch-1', cantiereId: 'cantiere-1');

    respond(_payload(scope: _scope({'cantieri': <String>[]})));
    await svc.sync();

    expect((await db.select(db.cantieri).get()).map((k) => k.id), ['cantiere-1']);
  });

  test('a pending ticket pins its customer, location, cantiere and agent', () async {
    await seedCustomer('cust-1');
    await seedLocation('loc-1');
    await seedAgent('agent-1');
    await seedCantiere('cantiere-1');
    await db
        .into(db.pendingTickets)
        .insert(
          PendingTicketsCompanion.insert(
            id: 'pending-1',
            createdAt: DateTime.utc(2026),
            title: 'Nuovo ticket',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            agentId: const Value('agent-1'),
            cantiereId: const Value('cantiere-1'),
          ),
        );

    respond(
      _payload(
        scope: _scope({
          'customers': <String>[],
          'locations': <String>[],
          'agents': <String>[],
          'cantieri': <String>[],
        }),
      ),
    );
    await svc.sync();

    expect(await db.select(db.customers).get(), hasLength(1));
    expect(await db.select(db.locations).get(), hasLength(1));
    expect(await db.select(db.agents).get(), hasLength(1));
    expect(await db.select(db.cantieri).get(), hasLength(1));
    expect(
      await db.select(db.pendingTickets).get(),
      hasLength(1),
      reason: 'the queued ticket itself is never a prune candidate',
    );
  });

  // ── Reports ───────────────────────────────────────────────────────────────

  test('a locally-owned draft is never pruned, and neither are its child rows', () async {
    await seedDraft('draft-local', isLocalOnly: true);
    await seedReportMateriale('rm-1', reportId: 'draft-local', materialeId: 'mat-1');
    await seedReportControllo('rc-1', reportId: 'draft-local');

    respond(_payload(scope: _scope({'draftReports': <String>[], 'submittedReports': <String>[]})));
    await svc.sync();

    expect((await db.select(db.draftReports).get()).map((r) => r.id), ['draft-local']);
    expect(await db.select(db.reportMateriali).get(), hasLength(1));
    expect(await db.select(db.reportControlli).get(), hasLength(1));
  });

  test(
    'a server draft absent from its manifest and unsent is kept; once submitted-then-gone it is pruned',
    () async {
      // Server-known (isLocalOnly false), still a Bozza, never submitted from this device.
      await seedDraft('draft-unsent');
      await seedReportMateriale('rm-kept', reportId: 'draft-unsent', materialeId: 'mat-1');
      // Submitted from this device: markSubmitted leaves stato=Inviato and submissionState=submitted.
      await seedDraft('draft-submitted', stato: 'Inviato', submissionState: 'submitted');
      await seedReportMateriale('rm-gone', reportId: 'draft-submitted', materialeId: 'mat-1');
      await seedReportControllo('rc-gone', reportId: 'draft-submitted');
      await seedReportStrumento('rs-gone', reportId: 'draft-submitted', strumentoId: 's1');

      respond(
        _payload(scope: _scope({'draftReports': <String>[], 'submittedReports': <String>[]})),
      );
      await svc.sync();

      expect(
        (await db.select(db.draftReports).get()).map((r) => r.id),
        ['draft-unsent'],
        reason: 'unsent work is never deleted on the strength of a manifest',
      );
      expect(await db.select(db.reportMateriali).get(), hasLength(1));
      expect(await db.select(db.reportControlli).get(), isEmpty);
      expect(await db.select(db.reportStrumenti).get(), isEmpty);
    },
  );

  // ── No scope / null member ────────────────────────────────────────────────

  Future<void> seedEverything() async {
    await seedAgent('agent-1');
    await seedCustomer('cust-1', agentId: 'agent-1');
    await seedLocation('loc-1');
    await seedCantiere('cantiere-1');
    await seedTicket('ticket-1');
    await seedSchedule('sched-1', ticketId: 'ticket-1');
    await seedMateriale('mat-1');
    await seedBarcode('bc-1');
    await seedStrumento('s1');
    await seedDraft('draft-1');
  }

  Future<void> expectEverythingStillThere() async {
    expect(await db.select(db.agents).get(), hasLength(1));
    expect(await db.select(db.customers).get(), hasLength(1));
    expect(await db.select(db.locations).get(), hasLength(1));
    expect(await db.select(db.cantieri).get(), hasLength(1));
    expect(await db.select(db.tickets).get(), hasLength(1));
    expect(await db.select(db.schedules).get(), hasLength(1));
    expect(await db.select(db.materiali).get(), hasLength(1));
    expect(await db.select(db.materialeBarcodes).get(), hasLength(1));
    expect(await db.select(db.strumenti).get(), hasLength(1));
    expect(await db.select(db.draftReports).get(), hasLength(1));
  }

  test('an older backend with no scope key deletes nothing', () async {
    await seedEverything();

    // No `scope` member and no `strumenti` member at all: the pre-v2 shape.
    respond(_payload());
    await svc.sync();

    await expectEverythingStillThere();
  });

  test('an explicit null scope deletes nothing', () async {
    await seedEverything();

    respond(_payload(scope: null));
    await svc.sync();

    await expectEverythingStillThere();
  });

  test('scope.strumenti == null leaves instruments untouched, even with an empty row list', () async {
    await seedStrumento('s1');
    await seedStrumento('s2');

    respond(
      _payload(
        // What the server sends a caller without team.strumento.read: instrumenti null in the
        // scope and an empty row list on the payload.
        scope: _scope(const <String, Object?>{}),
        carryStrumenti: true,
        strumenti: const [],
      ),
    );
    await svc.sync();

    expect(
      (await db.select(db.strumenti).get()).map((s) => s.id).toSet(),
      {'s1', 's2'},
      reason: 'null means "no authoritative set", not "nothing is in scope"',
    );
  });

  test('scope.strumenti == [] prunes an unpinned instrument but keeps a pinned one', () async {
    await seedStrumento('s1');
    await seedStrumento('s2');
    await seedDraft('draft-1', isLocalOnly: true);
    await seedReportStrumento('rs-1', reportId: 'draft-1', strumentoId: 's2');

    respond(
      _payload(
        scope: _scope({'strumenti': <String>[]}),
        carryStrumenti: true,
        strumenti: const [],
      ),
    );
    await svc.sync();

    expect((await db.select(db.strumenti).get()).map((s) => s.id), ['s2']);
  });

  // ── Children ──────────────────────────────────────────────────────────────

  test('ticket_materiali follows its ticket: pruned with it, kept with a pinned ticket', () async {
    await seedTicket('ticket-1');
    await seedTicket('ticket-2');
    await seedTicketMateriale('tm-1', ticketId: 'ticket-1');
    await seedTicketMateriale('tm-2', ticketId: 'ticket-2');
    await seedPendingAttachment('att-1', ticketId: 'ticket-2');

    respond(_payload(scope: _scope({'tickets': <String>[]})));
    await svc.sync();

    expect((await db.select(db.tickets).get()).map((t) => t.id), ['ticket-2']);
    expect(
      (await db.select(db.ticketMateriali).get()).map((m) => m.id),
      ['tm-2'],
      reason: 'fabbisogno is keyed by ticket and has no manifest of its own',
    );
  });

  test('checklist rows of a pruned ticket go with it', () async {
    await seedTicket('ticket-1');
    await seedTicketControl('ctrl-1', ticketId: 'ticket-1');
    await seedTicketAsset(ticketId: 'ticket-1');

    respond(_payload(scope: _scope({'tickets': <String>[]})));
    await svc.sync();

    expect(await db.select(db.ticketControls).get(), isEmpty);
    expect(await db.select(db.ticketAssets).get(), isEmpty);
  });

  test('a checklist omission prunes nothing: the checklist is not read as a manifest', () async {
    await seedTicket('ticket-1');
    await seedTicketControl('ctrl-1', ticketId: 'ticket-1');
    await seedTicketAsset(ticketId: 'ticket-1');

    // The server truncated this ticket's checklist out of the payload. Its ticket is still in
    // scope, and the omission says nothing about any manifest.
    respond(
      _payload(
        scope: _scope({'tickets': <String>['ticket-1']}),
        carryChecklist: true,
        omittedTicketIds: const ['ticket-1'],
      ),
    );
    await svc.sync();

    expect(
      await db.select(db.ticketControls).get(),
      hasLength(1),
      reason: 'checklistOmittedTicketIds withholds rows deliberately — never a deletion',
    );
    expect(await db.select(db.ticketAssets).get(), hasLength(1));
  });

  // ── Transaction boundary ──────────────────────────────────────────────────

  test('a failure mid-prune leaves the whole mirror unchanged', () async {
    // No existing suite asserts a transaction boundary, so this uses SQLite itself: a trigger
    // that aborts the ticket delete makes the prune fail several deletes in, and the rollback is
    // the same one every other statement in sync() shares.
    await db.customStatement(
      'CREATE TRIGGER fail_ticket_delete BEFORE DELETE ON tickets '
      "BEGIN SELECT RAISE(ABORT, 'boom'); END;",
    );
    await seedCustomer('cust-old');
    await seedSchedule('sched-old');
    await seedTicket('ticket-old');

    respond(
      _payload(
        scope: _scope({
          'schedules': <String>[],
          'tickets': <String>[],
          'customers': <String>[],
        }),
        customers: [_customerJson('cust-new')],
      ),
    );

    await expectLater(svc.sync(), throwsA(anything));

    expect(
      (await db.select(db.customers).get()).map((c) => c.id),
      ['cust-old'],
      reason: 'the upsert in this transaction must roll back with the prune',
    );
    expect(
      await db.select(db.schedules).get(),
      hasLength(1),
      reason: 'the schedule delete ran before the failing one and must roll back too',
    );
    expect(await db.select(db.tickets).get(), hasLength(1));
    expect(
      await db.getLastSync(),
      isNull,
      reason: 'a failed sync must not advance the cursor',
    );
  });
}

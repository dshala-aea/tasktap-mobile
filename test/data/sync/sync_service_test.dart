// Tests for SyncService — M3
//
// Uses an in-memory Drift DB and a mocked Dio so no real network is needed.
// Verifies:
//   - New entities are inserted on first sync.
//   - Existing entities are updated (upsert) on subsequent sync.
//   - lastSync is updated after each successful sync.
//   - The `since` query param is sent when lastSync is set.
//   - Providers emit cached data from Drift without a network call.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/timbra/cantiere_timbra_screen.dart' show cantieriProvider;
import 'package:tasktap_mobile/presentation/providers/schedule_providers.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class MockDio extends Mock implements Dio {}

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Creates an in-memory Drift DB for tests.
AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Build a minimal sync payload JSON map.
Map<String, dynamic> _syncPayload({
  DateTime? syncedAt,
  DateTime? since,
  List<Map<String, dynamic>> schedules = const [],
  List<Map<String, dynamic>> draftReports = const [],
  List<Map<String, dynamic>> submittedReports = const [],
  List<Map<String, dynamic>> customers = const [],
  List<Map<String, dynamic>> locations = const [],
  List<Map<String, dynamic>> tickets = const [],
  List<Map<String, dynamic>> ticketStatuses = const [],
  List<Map<String, dynamic>> ticketTypes = const [],
  List<Map<String, dynamic>> materiali = const [],
  List<Map<String, dynamic>> materialiBarcodes = const [],
  List<Map<String, dynamic>> cantieri = const [],
  List<Map<String, dynamic>> colleagues = const [],
}) {
  return {
    'syncedAt': (syncedAt ?? DateTime.utc(2026, 6, 21, 12)).toIso8601String(),
    'since': since?.toIso8601String(),
    'schedules': schedules,
    'draftReports': draftReports,
    'submittedReports': submittedReports,
    'customers': customers,
    'locations': locations,
    'tickets': tickets,
    'ticketStatuses': ticketStatuses,
    'ticketTypes': ticketTypes,
    'materiali': materiali,
    'materialiBarcodes': materialiBarcodes,
    'cantieri': cantieri,
    'colleagues': colleagues,
  };
}

Map<String, dynamic> _customerJson({String id = 'cust-1', String companyName = 'ACME Srl'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'companyName': companyName,
  'taxId': null,
  'address': 'Via Roma 1',
  'city': 'Milano',
  'postalCode': '20121',
  'country': 'IT',
  'phone': null,
  'email': null,
  'contactPerson': null,
  'notes': null,
  'isActive': true,
};

Map<String, dynamic> _locationJson({
  String id = 'loc-1',
  String customerId = 'cust-1',
  String name = 'Sede principale',
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'customerId': customerId,
  'name': name,
  'address': 'Via Roma 1',
  'city': 'Milano',
  'postalCode': '20121',
  'country': 'IT',
  'latitude': null,
  'longitude': null,
  'phone': null,
  'notes': null,
  'isActive': true,
};

Map<String, dynamic> _scheduleJson({
  String id = 'sched-1',
  String title = 'Manutenzione',
  String? updatedAt,
  String activityDate = '2026-06-21T00:00:00Z',
  List<Map<String, dynamic>>? assignees,
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': updatedAt,
  'ticketId': null,
  'activityDate': activityDate,
  'timeStart': '08:00:00',
  'timeEnd': '17:00:00',
  'userId': 'user-1',
  'statusId': 1,
  'locationId': 'loc-1',
  'allDay': false,
  'title': title,
  'description': 'Descrizione intervento',
  'assignees':
      assignees ??
      [
        {
          'userId': 'user-1',
          'isUserActive': true,
          'isDirect': true,
          'isLead': false,
          'isTeam': false,
          'isLegacyStaff': false,
        },
      ],
};

Map<String, dynamic> _ticketJson({String id = 'ticket-1'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'title': 'Intervento urgente',
  'description': null,
  'customerId': 'cust-1',
  'locationId': 'loc-1',
  'assignedUserId': 'user-1',
  'statusId': 1,
  'typeId': 1,
  'agentId': null,
  'closedAt': null,
  'technicianNotes': null,
  'internalNotes': null,
  'contractId': null,
  'prodottoAssistenzaId': null,
  'commessaId': null,
};

Map<String, dynamic> _ticketStatusJson({int id = 1, String name = 'Aperto'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'name': name,
  'isDefault': true,
  'isClosed': false,
};

Map<String, dynamic> _ticketTypeJson({int id = 1, String name = 'Assistenza'}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'name': name,
  'description': null,
};

Map<String, dynamic> _draftReportJson({
  String id = 'report-1',
  String stato = 'Bozza',
  String? updatedAt,
}) => {
  'id': id,
  'tenantId': 'tenant-1',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': updatedAt,
  'title': 'Rapportino bozza',
  'scheduleId': null,
  'ticketId': 'ticket-1',
  'customerId': 'cust-1',
  'details': null,
  'insertedUserId': 'user-1',
  'locationId': 'loc-1',
  'startedAt': null,
  'endedAt': null,
  'documentTemplateId': null,
  'customerSignatureAllegatoId': null,
  'technicianSignatureAllegatoId': null,
  'technicianNotes': null,
  'closedAt': null,
  'stato': stato,
  'inviatoAt': null,
  'controllatoAt': null,
  'controllatoDa': null,
  'fatturatoAt': null,
  'materialiNotRequired': false,
  'customerSignoffText': null,
  'customerSignoffAt': null,
};

/// Stub a Dio GET response with the given JSON body.
void _stubDioGet(MockDio mockDio, Map<String, dynamic> body, {Map<String, dynamic>? queryParams}) {
  when(
    () => mockDio.get<Map<String, dynamic>>(
      any(),
      queryParameters: queryParams != null
          ? captureAny(named: 'queryParameters')
          : any(named: 'queryParameters'),
    ),
  ).thenAnswer(
    (_) async => Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/api/sync/mobile'),
      statusCode: 200,
      data: body,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  _colleagueTests();
  late AppDatabase db;
  late MockDio mockDio;
  late SyncService svc;

  setUp(() {
    db = _makeDb();
    mockDio = MockDio();
    svc = SyncService(db: db, dio: mockDio);
  });

  tearDown(() async {
    await db.close();
  });

  // ── Insert new entities ────────────────────────────────────────────────────

  group('sync — insert new entities', () {
    test('inserts a new customer', () async {
      _stubDioGet(mockDio, _syncPayload(customers: [_customerJson()]));

      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'cust-1');
      expect(rows.first.companyName, 'ACME Srl');
    });

    test('inserts a new location', () async {
      _stubDioGet(mockDio, _syncPayload(locations: [_locationJson()]));

      await svc.sync();

      final rows = await db.select(db.locations).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'loc-1');
      expect(rows.first.name, 'Sede principale');
    });

    test('inserts a new ticket', () async {
      _stubDioGet(mockDio, _syncPayload(tickets: [_ticketJson()]));

      await svc.sync();

      final rows = await db.select(db.tickets).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'ticket-1');
    });

    test('inserts a new schedule with parsed time minutes', () async {
      _stubDioGet(mockDio, _syncPayload(schedules: [_scheduleJson()]));

      await svc.sync();

      final rows = await db.select(db.schedules).get();
      expect(rows.length, 1);
      final s = rows.first;
      expect(s.id, 'sched-1');
      expect(s.title, 'Manutenzione');
      // 08:00 → 480 minutes; 17:00 → 1020 minutes
      expect(s.timeStartMinutes, 480);
      expect(s.timeEndMinutes, 1020);
    });

    test('stores who is on a schedule', () async {
      _stubDioGet(mockDio, _syncPayload(schedules: [_scheduleJson()]));

      await svc.sync();

      final assignees = await db.select(db.scheduleAssignees).get();
      expect(assignees.length, 1);
      expect(assignees.first.scheduleId, 'sched-1');
      expect(assignees.first.userId, 'user-1');
      expect(assignees.first.isDirect, isTrue);
    });

    // The case the four dropped columns could not express at all: a job assigned to a squadra
    // named nobody the device could see.
    test('stores squadra members the old columns could not express', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          schedules: [
            _scheduleJson(
              assignees: [
                {
                  'userId': 'member-1',
                  'isUserActive': true,
                  'isDirect': false,
                  'isLead': false,
                  'isTeam': true,
                  'isLegacyStaff': false,
                },
                {
                  'userId': 'member-2',
                  'isUserActive': true,
                  'isDirect': false,
                  'isLead': false,
                  'isTeam': true,
                  'isLegacyStaff': false,
                },
              ],
            ),
          ],
        ),
      );

      await svc.sync();

      final assignees = await db.select(db.scheduleAssignees).get();
      expect(assignees.length, 2);
      expect(assignees.every((a) => a.isTeam), isTrue);
    });

    // Someone taken off a squadra stops appearing on the server; they must stop appearing here
    // too, which a merge-only upsert would never achieve.
    test('a removed assignee disappears on the next sync', () async {
      _stubDioGet(mockDio, _syncPayload(schedules: [_scheduleJson()]));
      await svc.sync();

      _stubDioGet(
        mockDio,
        _syncPayload(
          schedules: [_scheduleJson(updatedAt: '2026-06-22T00:00:00Z', assignees: const [])],
        ),
      );
      await svc.sync();

      expect(await db.select(db.scheduleAssignees).get(), isEmpty);
    });

    test('inserts a new draft report', () async {
      _stubDioGet(mockDio, _syncPayload(draftReports: [_draftReportJson()]));

      await svc.sync();

      final rows = await db.select(db.draftReports).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'report-1');
      expect(rows.first.stato, 'Bozza');
    });

    test('inserts multiple entities in one sync', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          customers: [_customerJson()],
          locations: [_locationJson()],
          tickets: [_ticketJson()],
          schedules: [_scheduleJson()],
          draftReports: [_draftReportJson()],
        ),
      );

      await svc.sync();

      expect((await db.select(db.customers).get()).length, 1);
      expect((await db.select(db.locations).get()).length, 1);
      expect((await db.select(db.tickets).get()).length, 1);
      expect((await db.select(db.schedules).get()).length, 1);
      expect((await db.select(db.draftReports).get()).length, 1);
    });
  });

  // ── Delta merge (upsert) ───────────────────────────────────────────────────

  group('sync — delta merge by id', () {
    test('updates existing customer on re-sync', () async {
      // First sync — insert
      _stubDioGet(
        mockDio,
        _syncPayload(customers: [_customerJson(companyName: 'Vecchio Nome Srl')]),
      );
      await svc.sync();

      // Second sync — update same id with new company name
      _stubDioGet(mockDio, _syncPayload(customers: [_customerJson(companyName: 'Nuovo Nome Spa')]));
      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1, reason: 'upsert must not create a duplicate');
      expect(rows.first.companyName, 'Nuovo Nome Spa');
    });

    test('updates existing schedule on re-sync', () async {
      _stubDioGet(mockDio, _syncPayload(schedules: [_scheduleJson(title: 'Primo')]));
      await svc.sync();

      _stubDioGet(mockDio, _syncPayload(schedules: [_scheduleJson(title: 'Aggiornato')]));
      await svc.sync();

      final rows = await db.select(db.schedules).get();
      expect(rows.length, 1);
      expect(rows.first.title, 'Aggiornato');
    });

    test('idempotent: calling sync twice with same payload yields one row', () async {
      final payload = _syncPayload(customers: [_customerJson()]);
      _stubDioGet(mockDio, payload);
      await svc.sync();

      _stubDioGet(mockDio, payload);
      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1);
    });
  });

  // ── Report lifecycle read-back (mobile audit item #1) ──────────────────────
  //
  // Mobile's rapportini list used to read only the local draft_reports rows this device itself
  // created — an office rejection (POST /api/reports/{id}/respingi) never reached the phone.
  // `submittedReports` (MobileUserSyncResult, backend) carries every report this technician
  // submitted that has since left Bozza; these tests verify it reconciles into the same
  // draft_reports table, converges on repeated syncs, and a Respinto change is picked up.

  group('sync — submittedReports (server-side lifecycle read-back)', () {
    test('upserts a submitted report even though it was never a local draft', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(submittedReports: [_draftReportJson(id: 'report-1', stato: 'Inviato')]),
      );

      await svc.sync();

      final rows = await db.select(db.draftReports).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'report-1');
      expect(rows.first.stato, 'Inviato');
      expect(rows.first.isLocalOnly, isFalse);
    });

    test('a Respinto status change from the office is picked up on the next sync', () async {
      // First sync: submitted, awaiting review.
      _stubDioGet(
        mockDio,
        _syncPayload(submittedReports: [_draftReportJson(id: 'report-1', stato: 'Inviato')]),
      );
      await svc.sync();
      expect((await db.select(db.draftReports).get()).single.stato, 'Inviato');

      // Office rejects it (POST /api/reports/{id}/respingi) — the next sync reflects that.
      _stubDioGet(
        mockDio,
        _syncPayload(
          submittedReports: [
            _draftReportJson(id: 'report-1', stato: 'Respinto', updatedAt: '2026-06-22T09:00:00Z'),
          ],
        ),
      );
      await svc.sync();

      final rows = await db.select(db.draftReports).get();
      expect(rows.length, 1, reason: 'must update in place, not duplicate');
      expect(rows.first.stato, 'Respinto');
    });

    test('an already-synced status is a no-op on a repeated sync with the same payload', () async {
      final payload = _syncPayload(
        submittedReports: [_draftReportJson(id: 'report-1', stato: 'Respinto')],
      );
      _stubDioGet(mockDio, payload);
      await svc.sync();

      _stubDioGet(mockDio, payload);
      await svc.sync();
      _stubDioGet(mockDio, payload);
      await svc.sync();

      final rows = await db.select(db.draftReports).get();
      expect(rows.length, 1);
      expect(rows.first.stato, 'Respinto');
    });

    test('does not disturb a genuinely separate local-only draft with the same-shaped id space', () async {
      // A local draft this device created and never submitted.
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'draft-local-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Bozza locale',
              insertedUserId: 'user-1',
              locationId: 'loc-1',
              isLocalOnly: const Value(true),
              stato: const Value('Bozza'),
            ),
          );

      _stubDioGet(
        mockDio,
        _syncPayload(submittedReports: [_draftReportJson(id: 'report-1', stato: 'Respinto')]),
      );
      await svc.sync();

      final rows = await db.select(db.draftReports).get();
      expect(rows.length, 2);
      final local = rows.firstWhere((r) => r.id == 'draft-local-1');
      expect(local.isLocalOnly, isTrue);
      expect(local.stato, 'Bozza');
    });
  });

  // ── Ticket lookup tables ───────────────────────────────────────────────────

  group('sync — ticket lookup tables', () {
    test('inserts a new ticketStatus', () async {
      _stubDioGet(mockDio, _syncPayload(ticketStatuses: [_ticketStatusJson()]));

      await svc.sync();

      final rows = await db.select(db.ticketStatuses).get();
      expect(rows.length, 1);
      expect(rows.first.id, 1);
      expect(rows.first.name, 'Aperto');
      expect(rows.first.isDefault, true);
      expect(rows.first.isClosed, false);
    });

    test('inserts a new ticketType', () async {
      _stubDioGet(mockDio, _syncPayload(ticketTypes: [_ticketTypeJson()]));

      await svc.sync();

      final rows = await db.select(db.ticketTypes).get();
      expect(rows.length, 1);
      expect(rows.first.id, 1);
      expect(rows.first.name, 'Assistenza');
    });

    test('upserts ticketStatus on re-sync', () async {
      _stubDioGet(mockDio, _syncPayload(ticketStatuses: [_ticketStatusJson(name: 'Vecchio')]));
      await svc.sync();

      _stubDioGet(mockDio, _syncPayload(ticketStatuses: [_ticketStatusJson(name: 'Aggiornato')]));
      await svc.sync();

      final rows = await db.select(db.ticketStatuses).get();
      expect(rows.length, 1);
      expect(rows.first.name, 'Aggiornato');
    });
  });

  // ── lastSync tracking ──────────────────────────────────────────────────────

  group('sync — lastSync', () {
    test('stores lastSync from the server syncedAt', () async {
      final ts = DateTime.utc(2026, 6, 21, 15, 30);
      _stubDioGet(mockDio, _syncPayload(syncedAt: ts));
      await svc.sync();

      final stored = await db.getLastSync();
      expect(stored, isNotNull);
      // Compare as UTC timestamps regardless of local vs UTC stored form.
      expect(stored!.millisecondsSinceEpoch, ts.millisecondsSinceEpoch);
    });

    test('sends since= param when lastSync is set', () async {
      // Seed a lastSync value
      final lastSyncTs = DateTime.utc(2026, 6, 20, 8);
      await db.setLastSync(lastSyncTs);

      // Capture what queryParameters were passed
      final capturedParams = <Map<String, dynamic>?>[];
      when(
        () => mockDio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((invocation) async {
        capturedParams.add(
          invocation.namedArguments[const Symbol('queryParameters')] as Map<String, dynamic>?,
        );
        return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/sync/mobile'),
          statusCode: 200,
          data: _syncPayload(syncedAt: DateTime.utc(2026, 6, 21)),
        );
      });

      await svc.sync();

      expect(capturedParams, hasLength(1));
      final params = capturedParams.first;
      expect(params, isNotNull);
      expect(params!.containsKey('since'), isTrue);
      expect(params['since'], lastSyncTs.toUtc().toIso8601String());
    });

    test('does NOT send since= param on first sync (no lastSync)', () async {
      final capturedParams = <Map<String, dynamic>?>[];
      when(
        () => mockDio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((invocation) async {
        capturedParams.add(
          invocation.namedArguments[const Symbol('queryParameters')] as Map<String, dynamic>?,
        );
        return Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/api/sync/mobile'),
          statusCode: 200,
          data: _syncPayload(),
        );
      });

      await svc.sync();

      final params = capturedParams.first ?? {};
      expect(params.containsKey('since'), isFalse);
    });
  });

  // ── ScheduleDto.parseTimeToMinutes ────────────────────────────────────────

  group('ScheduleDto.parseTimeToMinutes', () {
    test('08:00:00 → 480', () {
      expect(ScheduleDto.parseTimeToMinutes('08:00:00'), 480);
    });

    test('17:30:00 → 1050', () {
      expect(ScheduleDto.parseTimeToMinutes('17:30:00'), 1050);
    });

    test('00:00:00 → 0', () {
      expect(ScheduleDto.parseTimeToMinutes('00:00:00'), 0);
    });

    test('23:59:00 → 1439', () {
      expect(ScheduleDto.parseTimeToMinutes('23:59:00'), 1439);
    });
  });

  // ── SyncService path ──────────────────────────────────────────────────────

  test('SyncService calls /api/sync/mobile', () async {
    _stubDioGet(mockDio, _syncPayload());

    await svc.sync();

    verify(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/sync/mobile',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).called(1);
  });

  // ── Provider emits cached data offline ────────────────────────────────────

  group('Riverpod providers — offline cache', () {
    test('todaySchedulesProvider emits schedules from Drift without network', () async {
      // Pre-seed DB directly (no network)
      final today = DateTime.now().toUtc();
      final todayDate = DateTime.utc(today.year, today.month, today.day);

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'offline-sched',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: todayDate,
              timeStartMinutes: 480,
              timeEndMinutes: 1020,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Offline intervento',
              description: '',
            ),
          );

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final schedules = await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 1);
      expect(schedules.first.id, 'offline-sched');
      expect(schedules.first.title, 'Offline intervento');
    });

    test('weekSchedulesProvider emits schedules for next 7 days', () async {
      final now = DateTime.now().toUtc();
      final day0 = DateTime.utc(now.year, now.month, now.day); // today
      final day3 = day0.add(const Duration(days: 3)); // in window
      final day9 = day0.add(const Duration(days: 9)); // outside window

      Future<void> insertSched(String id, DateTime date) async {
        await db
            .into(db.schedules)
            .insert(
              SchedulesCompanion.insert(
                id: id,
                tenantId: 'tenant-1',
                createdAt: DateTime.utc(2026, 1, 1),
                activityDate: date,
                timeStartMinutes: 480,
                timeEndMinutes: 1020,
                userId: 'user-1',
                statusId: 1,
                locationId: 'loc-1',
                title: 'S-$id',
                description: '',
              ),
            );
      }

      await insertSched('today', day0);
      await insertSched('day3', day3);
      await insertSched('day9', day9);

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final schedules = await container.read(weekSchedulesProvider.future);
      final ids = schedules.map((s) => s.id).toList();
      expect(ids, containsAll(['today', 'day3']));
      expect(ids, isNot(contains('day9')));
    });

    test('draftReportsProvider emits Bozza reports only', () async {
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'r-bozza',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Bozza 1',
              insertedUserId: 'user-1',
              locationId: 'loc-1',
              stato: const Value('Bozza'),
            ),
          );
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'r-inviato',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Inviato 1',
              insertedUserId: 'user-1',
              locationId: 'loc-1',
              stato: const Value('Inviato'),
            ),
          );

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final reports = await container.read(draftReportsProvider.future);
      expect(reports.length, 1);
      expect(reports.first.id, 'r-bozza');
    });
  });

  // ── SyncDto JSON parsing ──────────────────────────────────────────────────

  group('SyncResultDto.fromJson', () {
    test('parses empty payload', () {
      final dto = SyncResultDto.fromJson(_syncPayload());
      expect(dto.schedules, isEmpty);
      expect(dto.customers, isEmpty);
      expect(dto.locations, isEmpty);
      expect(dto.tickets, isEmpty);
      expect(dto.draftReports, isEmpty);
    });

    test('parses nested entities', () {
      final dto = SyncResultDto.fromJson(
        _syncPayload(
          customers: [_customerJson()],
          locations: [_locationJson()],
          tickets: [_ticketJson()],
          schedules: [_scheduleJson()],
          draftReports: [_draftReportJson()],
        ),
      );
      expect(dto.customers.length, 1);
      expect(dto.locations.length, 1);
      expect(dto.tickets.length, 1);
      expect(dto.schedules.length, 1);
      expect(dto.draftReports.length, 1);
    });

    test('schedule timeStart 08:00:00 parsed to 480 minutes', () {
      final dto = SyncResultDto.fromJson(_syncPayload(schedules: [_scheduleJson()]));
      expect(ScheduleDto.parseTimeToMinutes(dto.schedules.first.timeStart), 480);
    });

    test('parses ticketStatuses and ticketTypes', () {
      final dto = SyncResultDto.fromJson(
        _syncPayload(ticketStatuses: [_ticketStatusJson()], ticketTypes: [_ticketTypeJson()]),
      );
      expect(dto.ticketStatuses.length, 1);
      expect(dto.ticketStatuses.first.name, 'Aperto');
      expect(dto.ticketTypes.length, 1);
      expect(dto.ticketTypes.first.name, 'Assistenza');
    });
  });

  // ── Oggi reads today's schedules ──────────────────────────────────────────

  group('Oggi — today schedules from cache', () {
    test('shows only today schedules, not future ones', () async {
      final today = DateTime.now().toUtc();
      final todayDate = DateTime.utc(today.year, today.month, today.day);
      final tomorrow = todayDate.add(const Duration(days: 1));

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'oggi-sched',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: todayDate,
              timeStartMinutes: 540,
              timeEndMinutes: 1080,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Oggi intervento',
              description: '',
            ),
          );

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'domani-sched',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: tomorrow,
              timeStartMinutes: 540,
              timeEndMinutes: 1080,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Domani intervento',
              description: '',
            ),
          );

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final schedules = await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 1);
      expect(schedules.first.id, 'oggi-sched');
    });

    test('today schedules are ordered by timeStartMinutes ASC', () async {
      final today = DateTime.now().toUtc();
      final todayDate = DateTime.utc(today.year, today.month, today.day);

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'late',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: todayDate,
              timeStartMinutes: 900, // 15:00
              timeEndMinutes: 1020,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Pomeriggio',
              description: '',
            ),
          );

      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'early',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              activityDate: todayDate,
              timeStartMinutes: 480, // 08:00
              timeEndMinutes: 600,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Mattina',
              description: '',
            ),
          );

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      final schedules = await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 2);
      expect(schedules.first.id, 'early');
      expect(schedules.last.id, 'late');
    });
  });

  // ── Catalogue tables ───────────────────────────────────────────────────────

  /// These two tables existed for months with nothing filling them, which left every screen
  /// reading them dead: the magazzino catalogue, admin materiali and cantieri, the schedule
  /// pickers, and — worst — cantiere clock-in, where a technician could not pick a site and so
  /// could not record site hours at all. The payload carried both arrays the whole time; only the
  /// client side of the wire was missing, which is the kind of gap that hides until someone opens
  /// the screen.
  group('sync — catalogue tables', () {
    test('materiali arrive in the local catalogue', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          materiali: [
            {
              'id': 'mat-1',
              'tenantId': 'ten-1',
              'createdAt': '2026-06-01T00:00:00Z',
              'updatedAt': null,
              'code': 'ART-001',
              'name': 'Tubo rame 15mm',
              'description': null,
              'unitOfMeasure': 'm',
              'category': 'Idraulica',
              'marca': null,
              'purchasePrice': 3.5,
              'salePrice': 6.0,
              'isActive': true,
            },
          ],
        ),
      );

      await svc.sync();

      final rows = await db.select(db.materiali).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, 'Tubo rame 15mm');
      expect(rows.first.salePrice, 6.0);
    });

    test('materiale barcodes arrive in the local mirror, for offline scan-to-lookup', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          materialiBarcodes: [
            {
              'id': 'bc-1',
              'tenantId': 'ten-1',
              'createdAt': '2026-06-01T00:00:00Z',
              'updatedAt': null,
              'materialeId': 'mat-1',
              'barcode': '8001234567890',
              'barcodeType': 'EAN13',
              'isPrimary': true,
            },
          ],
        ),
      );

      await svc.sync();

      final rows = await db.select(db.materialeBarcodes).get();
      expect(rows, hasLength(1));
      expect(rows.first.materialeId, 'mat-1');
      expect(rows.first.barcode, '8001234567890');
      expect(rows.first.barcodeType, 'EAN13');
      expect(rows.first.isPrimary, isTrue);
    });

    test('a re-synced materiale barcode updates in place rather than duplicating', () async {
      Map<String, dynamic> barcode(String value) => {
        'id': 'bc-1',
        'tenantId': 'ten-1',
        'createdAt': '2026-06-01T00:00:00Z',
        'updatedAt': null,
        'materialeId': 'mat-1',
        'barcode': value,
        'barcodeType': 'EAN13',
        'isPrimary': true,
      };

      _stubDioGet(mockDio, _syncPayload(materialiBarcodes: [barcode('8001111111111')]));
      await svc.sync();

      _stubDioGet(mockDio, _syncPayload(materialiBarcodes: [barcode('8002222222222')]));
      await svc.sync();

      final rows = await db.select(db.materialeBarcodes).get();
      expect(rows, hasLength(1));
      expect(rows.first.barcode, '8002222222222');
    });

    test('cantieri arrive in the local catalogue', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          cantieri: [
            {
              'id': 'can-1',
              'tenantId': 'ten-1',
              'createdAt': '2026-06-01T00:00:00Z',
              'updatedAt': null,
              'name': 'Cantiere Via Roma',
              'address': 'Via Roma 10',
              'city': 'Milano',
              'postalCode': '20121',
              'notes': null,
              'startDate': null,
              'endDate': null,
              'status': 'Active',
              'customerId': 'cli-1',
              'commessaId': null,
            },
          ],
        ),
      );

      await svc.sync();

      final rows = await db.select(db.cantieri).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, 'Cantiere Via Roma');
      expect(rows.first.status, 0, reason: 'Active maps to 0');
    });

    /// Closes the loop end-to-end: CantiereTimbraScreen's own `cantieriProvider` (not just the
    /// raw Drift table) reflects a normal sync — proving the cantiere clock-in picker is
    /// populated after a normal app session rather than permanently empty. See
    /// cantiere_timbra_screen.dart's `cantieriProvider` doc comment.
    test('cantieriProvider (the clock-in picker\'s own data source) reflects a normal sync', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(
          cantieri: [
            {
              'id': 'can-1',
              'tenantId': 'ten-1',
              'createdAt': '2026-06-01T00:00:00Z',
              'updatedAt': null,
              'name': 'Cantiere Via Roma',
              'address': null,
              'city': 'Milano',
              'postalCode': null,
              'notes': null,
              'startDate': null,
              'endDate': null,
              'status': 'Active',
              'customerId': 'cli-1',
              'commessaId': null,
            },
          ],
        ),
      );

      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      // Before a sync has ever run, a fresh device's picker is genuinely empty.
      expect(await container.read(cantieriProvider.future), isEmpty);

      await svc.sync();

      final cantieri = await container.read(cantieriProvider.future);
      expect(cantieri, hasLength(1));
      expect(cantieri.first.name, 'Cantiere Via Roma');
    });

    /// A re-sync must not duplicate the catalogue — it runs on every reconnect.
    test('re-syncing the same materiale updates rather than duplicates', () async {
      Map<String, dynamic> materiale(String name) => {
        'id': 'mat-1',
        'tenantId': 'ten-1',
        'createdAt': '2026-06-01T00:00:00Z',
        'updatedAt': null,
        'code': 'ART-001',
        'name': name,
        'description': null,
        'unitOfMeasure': null,
        'category': null,
        'marca': null,
        'purchasePrice': null,
        'salePrice': null,
        'isActive': true,
      };

      _stubDioGet(mockDio, _syncPayload(materiali: [materiale('Vecchio nome')]));
      await svc.sync();

      _stubDioGet(mockDio, _syncPayload(materiali: [materiale('Nuovo nome')]));
      await svc.sync();

      final rows = await db.select(db.materiali).get();
      expect(rows, hasLength(1));
      expect(rows.first.name, 'Nuovo nome');
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Colleagues — the list the rapportino staff picker reads.
//
// Mirrored so a technician can name who worked with them by tapping a name. Before it existed the
// step asked for a colleague's user id in a text box and invented `user-<timestamp>` when it was
// left blank, so hours reached payroll attributed to a person who does not exist.
// ══════════════════════════════════════════════════════════════════════════════

Map<String, dynamic> _colleagueJson({String id = 'user-1', String displayName = 'Mario Rossi'}) => {
  'id': id,
  'displayName': displayName,
};

void _colleagueTests() {
  group('SyncService — colleagues', () {
    late AppDatabase db;
    late MockDio dio;
    late SyncService service;

    setUp(() {
      db = _makeDb();
      dio = MockDio();
      service = SyncService(db: db, dio: dio);
    });

    tearDown(() async => db.close());

    void stubSync(List<Map<String, dynamic>> colleagues) {
      when(
        () => dio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/sync/mobile'),
          statusCode: 200,
          data: _syncPayload(colleagues: colleagues),
        ),
      );
    }

    test('stores the colleagues the server sent', () async {
      stubSync([
        _colleagueJson(id: 'user-1', displayName: 'Mario Rossi'),
        _colleagueJson(id: 'user-2', displayName: 'Anna Bianchi'),
      ]);

      await service.sync();

      final rows = await db.select(db.colleagues).get();
      expect(rows.map((c) => c.displayName), containsAll(['Mario Rossi', 'Anna Bianchi']));
    });

    /// The reason this is a wholesale replace rather than an upsert: someone who leaves the
    /// company simply stops being mentioned in the payload. An upsert would leave them in the
    /// picker forever, and nothing would ever remove them.
    test('drops a colleague the server no longer sends', () async {
      stubSync([
        _colleagueJson(id: 'user-1', displayName: 'Mario Rossi'),
        _colleagueJson(id: 'user-2', displayName: 'Anna Bianchi'),
      ]);
      await service.sync();

      stubSync([_colleagueJson(id: 'user-1', displayName: 'Mario Rossi')]);
      await service.sync();

      final rows = await db.select(db.colleagues).get();
      expect(rows.map((c) => c.id), ['user-1']);
    });

    test('renames a colleague in place rather than duplicating them', () async {
      stubSync([_colleagueJson(id: 'user-1', displayName: 'M. Rossi')]);
      await service.sync();

      stubSync([_colleagueJson(id: 'user-1', displayName: 'Mario Rossi')]);
      await service.sync();

      final rows = await db.select(db.colleagues).get();
      expect(rows, hasLength(1));
      expect(rows.single.displayName, 'Mario Rossi');
    });

    /// A delta sync that carries no colleagues must not wipe the picker. The technician would
    /// open the staff step on site and find nobody to add, with no way to tell why.
    test('an empty list leaves the existing colleagues alone', () async {
      stubSync([_colleagueJson(id: 'user-1', displayName: 'Mario Rossi')]);
      await service.sync();

      stubSync(const []);
      await service.sync();

      final rows = await db.select(db.colleagues).get();
      expect(
        rows,
        hasLength(1),
        reason: 'an absent list means "no change", not "nobody works here"',
      );
    });
  });
}

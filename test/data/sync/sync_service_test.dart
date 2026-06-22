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
  List<Map<String, dynamic>> customers = const [],
  List<Map<String, dynamic>> locations = const [],
  List<Map<String, dynamic>> tickets = const [],
  List<Map<String, dynamic>> ticketStatuses = const [],
  List<Map<String, dynamic>> ticketTypes = const [],
}) {
  return {
    'syncedAt': (syncedAt ?? DateTime.utc(2026, 6, 21, 12)).toIso8601String(),
    'since': since?.toIso8601String(),
    'schedules': schedules,
    'draftReports': draftReports,
    'customers': customers,
    'locations': locations,
    'tickets': tickets,
    'ticketStatuses': ticketStatuses,
    'ticketTypes': ticketTypes,
  };
}

Map<String, dynamic> _customerJson({
  String id = 'cust-1',
  String companyName = 'ACME Srl',
}) =>
    {
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
}) =>
    {
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
}) =>
    {
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
      'teamLeadId': 'user-1',
      'staffIds': '[]',
      'squadraId': null,
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

Map<String, dynamic> _ticketStatusJson({
  int id = 1,
  String name = 'Aperto',
}) =>
    {
      'id': id,
      'tenantId': 'tenant-1',
      'name': name,
      'isDefault': true,
      'isClosed': false,
    };

Map<String, dynamic> _ticketTypeJson({
  int id = 1,
  String name = 'Assistenza',
}) =>
    {
      'id': id,
      'tenantId': 'tenant-1',
      'name': name,
      'description': null,
    };

Map<String, dynamic> _draftReportJson({String id = 'report-1'}) => {
      'id': id,
      'tenantId': 'tenant-1',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': null,
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
      'stato': 'Bozza',
      'inviatoAt': null,
      'controllatoAt': null,
      'controllatoDa': null,
      'fatturatoAt': null,
      'materialiNotRequired': false,
      'customerSignoffText': null,
      'customerSignoffAt': null,
    };

/// Stub a Dio GET response with the given JSON body.
void _stubDioGet(MockDio mockDio, Map<String, dynamic> body,
    {Map<String, dynamic>? queryParams}) {
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
      _stubDioGet(
        mockDio,
        _syncPayload(customers: [_customerJson()]),
      );

      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'cust-1');
      expect(rows.first.companyName, 'ACME Srl');
    });

    test('inserts a new location', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(locations: [_locationJson()]),
      );

      await svc.sync();

      final rows = await db.select(db.locations).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'loc-1');
      expect(rows.first.name, 'Sede principale');
    });

    test('inserts a new ticket', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(tickets: [_ticketJson()]),
      );

      await svc.sync();

      final rows = await db.select(db.tickets).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'ticket-1');
    });

    test('inserts a new schedule with parsed time minutes', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(schedules: [_scheduleJson()]),
      );

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

    test('inserts a new draft report', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(draftReports: [_draftReportJson()]),
      );

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
        _syncPayload(
            customers: [_customerJson(companyName: 'Vecchio Nome Srl')]),
      );
      await svc.sync();

      // Second sync — update same id with new company name
      _stubDioGet(
        mockDio,
        _syncPayload(
            customers: [_customerJson(companyName: 'Nuovo Nome Spa')]),
      );
      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1, reason: 'upsert must not create a duplicate');
      expect(rows.first.companyName, 'Nuovo Nome Spa');
    });

    test('updates existing schedule on re-sync', () async {
      _stubDioGet(
          mockDio, _syncPayload(schedules: [_scheduleJson(title: 'Primo')]));
      await svc.sync();

      _stubDioGet(
          mockDio, _syncPayload(schedules: [_scheduleJson(title: 'Aggiornato')]));
      await svc.sync();

      final rows = await db.select(db.schedules).get();
      expect(rows.length, 1);
      expect(rows.first.title, 'Aggiornato');
    });

    test('idempotent: calling sync twice with same payload yields one row',
        () async {
      final payload = _syncPayload(customers: [_customerJson()]);
      _stubDioGet(mockDio, payload);
      await svc.sync();

      _stubDioGet(mockDio, payload);
      await svc.sync();

      final rows = await db.select(db.customers).get();
      expect(rows.length, 1);
    });
  });

  // ── Ticket lookup tables ───────────────────────────────────────────────────

  group('sync — ticket lookup tables', () {
    test('inserts a new ticketStatus', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(ticketStatuses: [_ticketStatusJson()]),
      );

      await svc.sync();

      final rows = await db.select(db.ticketStatuses).get();
      expect(rows.length, 1);
      expect(rows.first.id, 1);
      expect(rows.first.name, 'Aperto');
      expect(rows.first.isDefault, true);
      expect(rows.first.isClosed, false);
    });

    test('inserts a new ticketType', () async {
      _stubDioGet(
        mockDio,
        _syncPayload(ticketTypes: [_ticketTypeJson()]),
      );

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
      expect(
        stored!.millisecondsSinceEpoch,
        ts.millisecondsSinceEpoch,
      );
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
          invocation.namedArguments[const Symbol('queryParameters')]
              as Map<String, dynamic>?,
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
      expect(
        params['since'],
        lastSyncTs.toUtc().toIso8601String(),
      );
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
          invocation.namedArguments[const Symbol('queryParameters')]
              as Map<String, dynamic>?,
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
    test('todaySchedulesProvider emits schedules from Drift without network',
        () async {
      // Pre-seed DB directly (no network)
      final today = DateTime.now().toUtc();
      final todayDate = DateTime(today.year, today.month, today.day).toUtc();

      await db.into(db.schedules).insert(
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

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final schedules =
          await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 1);
      expect(schedules.first.id, 'offline-sched');
      expect(schedules.first.title, 'Offline intervento');
    });

    test('weekSchedulesProvider emits schedules for next 7 days', () async {
      final now = DateTime.now().toUtc();
      final day0 =
          DateTime(now.year, now.month, now.day).toUtc(); // today
      final day3 = day0.add(const Duration(days: 3)); // in window
      final day9 = day0.add(const Duration(days: 9)); // outside window

      Future<void> insertSched(String id, DateTime date) async {
        await db.into(db.schedules).insert(
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

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final schedules =
          await container.read(weekSchedulesProvider.future);
      final ids = schedules.map((s) => s.id).toList();
      expect(ids, containsAll(['today', 'day3']));
      expect(ids, isNot(contains('day9')));
    });

    test('draftReportsProvider emits Bozza reports only', () async {
      await db.into(db.draftReports).insert(
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
      await db.into(db.draftReports).insert(
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

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final reports =
          await container.read(draftReportsProvider.future);
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
      final dto = SyncResultDto.fromJson(_syncPayload(
        customers: [_customerJson()],
        locations: [_locationJson()],
        tickets: [_ticketJson()],
        schedules: [_scheduleJson()],
        draftReports: [_draftReportJson()],
      ));
      expect(dto.customers.length, 1);
      expect(dto.locations.length, 1);
      expect(dto.tickets.length, 1);
      expect(dto.schedules.length, 1);
      expect(dto.draftReports.length, 1);
    });

    test('schedule timeStart 08:00:00 parsed to 480 minutes', () {
      final dto = SyncResultDto.fromJson(
          _syncPayload(schedules: [_scheduleJson()]));
      expect(
        ScheduleDto.parseTimeToMinutes(dto.schedules.first.timeStart),
        480,
      );
    });

    test('parses ticketStatuses and ticketTypes', () {
      final dto = SyncResultDto.fromJson(_syncPayload(
        ticketStatuses: [_ticketStatusJson()],
        ticketTypes: [_ticketTypeJson()],
      ));
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
      final todayDate =
          DateTime(today.year, today.month, today.day).toUtc();
      final tomorrow = todayDate.add(const Duration(days: 1));

      await db.into(db.schedules).insert(
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

      await db.into(db.schedules).insert(
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

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final schedules =
          await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 1);
      expect(schedules.first.id, 'oggi-sched');
    });

    test('today schedules are ordered by timeStartMinutes ASC', () async {
      final today = DateTime.now().toUtc();
      final todayDate =
          DateTime(today.year, today.month, today.day).toUtc();

      await db.into(db.schedules).insert(
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

      await db.into(db.schedules).insert(
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

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final schedules =
          await container.read(todaySchedulesProvider.future);
      expect(schedules.length, 2);
      expect(schedules.first.id, 'early');
      expect(schedules.last.id, 'late');
    });
  });
}

// test/features/ticket/ticket_providers_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ticketsProvider emits empty list when db empty', () async {
    final result = await container.read(ticketsProvider.future);
    expect(result, isEmpty);
  });

  test('ticketsProvider emits seeded ticket', () async {
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );

    final result = await container.read(ticketsProvider.future);
    expect(result.length, 1);
    expect(result.first.title, 'Perdita idrica');
  });

  test('ticketStatusMapProvider emits id→name map', () async {
    await db
        .into(db.ticketStatuses)
        .insert(TicketStatusesCompanion.insert(id: Value(1), tenantId: 'tenant-1', name: 'Aperto'));
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: Value(2), tenantId: 'tenant-1', name: 'In corso'),
        );

    final result = await container.read(ticketStatusMapProvider.future);
    expect(result[1], 'Aperto');
    expect(result[2], 'In corso');
  });

  test('ticketTypeMapProvider emits id→name map', () async {
    await db
        .into(db.ticketTypes)
        .insert(
          TicketTypesCompanion.insert(id: Value(1), tenantId: 'tenant-1', name: 'Assistenza'),
        );

    final result = await container.read(ticketTypeMapProvider.future);
    expect(result[1], 'Assistenza');
  });

  test('ticketStatusMapProvider returns empty map when no statuses', () async {
    final result = await container.read(ticketStatusMapProvider.future);
    expect(result, isEmpty);
  });

  test('closedTicketStatusIdsProvider lists only the statuses flagged isClosed', () async {
    await db
        .into(db.ticketStatuses)
        .insert(TicketStatusesCompanion.insert(id: Value(1), tenantId: 'tenant-1', name: 'Aperto'));
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: Value(2),
            tenantId: 'tenant-1',
            name: 'Completato',
            isClosed: Value(true),
          ),
        );

    final result = await container.read(closedTicketStatusIdsProvider.future);
    expect(result, {2});
  });

  /// The bug this pair was written for: closing a ticket from the phone wrote the new `statusId`
  /// and no `closedAt` (that bookkeeping was the server's alone), so a rule that only read
  /// `closedAt` kept offering new work on a ticket the technician had just closed.
  test('mirroredTicketIsClosed reads closure from the status flag, not only from closedAt', () async {
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: Value(2),
            tenantId: 'tenant-1',
            name: 'Chiuso',
            isClosed: Value(true),
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
          ),
        );

    expect(await mirroredTicketIsClosed(db, 'ticket-1'), isTrue);
  });

  test('mirroredTicketIsClosed honours a server-stamped closedAt', () async {
    // The status is not flagged closed — the closure was recorded while the status list on this
    // device was stale. `closedAt` alone still has to answer true.
    await db
        .into(db.ticketStatuses)
        .insert(TicketStatusesCompanion.insert(id: Value(1), tenantId: 'tenant-1', name: 'Aperto'));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            closedAt: Value(DateTime.utc(2026, 6, 2)),
          ),
        );

    expect(await mirroredTicketIsClosed(db, 'ticket-1'), isTrue);
  });

  test('mirroredTicketIsClosed is false for an open ticket and for an unmirrored one', () async {
    await db
        .into(db.ticketStatuses)
        .insert(TicketStatusesCompanion.insert(id: Value(1), tenantId: 'tenant-1', name: 'Aperto'));
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ),
        );

    expect(await mirroredTicketIsClosed(db, 'ticket-1'), isFalse);
    // No evidence of closure is not evidence of closure — an unknown id is not refused here.
    expect(await mirroredTicketIsClosed(db, 'ticket-unknown'), isFalse);
  });

  test('schedulesForTicketProvider returns schedules for matching ticketId', () async {
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            ticketId: const Value('ticket-1'),
            activityDate: DateTime.utc(2026, 7, 1),
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Intervento',
            description: '',
          ),
        );

    // Schedule for a different ticket
    await db
        .into(db.schedules)
        .insert(
          SchedulesCompanion.insert(
            id: 'sched-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            ticketId: const Value('ticket-2'),
            activityDate: DateTime.utc(2026, 7, 2),
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Altro intervento',
            description: '',
          ),
        );

    final result = await container.read(schedulesForTicketProvider('ticket-1').future);
    expect(result.length, 1);
    expect(result.first.id, 'sched-1');
  });

  group('ticketMaterialiProvider — offline fabbisogno mirror', () {
    test('resolves a catalog-referenced item\'s name/code/unit from the synced Materiale', () async {
      await db
          .into(db.materiali)
          .insert(
            MaterialiCompanion.insert(
              id: 'mat-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              code: 'VLV-034',
              name: 'Valvola 3/4"',
              unitOfMeasure: const Value('pz'),
            ),
          );
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              ticketId: 'ticket-1',
              materialeId: const Value('mat-1'),
              quantity: 2,
              isAvailable: const Value(true),
            ),
          );

      final result = await container.read(ticketMaterialiProvider('ticket-1').future);

      expect(result, hasLength(1));
      expect(result.single.nome, 'Valvola 3/4"');
      expect(result.single.codice, 'VLV-034');
      expect(result.single.unitaMisura, 'pz');
      expect(result.single.quantita, 2);
      expect(result.single.disponibile, isTrue);
    });

    test('a free-text item (no materialeId) uses its own name, no catalog lookup', () async {
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm-2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              ticketId: 'ticket-1',
              freeTextName: const Value('Guarnizione generica'),
              quantity: 1,
            ),
          );

      final result = await container.read(ticketMaterialiProvider('ticket-1').future);

      expect(result, hasLength(1));
      expect(result.single.nome, 'Guarnizione generica');
      // Bare `isNull` is ambiguous in this file (drift.dart's own query-builder symbol vs.
      // matcher's) — plain `null` reads identically for an equality check.
      expect(result.single.materialeId, null);
      expect(result.single.codice, null);
    });

    test('only returns fabbisogno for the requested ticket', () async {
      await db
          .into(db.ticketMateriali)
          .insert(
            TicketMaterialiCompanion.insert(
              id: 'tm-3',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              ticketId: 'ticket-2',
              freeTextName: const Value('Not this ticket'),
              quantity: 1,
            ),
          );

      final result = await container.read(ticketMaterialiProvider('ticket-1').future);

      expect(result, isEmpty);
    });
  });
}

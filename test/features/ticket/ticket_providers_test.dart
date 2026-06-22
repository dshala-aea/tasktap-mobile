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
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
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
    await db.into(db.tickets).insert(TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Perdita idrica',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
        ));

    final result = await container.read(ticketsProvider.future);
    expect(result.length, 1);
    expect(result.first.title, 'Perdita idrica');
  });

  test('ticketStatusMapProvider emits id→name map', () async {
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
          id: Value(1),
          tenantId: 'tenant-1',
          name: 'Aperto',
        ));
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
          id: Value(2),
          tenantId: 'tenant-1',
          name: 'In corso',
        ));

    final result = await container.read(ticketStatusMapProvider.future);
    expect(result[1], 'Aperto');
    expect(result[2], 'In corso');
  });

  test('ticketTypeMapProvider emits id→name map', () async {
    await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
          id: Value(1),
          tenantId: 'tenant-1',
          name: 'Assistenza',
        ));

    final result = await container.read(ticketTypeMapProvider.future);
    expect(result[1], 'Assistenza');
  });

  test('ticketStatusMapProvider returns empty map when no statuses', () async {
    final result = await container.read(ticketStatusMapProvider.future);
    expect(result, isEmpty);
  });

  test('schedulesForTicketProvider returns schedules for matching ticketId',
      () async {
    await db.into(db.schedules).insert(SchedulesCompanion.insert(
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
        ));

    // Schedule for a different ticket
    await db.into(db.schedules).insert(SchedulesCompanion.insert(
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
        ));

    final result =
        await container.read(schedulesForTicketProvider('ticket-1').future);
    expect(result.length, 1);
    expect(result.first.id, 'sched-1');
  });
}

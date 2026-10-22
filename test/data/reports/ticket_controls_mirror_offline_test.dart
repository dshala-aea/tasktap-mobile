// dart format width=100
// The rapportino Controlli step's offline sources, in order: the sync mirror when it can answer
// for the ticket, the last online fetch's cache when it cannot, the honest offline state
// otherwise.
//
// What this pins: the step used to read ONLY the online-fetch cache, so a technician drafting a
// report on site for a ticket whose Controlli tab they had never opened saw "Controlli non
// disponibili offline" while that ticket's checklist sat synced in `ticket_controls`. The mirror
// can be trusted exactly when the ticket itself has synced and its checklist was not omitted from
// the payload — neither case may report "no controls" on evidence it does not have.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/ticket_controls_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

/// Every network call is a failure here: these tests are about what the device already holds.
class _FailingApiClient extends TicketDetailApiClient {
  _FailingApiClient() : super(Dio());

  @override
  Future<List<TicketControlGroupDto>> fetchControls(String ticketId) async =>
      throw StateError('the network must not answer this test');
}

TicketControlGroupDto _group(String id, String name, String controlLabel) => TicketControlGroupDto(
  id: id,
  name: name,
  sortOrder: 0,
  controls: [
    TicketControlDto(
      id: 'c-$id',
      templateControlId: 'tpl-$id',
      label: controlLabel,
      type: ControlType.checkbox,
      isRequired: true,
      sortOrder: 0,
      status: 'Pending',
    ),
  ],
);

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// The ticket arrived in a payload — which is what makes its (possibly empty) mirror the answer.
  Future<void> seedSyncedTicket({String id = 'ticket-1'}) => db
      .into(db.tickets)
      .insertOnConflictUpdate(
        TicketsCompanion.insert(
          id: id,
          tenantId: 't',
          title: 'Caldaia',
          customerId: 'cu1',
          locationId: 'loc1',
          statusId: 1,
          typeId: 1,
          createdAt: DateTime.utc(2026, 8, 16),
        ),
      );

  Future<void> seedMirror({String ticketId = 'ticket-1', String label = 'Dal mirror'}) async {
    await db
        .into(db.controlGroups)
        .insert(
          ControlGroupsCompanion.insert(
            id: 'g',
            maintenanceTemplateVersionId: 'v1',
            name: 'Sicurezza',
            sortOrder: 0,
          ),
        );
    await db
        .into(db.ticketControls)
        .insert(
          TicketControlsCompanion.insert(
            id: 'tc-1',
            ticketId: ticketId,
            templateControlId: 'tpl-tc-1',
            controlLineageId: 'lin-tc-1',
            groupId: 'g',
            label: label,
            type: 'Checkbox',
            isRequired: const Value(true),
          ),
        );
  }

  Future<void> seedOmitted({String ticketId = 'ticket-1'}) => db
      .into(db.checklistOmittedTickets)
      .insert(ChecklistOmittedTicketsCompanion.insert(ticketId: ticketId));

  Future<void> seedCache({String ticketId = 'ticket-1', String label = 'Dal cache'}) =>
      TicketControlsCacheRepository(db).cacheControls(ticketId, [
        _group('cached', 'Cache', label),
      ]);

  ProviderContainer container({bool online = false}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        ticketDetailApiClientProvider.overrideWithValue(_FailingApiClient()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The labels the step would render for the ticket-level tree.
  List<String> labels(List<TicketControlGroupDto> groups) => [
    for (final g in groups)
      for (final c in g.controls) c.label,
  ];

  test(
    'offline, a synced ticket with no omission marker answers from the mirror — never the API, '
    'and without the technician having opened this ticket before',
    () async {
      await seedSyncedTicket();
      await seedMirror();

      final groups = await container().read(cachedTicketControlsProvider('ticket-1').future);

      expect(labels(groups), ['Dal mirror']);
    },
  );

  test('offline, an empty mirror for a synced ticket is a definite "no controls", not an error', () async {
    await seedSyncedTicket();

    final groups = await container().read(cachedTicketControlsProvider('ticket-1').future);

    expect(groups, isEmpty);
  });

  test('offline, an authoritative mirror beats the older online cache', () async {
    await seedSyncedTicket();
    await seedMirror(label: 'Risposta attuale');
    await seedCache(label: 'Risposta vecchia');

    final groups = await container().read(cachedTicketControlsProvider('ticket-1').future);

    expect(labels(groups), ['Risposta attuale']);
  });

  test(
    'offline, a ticket whose checklist the payload omitted falls back to the cache — the mirror is '
    'known to be incomplete, so its emptiness proves nothing',
    () async {
      await seedSyncedTicket();
      await seedOmitted();
      await seedCache();

      final groups = await container().read(cachedTicketControlsProvider('ticket-1').future);

      expect(labels(groups), ['Dal cache']);
    },
  );

  test('offline, an omitted checklist with nothing cached is the honest offline state', () async {
    await seedSyncedTicket();
    await seedOmitted();

    expect(
      () => container().read(cachedTicketControlsProvider('ticket-1').future),
      throwsA(isA<TicketDetailOfflineException>()),
    );
  });

  test('offline, a ticket this device has never synced is not read from the mirror', () async {
    // No `tickets` row: zero mirror rows here means "unknown", so the cache is the only evidence.
    await seedCache();

    final groups = await container().read(cachedTicketControlsProvider('ticket-1').future);

    expect(labels(groups), ['Dal cache']);
  });

  test('online, a failing live fetch still degrades to the authoritative mirror', () async {
    await seedSyncedTicket();
    await seedMirror();

    final groups = await container(
      online: true,
    ).read(cachedTicketControlsProvider('ticket-1').future);

    expect(labels(groups), ['Dal mirror']);
  });
}

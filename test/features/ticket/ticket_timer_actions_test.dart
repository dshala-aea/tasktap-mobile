// dart format width=100
//
// `startTicketTimer` is the one place both entry points start a ticket's clock. The behaviour that
// matters is which of the two stores the session lands in, and under which key:
//
//   * online, the server creates the row and this device mirrors it immediately — otherwise a
//     technician who starts the clock at the office and loses signal on the way to site is left
//     with a running timer the phone cannot stop;
//   * offline (or a request that never reached the server), the session is written to the mirror
//     and queued;
//   * a failure the server actually answered is a decision, and is surfaced rather than queued;
//   * a replay that lands on a session the office already closed must not paint a running clock.
//
// The sync service is replaced with a counting no-op: what it does with the queue is covered by
// ticket_timer_sync_service_test.dart, and running it here would only race the assertions.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart' show businessTimeProvider;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/data/timbratura/ticket_timer_api_client.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_repository.dart';
import 'package:tasktap_mobile/data/timbratura/ticket_timer_sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_timer_actions.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart'
    show internalUserIdProvider;

/// Stands in for the online start route: records the key it was handed and answers with whatever
/// the test scripted.
class _ScriptedWorkflowClient extends TicketWorkflowApiClient {
  _ScriptedWorkflowClient({this.result, this.failure}) : super(Dio());

  final TicketTimerStart? result;
  final TicketWorkflowFailure? failure;
  final List<String?> receivedClientIds = <String?>[];

  /// The device reading the online tap carried — O-10: absent means the server stamped its own
  /// clock, which is only right when the phone has nothing to say about the instant.
  DateTime? receivedDeviceUtc;

  @override
  Future<TicketTimerStart> startTimer(
    String ticketId, {
    String? clientId,
    DateTime? deviceUtc,
  }) async {
    receivedClientIds.add(clientId);
    receivedDeviceUtc = deviceUtc;
    if (failure != null) throw failure!;
    return result!;
  }
}

/// A sync service that only counts: the assertions here are about what the tap writes, not about
/// what the sweep later sends.
class _CountingSyncService extends TicketTimerSyncService {
  _CountingSyncService(TicketTimerRepository repo)
    : super(repo: repo, apiClient: _UnusedTimerApiClient());

  int syncs = 0;

  @override
  Future<void> syncNow({bool manual = false}) async {
    syncs++;
  }
}

class _UnusedTimerApiClient implements TicketTimerApiClient {
  @override
  Future<List<TicketMobileSessionResult>> upsertSessions(
    List<TicketMobileSessionDto> sessions,
  ) => throw StateError('the counting sync service never pushes');
}

DioException _noResponse() => DioException(
  requestOptions: RequestOptions(path: '/x'),
  type: DioExceptionType.connectionError,
);

DioException _refused() => DioException(
  requestOptions: RequestOptions(path: '/x'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: 400,
    data: 'You already have an active ticket work log. Stop it first.',
  ),
);

void main() {
  late AppDatabase db;
  late TicketTimerRepository repo;
  late _CountingSyncService sync;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = TicketTimerRepository(db, businessTime: BusinessTime.fallback());
    sync = _CountingSyncService(repo);
  });

  tearDown(() async => db.close());

  /// Pumps a bare [Consumer] and hands back its `ref` — the action takes a `WidgetRef`, which only
  /// a build can supply.
  Future<WidgetRef> pumpRef(
    WidgetTester tester, {
    required TicketWorkflowApiClient client,
    required bool online,
  }) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          businessTimeProvider.overrideWithValue(BusinessTime.fallback()),
          ticketTimerRepositoryProvider.overrideWithValue(repo),
          ticketTimerSyncServiceProvider.overrideWithValue(sync),
          ticketWorkflowApiClientProvider.overrideWithValue(client),
          isOnlineProvider.overrideWithValue(online),
          internalUserIdProvider.overrideWith((ref) async => 'user-1'),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ref;
  }

  testWidgets('an online start mirrors the session the server created, under the same key', (
    tester,
  ) async {
    final client = _ScriptedWorkflowClient(
      result: const TicketTimerStart(id: 'server-1', isActive: true),
    );
    final ref = await pumpRef(tester, client: client, online: true);

    await startTicketTimer(ref, 't1');

    final key = client.receivedClientIds.single;
    expect(key, isNotNull, reason: 'a start with no key cannot be retried onto its own row');
    final row = (await repo.forTicket('t1')).single;
    expect(row.id, 'server-1');
    expect(row.clientId, key);
    expect(row.isPendingSync, isFalse, reason: 'the server already holds the start');
    expect(row.endSeconds, isNull, reason: 'the clock is running, so "Ferma" has something to close');
    expect(sync.syncs, 0, reason: 'nothing is owed to the server');
  });

  testWidgets('a start written on the device is queued for the sweep', (tester) async {
    final client = _ScriptedWorkflowClient(
      result: const TicketTimerStart(id: 'server-1', isActive: true),
    );
    final ref = await pumpRef(tester, client: client, online: false);

    await startTicketTimer(ref, 't1');

    expect(client.receivedClientIds, isEmpty, reason: 'no signal, so the route was not called');
    final row = (await repo.forTicket('t1')).single;
    expect(row.isPendingSync, isTrue);
    expect(row.endSeconds, isNull);
    expect(sync.syncs, 1);
  });

  testWidgets('a request that never reached the server falls back to the device', (tester) async {
    final client = _ScriptedWorkflowClient(
      failure: TicketWorkflowFailure('Nessuna connessione.', cause: _noResponse()),
    );
    final ref = await pumpRef(tester, client: client, online: true);

    await startTicketTimer(ref, 't1');

    final row = (await repo.forTicket('t1')).single;
    expect(row.isPendingSync, isTrue, reason: 'the tap is durable the instant it returns');
    expect(sync.syncs, 1);
  });

  testWidgets('a refusal the server made is surfaced, never queued', (tester) async {
    final client = _ScriptedWorkflowClient(
      failure: TicketWorkflowFailure(
        'Hai già un timer avviato su un altro intervento.',
        cause: _refused(),
      ),
    );
    final ref = await pumpRef(tester, client: client, online: true);

    await expectLater(() => startTicketTimer(ref, 't1'), throwsA(isA<TicketWorkflowFailure>()));

    expect(await repo.forTicket('t1'), isEmpty, reason: 'queuing it would book the hours twice');
    expect(sync.syncs, 0);
  });

  testWidgets('a replay onto a session the office already closed is not shown as running', (
    tester,
  ) async {
    final client = _ScriptedWorkflowClient(
      result: const TicketTimerStart(id: 'server-1', isActive: false),
    );
    final ref = await pumpRef(tester, client: client, online: true);

    await expectLater(
      () => startTicketTimer(ref, 't1'),
      throwsA(isA<TicketTimerAlreadyClosed>()),
    );

    expect(
      await repo.forTicket('t1'),
      isEmpty,
      reason: 'a mirrored row with no end would render a clock that is not counting',
    );
  });
}

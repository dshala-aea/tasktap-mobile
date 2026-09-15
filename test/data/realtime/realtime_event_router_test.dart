// dart format width=100
// Tests for routeRealtimeEvent — see realtime_event_router.dart's own header comment for why two
// different re-fetch mechanisms are used (direct invalidation for the one network-backed
// FutureProvider target; invalidation + a triggered general sync for the Drift-mirrored
// StreamProvider targets, whose real refresh comes from the sync writing new rows, not from
// invalidation alone).
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/realtime/realtime_connection.dart';
import 'package:tasktap_mobile/data/realtime/realtime_event_router.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show appDatabaseProvider, syncServiceProvider, syncProvider, SyncService, SyncStatus;
import 'package:tasktap_mobile/features/altro/notifiche_provider.dart'
    show NotificheNotifier, notificheProvider;
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart' show cantiereByIdProvider;
import 'package:tasktap_mobile/features/rapportino/rapportino_list_providers.dart'
    show rapportiniListProvider;
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart' show ticketWorklogsProvider;
import 'package:tasktap_mobile/presentation/providers/schedule_providers.dart'
    show ticketByIdProvider;

class MockSyncService extends Mock implements SyncService {}

/// Records [refresh] calls instead of actually hitting the network — `Env.apiBaseUrl` is empty
/// in this test suite (no API_BASE_URL dart-define), which makes the real `refresh()` a silent
/// no-op that leaves no observable trace, so a plain [NotificheNotifier] can't tell us whether
/// [routeRealtimeNotification] actually called it.
class _RefreshTrackingNotifier extends NotificheNotifier {
  _RefreshTrackingNotifier(super.db, super.dio, super.ref);

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

void main() {
  test('a TicketWorkLogStarted event invalidates ticketWorklogsProvider for that ticket', () async {
    var invalidated = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(
      ticketWorklogsProvider('t1'),
      (prev, next) => invalidated = true,
      fireImmediately: false,
    );
    // Establish the provider instance before invalidating it — otherwise there is nothing to
    // invalidate and the listener above would never see a rebuild.
    container.read(ticketWorklogsProvider('t1'));

    routeRealtimeEvent(
      container,
      RealtimeEvent.fromHubPayload({
        'type': 'TicketWorkLogStarted',
        'data': {'ticketId': 't1', 'workLogId': 'w1'},
      }),
    );

    // Riverpod delivers the invalidated rebuild's listener notification on the next microtask,
    // not synchronously within invalidate() itself.
    await Future<void>.delayed(Duration.zero);
    expect(invalidated, isTrue);
  });

  test('a TicketWorkLogStopped event invalidates ticketWorklogsProvider for that ticket', () async {
    var invalidated = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(
      ticketWorklogsProvider('t2'),
      (prev, next) => invalidated = true,
      fireImmediately: false,
    );
    container.read(ticketWorklogsProvider('t2'));

    routeRealtimeEvent(
      container,
      RealtimeEvent.fromHubPayload({
        'type': 'TicketWorkLogStopped',
        'data': {'ticketId': 't2', 'workLogId': 'w2'},
      }),
    );

    await Future<void>.delayed(Duration.zero);
    expect(invalidated, isTrue);
  });

  test(
    'a TicketUpdated event invalidates ticketByIdProvider for that ticket and triggers a sync',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final mockSyncService = MockSyncService();
      when(() => mockSyncService.sync()).thenAnswer((_) async => DateTime.utc(2026, 1, 1));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncServiceProvider.overrideWithValue(mockSyncService),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      var invalidated = false;
      container.listen(
        ticketByIdProvider('t1'),
        (prev, next) => invalidated = true,
        fireImmediately: false,
      );
      container.read(ticketByIdProvider('t1'));

      routeRealtimeEvent(
        container,
        RealtimeEvent.fromHubPayload({
          'type': 'TicketUpdated',
          'data': {'ticketId': 't1'},
        }),
      );

      // Riverpod delivers the invalidated rebuild's listener notification on the next microtask,
      // not synchronously within invalidate() itself; performSync() is likewise fire-and-forget
      // from the router's point of view. Give both a turn of the event loop before asserting.
      await Future<void>.delayed(Duration.zero);
      expect(invalidated, isTrue);
      verify(() => mockSyncService.sync()).called(1);
      expect(container.read(syncProvider).status, SyncStatus.done);
    },
  );

  test(
    'a CantiereStatusChanged event invalidates cantiereByIdProvider for that cantiere and '
    'triggers a sync (without trusting the raw status ordinal in the payload)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final mockSyncService = MockSyncService();
      when(() => mockSyncService.sync()).thenAnswer((_) async => DateTime.utc(2026, 1, 1));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncServiceProvider.overrideWithValue(mockSyncService),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      var invalidated = false;
      container.listen(
        cantiereByIdProvider('c1'),
        (prev, next) => invalidated = true,
        fireImmediately: false,
      );
      container.read(cantiereByIdProvider('c1'));

      routeRealtimeEvent(
        container,
        // status is a raw enum ordinal on the wire — deliberately not read by the router at all,
        // matching this plan's central rule that a push payload is a re-fetch signal, not a
        // trusted value.
        RealtimeEvent.fromHubPayload({
          'type': 'CantiereStatusChanged',
          'data': {'cantiereId': 'c1', 'status': 1},
        }),
      );

      await Future<void>.delayed(Duration.zero);
      expect(invalidated, isTrue);
      verify(() => mockSyncService.sync()).called(1);
    },
  );

  test(
    'a RapportinoSubmitted event invalidates rapportiniListProvider and triggers a sync',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final mockSyncService = MockSyncService();
      when(() => mockSyncService.sync()).thenAnswer((_) async => DateTime.utc(2026, 1, 1));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncServiceProvider.overrideWithValue(mockSyncService),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      var invalidated = false;
      container.listen(rapportiniListProvider, (prev, next) => invalidated = true, fireImmediately: false);
      container.read(rapportiniListProvider);

      routeRealtimeEvent(
        container,
        RealtimeEvent.fromHubPayload({
          'type': 'RapportinoSubmitted',
          'data': {'reportId': 'r1'},
        }),
      );

      await Future<void>.delayed(Duration.zero);
      expect(invalidated, isTrue);
      verify(() => mockSyncService.sync()).called(1);
    },
  );

  test(
    'routeRealtimeNotification triggers the same notificheProvider refresh app-resume uses',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      late _RefreshTrackingNotifier notifier;

      final container = ProviderContainer(
        overrides: [
          notificheProvider.overrideWith((ref) {
            notifier = _RefreshTrackingNotifier(db, Dio(), ref);
            return notifier;
          }),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      // Establish the provider instance before routing a notification. NotificheNotifier's
      // constructor kicks off an async, unawaitable _loadFromCache() Drift query (see
      // notifiche_screen_test.dart's own note on this) — give it a turn of the event loop to
      // settle before tearDown disposes the container, otherwise that query resolves against an
      // already-disposed StateNotifier and throws.
      container.read(notificheProvider);
      await Future<void>.delayed(Duration.zero);

      routeRealtimeNotification(container);

      expect(notifier.refreshCalls, 1);
    },
  );
}

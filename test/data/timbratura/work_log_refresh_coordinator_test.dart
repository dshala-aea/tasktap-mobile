// dart format width=100
// The trigger side of cross-device timbratura sync: a WorkLogChanged push (or resume / screen open
// / reconnect) must reconcile local state AND refetch the dashboard's tracker list, and a burst of
// pushes must collapse into one refresh.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/realtime/realtime_connection.dart';
import 'package:tasktap_mobile/data/realtime/realtime_event_router.dart';
import 'package:tasktap_mobile/data/timbratura/work_log_refresh_coordinator.dart';

class _FakeCoordinator extends WorkLogRefreshCoordinator {
  _FakeCoordinator() : super(reconcile: () async {}, refetchTrackers: () {});
  int requested = 0;
  int immediate = 0;

  @override
  void requestRefresh() => requested++;

  @override
  Future<void> refreshNow() async => immediate++;
}

void main() {
  group('WorkLogRefreshCoordinator', () {
    test('requestRefresh debounces a burst into one reconcile + one refetch', () {
      fakeAsync((async) {
        var reconciles = 0;
        var refetches = 0;
        final c = WorkLogRefreshCoordinator(
          reconcile: () async => reconciles++,
          refetchTrackers: () => refetches++,
        );
        c.requestRefresh();
        async.elapse(const Duration(milliseconds: 300));
        c.requestRefresh();
        c.requestRefresh();
        async.elapse(const Duration(milliseconds: 900));
        expect(reconciles, 0, reason: 'the window restarts on every event');
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        expect(reconciles, 1);
        expect(refetches, 1);
        c.dispose();
      });
    });

    test('refreshNow acts immediately and cancels a pending debounced one', () {
      fakeAsync((async) {
        var reconciles = 0;
        var refetches = 0;
        final c = WorkLogRefreshCoordinator(
          reconcile: () async => reconciles++,
          refetchTrackers: () => refetches++,
        );
        c.requestRefresh();
        c.refreshNow();
        async.flushMicrotasks();
        expect((reconciles, refetches), (1, 1));

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect((reconciles, refetches), (1, 1));
        c.dispose();
      });
    });

    test('a failing reconcile still refetches the tracker list and never throws', () async {
      var refetches = 0;
      final c = WorkLogRefreshCoordinator(
        reconcile: () async => throw Exception('offline'),
        refetchTrackers: () => refetches++,
      );
      await c.refreshNow();
      expect(refetches, 1);
      c.dispose();
    });

    test('dispose cancels a pending refresh', () {
      fakeAsync((async) {
        var reconciles = 0;
        final c = WorkLogRefreshCoordinator(
          reconcile: () async => reconciles++,
          refetchTrackers: () {},
        );
        c.requestRefresh();
        c.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(reconciles, 0);
      });
    });
  });

  group('routeRealtimeEvent', () {
    test('a WorkLogChanged envelope (real wire shape) requests a refresh', () {
      final fake = _FakeCoordinator();
      final container = ProviderContainer(
        overrides: [workLogRefreshCoordinatorProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      routeRealtimeEvent(
        container,
        RealtimeEvent.fromHubPayload({
          'type': 'WorkLogChanged',
          'data': {'action': 'started', 'source': 'web', 'at': '2026-09-30T08:23:45.1234567Z'},
          'occurredAt': '2026-09-30T08:23:45.2000000Z',
        }),
      );

      expect(fake.requested, 1);
    });

    test('every action variant is handled the same way', () {
      final fake = _FakeCoordinator();
      final container = ProviderContainer(
        overrides: [workLogRefreshCoordinatorProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      for (final action in ['started', 'ended', 'breakStarted', 'breakEnded']) {
        routeRealtimeEvent(
          container,
          RealtimeEvent.fromHubPayload({
            'type': 'WorkLogChanged',
            'data': {'action': action, 'source': 'mobile', 'at': '2026-09-30T08:23:45Z'},
          }),
        );
      }
      expect(fake.requested, 4);
    });
  });
}

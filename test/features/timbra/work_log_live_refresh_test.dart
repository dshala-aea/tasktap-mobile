// dart format width=100
// WorkLogLiveRefresh: the no-push safety net around the dashboard and the timbra screen. Refreshes
// on every appearance and on app resume, and polls every 15s while visible and foregrounded —
// including with Impostazioni → "Modalità offline" on (owner decision D7: that setting gates
// speculative downloads, never freshness).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show offlineModeProvider;
import 'package:tasktap_mobile/data/timbratura/work_log_refresh_coordinator.dart';
import 'package:tasktap_mobile/features/timbra/work_log_live_refresh.dart';

class _Fake extends WorkLogRefreshCoordinator {
  _Fake() : super(reconcile: () async {}, refetchTrackers: () {});
  int immediate = 0;

  @override
  Future<void> refreshNow({bool sync = true}) async => immediate++;
}

Widget _host(_Fake fake, {bool offlineMode = false, bool visible = true}) => ProviderScope(
  overrides: [
    workLogRefreshCoordinatorProvider.overrideWithValue(fake),
    offlineModeProvider.overrideWithValue(offlineMode),
  ],
  child: MaterialApp(
    home: TickerMode(
      enabled: visible,
      child: const WorkLogLiveRefresh(child: SizedBox()),
    ),
  ),
);

void main() {
  testWidgets('refreshes as soon as it appears', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake));
    await tester.pump();
    expect(fake.immediate, 1);
  });

  testWidgets('polls every 15s while visible and foregrounded', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    expect(fake.immediate, 3);
  });

  // D7: freshness is not a background convenience. A technician who switched "Modalità offline"
  // on is asking the app to stop working around the network, not asking to be shown a stale timer
  // while the phone has signal.
  testWidgets('still polls with offline mode on', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake, offlineMode: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    expect(fake.immediate, 4, reason: 'appear + three 15s ticks');
  });

  testWidgets('stops polling when the app is backgrounded, refreshes at once on resume', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(fake.immediate, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fake.immediate, 2);
    await tester.pump(const Duration(seconds: 15));
    expect(fake.immediate, 3);
  });

  testWidgets('does not poll while its tab is hidden; refreshes when it is shown again', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake, visible: false));
    await tester.pump(const Duration(seconds: 60));
    expect(fake.immediate, 0);

    await tester.pumpWidget(_host(fake, visible: true));
    await tester.pump();
    expect(fake.immediate, 1);
  });
}

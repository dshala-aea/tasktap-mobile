// dart format width=100
// WorkLogLiveRefresh: the no-push safety net around the dashboard and the timbra screen. Refreshes
// on every appearance and on app resume, and polls every 15s ONLY while visible, foregrounded and
// the "sync in background" preference allows it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show backgroundSyncPreferenceProvider;
import 'package:tasktap_mobile/data/timbratura/work_log_refresh_coordinator.dart';
import 'package:tasktap_mobile/features/timbra/work_log_live_refresh.dart';

class _Fake extends WorkLogRefreshCoordinator {
  _Fake() : super(reconcile: () async {}, refetchTrackers: () {});
  int immediate = 0;

  @override
  Future<void> refreshNow({bool sync = true}) async => immediate++;
}

Widget _host(_Fake fake, {bool background = true, bool visible = true}) => ProviderScope(
  overrides: [
    workLogRefreshCoordinatorProvider.overrideWithValue(fake),
    backgroundSyncPreferenceProvider.overrideWithValue(background),
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

  testWidgets('does not poll when background sync is off (still refreshes on appear)', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_host(fake, background: false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 45));
    expect(fake.immediate, 1);
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

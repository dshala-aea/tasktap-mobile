// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/widgets/offline_sync_banner.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show lastSyncProvider;

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: OfflineSyncBanner())),
);

/// The offline line ends with "aggiornato …", read from [lastSyncProvider]. Always overridden:
/// leaving it out would have the banner reach `appDatabaseProvider` and open the real database
/// inside a widget test.
Override _lastSync(DateTime? at) => lastSyncProvider.overrideWith((ref) => Stream.value(at));

void main() {
  testWidgets('renders nothing when online and fully synced', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        _lastSync(DateTime(2026, 10, 23, 8, 42)),
      ]),
    );
    await tester.pump();

    expect(find.byType(OfflineSyncBanner), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.textContaining('in coda'), findsNothing);
    // Online means refreshing: the freshness line belongs to the offline branch only.
    expect(find.textContaining('aggiornato'), findsNothing);
  });

  testWidgets('shows an offline indicator when disconnected', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        _lastSync(DateTime(2026, 10, 23, 8, 42)),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('shows the queued count alongside offline instead of hiding it', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 3, failed: 0))),
        _lastSync(DateTime(2026, 10, 23, 8, 42)),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('3 in coda'), findsOneWidget);
  });

  testWidgets('shows the failed count alongside offline, taking precedence over pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 1, failed: 2))),
        _lastSync(DateTime(2026, 10, 23, 8, 42)),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('2 da riprovare'), findsOneWidget);
    expect(find.textContaining('in coda'), findsNothing);
  });

  // The question the banner already answers — "is what I'm looking at current?" — answered
  // where it is asked, instead of several taps away in Impostazioni → Sistema.
  testWidgets('offline, also says when the data was last refreshed', (tester) async {
    final now = DateTime.now();
    final lastSync = DateTime(now.year, now.month, now.day, 8, 42);

    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        _lastSync(lastSync),
      ]),
    );
    await tester.pump();
    // The override is a `Stream.value`: it emits on a microtask, after the frame that built the
    // banner with no value yet (`aggiornato mai`). One pump is a race — it passed in the three
    // device-zone shards and failed in the UTC job on the same commit — so pump until it lands.
    await tester.pump();

    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.textContaining('aggiornato oggi 08:42'), findsOneWidget);
  });

  testWidgets('offline on a phone that has never synced says so', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        _lastSync(null),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('aggiornato mai'), findsOneWidget);
  });

  testWidgets('shows a pending count when online but items are queued', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 3, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('3'), findsOneWidget);

    final container = tester.widget<Container>(find.byKey(const Key('offlineSyncBannerContainer')));
    expect(container.color, AppPalette.light.bg3);
  });

  testWidgets('shows a distinct failed-state indicator, never folded into pending', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        // pending is also non-zero here — asserts failed rows are never silently folded into the
        // pending count/label.
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 1, failed: 2))),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('2 da riprovare'), findsOneWidget);
    expect(find.textContaining('in coda'), findsNothing);

    final container = tester.widget<Container>(find.byKey(const Key('offlineSyncBannerContainer')));
    // The failed state renders with a visibly different fill than the plain-pending case above
    // (AppPalette.light.red, not AppPalette.light.bg3) — this is the core differentiator: a
    // failed row must never look the same as one that's merely queued.
    expect(container.color, AppPalette.light.red);
    expect(container.color, isNot(AppPalette.light.bg3));

    final text = tester.widget<Text>(find.textContaining('da riprovare'));
    expect(text.style?.color, AppPalette.light.inkInverse);
  });
}

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}

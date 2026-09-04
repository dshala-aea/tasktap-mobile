// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/offline_sync_banner.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: OfflineSyncBanner())),
);

void main() {
  testWidgets('renders nothing when online and fully synced', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(true)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.byType(OfflineSyncBanner), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.textContaining('in coda'), findsNothing);
  });

  testWidgets('shows an offline indicator when disconnected', (tester) async {
    await tester.pumpWidget(
      _wrap([
        connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
        pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
      ]),
    );
    await tester.pump();

    expect(find.textContaining('Offline'), findsOneWidget);
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
  });
}

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}

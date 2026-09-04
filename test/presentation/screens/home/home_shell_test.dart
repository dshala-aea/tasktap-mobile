// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/presentation/screens/home/home_shell.dart';

class MockDio extends Mock implements Dio {}

/// Same fake as offline_sync_banner_test.dart's own — [OfflineSyncBanner] reads this provider
/// directly, and HomeShell's own initState watchers (entitlement refresh, reconnect hooks) also
/// read it, so it must be overridden regardless of what the banner itself needs.
class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}

/// A minimal stand-in for a real tab screen. HomeShell's own tree (nav + Stack + banner) is what
/// this test exercises — not real branch content, which would drag in each tab's own provider
/// graph for no benefit here.
class _BranchScreen extends StatelessWidget {
  const _BranchScreen(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

/// Builds a real [StatefulNavigationShell] via a 2-branch [StatefulShellRoute.indexedStack] — the
/// same construct app_router.dart wires HomeShell into (with 5 branches there), just trimmed to
/// the minimum that still produces the real go_router object HomeShell's constructor requires.
GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/a',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/a', builder: (_, _) => const _BranchScreen('A'))],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/b', builder: (_, _) => const _BranchScreen('B'))],
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  testWidgets('OfflineSyncBanner is mounted in HomeShell regardless of active tab', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final dio = MockDio();
    // HomeShell.initState fires an immediate entitlement refresh
    // (initEntitlementRefreshWatcher), which calls this exact endpoint with a narrow
    // `on DioException` catch — an unstubbed mock call would surface as an unhandled Future
    // rejection instead. A benign non-200 response keeps it a clean, silent no-op, matching what
    // an offline device would see.
    when(() => dio.get<Map<String, dynamic>>(any())).thenAnswer(
      (_) async => Response(requestOptions: RequestOptions(path: '/api/Auth/me'), statusCode: 401),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(dio),
          connectivityProvider.overrideWith(() => _FakeConnectivity(false)),
          pendingSyncCountProvider.overrideWith((ref) => Stream.value((pending: 0, failed: 0))),
        ],
        child: MaterialApp.router(routerConfig: _buildTestRouter()),
      ),
    );
    // First frame mounts HomeShell and fires its postFrameCallback (sync + watcher init).
    await tester.pump();
    // Let the watchers' fire-and-forget Futures (entitlement refresh, reconcilers, queue
    // flushes — all either DB-empty no-ops or internally error-swallowing, see the provider
    // files under lib/data/) resolve before asserting.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OfflineSyncBanner), findsOneWidget);
    // Fake connectivity is offline, so the banner should also actually be showing its label —
    // proof it is live-wired to the same provider, not just present-but-inert in the tree, and
    // that it sits in HomeShell's own Stack (above `content`) rather than inside one branch's
    // subtree, since the active branch here ('A') renders none of this itself.
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);

    // Dispose the whole tree so HomeShell.dispose() cancels its 60s reconcile-poll Timer —
    // otherwise flutter_test fails the test over a still-pending Timer.
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(Duration.zero);
    }
    await db.close();
  });
}

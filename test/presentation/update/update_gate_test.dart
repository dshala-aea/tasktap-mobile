// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/update/app_version_evaluator.dart';
import 'package:tasktap_mobile/core/update/app_version_policy_providers.dart';
import 'package:tasktap_mobile/core/update/app_version_policy_repository.dart';
import 'package:tasktap_mobile/core/update/update_required_state.dart';
import 'package:tasktap_mobile/data/api/app_version_policy_api.dart';
import 'package:tasktap_mobile/data/sync/pending_sync_count_provider.dart';
import 'package:tasktap_mobile/presentation/screens/update/update_gate.dart';

class _FakeStatus extends AppVersionStatusNotifier {
  _FakeStatus(this._initial);

  final AppVersionStatus _initial;
  int refreshCalls = 0;
  int dismissCalls = 0;

  @override
  AppVersionStatus build() => _initial;

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> dismissAvailable() async {
    dismissCalls++;
    state = state.copyWith(bannerDismissed: true);
  }
}

const _requiredStatus = AppVersionStatus(
  policy: AppVersionPolicy(minimumVersion: '1.0.12', message: 'Nota dell’ufficio'),
  verdict: AppVersionVerdict.updateRequired,
);
const _availableStatus = AppVersionStatus(
  policy: AppVersionPolicy(recommendedVersion: '1.1.0'),
  verdict: AppVersionVerdict.updateAvailable,
);

final _store = Uri.parse('https://store.example/app');

class _Harness {
  _Harness({
    required AppVersionStatus status,
    bool isRequired = false,
    bool isAvailable = false,
    Stream<PendingSyncCount>? pending,
  }) : fake = _FakeStatus(status),
       launched = [],
       overrides = [] {
    overrides.addAll([
      appVersionStatusProvider.overrideWith(() => fake),
      updateRequiredProvider.overrideWith((ref) {
        final n = UpdateRequiredNotifier();
        if (isRequired) n.markRequired();
        return n;
      }),
      updateAvailableProvider.overrideWith((ref) {
        final n = UpdateAvailableNotifier();
        if (isAvailable) n.markAvailable();
        return n;
      }),
      pendingSyncCountProvider.overrideWith(
        (ref) => pending ?? Stream.value((pending: 0, failed: 0)),
      ),
      storeUriProvider.overrideWithValue(_store),
      storeLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ]);
  }

  final _FakeStatus fake;
  final List<Uri> launched;
  final List<Override> overrides;

  Widget app() => ProviderScope(
    retry: (_, _) => null,
    overrides: overrides,
    child: const MaterialApp(
      home: Scaffold(body: UpdateGate(child: Center(child: Text('home')))),
    ),
  );
}

Stream<PendingSyncCount> _pending(int n) => Stream.value((pending: n, failed: 0));

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(h.app());
  await tester.pump();
  await tester.pump();
}

void main() {
  const screenKey = Key('updateRequiredScreen');
  const pendingBannerKey = Key('updatePendingSyncBanner');
  const availableBannerKey = Key('updateAvailableBanner');

  group('gate rule in the shell', () {
    testWidgets('required and nothing pending: blocking screen, app kept mounted underneath', (
      tester,
    ) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(0));
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsOneWidget);
      expect(find.text('Aggiornamento necessario'), findsOneWidget);
      expect(find.textContaining('al sicuro'), findsOneWidget);
      expect(find.text('Nota dell’ufficio'), findsOneWidget);
      // Hidden, not unmounted: navigation state survives a lowered minimum.
      expect(find.text('home'), findsNothing);
      expect(find.text('home', skipOffstage: false), findsOneWidget);
    });

    testWidgets('the store button opens the store uri', (tester) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(0));
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('updateRequiredButton')));
      await tester.pump();

      expect(h.launched, [_store]);
    });

    testWidgets('required and items pending: calm banner, no block, app usable', (tester) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(5));
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsNothing);
      expect(find.byKey(pendingBannerKey), findsOneWidget);
      expect(find.text('Sincronizza, poi aggiorna'), findsOneWidget);
      expect(find.textContaining('5 elementi in attesa di invio'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('one pending item reads in the singular', (tester) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(1));
      await _pump(tester, h);

      expect(find.textContaining('1 elemento in attesa di invio'), findsOneWidget);
    });

    testWidgets('the pending banner still lets the user update', (tester) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(2));
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('updatePendingSyncButton')));
      await tester.pump();

      expect(h.launched, [_store]);
    });

    testWidgets('pending count still loading: never blocks', (tester) async {
      final never = StreamController<PendingSyncCount>();
      addTearDown(never.close);
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: never.stream);
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsNothing);
      expect(find.byKey(pendingBannerKey), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('pending count unreadable (error): never blocks', (tester) async {
      final h = _Harness(
        status: _requiredStatus,
        isRequired: true,
        pending: Stream<PendingSyncCount>.error(StateError('db')),
      );
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('not required: nothing forced, whatever is pending', (tester) async {
      final h = _Harness(status: AppVersionStatus.none, pending: _pending(0));
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsNothing);
      expect(find.byKey(pendingBannerKey), findsNothing);
      expect(find.byKey(availableBannerKey), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('the server flag alone (426 / header, no local verdict) blocks when nothing pending', (
      tester,
    ) async {
      final h = _Harness(status: AppVersionStatus.none, isRequired: true, pending: _pending(0));
      await _pump(tester, h);

      expect(find.byKey(screenKey), findsOneWidget);
    });

    testWidgets('block lifts when the app-wide flag clears', (tester) async {
      final h = _Harness(status: _requiredStatus, isRequired: true, pending: _pending(0));
      await _pump(tester, h);
      expect(find.byKey(screenKey), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byType(UpdateGate)));
      container.read(updateRequiredProvider.notifier).clear();
      await tester.pump();

      expect(find.byKey(screenKey), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('update available banner', () {
    testWidgets('shown below recommended, with a store button', (tester) async {
      final h = _Harness(status: _availableStatus, isAvailable: true);
      await _pump(tester, h);

      expect(find.byKey(availableBannerKey), findsOneWidget);
      expect(find.text('home'), findsOneWidget);

      await tester.tap(find.byKey(const Key('updateAvailableButton')));
      await tester.pump();
      expect(h.launched, [_store]);
    });

    testWidgets('dismiss hides it and asks the notifier to remember', (tester) async {
      final h = _Harness(status: _availableStatus, isAvailable: true);
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('updateAvailableDismiss')));
      await tester.pump();

      expect(h.fake.dismissCalls, 1);
      expect(find.byKey(availableBannerKey), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('already dismissed (remembered): not shown', (tester) async {
      final h = _Harness(status: _availableStatus.copyWith(bannerDismissed: true), isAvailable: true);
      await _pump(tester, h);

      expect(find.byKey(availableBannerKey), findsNothing);
    });

    testWidgets('not shown while an update is required', (tester) async {
      final h = _Harness(
        status: _requiredStatus,
        isRequired: true,
        isAvailable: true,
        pending: _pending(3),
      );
      await _pump(tester, h);

      expect(find.byKey(availableBannerKey), findsNothing);
      expect(find.byKey(pendingBannerKey), findsOneWidget);
    });
  });

  testWidgets('returning to the foreground refreshes the policy', (tester) async {
    final h = _Harness(status: AppVersionStatus.none);
    await _pump(tester, h);
    expect(h.fake.refreshCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(h.fake.refreshCalls, 1);
  });
}

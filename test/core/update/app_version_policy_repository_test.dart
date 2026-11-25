// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/update/app_version_evaluator.dart';
import 'package:tasktap_mobile/core/update/app_version_policy_providers.dart';
import 'package:tasktap_mobile/core/update/app_version_policy_repository.dart';
import 'package:tasktap_mobile/core/update/update_required_state.dart';
import 'package:tasktap_mobile/data/api/app_version_policy_api.dart';

const _installed = '1.0.11+42';

AppVersionPolicyRepository _repo({
  required Future<AppVersionPolicy> Function(String) fetch,
  DateTime Function()? now,
  String? installed = _installed,
}) => AppVersionPolicyRepository(
  fetchPolicy: fetch,
  store: AppVersionPolicyStore(),
  installedVersion: () async => installed,
  platform: 'android',
  now: now,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppVersionPolicyRepository', () {
    test('a fetched policy is judged locally and cached', () async {
      final repo = _repo(
        fetch: (_) async => const AppVersionPolicy(minimumVersion: '1.0.12', storeUrl: 'https://s/x', message: 'm'),
      );

      final r = await repo.refresh();

      expect(r.fresh, isTrue);
      expect(r.status.updateRequired, isTrue);
      expect(r.status.storeUrl, 'https://s/x');
      expect(r.status.message, 'm');
      // The cache alone (no network) gives the same verdict.
      final cached = await repo.loadCached();
      expect(cached.updateRequired, isTrue);
    });

    test('fetch failure keeps the cached policy and never throws', () async {
      var fail = false;
      final repo = _repo(
        fetch: (_) async {
          if (fail) throw Exception('offline');
          return const AppVersionPolicy(minimumVersion: '1.0.12');
        },
      );
      await repo.refresh();

      fail = true;
      final r = await repo.refresh();

      expect(r.fresh, isFalse);
      expect(r.status.updateRequired, isTrue);
    });

    test('no policy ever (nothing cached, fetch fails) -> nothing required or available', () async {
      final repo = _repo(fetch: (_) async => throw Exception('offline'));

      final r = await repo.refresh();

      expect(r.fresh, isFalse);
      expect(r.status.verdict, AppVersionVerdict.ok);
      expect(r.status.updateRequired, isFalse);
      expect(r.status.updateAvailable, isFalse);
    });

    test('a corrupt cache reads as nothing cached', () async {
      SharedPreferences.setMockInitialValues({AppVersionPolicyStore.policyKey: '{not json'});
      final repo = _repo(fetch: (_) async => throw Exception('offline'));

      expect((await repo.loadCached()).updateRequired, isFalse);
    });

    test('a lowered minimum replaces the cached one', () async {
      var min = '1.0.12';
      final repo = _repo(fetch: (_) async => AppVersionPolicy(minimumVersion: min));
      expect((await repo.refresh()).status.updateRequired, isTrue);

      min = '1.0.11';
      final r = await repo.refresh();

      expect(r.status.updateRequired, isFalse);
      expect((await repo.loadCached()).updateRequired, isFalse);
    });

    test('unreadable installed version never blocks', () async {
      final repo = _repo(
        fetch: (_) async => const AppVersionPolicy(minimumVersion: '9.9.9'),
        installed: null,
      );
      expect((await repo.refresh()).status.updateRequired, isFalse);
    });

    test('below recommended: available, banner dismissal lasts 7 days, per build', () async {
      var now = DateTime.utc(2026, 11, 25, 9);
      final repo = _repo(
        fetch: (_) async => const AppVersionPolicy(recommendedVersion: '1.1.0'),
        now: () => now,
      );
      final first = (await repo.refresh()).status;
      expect(first.updateAvailable, isTrue);
      expect(first.bannerDismissed, isFalse);

      await repo.dismissAvailable(first);

      now = now.add(const Duration(days: 6, hours: 23));
      expect((await repo.loadCached()).bannerDismissed, isTrue);

      now = DateTime.utc(2026, 11, 25, 9).add(const Duration(days: 7, minutes: 1));
      expect((await repo.loadCached()).bannerDismissed, isFalse);

      // Another installed build is a different token: not dismissed.
      now = DateTime.utc(2026, 11, 25, 10);
      final otherBuild = _repo(
        fetch: (_) async => const AppVersionPolicy(recommendedVersion: '1.1.0'),
        now: () => now,
        installed: '1.0.11+43',
      );
      expect((await otherBuild.loadCached()).bannerDismissed, isFalse);
    });

    test('a dismissal stamped in the future (clock moved back) does not hide the banner', () async {
      var now = DateTime.utc(2026, 11, 25, 9);
      final repo = _repo(
        fetch: (_) async => const AppVersionPolicy(recommendedVersion: '1.1.0'),
        now: () => now,
      );
      final status = (await repo.refresh()).status;
      await repo.dismissAvailable(status);

      now = now.subtract(const Duration(days: 2));

      expect((await repo.loadCached()).bannerDismissed, isFalse);
    });
  });

  group('AppVersionStatusNotifier', () {
    ProviderContainer containerFor(AppVersionPolicyRepository repo) {
      final c = ProviderContainer(
        overrides: [appVersionPolicyRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('cached required policy applies at launch even when the fetch fails (offline launch)', () async {
      await _repo(fetch: (_) async => const AppVersionPolicy(minimumVersion: '1.0.12')).refresh();
      final c = containerFor(_repo(fetch: (_) async => throw Exception('offline')));

      c.read(appVersionStatusProvider);
      await pumpEventQueue();

      expect(c.read(appVersionStatusProvider).updateRequired, isTrue);
      expect(c.read(updateRequiredProvider), isTrue);
    });

    test('no cache and a failing fetch: nothing is marked', () async {
      final c = containerFor(_repo(fetch: (_) async => throw Exception('offline')));

      c.read(appVersionStatusProvider);
      await pumpEventQueue();

      expect(c.read(updateRequiredProvider), isFalse);
      expect(c.read(updateAvailableProvider), isFalse);
    });

    test('a fresh policy that says OK releases a running app marked by a 426', () async {
      final c = containerFor(_repo(fetch: (_) async => const AppVersionPolicy(minimumVersion: '1.0.11')));
      c.read(updateRequiredProvider.notifier).markRequired();

      c.read(appVersionStatusProvider);
      await pumpEventQueue();

      expect(c.read(updateRequiredProvider), isFalse);
    });

    test('a failed fetch does not release a 426 mark', () async {
      final c = containerFor(_repo(fetch: (_) async => throw Exception('offline')));
      c.read(updateRequiredProvider.notifier).markRequired();

      c.read(appVersionStatusProvider);
      await pumpEventQueue();

      expect(c.read(updateRequiredProvider), isTrue);
    });

    test('below recommended marks available; dismissal persists across a restart', () async {
      const policy = AppVersionPolicy(recommendedVersion: '1.1.0');
      final c1 = containerFor(_repo(fetch: (_) async => policy));
      c1.read(appVersionStatusProvider);
      await pumpEventQueue();
      expect(c1.read(updateAvailableProvider), isTrue);
      expect(c1.read(appVersionStatusProvider).bannerDismissed, isFalse);

      await c1.read(appVersionStatusProvider.notifier).dismissAvailable();
      expect(c1.read(appVersionStatusProvider).bannerDismissed, isTrue);

      // A new "launch" (new container, same prefs).
      final c2 = containerFor(_repo(fetch: (_) async => policy));
      c2.read(appVersionStatusProvider);
      await pumpEventQueue();
      expect(c2.read(appVersionStatusProvider).bannerDismissed, isTrue);
    });

    group('resume throttle', () {
      test('skips a resume refresh within 15 minutes, refetches after', () async {
        var fetches = 0;
        var now = DateTime.utc(2026, 11, 25, 9);
        final repo = _repo(
          fetch: (_) async {
            fetches++;
            return const AppVersionPolicy();
          },
        );
        final c = ProviderContainer(
          overrides: [
            appVersionPolicyRepositoryProvider.overrideWithValue(repo),
            appVersionClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(c.dispose);
        final notifier = c.read(appVersionStatusProvider.notifier);
        await pumpEventQueue();
        expect(fetches, 1); // launch

        now = now.add(const Duration(minutes: 5));
        await notifier.refreshOnResume();
        expect(fetches, 1);

        now = now.add(const Duration(minutes: 11)); // 16 min since launch
        await notifier.refreshOnResume();
        expect(fetches, 2);

        now = now.add(const Duration(minutes: 1));
        await notifier.refreshOnResume();
        expect(fetches, 2);
      });

      test('a failed attempt also counts for the throttle', () async {
        var fetches = 0;
        var now = DateTime.utc(2026, 11, 25, 9);
        final repo = _repo(
          fetch: (_) async {
            fetches++;
            throw Exception('offline');
          },
        );
        final c = ProviderContainer(
          overrides: [
            appVersionPolicyRepositoryProvider.overrideWithValue(repo),
            appVersionClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(c.dispose);
        final notifier = c.read(appVersionStatusProvider.notifier);
        await pumpEventQueue();
        now = now.add(const Duration(minutes: 1));
        await notifier.refreshOnResume();

        expect(fetches, 1);
      });

      test('while an update is required every resume refetches (store return releases promptly)', () async {
        var fetches = 0;
        var now = DateTime.utc(2026, 11, 25, 9);
        final repo = _repo(
          fetch: (_) async {
            fetches++;
            return const AppVersionPolicy(minimumVersion: '1.0.12');
          },
        );
        final c = ProviderContainer(
          overrides: [
            appVersionPolicyRepositoryProvider.overrideWithValue(repo),
            appVersionClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(c.dispose);
        final notifier = c.read(appVersionStatusProvider.notifier);
        await pumpEventQueue();
        expect(c.read(updateRequiredProvider), isTrue);

        now = now.add(const Duration(seconds: 30));
        await notifier.refreshOnResume();

        expect(fetches, 2);
      });
    });
  });
}

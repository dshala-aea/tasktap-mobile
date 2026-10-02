import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/time/business_time_providers.dart';

class _SlowStore extends BusinessZoneStore {
  _SlowStore(this.gate, this.value);
  final Completer<void> gate;
  final String? value;

  @override
  Future<String?> readCached() async {
    await gate.future;
    return value;
  }
}

ProviderContainer _container({List<Override> overrides = const []}) {
  final c = ProviderContainer(overrides: overrides);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default state is Europe/Rome with nothing cached', () async {
    final c = _container();
    expect(c.read(businessZoneIdProvider), 'Europe/Rome');
    await c.read(businessZoneIdProvider.notifier).hydrateForTest();
    expect(c.read(businessZoneIdProvider), 'Europe/Rome');
  });

  test('hydrates lazily from the persisted zone', () async {
    SharedPreferences.setMockInitialValues({
      tenantTimeZonePrefsKey: 'America/New_York',
    });
    final c = _container();
    expect(c.read(businessZoneIdProvider), 'Europe/Rome');
    await c.read(businessZoneIdProvider.notifier).hydrateForTest();
    expect(c.read(businessZoneIdProvider), 'America/New_York');
  });

  test('invalid persisted id falls back to Rome', () async {
    SharedPreferences.setMockInitialValues({
      tenantTimeZonePrefsKey: 'W. Europe Standard Time',
    });
    final c = _container();
    await c.read(businessZoneIdProvider.notifier).hydrateForTest();
    expect(c.read(businessZoneIdProvider), 'Europe/Rome');
  });

  test('set persists and updates state', () async {
    final c = _container();
    await c.read(businessZoneIdProvider.notifier).set('Asia/Tokyo');
    expect(c.read(businessZoneIdProvider), 'Asia/Tokyo');
    expect(await BusinessZoneStore().readCached(), 'Asia/Tokyo');
  });

  test('set ignores null, empty and unknown ids', () async {
    final c = _container();
    final n = c.read(businessZoneIdProvider.notifier);
    await n.set('Asia/Tokyo');
    for (final bad in <String?>[
      null,
      '',
      'Nope/Zone',
      'W. Europe Standard Time',
    ]) {
      await n.set(bad);
      expect(c.read(businessZoneIdProvider), 'Asia/Tokyo', reason: '$bad');
    }
    expect(await BusinessZoneStore().readCached(), 'Asia/Tokyo');
  });

  test(
    'businessTimeProvider follows the zone and the overridden clock',
    () async {
      final c = _container(
        overrides: [
          clockProvider.overrideWithValue(
            () => DateTime.utc(2026, 3, 10, 23, 30),
          ),
        ],
      );
      expect(
        c.read(businessTimeProvider).businessToday(),
        DateTime.utc(2026, 3, 11),
      );
      await c.read(businessZoneIdProvider.notifier).set('America/New_York');
      expect(c.read(businessTimeProvider).zoneId, 'America/New_York');
      expect(
        c.read(businessTimeProvider).businessToday(),
        DateTime.utc(2026, 3, 10),
      );
    },
  );

  test('stale hydration does not overwrite a reset', () async {
    final gate = Completer<void>();
    final c = _container(
      overrides: [
        businessZoneStoreProvider.overrideWithValue(
          _SlowStore(gate, 'Asia/Tokyo'),
        ),
      ],
    );
    final n = c.read(businessZoneIdProvider.notifier);
    final hydrating = n.hydrateForTest();
    await n.reset();
    gate.complete();
    await hydrating;
    expect(c.read(businessZoneIdProvider), 'Europe/Rome');
  });

  test('stale hydration does not overwrite a newer set', () async {
    final gate = Completer<void>();
    final c = _container(
      overrides: [
        businessZoneStoreProvider.overrideWithValue(
          _SlowStore(gate, 'Asia/Tokyo'),
        ),
      ],
    );
    final n = c.read(businessZoneIdProvider.notifier);
    final hydrating = n.hydrateForTest();
    await n.set('America/New_York');
    gate.complete();
    await hydrating;
    expect(c.read(businessZoneIdProvider), 'America/New_York');
  });

  test(
    'logout resets the zone to Rome and a following /me without the key stays Rome',
    () async {
      final c = _container();
      final n = c.read(businessZoneIdProvider.notifier);
      await n.set('America/New_York');
      await n.reset();
      expect(c.read(businessZoneIdProvider), 'Europe/Rome');
      expect(await BusinessZoneStore().readCached(), isNull);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          tenantTimeZonePrefsKey,
        ),
        isFalse,
      );
      await n.set(
        null,
      ); // what the /me callback does for a body without the key
      expect(c.read(businessZoneIdProvider), 'Europe/Rome');
    },
  );
}

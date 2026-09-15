// Tests for KioskModeNotifier — the state machine behind kiosk mode's activate/deactivate/poll
// lifecycle (lib/presentation/providers/kiosk_providers.dart).
//
// KioskCredentialsStore, KioskApiClient and IKioskLockService are all mocked (mocktail); nothing
// here touches real secure storage, network, or platform channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/kiosk/kiosk_lock_service.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_api_client.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_credentials_store.dart';
import 'package:tasktap_mobile/presentation/providers/kiosk_providers.dart';

class MockStore extends Mock implements KioskCredentialsStore {}

class MockApi extends Mock implements KioskApiClient {}

class MockLock extends Mock implements IKioskLockService {}

void main() {
  late MockStore store;
  late MockApi api;
  late MockLock lock;

  setUp(() {
    store = MockStore();
    api = MockApi();
    lock = MockLock();
  });

  KioskModeNotifier build() => KioskModeNotifier(store, api, lock);

  group('_init (constructor)', () {
    test('no stored credentials → inactive, never touches the lock service', () async {
      when(() => store.read()).thenAnswer((_) async => null);

      final notifier = build();
      await Future<void>.delayed(Duration.zero); // let _init's awaits settle

      expect(notifier.state.loading, isFalse);
      expect(notifier.state.active, isFalse);
      verifyNever(() => lock.start());
    });

    test('stored credentials → re-locks immediately on cold start', () async {
      when(() => store.read()).thenAnswer(
        (_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: 'Totem A'),
      );
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.active, isTrue);
      expect(notifier.state.deviceLabel, 'Totem A');
      expect(notifier.state.lockOutcome, KioskLockOutcome.locked);
      verify(() => lock.start()).called(1);
    });
  });

  group('activate', () {
    test('validates against the backend, persists, locks, and flips active', () async {
      when(() => store.read()).thenAnswer((_) async => null);
      when(
        () => api.fetchQr('sp_new'),
      ).thenAnswer((_) async => const KioskQrToken(token: 't', expiresInSeconds: 60));
      when(
        () => store.save(rawKey: any(named: 'rawKey'), deviceLabel: any(named: 'deviceLabel'), exitPin: any(named: 'exitPin')),
      ).thenAnswer((_) async {});
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      await notifier.activate(rawKey: 'sp_new', deviceLabel: 'Totem B', exitPin: '1234');

      expect(notifier.state.active, isTrue);
      expect(notifier.state.deviceLabel, 'Totem B');
      verify(
        () => store.save(rawKey: 'sp_new', deviceLabel: 'Totem B', exitPin: '1234'),
      ).called(1);
      verify(() => lock.start()).called(1);
    });

    test('an invalid/revoked key throws and persists/locks nothing', () async {
      when(() => store.read()).thenAnswer((_) async => null);
      when(
        () => api.fetchQr('sp_bad'),
      ).thenThrow(const KioskApiException(KioskApiFailureReason.invalidOrRevoked));

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        notifier.activate(rawKey: 'sp_bad', deviceLabel: '', exitPin: '1234'),
        throwsA(isA<KioskApiException>()),
      );

      expect(notifier.state.active, isFalse);
      verifyNever(
        () => store.save(rawKey: any(named: 'rawKey'), deviceLabel: any(named: 'deviceLabel'), exitPin: any(named: 'exitPin')),
      );
      verifyNever(() => lock.start());
    });
  });

  group('refreshQr', () {
    test('returns the token on success', () async {
      when(
        () => store.read(),
      ).thenAnswer((_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: ''));
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);
      when(
        () => api.fetchQr('sp_x'),
      ).thenAnswer((_) async => const KioskQrToken(token: 'abc', expiresInSeconds: 45));

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      final token = await notifier.refreshQr();

      expect(token.token, 'abc');
    });

    test('invalidOrRevoked auto-deactivates: unlocks, clears storage, flips inactive', () async {
      when(
        () => store.read(),
      ).thenAnswer((_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: ''));
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);
      when(() => lock.stop()).thenAnswer((_) async {});
      when(() => store.clear()).thenAnswer((_) async {});
      when(
        () => api.fetchQr('sp_x'),
      ).thenThrow(const KioskApiException(KioskApiFailureReason.invalidOrRevoked));

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      await expectLater(notifier.refreshQr(), throwsA(isA<KioskApiException>()));

      expect(notifier.state.active, isFalse);
      verify(() => lock.stop()).called(1);
      verify(() => store.clear()).called(1);
    });

    test('a transient network failure does NOT deactivate — device stays pinned', () async {
      when(
        () => store.read(),
      ).thenAnswer((_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: ''));
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);
      when(() => api.fetchQr('sp_x')).thenThrow(const KioskApiException(KioskApiFailureReason.network));

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      await expectLater(notifier.refreshQr(), throwsA(isA<KioskApiException>()));

      expect(notifier.state.active, isTrue);
      verifyNever(() => lock.stop());
      verifyNever(() => store.clear());
    });
  });

  group('deactivate', () {
    test('wrong PIN leaves kiosk mode active', () async {
      when(
        () => store.read(),
      ).thenAnswer((_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: ''));
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);
      when(() => store.verifyExitPin('0000')).thenAnswer((_) async => false);

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      final ok = await notifier.deactivate('0000');

      expect(ok, isFalse);
      expect(notifier.state.active, isTrue);
      verifyNever(() => lock.stop());
    });

    test('correct PIN unlocks, clears storage, flips inactive', () async {
      when(
        () => store.read(),
      ).thenAnswer((_) async => const KioskCredentials(rawKey: 'sp_x', deviceLabel: ''));
      when(() => lock.start()).thenAnswer((_) async => KioskLockOutcome.locked);
      when(() => store.verifyExitPin('1234')).thenAnswer((_) async => true);
      when(() => lock.stop()).thenAnswer((_) async {});
      when(() => store.clear()).thenAnswer((_) async {});

      final notifier = build();
      await Future<void>.delayed(Duration.zero);

      final ok = await notifier.deactivate('1234');

      expect(ok, isTrue);
      expect(notifier.state.active, isFalse);
      verify(() => lock.stop()).called(1);
      verify(() => store.clear()).called(1);
    });
  });
}

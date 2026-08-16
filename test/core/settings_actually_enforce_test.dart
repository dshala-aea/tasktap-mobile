import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/security/biometric_lock.dart';
import 'package:tasktap_mobile/core/security/biometric_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

/// Two settings claimed a control they did not have.
///
/// "Geolocalizzazione" wrote a bool nothing read, while `cantiere_timbra_screen` captured a
/// position on every clock-in regardless. "Autenticazione biometrica" offered fingerprint/Face ID
/// unlock with no biometrics package in the project at all.
///
/// A settings switch that reports a choice it does not enforce is worse than no switch: it stops
/// the user looking for a real control, and under a consent audit it is a false statement about
/// processing. These tests assert enforcement, not the presence of a widget.
class _FakeBiometrics implements IBiometricService {
  _FakeBiometrics({this.succeeds = true});

  bool succeeds;
  int prompts = 0;

  // The lock never asks — availability is checked once in Impostazioni, before the setting may be
  // switched on, so by the time the lock exists the device is known to be capable.
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return succeeds;
  }
}


/// Drives the real lifecycle channel. `binding.handleAppLifecycleStateChanged` does not reach
/// WidgetsBindingObservers in the test binding, so a lock that keys off `paused`/`resumed` has to
/// be exercised the way the platform does it.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

class _FakeStore implements LockActivityStore {
  _FakeStore(this._lastActiveAt);

  final DateTime? _lastActiveAt;
  DateTime? written;

  @override
  Future<DateTime?> lastActiveAt() async => written ?? _lastActiveAt;

  @override
  Future<void> markActive(DateTime at) async => written = at;
}

class _FakeAuth implements IAuthRepository {
  _FakeAuth({this.throws = false});

  final bool throws;
  int refreshes = 0;

  @override
  Future<({AuthFailure? failure, AuthUser? user})> refreshSession() async {
    refreshes++;
    if (throws) throw Exception('offline');
    return (user: null, failure: null);
  }

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => const Stream.empty();

  @override
  Future<({AuthFailure? failure, AuthUser? user})> signIn() async => (user: null, failure: null);

  @override
  Future<void> signOut() async {}
}

void main() {
  group('the GPS setting gates capture', () {
    ILocationService serviceWith(bool allowed) {
      final container = ProviderContainer(
        overrides: [gpsPreferenceProvider.overrideWithValue(allowed)],
      );
      addTearDown(container.dispose);
      return container.read(locationServiceProvider);
    }

    test('off means no position is ever produced', () async {
      final service = serviceWith(false);

      expect(service, isA<DisabledLocationService>());
      // Null is what every call site already handles as "denied", so the record simply carries no
      // position rather than a fabricated one.
      expect(await service.getCurrentPosition(), isNull);
    });

    test('on uses the real service', () {
      expect(serviceWith(true), isA<LocationService>());
    });

    test('the gate is a single choke point, not a per-call-site check', () {
      // The defect was that honouring the setting depended on every call site remembering it.
      // Resolving the service through the provider is what makes a future call site gated by
      // default rather than by diligence.
      final container = ProviderContainer(
        overrides: [gpsPreferenceProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      expect(container.read(locationServiceProvider), isA<DisabledLocationService>());
    });
  });

  group('an unavailable position is recorded as absent, never as a value', () {
    test('the disabled service yields null rather than a placeholder coordinate', () async {
      // The rapportino step used to write (0.0, 0.0) — Null Island — mark the position
      // "acquired" and render it as measured, so a report could reach an invoice carrying a
      // coordinate that was never anywhere. Null is the only honest answer, and every call site
      // already treats it as one.
      const service = DisabledLocationService();
      final coords = await service.getCurrentPosition();

      expect(coords, isNull);
    });

    test('no call site is handed a zero-island fallback', () {
      // A regression here would not be a crash — it would be a plausible-looking coordinate in a
      // signed document, which is why it is worth asserting on the source.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains('setGps(0') ||
            src.contains('setGps(lat, lng)') && src.contains('const double lat = 0')) {
          offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }

      expect(offenders, isEmpty, reason: 'record no position rather than a fabricated one');
    });
  });

  group('the biometric setting gates the app', () {
    Future<(_FakeBiometrics, _FakeStore)> pumpLock(
      WidgetTester tester, {
      required bool enabled,
      bool succeeds = true,
      DateTime? lastActiveAt,
      Duration grace = const Duration(minutes: 5),
    }) async {
      final fake = _FakeBiometrics(succeeds: succeeds);
      final store = _FakeStore(lastActiveAt);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricServiceProvider.overrideWithValue(fake),
            authRepositoryProvider.overrideWithValue(_FakeAuth()),
          ],
          child: MaterialApp(
            home: BiometricLock(
              enabled: enabled,
              grace: grace,
              store: store,
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (fake, store);
    }

    testWidgets('off is a pass-through and never prompts', (tester) async {
      final (fake, _) = await pumpLock(tester, enabled: false);

      expect(find.text('dati riservati'), findsOneWidget);
      expect(fake.prompts, 0);
    });

    testWidgets('a cold start with no record asks', (tester) async {
      final (fake, _) = await pumpLock(tester, enabled: true, succeeds: false);

      expect(fake.prompts, greaterThan(0), reason: 'the lock must actually call the platform');
      expect(find.text('TaskTap è bloccato'), findsOneWidget);
    });

    testWidgets('a successful prompt reveals the app and records the moment', (tester) async {
      final (_, store) = await pumpLock(tester, enabled: true);

      expect(find.text('TaskTap è bloccato'), findsNothing);
      expect(find.text('dati riservati'), findsOneWidget);
      expect(store.written, isNotNull, reason: 'the grace window starts from the unlock');
    });

    testWidgets('the covered child keeps its state rather than being disposed', (tester) async {
      // A running timer or a half-written rapportino must survive being locked, so the lock
      // covers the tree instead of replacing it.
      final (fake, _) = await pumpLock(tester, enabled: true, succeeds: false);

      expect(fake.prompts, greaterThan(0));
      expect(
        find.text('dati riservati', skipOffstage: false),
        findsOneWidget,
        reason: 'the child stays in the tree beneath the lock',
      );
    });

    testWidgets('a failed prompt offers a way to retry', (tester) async {
      // A lock with no retry after a dismissed OS prompt is a lock-out.
      await pumpLock(tester, enabled: true, succeeds: false);

      expect(find.text('Sblocca'), findsOneWidget);
    });
  });

  /// The prompt used to fire on every single return to the foreground.
  ///
  /// A technician checks the address in Maps, photographs a serial number, answers a message and
  /// comes back: four fingerprint prompts to do one intervento. A control that fires that often
  /// gets swatted away, and the usual next step is turning it off — which protects the data less
  /// than a lock that asks less often.
  group('the lock asks only when the app has actually been away', () {
    Future<_FakeBiometrics> pump(
      WidgetTester tester, {
      required DateTime? lastActiveAt,
      Duration grace = const Duration(minutes: 5),
      _FakeAuth? auth,
    }) async {
      final fake = _FakeBiometrics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricServiceProvider.overrideWithValue(fake),
            authRepositoryProvider.overrideWithValue(auth ?? _FakeAuth()),
          ],
          child: MaterialApp(
            home: BiometricLock(
              enabled: true,
              grace: grace,
              store: _FakeStore(lastActiveAt),
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('a restart inside the window opens straight into the app', (tester) async {
      final fake = await pump(
        tester,
        lastActiveAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(fake.prompts, 0);
      expect(find.text('dati riservati'), findsOneWidget);
    });

    testWidgets('a restart after the window asks', (tester) async {
      final fake = await pump(
        tester,
        lastActiveAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );

      expect(fake.prompts, 1);
    });

    testWidgets('the app is covered while backgrounded even inside the window', (tester) async {
      // The prompt is what got cheaper, not the privacy.
      //
      // Note `inactive`, not `paused`: by the time `paused` arrives the framework has stopped
      // producing frames, so a cover raised there is never painted and the snapshot the OS keeps
      // is still the content. This test only passes because the cover goes up a step earlier —
      // which is also the only reason it works on a device.
      final fake = await pump(
        tester,
        lastActiveAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();

      expect(find.text('dati riservati', skipOffstage: false), findsOneWidget);
      expect(find.byIcon(LucideIcons.fingerprint), findsWidgets, reason: 'covered');
      // Covered, but not asking: there is nothing for the technician to do and it is gone before
      // they see it, so no copy and no button flash past on every app switch.
      expect(find.text('TaskTap è bloccato'), findsNothing);
      expect(fake.prompts, 0);
    });

    testWidgets('coming back inside the window lifts the cover without asking', (tester) async {
      final fake = await pump(
        tester,
        lastActiveAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );

      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.paused);
      await tester.pump();
      await _lifecycle(tester, AppLifecycleState.inactive);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(fake.prompts, 0);
      expect(find.text('TaskTap è bloccato'), findsNothing);
    });

    testWidgets('a clock wound backwards does not buy an open app', (tester) async {
      // Otherwise changing the device date is a way past the lock.
      final fake = await pump(tester, lastActiveAt: DateTime.now().add(const Duration(days: 1)));

      expect(fake.prompts, 1);
    });
  });

  group('unlocking gets the session working again', () {
    testWidgets('a successful unlock refreshes the backend session', (tester) async {
      // The access token is short-lived and the app is often away for longer than it. Without
      // this the first tap after unlocking stalls while a request bounces off a 401 and the
      // interceptor refreshes — which reads as the app being slow, not as it being secure.
      final auth = _FakeAuth();
      final fake = _FakeBiometrics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricServiceProvider.overrideWithValue(fake),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: MaterialApp(
            home: BiometricLock(
              enabled: true,
              store: _FakeStore(null),
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.prompts, 1);
      expect(auth.refreshes, 1);
    });

    testWidgets('opening inside the grace window still refreshes', (tester) async {
      // Skipping the prompt must not mean skipping the session. This is the path most opens take.
      final auth = _FakeAuth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricServiceProvider.overrideWithValue(_FakeBiometrics()),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: MaterialApp(
            home: BiometricLock(
              enabled: true,
              store: _FakeStore(DateTime.now().subtract(const Duration(seconds: 10))),
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.refreshes, 1);
    });

    testWidgets('a refresh that fails does not hold the app shut', (tester) async {
      // Offline is the normal condition in a plant room. The cached data is still readable, and
      // the interceptor and the reconnect watcher both retry later.
      final auth = _FakeAuth(throws: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            biometricServiceProvider.overrideWithValue(_FakeBiometrics()),
            authRepositoryProvider.overrideWithValue(auth),
          ],
          child: MaterialApp(
            home: BiometricLock(
              enabled: true,
              store: _FakeStore(null),
              child: const Scaffold(body: Text('dati riservati')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('dati riservati'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

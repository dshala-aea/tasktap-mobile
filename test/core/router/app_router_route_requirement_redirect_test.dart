// Integration test for buildRouter's `redirect` callback applying the `_routeRequirements`
// route-requirement guard (lib/core/router/app_router.dart) to the admin schedule routes.
//
// Before this guard existed, a technician who navigated straight to an admin route (deep link,
// restored nav state, guessed URL) would simply render it — authorization only ever hid the tile.
// This asserts the actual regression this task closes: visiting the admin schedule list's full
// matched-location path (`/altro/pianificazioni`, traced from the route tree — see
// app_router.dart's `_routeRequirements` doc comment) while the `pianificazione.schedule.write`
// capability is denied lands on ForbiddenScreen, not AdminScheduleListScreen.
//
// Mirrors test/presentation/app_shell_test.dart's proven scaffolding for pumping the real
// TaskTapApp with a working router (mock auth repo, in-memory Drift DB, stubbed sync Dio) rather
// than inventing a lighter harness — building buildRouter's GoRouter standalone still lands on
// the real initialLocation (/dashboard) on first frame, which needs the same dependencies to
// render without throwing.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/kiosk/kiosk_lock_service.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_api_client.dart';
import 'package:tasktap_mobile/data/kiosk/kiosk_credentials_store.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' show AppDatabase;
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/admin/customers/admin_customer_form_screen.dart';
import 'package:tasktap_mobile/features/admin/magazzini/admin_magazzino_list_screen.dart';
import 'package:tasktap_mobile/features/admin/schedules/admin_schedule_list_screen.dart';
import 'package:tasktap_mobile/features/altro/forbidden_screen.dart';
import 'package:tasktap_mobile/features/cantiere/cantieri_list_screen.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/providers/kiosk_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

class MockKioskStore extends Mock implements KioskCredentialsStore {}

class MockKioskApi extends Mock implements KioskApiClient {}

class MockKioskLock extends Mock implements IKioskLockService {}

Map<String, dynamic> _emptySyncPayload() => {
  'syncedAt': DateTime.utc(2026, 9, 17).toIso8601String(),
  'since': null,
  'schedules': <dynamic>[],
  'draftReports': <dynamic>[],
  'customers': <dynamic>[],
  'locations': <dynamic>[],
  'tickets': <dynamic>[],
};

Widget _buildApp({
  required MockAuthRepository repo,
  required AppDatabase db,
  required MockDio mockDio,
  required Entitlement? cachedEntitlement,
}) {
  // The real KioskModeNotifier reads FlutterSecureStorage via a platform channel that never
  // answers in this widget-test host, so kioskModeProvider's state never leaves its initial
  // `loading: true` — and buildRouter's redirect stays "put" on every call for as long as that's
  // true (same as it would for a genuinely slow cold start), never reaching the auth/capability
  // checks below it. Override with a fake store that resolves `read()` to null immediately, the
  // same pattern test/presentation/providers/kiosk_providers_test.dart uses, so kiosk mode
  // settles to {loading: false, active: false} on the very first microtask.
  final kioskStore = MockKioskStore();
  when(() => kioskStore.read()).thenAnswer((_) async => null);

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      cachedEntitlementProvider.overrideWith((ref) => Future.value(cachedEntitlement)),
      kioskModeProvider.overrideWith(
        (ref) => KioskModeNotifier(kioskStore, MockKioskApi(), MockKioskLock()),
      ),
    ],
    child: const TaskTapApp(),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;
  late AppDatabase db;
  late MockDio mockDio;
  late AuthUser fakeUser;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    when(
      () =>
          mockDio.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/sync/mobile'),
        statusCode: 200,
        data: _emptySyncPayload(),
      ),
    );

    fakeUser = AuthUser(
      id: 'test-user',
      email: 'dispatcher@tasktap.io',
      accessToken: 'fake-token',
      refreshToken: 'fake-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
    // NOT added here: authStream is a broadcast StreamController, and authStateProvider (a
    // StreamProvider) only subscribes once something first reads it — which happens during the
    // first pumpWidget below (buildRouter's own _AuthStateListenable). An event added before that
    // subscription exists is simply dropped (broadcast streams never replay), so each test adds
    // fakeUser itself, right after its first pump.
  });

  tearDown(() async {
    await authStream.close();
    await db.close();
  });

  testWidgets(
    'denied pianificazione.schedule.write capability redirects /altro/pianificazioni to /forbidden',
    (tester) async {
      final cached = Entitlement(
        features: const {'pianificazione'},
        // Module is offered but the finer-grained write capability is NOT held — the admin
        // schedule surface must still be unreachable (this is exactly why the guard checks the
        // capability, not just the module).
        capabilities: const {'pianificazione.schedule.read'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 17),
      );

      await tester.pumpWidget(
        _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
      );
      authStream.add(fakeUser);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/altro/pianificazioni');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ForbiddenScreen), findsOneWidget);
      expect(find.byType(AdminScheduleListScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'held pianificazione.schedule.write capability reaches the admin schedule list, not /forbidden',
    (tester) async {
      final cached = Entitlement(
        features: const {'pianificazione'},
        capabilities: const {'pianificazione.schedule.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 17),
      );

      await tester.pumpWidget(
        _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
      );
      authStream.add(fakeUser);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/altro/pianificazioni');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ForbiddenScreen), findsNothing);
      expect(find.byType(AdminScheduleListScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  // Proves the permission-gate sweep's new table rows use the same generic mechanism as
  // pianificazione above, not something pianificazione-specific — one capability-gated admin
  // subtree (magazzino.warehouse.read) and one module-gated operational route (cantieri).

  testWidgets(
    'denied magazzino.warehouse.read capability redirects /altro/magazzino/magazzini to /forbidden',
    (tester) async {
      final cached = Entitlement(
        features: const {'magazzino'},
        capabilities: const {},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 23),
      );

      await tester.pumpWidget(
        _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
      );
      authStream.add(fakeUser);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/altro/magazzino/magazzini');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ForbiddenScreen), findsOneWidget);
      expect(find.byType(AdminMagazzinoListScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('unentitled cantieri module redirects /cantieri to /forbidden', (tester) async {
    final cached = Entitlement(
      features: const {},
      capabilities: const {},
      seatType: 'office',
      fetchedAt: DateTime.utc(2026, 9, 23),
    );

    await tester.pumpWidget(
      _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
    );
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/cantieri');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(ForbiddenScreen), findsOneWidget);
    expect(find.byType(CantieriListScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  // Closes the residual gap the sweep documented but didn't fix: clienti/sedi mix open read with
  // gated write, so the list-level `.read` requirement alone would let a held-read/denied-write
  // user reach `nuovo`/`:id/modifica` by deep-linking past the button-level CapabilityGate that
  // hides those triggers in the UI. `nuovo` is the simpler case to assert directly (no `:id` to
  // fabricate) — same write-segment mechanism also covers `:id/modifica`.

  testWidgets(
    'held clienti.customer.read but denied .write redirects /altro/clienti/nuovo to /forbidden',
    (tester) async {
      final cached = Entitlement(
        features: const {'clienti'},
        capabilities: const {'clienti.customer.read'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 24),
      );

      await tester.pumpWidget(
        _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
      );
      authStream.add(fakeUser);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/altro/clienti/nuovo');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ForbiddenScreen), findsOneWidget);
      expect(find.byType(AdminCustomerFormScreen), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'held clienti.customer.write reaches /altro/clienti/nuovo, not /forbidden',
    (tester) async {
      final cached = Entitlement(
        features: const {'clienti'},
        capabilities: const {'clienti.customer.read', 'clienti.customer.write'},
        seatType: 'office',
        fetchedAt: DateTime.utc(2026, 9, 24),
      );

      await tester.pumpWidget(
        _buildApp(repo: repo, db: db, mockDio: mockDio, cachedEntitlement: cached),
      );
      authStream.add(fakeUser);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/altro/clienti/nuovo');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ForbiddenScreen), findsNothing);
      expect(find.byType(AdminCustomerFormScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

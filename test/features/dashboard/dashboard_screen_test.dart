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
import 'package:tasktap_mobile/core/location/location_service.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/features/dashboard/id_plate_hero_comp.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/dashboard/active_tracker_strip.dart';
import 'package:tasktap_mobile/features/dashboard/dashboard_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildDashboard({required AppDatabase db, required MockAuthRepository repo}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
      // PunchNotifier calls this (best-effort, silent GPS capture) on every punch — same reasoning
      // as timbra_screen_test.dart's own override.
      locationServiceProvider.overrideWithValue(const DisabledLocationService()),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );
}

/// Builds the Dashboard behind a real [GoRouter] with marker screens at the standalone Timbra
/// route and the (distinct) cantiere-timbra route, so a test can assert *which* route a tile
/// actually pushes rather than only checking that some text containing "Timbra" is on screen.
GoRouter _makeQuickActionRouter() => GoRouter(
  initialLocation: '/dashboard',
  routes: [
    GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
    GoRoute(
      path: AppRoutes.timbra,
      builder: (_, _) => const Scaffold(body: Center(child: Text('TIMBRA-SCREEN-MARKER'))),
    ),
    GoRoute(
      path: AppRoutes.cantiereTimbra,
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('CANTIERE-TIMBRA-SCREEN-MARKER'))),
    ),
  ],
);

Widget _buildDashboardWithRouter({
  required AppDatabase db,
  required MockAuthRepository repo,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
      locationServiceProvider.overrideWithValue(const DisabledLocationService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  /// Pumps the dashboard and emits the authenticated user once the
  /// provider has subscribed to the (broadcast) auth stream.
  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(_buildDashboard(db: db, repo: repo));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  group('DashboardScreen', () {
    testWidgets('renders hero with user email when no displayName', (tester) async {
      await pumpDashboard(tester);
      // ID-plate hero: the name is the plate's identity line — uppercased, no separate greeting
      // text. "mario@tasktap.io" becomes "MARIO@TASKTAP.IO" on the plate.
      expect(find.text('MARIO@TASKTAP.IO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the hero is a compact plate, not a tall panel', (tester) async {
      // minHeight was 430 unconditionally: with no clock running that is most of a phone screen
      // given to an empty gradient with a name at the top, and the day's work starting below the
      // fold. The ID plate always shows its readout row (job count, even at zero), but stays a
      // compact stamped band, not a near-full-screen hero. Idle now also carries a one-line
      // "Timbra ingresso" prompt (a real action, not a placeholder) — a few points taller than a
      // bare gradient, still nowhere near the old 430.
      await pumpDashboard(tester);

      final heroHeight = tester.getSize(find.byType(IdPlateHeroComp)).height;
      expect(
        heroHeight,
        lessThan(280),
        reason: 'the plate should stay a compact identity band, not a tall panel',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('leads with today, not with a grid of counts', (tester) async {
      // The 2x2 StatsGrid rendered "Interventi oggi 3 / In corso 1 / Completati 2 / Prossimi 5"
      // across the width of the screen, above everything. Every one of those numbers is the
      // length of a list that is right there, and none of them is something to act on. It is
      // gone, and the day it was counting is the first thing under the hero.
      await pumpDashboard(tester);

      expect(find.byType(StatsGrid), findsNothing);
      expect(find.text('Oggi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('offers the two things a technician starts from here, plus Le mie timbrature', (
      tester,
    ) async {
      // Was four. "Rapportini" and "Magazzino" are destinations the Altro tab already reaches;
      // a shortcut to a screen one tap away is not a shortcut, it is a second door. "Le mie
      // timbrature" was added back as a third tile — a view, not a start action — because it's
      // the personal-Timbra home now that the Timbra bottom-nav tab is gone.
      await pumpDashboard(tester);

      expect(find.byType(QuickAction, skipOffstage: false), findsNWidgets(3));
      expect(find.text('Magazzino', skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    // ── Le mie timbrature (Task 11: personal-Timbra entry point) ────────────
    //
    // AppRoutes.timbra became a standalone pushed route once the Timbra bottom-nav tab was
    // replaced by Cantieri; this tile is the new entry point for a technician's own clock in/out.

    testWidgets('shows a Timbra quick action that pushes the standalone Timbra route', (
      tester,
    ) async {
      await pumpDashboard(tester);

      // Same skipOffstage: false convention as the QuickAction count test above — this tile
      // sits below the fold in the CustomScrollView at the test viewport's default size.
      expect(find.textContaining('mie\ntimbrature', skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'tapping Le mie timbrature pushes AppRoutes.timbra specifically, not cantiere timbra',
      (tester) async {
        final router = _makeQuickActionRouter();
        await tester.pumpWidget(_buildDashboardWithRouter(db: db, repo: repo, router: router));
        await tester.pump();
        authStream.add(fakeUser);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        final tile = find.text('Le mie\ntimbrature', skipOffstage: false);
        expect(tile, findsOneWidget);

        // Scroll it into the viewport before tapping — it sits below the fold by default.
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();

        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(find.text('TIMBRA-SCREEN-MARKER'), findsOneWidget);
        expect(find.text('CANTIERE-TIMBRA-SCREEN-MARKER'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('shows the clock-in prompt, not a placeholder, when no clock is running', (
      tester,
    ) async {
      await pumpDashboard(tester);

      // No ActiveTrackerStrip and no inert status text — the hero drew a grey glass panel reading
      // "Non hai interventi attivi al momento" for the ordinary condition of being between jobs,
      // and the absence of rows already said that on its own. What idle shows instead is a real
      // action: "Timbra ingresso".
      expect(find.byType(ActiveTrackerStrip), findsNothing);
      expect(find.textContaining('attiv'), findsNothing);
      expect(find.text('Timbra ingresso'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an in-progress schedule is not a running clock, and does not appear', (
      tester,
    ) async {
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: dayStart,
              activityDate: dayStart,
              timeStartMinutes: 480,
              timeEndMinutes: 1020,
              userId: 'u1',
              statusId: 2, // In corso
              locationId: 'loc-1',
              title: 'Sostituzione caldaia',
              description: '',
            ),
          );

      await pumpDashboard(tester);

      // A schedule marked "In corso" is the calendar's intention, not a clock anybody is being
      // paid against. The hero used to render it as a card with a 00:00:00 timer — a stopped clock
      // dressed as a running one, on the surface whose only job is live time.
      expect(find.byType(ActiveTrackerStrip), findsNothing);

      // It does belong in the day's work, though, and that list used to start at tomorrow: the
      // dashboard showed today's interventi only as a digit in the stat grid.
      expect(find.text('Sostituzione caldaia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('bell shows a dot when there are unread notifications', (tester) async {
      await pumpDashboard(tester);

      final bell = tester.widget<HeaderIconBtn>(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Notifiche'),
      );
      expect(bell.showDot, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('bell shows a dot once an unread notification is cached', (tester) async {
      await db
          .into(db.appNotifications)
          .insert(
            AppNotificationsCompanion.insert(
              id: 'notif-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.now().toUtc(),
              userId: 'u1',
              title: 'Nuovo ticket assegnato',
              message: 'Ticket #42 assegnato a te',
              type: 'ticket',
              deliveryType: 'push',
            ),
          );

      await pumpDashboard(tester);

      final bell = tester.widget<HeaderIconBtn>(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Notifiche'),
      );
      expect(bell.showDot, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    // ── Clock-in from Home (2026-08-30 polish pass) ─────────────────────────
    //
    // A punch fired from the idle hero used to hand back control with nothing but the hero
    // swapping shape — no confirmation at all that "Turno iniziato" the way there is for a failed
    // punch (TimbraScreen's own inline error text).

    testWidgets('tapping Timbra ingresso shows a confirmation and swaps to the active tracker', (
      tester,
    ) async {
      await pumpDashboard(tester);
      expect(find.text('Timbra ingresso'), findsOneWidget);

      await tester.tap(find.text('Timbra ingresso'));
      // Bounded pumps, not pumpAndSettle: ActiveTrackerStrip watches nowProvider, the same
      // per-second live clock TimbraScreen's own tests avoid settling against (see
      // timbra_screen_test.dart's _teardownTimer comment) — pumpAndSettle would never return once
      // it mounts.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350)); // punch write + crossfade
      await tester.pump(); // let the SnackBar's entrance animation start

      expect(find.text('Turno iniziato'), findsOneWidget);
      expect(find.byType(ActiveTrackerStrip), findsOneWidget);
      expect(find.text('Timbra ingresso'), findsNothing);

      // Disposes by unmounting, same as timbra_screen_test.dart's _teardownTimer — cancels
      // nowProvider's Timer.periodic instead of leaving it pending past the test.
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 5; i++) {
        await tester.pump(Duration.zero);
      }
    });
  });
}

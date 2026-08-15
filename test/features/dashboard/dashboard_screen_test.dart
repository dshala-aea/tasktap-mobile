import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
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
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
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
      expect(find.text('mario@tasktap.io'), findsOneWidget);
      expect(find.text('Bentornato'), findsOneWidget);
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

    testWidgets('offers only the two things a technician starts from here', (tester) async {
      // Was four. "Rapportini" and "Magazzino" are destinations the Altro tab already reaches;
      // a shortcut to a screen one tap away is not a shortcut, it is a second door.
      await pumpDashboard(tester);

      expect(find.byType(QuickAction, skipOffstage: false), findsNWidgets(2));
      expect(find.text('Magazzino', skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows nothing at all when no clock is running', (tester) async {
      await pumpDashboard(tester);

      // Nothing at all, not a placeholder. The hero drew a grey glass panel reading "Non hai
      // interventi attivi al momento" for the ordinary condition of being between jobs — most of
      // the morning — and the absence of rows already says it.
      expect(find.byType(ActiveTrackerStrip), findsNothing);
      expect(find.textContaining('attiv'), findsNothing);
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
  });
}

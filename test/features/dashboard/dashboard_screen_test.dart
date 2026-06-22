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
import 'package:tasktap_mobile/features/dashboard/dashboard_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildDashboard({
  required AppDatabase db,
  required MockAuthRepository repo,
}) {
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
    testWidgets('renders hero with user email when no displayName',
        (tester) async {
      await pumpDashboard(tester);
      expect(find.text('mario@tasktap.io'), findsOneWidget);
      expect(find.text('Bentornato'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatsGrid', (tester) async {
      await pumpDashboard(tester);
      expect(find.byType(StatsGrid), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows 4 QuickAction widgets', (tester) async {
      await pumpDashboard(tester);
      expect(find.byType(QuickAction, skipOffstage: false), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty state when no active jobs', (tester) async {
      await pumpDashboard(tester);
      expect(find.byType(EmptyState), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows ActiveJobCard when in-progress schedule present',
        (tester) async {
      final today = DateTime.now().toUtc();
      final dayStart = DateTime.utc(today.year, today.month, today.day);
      await db.into(db.schedules).insert(SchedulesCompanion.insert(
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
          ));

      await pumpDashboard(tester);
      expect(find.byType(ActiveJobCard), findsOneWidget);
      expect(find.text('Sostituzione caldaia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

// ── Helpers ───────────────────────────────────────────────────────────────

Map<String, dynamic> _emptySyncPayload() => {
  'syncedAt': DateTime.utc(2026, 6, 21).toIso8601String(),
  'since': null,
  'schedules': <dynamic>[],
  'draftReports': <dynamic>[],
  'customers': <dynamic>[],
  'locations': <dynamic>[],
  'tickets': <dynamic>[],
};

/// Builds a [TaskTapApp] with:
/// - Mock auth repository emitting an authenticated user.
/// - A provided in-memory Drift DB.
/// - Stub Dio that returns an empty sync payload.
Widget _buildAuthenticatedApp(MockAuthRepository repo, AppDatabase db, MockDio mockDio) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
    ],
    child: const TaskTapApp(),
  );
}

void main() {
  setUpAll(() async {
    // Suppress the "multiple AppDatabase instances" Drift warning in tests.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    // The dashboard's ID-plate hero formats today's date in Italian; without this, mounting the
    // real app tree throws LocaleDataException the moment it builds.
    await initializeDateFormatting('it', null);
  });

  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;
  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    // Stub sync endpoint to return an empty payload.
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

    // Emit a signed-in user so the router shows the main shell.
    final fakeUser = AuthUser(
      id: 'test-user',
      email: 'tech@tasktap.io',
      accessToken: 'fake-token',
      refreshToken: 'fake-refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
    // Emit the user immediately.
    Future.microtask(() => authStream.add(fakeUser));
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  group('TaskTapApp shell smoke test', () {
    testWidgets('app renders without throwing', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(MaterialApp), findsWidgets);
      // Unmount widget tree before tearDown to let Drift close its streams.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('AppBottomNav is visible (5-tab pill)', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byType(AppBottomNav), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Dashboard tab is active label on launch', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Active tab shows its label; Dashboard is index 0 (initial route).
      expect(find.text('Dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('tapping Ticket tab switches branch', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo, db, mockDio));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Inactive tabs render icon-only; find by Semantics label.
      final ticketTab = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Ticket',
      );
      expect(ticketTab, findsWidgets);
      await tester.tap(ticketTab.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // Ticket is now the active tab → its label is shown in the nav.
      // (TicketListScreen also renders a "Ticket" heading, so at least one match.)
      expect(find.text('Ticket'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}

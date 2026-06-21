import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/main.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Mock ──────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Builds a [TaskTapApp] with a mock auth repository that immediately
/// emits an authenticated user, so the router's redirect lands on the
/// main app shell instead of /login.
Widget _buildAuthenticatedApp(MockAuthRepository repo) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const TaskTapApp(),
  );
}

void main() {
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();

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

  tearDown(() {
    authStream.close();
  });

  group('TaskTapApp shell smoke test', () {
    testWidgets('app renders without throwing', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The shell should be on screen (no exception thrown).
      expect(find.byType(MaterialApp), findsWidgets);
    });

    testWidgets('bottom navigation bar is visible', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('bottom nav has 4 destinations', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(NavigationDestination), findsNWidgets(4));
    });

    testWidgets('tab labels are in Italian', (tester) async {
      await tester.pumpWidget(_buildAuthenticatedApp(repo));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Oggi'), findsWidgets);
      expect(find.text('Interventi'), findsWidgets);
      expect(find.text('Rapportini'), findsWidgets);
      expect(find.text('Profilo'), findsWidgets);
    });
  });
}

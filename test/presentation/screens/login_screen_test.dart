import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/screens/login/login_screen.dart';

// ── Mock ──────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────

Widget _buildLoginScreen(IAuthRepository repo) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: LoginScreen()),
  );
}

/// The primary login CTA — the AppButton labelled 'Accedi' (distinct from the
/// screen heading, which is also 'Accedi').
Finder get _loginCta => find.descendant(of: find.byType(AppButton), matching: find.text('Accedi'));

void main() {
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(null);
  });

  tearDown(() {
    authStream.close();
  });

  // ── Rendering ──────────────────────────────────────────────────────────

  group('LoginScreen rendering', () {
    testWidgets('renders TaskTap logo', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('TT'), findsOneWidget);
      expect(find.text('TaskTap'), findsOneWidget);
    });

    testWidgets('renders the Accedi CTA', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(_loginCta, findsOneWidget);
    });

    testWidgets('does not render email/password fields (OIDC redirect)', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);
    });
  });

  // ── Sign-in ──────────────────────────────────────────────────────────────

  group('LoginScreen sign-in', () {
    testWidgets('tapping Accedi starts the interactive sign-in', (tester) async {
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      verify(() => repo.signIn()).called(1);
    });
  });

  // ── Error display ──────────────────────────────────────────────────────

  group('LoginScreen error display', () {
    testWidgets('shows the network error banner on NetworkError', (tester) async {
      when(
        () => repo.signIn(),
      ).thenAnswer((_) async => (user: null, failure: const NetworkError()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(find.textContaining('connessione'), findsOneWidget);
    });
  });
}

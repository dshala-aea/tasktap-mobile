import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/vetro_button.dart';
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

/// The primary login CTA — the VetroButton labelled 'Accedi' (distinct from the
/// screen heading, which is also 'Accedi').
Finder get _loginCta =>
    find.descendant(of: find.byType(VetroButton), matching: find.text('Accedi'));

Finder get _usernameField => find.byKey(const ValueKey('login-username'));
Finder get _passwordField => find.byKey(const ValueKey('login-password'));

Future<void> _enterCredentials(WidgetTester tester, {String username = 'tech@tasktap.io', String password = 'correct-password'}) async {
  await tester.enterText(_usernameField, username);
  await tester.enterText(_passwordField, password);
}

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

    testWidgets('renders username and password fields (native login)', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(_usernameField, findsOneWidget);
      expect(_passwordField, findsOneWidget);
    });

    testWidgets('renders the Password dimenticata? link', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Password dimenticata?'), findsOneWidget);
    });
  });

  // ── Sign-in ──────────────────────────────────────────────────────────────

  group('LoginScreen sign-in', () {
    testWidgets('submitting valid credentials calls signInWithPassword', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await _enterCredentials(tester);
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      verify(() => repo.signInWithPassword('tech@tasktap.io', 'correct-password')).called(1);
      verifyNever(() => repo.signIn());
    });
  });

  // ── Error display ──────────────────────────────────────────────────────

  group('LoginScreen error display', () {
    testWidgets('wrong credentials shows the error banner', (tester) async {
      when(() => repo.signInWithPassword(any(), any())).thenAnswer(
        (_) async => (user: null, failure: const InvalidCredentials()),
      );

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await _enterCredentials(tester, password: 'wrong');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(find.text('Email o password errati. Controlla le credenziali e riprova.'), findsOneWidget);
    });

    testWidgets('shows the network error banner on NetworkError', (tester) async {
      when(() => repo.signInWithPassword(any(), any())).thenAnswer(
        (_) async => (user: null, failure: const NetworkError()),
      );

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await _enterCredentials(tester);
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(find.textContaining('connessione'), findsOneWidget);
    });
  });

  // ── Forgot password ──────────────────────────────────────────────────────

  group('LoginScreen forgot password', () {
    testWidgets('"Password dimenticata?" calls signIn (browser flow), not signInWithPassword', (tester) async {
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Password dimenticata?'));
      await tester.pumpAndSettle();

      verify(() => repo.signIn()).called(1);
      verifyNever(() => repo.signInWithPassword(any(), any()));
    });
  });
}

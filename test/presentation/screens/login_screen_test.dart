import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
    child: const MaterialApp(
      home: LoginScreen(),
    ),
  );
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
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('renders Accedi button', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Accedi'), findsWidgets);
    });

    testWidgets('renders Ricordami checkbox checked by default', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('renders TaskTap logo', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('TT'), findsOneWidget);
      expect(find.text('TaskTap'), findsOneWidget);
    });
  });

  // ── Validation ─────────────────────────────────────────────────────────

  group('LoginScreen validation', () {
    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      // Tap the ElevatedButton (the Accedi CTA) without filling any field.
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(find.text('Inserisci l\'email'), findsOneWidget);
    });

    testWidgets('shows error when email format is invalid', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'not-an-email',
      );
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(find.text('Inserisci un\'email valida'), findsOneWidget);
    });

    testWidgets('shows error when password is empty', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'valid@email.com',
      );
      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(find.text('Inserisci la password'), findsOneWidget);
    });

    testWidgets('no validation error with valid email and password', (tester) async {
      when(() => repo.signInWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer(
            (_) async => (user: null, failure: const InvalidCredentials()),
          );

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'tech@tasktap.io');
      await tester.enterText(fields.at(1), 'mypassword');

      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(find.text('Inserisci l\'email'), findsNothing);
      expect(find.text('Inserisci la password'), findsNothing);
    });
  });

  // ── Error display ──────────────────────────────────────────────────────

  group('LoginScreen error display', () {
    testWidgets('shows Italian error banner on InvalidCredentials', (tester) async {
      when(() => repo.signInWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer(
            (_) async => (user: null, failure: const InvalidCredentials()),
          );

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'tech@tasktap.io');
      await tester.enterText(fields.at(1), 'wrongpass');

      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Email o password errati'),
        findsOneWidget,
      );
    });

    testWidgets('shows network error banner on NetworkError', (tester) async {
      when(() => repo.signInWithEmailPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer(
            (_) async => (user: null, failure: const NetworkError()),
          );

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'tech@tasktap.io');
      await tester.enterText(fields.at(1), 'pass');

      await tester.tap(find.byType(ElevatedButton).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('connessione'), findsOneWidget);
    });
  });
}

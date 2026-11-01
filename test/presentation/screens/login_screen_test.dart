// Two-step login: the email is asked first, then the sign-in method (password or passkey).
//
// The methods are a real choice, not two fields competing in one form: both backends need the
// email before anything can happen (the password BFF and the ZITADEL session behind the passkey
// flow).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/security/passkey_support.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/domain/auth/auth_failure.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/presentation/screens/login/login_screen.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

Widget _buildLoginScreen(IAuthRepository repo, {bool passkeySupported = false}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      passkeySupportedProvider.overrideWith((ref) async => passkeySupported),
    ],
    child: const MaterialApp(home: LoginScreen()),
  );
}

Finder get _continueCta =>
    find.descendant(of: find.byType(AppButton), matching: find.text('Continua'));

Finder get _loginCta =>
    find.descendant(of: find.byType(AppButton), matching: find.text('Accedi'));

Finder get _usernameField => find.byKey(const ValueKey('login-username'));
Finder get _passwordField => find.byKey(const ValueKey('login-password'));
Finder get _browserFallbackButton => find.text('Accedi con il browser');
Finder get _passkeyButton => find.text('Accedi con passkey');

TextField _usernameTextField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(of: _usernameField, matching: find.byType(TextField)),
);

TextField _passwordTextField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(of: _passwordField, matching: find.byType(TextField)),
);

String? _usernameText(WidgetTester tester) => _usernameTextField(tester).controller?.text;

Future<void> _goToMethodStep(
  WidgetTester tester, {
  String email = 'tech@tasktap.io',
}) async {
  await tester.enterText(_usernameField, email);
  await tester.pump();
  await tester.tap(_continueCta);
  await tester.pumpAndSettle();
}

void main() {
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(null);
  });

  tearDown(() {
    authStream.close();
  });

  group('step 1 — email', () {
    testWidgets('renders the logo and asks only for the email', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('TT'), findsOneWidget);
      expect(find.text('TaskTap'), findsOneWidget);
      expect(_usernameField, findsOneWidget);
      expect(_continueCta, findsOneWidget);

      // The method — and its password — belongs to the next step.
      expect(_passwordField, findsNothing);
      expect(_passkeyButton, findsNothing);
      expect(find.text('Password dimenticata?'), findsNothing);
    });

    testWidgets('Continua refuses an address that is not an email', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      AppButton button() =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continua'));

      await tester.enterText(_usernameField, 'not-an-email');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(_usernameField, 'tech@tasktap.io');
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('Continua is disabled while the email is empty', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      AppButton button() =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continua'));
      expect(button().onPressed, isNull);

      await tester.enterText(_usernameField, 'tech@tasktap.io');
      await tester.pump();
      expect(button().onPressed, isNotNull);
    });
  });

  group('step 2 — method', () {
    testWidgets('shows the email, the password field and the password CTA', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      expect(_usernameField, findsOneWidget);
      expect(_usernameText(tester), 'tech@tasktap.io');
      expect(_passwordField, findsOneWidget);
      expect(_loginCta, findsOneWidget);
      expect(find.text('Password dimenticata?'), findsOneWidget);
    });

    testWidgets('offers the passkey when the device supports it', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo, passkeySupported: true));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      expect(_passkeyButton, findsOneWidget);
    });

    testWidgets('hides the passkey when the device has no support', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      expect(_passkeyButton, findsNothing);
    });

    testWidgets('Cambia returns to step 1 with the email preserved', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.tap(find.text('Cambia'));
      await tester.pumpAndSettle();

      expect(_continueCta, findsOneWidget);
      expect(_usernameText(tester), 'tech@tasktap.io');
    });

    testWidgets('Cambia clears the error of the failed attempt', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: const InvalidCredentials()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);
      await tester.enterText(_passwordField, 'wrong');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();
      expect(find.text(authFailureMessage(const InvalidCredentials())), findsOneWidget);

      await tester.tap(find.text('Cambia'));
      await tester.pumpAndSettle();
      await tester.tap(_continueCta);
      await tester.pumpAndSettle();

      expect(find.text(authFailureMessage(const InvalidCredentials())), findsNothing);
    });

    testWidgets('both fields stay inside one AutofillGroup', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      final group = find.byType(AutofillGroup);
      expect(group, findsOneWidget);
      expect(find.ancestor(of: _usernameField, matching: group), findsOneWidget);
      expect(find.ancestor(of: _passwordField, matching: group), findsOneWidget);
    });

    testWidgets('the fields declare their autofill hints', (tester) async {
      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      final username = _usernameTextField(tester);
      final password = _passwordTextField(tester);
      expect(username.autofillHints, contains(AutofillHints.username));
      expect(password.autofillHints, contains(AutofillHints.password));
    });
  });

  group('remembered email', () {
    testWidgets('a saved email prefills the first step', (tester) async {
      SharedPreferences.setMockInitialValues({'login.last_email': 'saved@tasktap.io'});

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();

      expect(_usernameText(tester), 'saved@tasktap.io');
    });

    testWidgets('a successful password sign-in remembers the email', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);
      await tester.enterText(_passwordField, 'correct-password');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('login.last_email'), 'tech@tasktap.io');
    });

    testWidgets('a failed attempt does not overwrite the saved email', (tester) async {
      SharedPreferences.setMockInitialValues({'login.last_email': 'old@tasktap.io'});
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: const InvalidCredentials()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester, email: 'new@tasktap.io');
      await tester.enterText(_passwordField, 'wrong');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('login.last_email'), 'old@tasktap.io');
    });
  });

  group('signing in', () {
    testWidgets('a valid password calls signInWithPassword with the step-1 email', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.enterText(_passwordField, 'correct-password');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      verify(() => repo.signInWithPassword('tech@tasktap.io', 'correct-password')).called(1);
      verifyNever(() => repo.signIn());
    });

    testWidgets('a wrong password stays on the method step', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: const InvalidCredentials()));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.enterText(_passwordField, 'wrong');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(_passwordField, findsOneWidget);
      expect(_continueCta, findsNothing);
      expect(find.text(authFailureMessage(const InvalidCredentials())), findsOneWidget);
      expect(_browserFallbackButton, findsNothing);
    });

    testWidgets('the passkey action uses the step-1 email', (tester) async {
      when(() => repo.signInWithPasskey(any()))
          .thenAnswer((_) async => (user: null, failure: const PasskeyCancelled()));

      await tester.pumpWidget(_buildLoginScreen(repo, passkeySupported: true));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.tap(_passkeyButton);
      await tester.pumpAndSettle();

      verify(() => repo.signInWithPasskey('tech@tasktap.io')).called(1);
    });

    testWidgets('double tapping the passkey action starts one attempt', (tester) async {
      final completer = Completer<({AuthUser? user, AuthFailure? failure})>();
      when(() => repo.signInWithPasskey(any())).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildLoginScreen(repo, passkeySupported: true));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.tap(_passkeyButton);
      await tester.tap(_passkeyButton);

      completer.complete((user: null, failure: const PasskeyCancelled()));
      await tester.pumpAndSettle();

      verify(() => repo.signInWithPasskey('tech@tasktap.io')).called(1);
    });

    testWidgets('Password dimenticata? uses the browser flow', (tester) async {
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.tap(find.text('Password dimenticata?'));
      await tester.pumpAndSettle();

      verify(() => repo.signIn()).called(1);
      verifyNever(() => repo.signInWithPassword(any(), any()));
    });

    testWidgets('an unexpected failure still offers the browser fallback', (tester) async {
      when(() => repo.signInWithPassword(any(), any()))
          .thenAnswer((_) async => (user: null, failure: const NetworkError()));
      when(() => repo.signIn()).thenAnswer((_) async => (user: null, failure: null));

      await tester.pumpWidget(_buildLoginScreen(repo));
      await tester.pumpAndSettle();
      await _goToMethodStep(tester);

      await tester.enterText(_passwordField, 'pw');
      await tester.tap(_loginCta);
      await tester.pumpAndSettle();

      expect(_browserFallbackButton, findsOneWidget);
      await tester.tap(_browserFallbackButton);
      await tester.pumpAndSettle();
      verify(() => repo.signIn()).called(1);
    });
  });
}
